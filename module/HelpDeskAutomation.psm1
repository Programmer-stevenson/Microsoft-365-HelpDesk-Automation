Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:GraphRoot = 'https://graph.microsoft.com/v1.0'

function Get-HdaProjectRoot {
    [CmdletBinding()]
    param()
    return $script:ProjectRoot
}

function Initialize-HdaDataStore {
    [CmdletBinding()]
    param()

    foreach ($folder in @('data', 'data/snapshots', 'data/offboarding', 'reports')) {
        $path = Join-Path $script:ProjectRoot $folder
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function New-HdaOperationId {
    [CmdletBinding()]
    param()
    return ('HDA-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), (Get-Random -Minimum 1000 -Maximum 9999))
}

function Get-HdaRandomIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$MaxExclusive)

    if ($MaxExclusive -le 0) { throw 'MaxExclusive must be greater than zero.' }

    $bytes = New-Object byte[] 4
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
        $value = [BitConverter]::ToUInt32($bytes, 0)
        return [int]($value % [uint32]$MaxExclusive)
    }
    finally {
        $rng.Dispose()
    }
}

function New-HdaTemporaryPassword {
    [CmdletBinding()]
    param([ValidateRange(14, 64)][int]$Length = 18)

    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digits = '23456789'
    $symbols = '!@#$%*-_+'
    $all = $upper + $lower + $digits + $symbols

    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($set in @($upper, $lower, $digits, $symbols)) {
        $chars.Add($set[(Get-HdaRandomIndex -MaxExclusive $set.Length)])
    }
    while ($chars.Count -lt $Length) {
        $chars.Add($all[(Get-HdaRandomIndex -MaxExclusive $all.Length)])
    }

    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = Get-HdaRandomIndex -MaxExclusive ($i + 1)
        $tmp = $chars[$i]
        $chars[$i] = $chars[$j]
        $chars[$j] = $tmp
    }

    return -join $chars
}

function Connect-HdaGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Scopes,
        [string]$TenantId,
        [switch]$UseDeviceCode,
        [switch]$ForceReconnect
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication is not installed. Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $requestedScopes = @($Scopes | Where-Object { $_ } | Sort-Object -Unique)
    $context = Get-MgContext -ErrorAction SilentlyContinue
    $needsConnect = $ForceReconnect -or -not $context -or -not $context.Account

    if (-not $needsConnect) {
        $missingScopes = @($requestedScopes | Where-Object { $_ -notin @($context.Scopes) })
        if ($missingScopes.Count -gt 0) { $needsConnect = $true }
        if ($TenantId -and $context.TenantId -ne $TenantId) { $needsConnect = $true }
    }

    if ($needsConnect) {
        # Reconnect when the process token does not contain every scope required by the
        # requested workflow or when the caller switches tenants. This avoids silently
        # reusing a stale Graph context with insufficient delegated consent.
        if ($context -and $context.Account) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }

        $connectParams = @{
            Scopes       = $requestedScopes
            ContextScope = 'Process'
            NoWelcome    = $true
        }
        if ($TenantId) { $connectParams.TenantId = $TenantId }
        if ($UseDeviceCode) { $connectParams.UseDeviceAuthentication = $true }

        Connect-MgGraph @connectParams | Out-Null
        $context = Get-MgContext
    }

    if (-not $context -or -not $context.Account) {
        throw 'Microsoft Graph authentication did not return an authenticated context.'
    }

    return $context
}

function Get-HdaGraphContextInfo {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ account = $null; tenantId = $null; authType = $null }
    }

    $context = Get-MgContext -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        account  = $context.Account
        tenantId = $context.TenantId
        authType = $context.AuthType
    }
}

function Invoke-HdaGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        $Body,
        [hashtable]$Headers
    )

    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    }

    $requestParams = @{
        Method     = $Method
        Uri        = $Uri
        OutputType = 'PSObject'
    }
    if ($Headers) { $requestParams.Headers = $Headers }

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $requestParams.Body = ($Body | ConvertTo-Json -Depth 30 -Compress)
        $requestParams.ContentType = 'application/json'
    }

    return Invoke-MgGraphRequest @requestParams
}

