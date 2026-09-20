[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$UserId,
    [string]$NewTemporaryPassword,
    [string]$TicketId = 'INC-UNSPECIFIED',
    [switch]$RevokeSessions,
    [switch]$EnableAccount,
    [switch]$NoForceChangePassword,
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../module/HelpDeskAutomation.psm1') -Force
Initialize-HdaDataStore

$operationId = New-HdaOperationId
$password = if ($NewTemporaryPassword) { $NewTemporaryPassword } else { New-HdaTemporaryPassword }
$forceChange = -not $NoForceChangePassword

$scopes = @(
    'User.Read.All',
    'User-PasswordProfile.ReadWrite.All'
)

if ($RevokeSessions) {
    $scopes += 'User.RevokeSessions.All'
}

if ($EnableAccount) {
    $scopes += 'User.EnableDisableAccount.All'
}

Connect-HdaGraph -Scopes $scopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null

try {
    $user = Resolve-HdaGraphUser -Identity $UserId
    $uid = [string]$user.id

    if ($PSCmdlet.ShouldProcess($user.userPrincipalName, 'Reset password and apply selected access-recovery actions through Microsoft Graph')) {
        Invoke-HdaGraphRequest `
            -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/users/$uid" `
            -Body @{
                passwordProfile = @{
                    password                      = $password
                    forceChangePasswordNextSignIn = $forceChange
                }
            } | Out-Null

        if ($EnableAccount -and -not $user.accountEnabled) {
            Invoke-HdaGraphRequest `
                -Method PATCH `
                -Uri "https://graph.microsoft.com/v1.0/users/$uid" `
                -Body @{ accountEnabled = $true } | Out-Null
        }

        if ($RevokeSessions) {
            Invoke-HdaGraphRequest `
                -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/users/$uid/revokeSignInSessions" | Out-Null
        }

        Write-HdaAuditEvent `
            -OperationId $operationId `
            -TargetUser $user.userPrincipalName `
            -Action 'Access recovery / password reset' `
            -Status Success `
            -TicketId $TicketId `
            -Details @{
                passwordReset       = $true
                forceChangePassword = $forceChange
                sessionsRevoked     = [bool]$RevokeSessions
                accountEnabled      = [bool]$EnableAccount
            } | Out-Null

        Write-Host "Access recovery completed for $($user.userPrincipalName)." -ForegroundColor Green
        Write-Host "Temporary password (displayed once; transfer securely): $password" -ForegroundColor Yellow
    }
}
catch {
    try {
        Write-HdaAuditEvent `
            -OperationId $operationId `
            -TargetUser $UserId `
            -Action 'Access recovery / password reset' `
            -Status Failed `
            -TicketId $TicketId `
            -Details @{ error = $_.Exception.Message } | Out-Null
    }
    catch { }

    throw
}
