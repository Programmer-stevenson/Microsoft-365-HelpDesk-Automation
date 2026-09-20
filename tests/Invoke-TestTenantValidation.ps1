<#
.SYNOPSIS
Runs read-only and optional disposable-user integration tests against an authorized Microsoft 365 test tenant.

.DESCRIPTION
The default path is read-only. Pass -RunWriteTests only in a developer/test tenant where you are authorized
and are comfortable creating, resetting, disabling, and optionally de-licensing a disposable test account.
No password or access token is written to the results file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExistingTestUser,
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [switch]$IncludeSignInActivity,
    [switch]$IncludeIntuneDevices,
    [switch]$RunWriteTests,
    [string]$TestDomain,
    [string]$TestGroup,
    [string]$LicenseSkuPartNumber
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'module/HelpDeskAutomation.psm1') -Force
Initialize-HdaDataStore

$resultsDir = Join-Path $PSScriptRoot 'results'
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]
$createdUpn = $null

function Add-IntegrationResult {
    param(
        [Parameter(Mandatory)][string]$Test,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL','SKIP')][string]$Status,
        [string]$Details
    )

    $results.Add([pscustomobject]@{
        test      = $Test
        status    = $Status
        details   = $Details
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    })
}

function Invoke-CheckedStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    try {
        & $Action
        Add-IntegrationResult -Test $Name -Status PASS -Details 'Completed without exception.'
    }
    catch {
        Add-IntegrationResult -Test $Name -Status FAIL -Details $_.Exception.Message
        throw
    }
}

Write-Host '=== Microsoft 365 Help Desk Automation — Test Tenant Validation ===' -ForegroundColor Cyan
Write-Host 'Default mode is read-only. Live write tests require -RunWriteTests.' -ForegroundColor DarkGray
Write-Host ''

