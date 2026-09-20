[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserId,
    [string]$TicketId = 'INC-UNSPECIFIED',
    [string]$OutputPath,
    [switch]$IncludeSignInActivity,
    [switch]$IncludeIntuneDevices,
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
    'Device.Read.All'
)

if ($IncludeSignInActivity) {
    $scopes += 'AuditLog.Read.All'
}

if ($IncludeIntuneDevices) {
    $scopes += 'DeviceManagementManagedDevices.Read.All'
}

Connect-HdaGraph -Scopes $scopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null

try {
    $snapshot = Get-HdaGraphUserSnapshot `
        -Identity $UserId `
        -IncludeSignInActivity:$IncludeSignInActivity `
        -IncludeIntuneDevices:$IncludeIntuneDevices

    if (-not $OutputPath) {
        $safeName = ($snapshot.user.userPrincipalName -replace '[^A-Za-z0-9._-]', '_')
        $OutputPath = Join-Path (Get-HdaProjectRoot) "data/snapshots/$safeName.json"
    }

    $snapshot | ConvertTo-Json -Depth 30 | Set-Content -Path $OutputPath -Encoding UTF8

    Write-HdaAuditEvent `
        -OperationId $operationId `
        -TargetUser $snapshot.user.userPrincipalName `
        -Action 'User support snapshot' `
        -Status Success `
        -TicketId $TicketId `
        -Details @{
            accountEnabled        = $snapshot.user.accountEnabled
            groupCount            = @($snapshot.groups).Count
            licenseCount          = @($snapshot.licenses).Count
            registeredDeviceCount = @($snapshot.registeredDevices).Count
            managedDeviceCount    = @($snapshot.managedDevices).Count
            signInIncluded        = [bool]$IncludeSignInActivity
            intuneIncluded        = [bool]$IncludeIntuneDevices
            outputPath            = $OutputPath
        } | Out-Null

    Write-Host "Microsoft Graph support snapshot written to: $OutputPath" -ForegroundColor Green
    $snapshot
}
catch {
    try {
        Write-HdaAuditEvent `
            -OperationId $operationId `
            -TargetUser $UserId `
            -Action 'User support snapshot' `
            -Status Failed `
            -TicketId $TicketId `
            -Details @{ error = $_.Exception.Message } | Out-Null
    }
    catch { }

    throw
}
