[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$DisplayName,
    [string]$UserPrincipalName,
    [string]$GivenName,
    [string]$Surname,
    [string]$Department,
    [string]$JobTitle,
    [string]$UsageLocation,
    [string]$OfficeLocation,
    [string]$TemporaryPassword,
    [string[]]$Groups,
    [string[]]$LicenseSkuPartNumbers,
    [string]$TicketId = 'REQ-UNSPECIFIED',
    [string]$CsvPath,
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../module/HelpDeskAutomation.psm1') -Force
Initialize-HdaDataStore

function Split-HdaListValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split '[;,]' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) {
        throw "CSV not found: $CsvPath"
    }

    $records = @(Import-Csv $CsvPath)
}
else {
    if ([string]::IsNullOrWhiteSpace($DisplayName) -or [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        throw 'Provide -DisplayName and -UserPrincipalName, or use -CsvPath.'
    }

    $records = @(
        [pscustomobject]@{
            DisplayName           = $DisplayName
            UserPrincipalName     = $UserPrincipalName
            GivenName             = $GivenName
            Surname               = $Surname
            Department            = $Department
            JobTitle              = $JobTitle
            UsageLocation         = $UsageLocation
            OfficeLocation        = $OfficeLocation
            TemporaryPassword     = $TemporaryPassword
            Groups                = ($Groups -join ';')
            LicenseSkuPartNumbers = ($LicenseSkuPartNumbers -join ';')
            TicketId              = $TicketId
        }
    )
}

$needsGroups = $false
$needsLicenses = $false

foreach ($record in $records) {
    if ((Split-HdaListValue ([string]$record.Groups)).Count -gt 0) {
        $needsGroups = $true
    }

    if ((Split-HdaListValue ([string]$record.LicenseSkuPartNumbers)).Count -gt 0) {
        $needsLicenses = $true
    }
}

$scopes = @('User.Create')

if ($needsGroups) {
    $scopes += @('Group.Read.All', 'GroupMember.ReadWrite.All')
}

if ($needsLicenses) {
    $scopes += @('LicenseAssignment.Read.All', 'LicenseAssignment.ReadWrite.All')
}

Connect-HdaGraph -Scopes $scopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null

foreach ($record in $records) {
    $operationId = New-HdaOperationId
    $upn = [string]$record.UserPrincipalName
    $name = [string]$record.DisplayName
    $recordTicket = if ($record.TicketId) { [string]$record.TicketId } else { $TicketId }
    $password = if ($record.TemporaryPassword) { [string]$record.TemporaryPassword } else { New-HdaTemporaryPassword }
    $recordGroups = @(Split-HdaListValue ([string]$record.Groups))
    $recordLicenses = @(Split-HdaListValue ([string]$record.LicenseSkuPartNumbers))

    if ([string]::IsNullOrWhiteSpace($upn) -or [string]::IsNullOrWhiteSpace($name)) {
        throw 'Each onboarding record requires DisplayName and UserPrincipalName.'
    }

    if ($recordLicenses.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$record.UsageLocation)) {
        throw "UsageLocation is required when assigning licenses to '$upn' (for example, US)."
    }

    try {
        $resolvedGroups = @()
        foreach ($groupIdentity in $recordGroups) {
            $resolvedGroups += Resolve-HdaGraphGroup -Identity $groupIdentity
        }

        $resolvedLicenses = @()
        foreach ($skuIdentity in $recordLicenses) {
            $resolvedLicenses += Resolve-HdaLicenseSku -Identity $skuIdentity
        }

        if ($PSCmdlet.ShouldProcess($upn, 'Create Microsoft Entra user through Microsoft Graph and apply requested groups/licenses')) {
            $mailNickname = ($upn.Split('@')[0] -replace '[^A-Za-z0-9._-]', '')

            $body = @{
                accountEnabled    = $true
                displayName       = $name
                mailNickname      = $mailNickname
                userPrincipalName = $upn
                passwordProfile   = @{
                    forceChangePasswordNextSignIn = $true
                    password                      = $password
                }
            }

            foreach ($pair in @{
                givenName      = [string]$record.GivenName
                surname        = [string]$record.Surname
                department     = [string]$record.Department
                jobTitle       = [string]$record.JobTitle
                usageLocation  = [string]$record.UsageLocation
                officeLocation = [string]$record.OfficeLocation
            }.GetEnumerator()) {
                if (-not [string]::IsNullOrWhiteSpace($pair.Value)) {
                    $body[$pair.Key] = $pair.Value
                }
            }

            $user = Invoke-HdaGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/users' -Body $body

            foreach ($group in $resolvedGroups) {
                Invoke-HdaGraphRequest `
                    -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/members/`$ref" `
                    -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.id)" } | Out-Null
            }

            if ($resolvedLicenses.Count -gt 0) {
                $addLicenses = @(
                    $resolvedLicenses |
                        ForEach-Object { @{ skuId = [string]$_.skuId } }
                )

                Invoke-HdaGraphRequest `
                    -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)/assignLicense" `
                    -Body @{
                        addLicenses    = $addLicenses
                        removeLicenses = @()
                    } | Out-Null
            }

            Write-HdaAuditEvent `
                -OperationId $operationId `
                -TargetUser $upn `
                -Action 'Employee onboarding' `
                -Status Success `
                -TicketId $recordTicket `
                -Details @{
                    displayName         = $name
                    department          = [string]$record.Department
                    jobTitle            = [string]$record.JobTitle
                    groupsAssigned      = @($resolvedGroups).Count
                    licensesAssigned    = @($resolvedLicenses).Count
                    forcePasswordChange = $true
                } | Out-Null

            Write-Host "Created Entra user: $name <$upn>" -ForegroundColor Green
            Write-Host "Temporary password (displayed once; transfer securely): $password" -ForegroundColor Yellow
        }
    }
    catch {
        try {
            Write-HdaAuditEvent `
                -OperationId $operationId `
                -TargetUser $upn `
                -Action 'Employee onboarding' `
                -Status Failed `
                -TicketId $recordTicket `
                -Details @{ error = $_.Exception.Message } | Out-Null
        }
        catch { }

        throw
    }
}