function Invoke-HdaGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers
    )

    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri

    do {
        $response = if ($Headers) {
            Invoke-HdaGraphRequest -Method GET -Uri $next -Headers $Headers
        }
        else {
            Invoke-HdaGraphRequest -Method GET -Uri $next
        }

        foreach ($item in @($response.value)) {
            if ($null -ne $item) { $items.Add($item) }
        }

        $next = $response.'@odata.nextLink'
    } while ($next)

    return @($items)
}

function Resolve-HdaGraphUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)

    $encoded = [System.Uri]::EscapeDataString($Identity)
    $select = 'id,displayName,givenName,surname,userPrincipalName,mail,department,jobTitle,officeLocation,usageLocation,accountEnabled,createdDateTime,lastPasswordChangeDateTime,licenseAssignmentStates'
    return Invoke-HdaGraphRequest -Method GET -Uri "${script:GraphRoot}/users/${encoded}?`$select=$select"
}

function Resolve-HdaGraphGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)

    $parsedGuid = [guid]::Empty
    if ([guid]::TryParse($Identity, [ref]$parsedGuid)) {
        $encoded = [System.Uri]::EscapeDataString($Identity)
        return Invoke-HdaGraphRequest -Method GET -Uri "${script:GraphRoot}/groups/${encoded}?`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,membershipRule"
    }

    $escaped = $Identity.Replace("'", "''")
    $filter = [System.Uri]::EscapeDataString("displayName eq '$escaped'")
    $results = @(Invoke-HdaGraphCollection -Uri "$script:GraphRoot/groups?`$filter=$filter&`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,membershipRule")

    if ($results.Count -eq 0) { throw "Microsoft Entra group '$Identity' was not found." }
    if ($results.Count -gt 1) { throw "More than one group is named '$Identity'. Use the group object ID instead." }

    return $results[0]
}

function Resolve-HdaLicenseSku {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Identity)

    $skus = @(Invoke-HdaGraphCollection -Uri "$script:GraphRoot/subscribedSkus?`$select=id,skuId,skuPartNumber,consumedUnits,capabilityStatus,prepaidUnits")
    $parsedGuid = [guid]::Empty

    if ([guid]::TryParse($Identity, [ref]$parsedGuid)) {
        $matches = @($skus | Where-Object { [string]$_.skuId -eq [string]$Identity })
    }
    else {
        $matches = @($skus | Where-Object { [string]$_.skuPartNumber -ieq [string]$Identity })
    }

    if ($matches.Count -eq 0) {
        throw "License SKU '$Identity' was not found in this tenant. Use Test-GraphConnection.ps1 to list available SKUs."
    }

    return $matches[0]
}

function Get-HdaGraphOrganization {
    [CmdletBinding()]
    param()

    $orgs = @(Invoke-HdaGraphCollection -Uri "$script:GraphRoot/organization?`$select=id,displayName,verifiedDomains")
    if ($orgs.Count -eq 0) { throw 'No Microsoft Entra organization object was returned.' }

    return $orgs[0]
}

function Get-HdaGraphUserGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserObjectId)

    $uid = [System.Uri]::EscapeDataString($UserObjectId)
    return @(Invoke-HdaGraphCollection -Uri "${script:GraphRoot}/users/${uid}/memberOf/microsoft.graph.group?`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,membershipRule")
}

function Get-HdaGraphUserLicenses {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserObjectId)

    $uid = [System.Uri]::EscapeDataString($UserObjectId)
    return @(Invoke-HdaGraphCollection -Uri "${script:GraphRoot}/users/${uid}/licenseDetails?`$select=id,skuId,skuPartNumber")
}

