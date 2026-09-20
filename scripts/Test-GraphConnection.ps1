[CmdletBinding()]
param(
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../module/HelpDeskAutomation.psm1') -Force

$scopes = @(
    'User.Read',
    'Organization.Read.All',
    'LicenseAssignment.Read.All'
)

$context = Connect-HdaGraph -Scopes $scopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode

$me = Invoke-HdaGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
$org = Get-HdaGraphOrganization
$skus = @(Invoke-HdaGraphCollection -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuId,skuPartNumber,consumedUnits,capabilityStatus,prepaidUnits')

Write-Host ''
Write-Host 'Microsoft Graph connection successful.' -ForegroundColor Green
Write-Host "Signed in as : $($me.userPrincipalName)"
Write-Host "Tenant       : $($org.displayName)"
Write-Host "Tenant ID    : $($context.TenantId)"
Write-Host ''
Write-Host 'Available license SKUs:' -ForegroundColor Cyan

$skus |
    Sort-Object skuPartNumber |
    Select-Object skuPartNumber, skuId, consumedUnits, capabilityStatus |
    Format-Table -AutoSize