try {
    Invoke-CheckedStep -Name 'Graph connection' -Action {
        & (Join-Path $root 'scripts/Test-GraphConnection.ps1') -TenantId $TenantId -UseDeviceCode:$UseDeviceCode
    }

    $snapshotPath = Join-Path $resultsDir 'existing-user-snapshot.json'
    Invoke-CheckedStep -Name 'Read-only support snapshot' -Action {
        & (Join-Path $root 'scripts/Get-UserSupportSnapshot.ps1') `
            -UserId $ExistingTestUser `
            -TicketId 'TEST-READ-001' `
            -OutputPath $snapshotPath `
            -IncludeSignInActivity:$IncludeSignInActivity `
            -IncludeIntuneDevices:$IncludeIntuneDevices `
            -TenantId $TenantId `
            -UseDeviceCode:$UseDeviceCode | Out-Null
    }

    $reportPath = Join-Path $resultsDir 'integration-report.html'
    Invoke-CheckedStep -Name 'HTML operations report' -Action {
        & (Join-Path $root 'scripts/Export-HelpDeskAudit.ps1') `
            -UserId $ExistingTestUser `
            -OutputPath $reportPath `
            -IncludeSignInActivity:$IncludeSignInActivity `
            -IncludeIntuneDevices:$IncludeIntuneDevices `
            -TenantId $TenantId `
            -UseDeviceCode:$UseDeviceCode
    }

    # Exercise all write scripts safely with ShouldProcess before any optional live write test.
    Invoke-CheckedStep -Name 'Password reset WhatIf safety' -Action {
        & (Join-Path $root 'scripts/Reset-UserAccess.ps1') `
            -UserId $ExistingTestUser `
            -RevokeSessions `
            -TicketId 'TEST-WHATIF-RESET' `
            -TenantId $TenantId `
            -UseDeviceCode:$UseDeviceCode `
            -WhatIf
    }

    Invoke-CheckedStep -Name 'Offboarding WhatIf safety' -Action {
        & (Join-Path $root 'scripts/Offboard-Employee.ps1') `
            -UserId $ExistingTestUser `
            -TicketId 'TEST-WHATIF-OFFBOARD' `
            -TenantId $TenantId `
            -UseDeviceCode:$UseDeviceCode `
            -WhatIf
    }

    if (-not $RunWriteTests) {
        Add-IntegrationResult -Test 'Disposable-user live workflow' -Status SKIP -Details 'Run again with -RunWriteTests and -TestDomain in an authorized test tenant.'
    }
    else {
        if ([string]::IsNullOrWhiteSpace($TestDomain)) {
            throw '-TestDomain is required with -RunWriteTests, for example contoso.onmicrosoft.com.'
        }

        $suffix = Get-Date -Format 'yyyyMMddHHmmss'
        $createdUpn = "hda.integration.$suffix@$TestDomain"
        $displayName = "HDA Integration $suffix"

        $newParams = @{
            DisplayName       = $displayName
            UserPrincipalName = $createdUpn
            GivenName         = 'HDA'
            Surname           = "Integration$suffix"
            Department        = 'IT Lab'
            JobTitle          = 'Automation Test User'
            UsageLocation     = 'US'
            OfficeLocation    = 'Test Tenant'
            TicketId          = 'TEST-WRITE-ONBOARD'
            TenantId          = $TenantId
            UseDeviceCode     = $UseDeviceCode
            Confirm           = $false
        }
        if ($TestGroup) { $newParams.Groups = @($TestGroup) }
        if ($LicenseSkuPartNumber) { $newParams.LicenseSkuPartNumbers = @($LicenseSkuPartNumber) }

        Invoke-CheckedStep -Name 'Disposable user onboarding' -Action {
            & (Join-Path $root 'scripts/New-Employee.ps1') @newParams
        }

        Connect-HdaGraph -Scopes @('User.Read.All','GroupMember.Read.All','LicenseAssignment.Read.All') -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null
        $created = Resolve-HdaGraphUser -Identity $createdUpn
        if (-not $created.accountEnabled) { throw 'Created test user exists but accountEnabled is false.' }
        if ($created.department -ne 'IT Lab') { throw "Expected department 'IT Lab'; Graph returned '$($created.department)'." }
        if ($created.jobTitle -ne 'Automation Test User') { throw "Expected job title 'Automation Test User'; Graph returned '$($created.jobTitle)'." }
        Add-IntegrationResult -Test 'Verify created user attributes' -Status PASS -Details "Verified $createdUpn through Microsoft Graph."

        if ($TestGroup) {
            $groupNames = @(Get-HdaGraphUserGroups -UserObjectId ([string]$created.id) | Select-Object -ExpandProperty displayName)
            if ($TestGroup -notin $groupNames) { throw "Test group '$TestGroup' was not found in the created user's direct memberships." }
            Add-IntegrationResult -Test 'Verify group assignment' -Status PASS -Details $TestGroup
        }
        else {
            Add-IntegrationResult -Test 'Verify group assignment' -Status SKIP -Details 'No -TestGroup supplied.'
        }

        if ($LicenseSkuPartNumber) {
            $licenseNames = @(Get-HdaGraphUserLicenses -UserObjectId ([string]$created.id) | Select-Object -ExpandProperty skuPartNumber)
            if ($LicenseSkuPartNumber -notin $licenseNames) { throw "License '$LicenseSkuPartNumber' was not returned for the created user." }
            Add-IntegrationResult -Test 'Verify license assignment' -Status PASS -Details $LicenseSkuPartNumber
        }
        else {
            Add-IntegrationResult -Test 'Verify license assignment' -Status SKIP -Details 'No -LicenseSkuPartNumber supplied.'
        }

        Invoke-CheckedStep -Name 'Disposable user access reset + session revoke' -Action {
            & (Join-Path $root 'scripts/Reset-UserAccess.ps1') `
                -UserId $createdUpn `
                -RevokeSessions `
                -TicketId 'TEST-WRITE-RESET' `
                -TenantId $TenantId `
                -UseDeviceCode:$UseDeviceCode `
                -Confirm:$false
        }

        $offboardParams = @{
            UserId        = $createdUpn
            TicketId      = 'TEST-WRITE-OFFBOARD'
            TenantId      = $TenantId
            UseDeviceCode = $UseDeviceCode
            Confirm       = $false
        }
        if ($TestGroup) { $offboardParams.RemoveDirectGroupMemberships = $true }
        if ($LicenseSkuPartNumber) { $offboardParams.RemoveLicenses = $true }

        Invoke-CheckedStep -Name 'Disposable user offboarding' -Action {
            & (Join-Path $root 'scripts/Offboard-Employee.ps1') @offboardParams
        }

        Connect-HdaGraph -Scopes @('User.Read.All') -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null
        $offboarded = Resolve-HdaGraphUser -Identity $createdUpn
        if ($offboarded.accountEnabled) { throw 'Offboarding completed without exception, but the disposable account is still enabled.' }
        Add-IntegrationResult -Test 'Verify account disabled after offboarding' -Status PASS -Details $createdUpn
    }
}
catch {
    Write-Error $_
}
finally {
    $resultsPath = Join-Path $resultsDir 'test-tenant-results.json'
    $summary = [pscustomobject]@{
        generatedAt       = (Get-Date).ToUniversalTime().ToString('o')
        tenantId          = $TenantId
        existingTestUser  = $ExistingTestUser
        disposableTestUpn = $createdUpn
        writeTestsEnabled = [bool]$RunWriteTests
        passed            = @($results | Where-Object status -eq 'PASS').Count
        failed            = @($results | Where-Object status -eq 'FAIL').Count
        skipped           = @($results | Where-Object status -eq 'SKIP').Count
        results           = @($results)
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $resultsPath -Encoding UTF8

    Write-Host ''
    $results | Format-Table test, status, details -AutoSize
    Write-Host "Results written to: $resultsPath" -ForegroundColor Cyan

    if (@($results | Where-Object status -eq 'FAIL').Count -gt 0) {
        throw 'One or more integration tests failed. Review the results file and output above.'
    }
}