function Get-HdaGraphUserSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [switch]$IncludeSignInActivity,
        [switch]$IncludeIntuneDevices
    )

    $user = Resolve-HdaGraphUser -Identity $Identity
    $uid = [System.Uri]::EscapeDataString([string]$user.id)
    $notes = New-Object System.Collections.Generic.List[string]

    $groups = @()
    $licenses = @()
    $registeredDevices = @()
    $managedDevices = @()
    $manager = $null
    $lastSignIn = $null

    try { $groups = @(Get-HdaGraphUserGroups -UserObjectId ([string]$user.id)) }
    catch { $notes.Add("Group lookup unavailable: $($_.Exception.Message)") }

    try { $licenses = @(Get-HdaGraphUserLicenses -UserObjectId ([string]$user.id)) }
    catch { $notes.Add("License lookup unavailable: $($_.Exception.Message)") }

    try {
        $registeredDevices = @(Invoke-HdaGraphCollection -Uri "${script:GraphRoot}/users/${uid}/registeredDevices/microsoft.graph.device?`$select=id,displayName,operatingSystem,operatingSystemVersion,trustType,approximateLastSignInDateTime,accountEnabled")
    }
    catch { $notes.Add("Registered-device lookup unavailable: $($_.Exception.Message)") }

    try {
        $manager = Invoke-HdaGraphRequest -Method GET -Uri "${script:GraphRoot}/users/${uid}/manager?`$select=id,displayName,userPrincipalName"
    }
    catch { $notes.Add('Manager information was unavailable or not assigned.') }

    if ($IncludeSignInActivity) {
        try {
            $activity = Invoke-HdaGraphRequest -Method GET -Uri "${script:GraphRoot}/users/${uid}?`$select=signInActivity"
            $lastSignIn = $activity.signInActivity.lastSignInDateTime
        }
        catch {
            $notes.Add('Sign-in activity was unavailable. It requires AuditLog.Read.All and supported Microsoft Entra licensing.')
        }
    }

    if ($IncludeIntuneDevices) {
        try {
            $filter = [System.Uri]::EscapeDataString("userId eq '$($user.id)'")
            $select = 'id,deviceName,managedDeviceName,operatingSystem,osVersion,complianceState,lastSyncDateTime,managementAgent,manufacturer,model,azureADDeviceId,userPrincipalName,enrolledDateTime'
            $managedDevices = @(Invoke-HdaGraphCollection -Uri "${script:GraphRoot}/deviceManagement/managedDevices?`$filter=$filter&`$select=$select")
        }
        catch {
            $notes.Add('Intune managed-device data was unavailable. The tenant needs Intune and DeviceManagementManagedDevices.Read.All.')
        }
    }

    $context = Get-HdaGraphContextInfo

    return [pscustomobject]@{
        generatedAt        = (Get-Date).ToUniversalTime().ToString('o')
        source             = 'Microsoft Graph'
        tenantId           = $context.tenantId
        authenticatedAs    = $context.account
        user               = $user
        manager            = $manager
        groups             = @($groups)
        licenses           = @($licenses)
        registeredDevices  = @($registeredDevices)
        managedDevices     = @($managedDevices)
        lastSignInDateTime = $lastSignIn
        notes              = @($notes)
    }
}

function Write-HdaAuditEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$TargetUser,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][ValidateSet('Success', 'Warning', 'Failed', 'Info')][string]$Status,
        [string]$TicketId,
        [hashtable]$Details = @{}
    )

    Initialize-HdaDataStore
    $context = Get-HdaGraphContextInfo

    $event = [ordered]@{
        eventId     = ([guid]::NewGuid().ToString())
        operationId = $OperationId
        timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        ticketId    = $TicketId
        operator    = $context.account
        tenantId    = $context.tenantId
        source      = 'Microsoft Graph'
        targetUser  = $TargetUser
        action      = $Action
        status      = $Status
        details     = $Details
    }

    $logPath = Join-Path $script:ProjectRoot 'data/audit-log.jsonl'
    ($event | ConvertTo-Json -Depth 20 -Compress) | Add-Content -Path $logPath -Encoding UTF8
    return [pscustomobject]$event
}

function Get-HdaAuditEvents {
    [CmdletBinding()]
    param([string]$Path = (Join-Path $script:ProjectRoot 'data/audit-log.jsonl'))

    if (-not (Test-Path $Path)) { return @() }

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $events.Add(($line | ConvertFrom-Json)) }
        catch { Write-Warning "Skipping malformed audit line: $($_.Exception.Message)" }
    }
    return @($events)
}

Export-ModuleMember -Function @(
    'Get-HdaProjectRoot',
    'Initialize-HdaDataStore',
    'New-HdaOperationId',
    'New-HdaTemporaryPassword',
    'Connect-HdaGraph',
    'Get-HdaGraphContextInfo',
    'Invoke-HdaGraphRequest',
    'Invoke-HdaGraphCollection',
    'Resolve-HdaGraphUser',
    'Resolve-HdaGraphGroup',
    'Resolve-HdaLicenseSku',
    'Get-HdaGraphOrganization',
    'Get-HdaGraphUserGroups',
    'Get-HdaGraphUserLicenses',
    'Get-HdaGraphUserSnapshot',
    'Write-HdaAuditEvent',
    'Get-HdaAuditEvents'
)
