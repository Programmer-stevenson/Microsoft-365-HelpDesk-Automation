[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$UserId,
    [string]$TicketId = 'CHG-UNSPECIFIED',
    [switch]$RemoveDirectGroupMemberships,
    [switch]$RemoveLicenses,
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../module/HelpDeskAutomation.psm1') -Force
Initialize-HdaDataStore

$operationId = New-HdaOperationId

$scopes = @(
    'User.Read.All',
    'GroupMember.Read.All',
    'LicenseAssignment.Read.All',
    'User.EnableDisableAccount.All',
    'User.RevokeSessions.All'
)

if ($RemoveDirectGroupMemberships) {
    $scopes += 'GroupMember.ReadWrite.All'
}

if ($RemoveLicenses) {
    $scopes += 'LicenseAssignment.ReadWrite.All'
}

Connect-HdaGraph -Scopes $scopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null

try {
    $user = Resolve-HdaGraphUser -Identity $UserId
    $uid = [string]$user.id
    $groups = @(Get-HdaGraphUserGroups -UserObjectId $uid)
    $licenses = @(Get-HdaGraphUserLicenses -UserObjectId $uid)

    $evidenceDir = Join-Path (Get-HdaProjectRoot) 'data/offboarding'
    $safeName = ($user.userPrincipalName -replace '[^A-Za-z0-9._-]', '_')
    $evidencePath = Join-Path $evidenceDir "$safeName-preoffboarding.json"

    [pscustomobject]@{
        exportedAt = (Get-Date).ToUniversalTime().ToString('o')
        source     = 'Microsoft Graph'
        user       = $user
        groups     = $groups
        licenses   = $licenses
    } |
        ConvertTo-Json -Depth 30 |
        Set-Content -Path $evidencePath -Encoding UTF8

    if ($PSCmdlet.ShouldProcess($user.userPrincipalName, 'Disable account, revoke sign-in sessions, and apply selected cleanup actions through Microsoft Graph')) {
        Invoke-HdaGraphRequest `
            -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/users/$uid" `
            -Body @{ accountEnabled = $false } | Out-Null

        Invoke-HdaGraphRequest `
            -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/users/$uid/revokeSignInSessions" | Out-Null

        $removedGroups = 0
        $groupWarnings = New-Object System.Collections.Generic.List[string]

        if ($RemoveDirectGroupMemberships) {
            foreach ($group in $groups) {
                try {
                    Invoke-HdaGraphRequest `
                        -Method DELETE `
                        -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/members/$uid/`$ref" | Out-Null

                    $removedGroups++
                }
                catch {
                    $groupWarnings.Add("$($group.displayName): $($_.Exception.Message)")
                }
            }
        }

        $removedLicenses = 0
        $directLicenseSkuIds = @(
            @($user.licenseAssignmentStates) |
                Where-Object { -not $_.assignedByGroup -and $_.state -in @('Active', 'ActiveWithError') } |
                ForEach-Object { [string]$_.skuId } |
                Sort-Object -Unique
        )
        $groupBasedLicenseAssignments = @(
            @($user.licenseAssignmentStates) |
                Where-Object { $_.assignedByGroup } |
                Select-Object skuId, assignedByGroup, state
        )

        if ($RemoveLicenses -and $directLicenseSkuIds.Count -gt 0) {
            Invoke-HdaGraphRequest `
                -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/users/$uid/assignLicense" `
                -Body @{
                    addLicenses    = @()
                    removeLicenses = $directLicenseSkuIds
                } | Out-Null

            $removedLicenses = $directLicenseSkuIds.Count
        }

        if ($RemoveLicenses -and $groupBasedLicenseAssignments.Count -gt 0) {
            Write-Warning "$($groupBasedLicenseAssignments.Count) license assignment(s) are inherited from groups and cannot be removed as direct user licenses. Review group memberships if those entitlements must be removed."
        }

        $status = if ($groupWarnings.Count -gt 0) { 'Warning' } else { 'Success' }

        Write-HdaAuditEvent `
            -OperationId $operationId `
            -TargetUser $user.userPrincipalName `
            -Action 'Employee offboarding' `
            -Status $status `
            -TicketId $TicketId `
            -Details @{
                accountDisabled        = $true
                sessionsRevoked        = $true
                preOffboardingGroups   = $groups.Count
                preOffboardingLicenses = $licenses.Count
                groupsRemoved          = $removedGroups
                directLicensesRemoved  = $removedLicenses
                groupBasedLicenses     = $groupBasedLicenseAssignments.Count
                groupRemovalWarnings   = @($groupWarnings)
                evidencePath           = $evidencePath
            } | Out-Null

        Write-Host "Offboarded $($user.displayName) <$($user.userPrincipalName)>" -ForegroundColor Green
        Write-Host "Pre-offboarding evidence: $evidencePath" -ForegroundColor Cyan

        if ($groupWarnings.Count -gt 0) {
            Write-Warning 'One or more group memberships could not be removed. Dynamic, role-assignable, or otherwise protected groups can require different handling.'
            $groupWarnings | ForEach-Object { Write-Warning $_ }
        }
    }
}
catch {
    try {
        Write-HdaAuditEvent `
            -OperationId $operationId `
            -TargetUser $UserId `
            -Action 'Employee offboarding' `
            -Status Failed `
            -TicketId $TicketId `
            -Details @{ error = $_.Exception.Message } | Out-Null
    }
    catch { }

    throw
}
