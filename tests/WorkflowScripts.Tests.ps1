BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:Root 'module/HelpDeskAutomation.psm1') -Force

    $script:FakeUser = [pscustomobject]@{
        id                         = '11111111-1111-1111-1111-111111111111'
        displayName                = 'Jordan Lee'
        givenName                  = 'Jordan'
        surname                    = 'Lee'
        userPrincipalName          = 'jordan.lee@contoso.onmicrosoft.com'
        mail                       = 'jordan.lee@contoso.onmicrosoft.com'
        department                 = 'IT Lab'
        jobTitle                   = 'Automation Test User'
        officeLocation             = 'Lab'
        usageLocation              = 'US'
        accountEnabled             = $true
        createdDateTime            = '2026-09-13T20:00:00Z'
        lastPasswordChangeDateTime = '2026-09-13T20:00:00Z'
        licenseAssignmentStates    = @(
            [pscustomobject]@{ skuId = 'sku-1'; assignedByGroup = $null; state = 'Active' },
            [pscustomobject]@{ skuId = 'sku-group'; assignedByGroup = 'licensing-group-1'; state = 'Active' }
        )
    }

    $script:FakeSnapshot = [pscustomobject]@{
        generatedAt        = '2026-09-13T20:00:00Z'
        source             = 'Microsoft Graph'
        tenantId           = '22222222-2222-2222-2222-222222222222'
        authenticatedAs    = 'admin@contoso.onmicrosoft.com'
        user               = $script:FakeUser
        manager            = [pscustomobject]@{ displayName = 'Alex Morgan'; userPrincipalName = 'alex@contoso.onmicrosoft.com' }
        groups             = @([pscustomobject]@{ id = 'g1'; displayName = 'All Employees' })
        licenses           = @([pscustomobject]@{ skuId = '33333333-3333-3333-3333-333333333333'; skuPartNumber = 'O365_BUSINESS_PREMIUM' })
        registeredDevices  = @([pscustomobject]@{ displayName = 'LT-JLEE-01'; operatingSystem = 'Windows'; operatingSystemVersion = '11'; trustType = 'AzureAd'; approximateLastSignInDateTime = '2026-09-13T19:00:00Z' })
        managedDevices     = @([pscustomobject]@{ deviceName = 'LT-JLEE-01'; operatingSystem = 'Windows'; osVersion = '11'; complianceState = 'compliant'; lastSyncDateTime = '2026-09-13T19:30:00Z' })
        lastSignInDateTime = '2026-09-13T19:00:00Z'
        notes              = @()
    }
}

BeforeEach {
    Mock Import-Module { }
    Mock Initialize-HdaDataStore { }
    Mock New-HdaOperationId { 'HDA-20260913-200000-1234' }
    Mock Connect-HdaGraph { [pscustomobject]@{ Account = 'admin@contoso.onmicrosoft.com'; TenantId = 'tenant-id' } }
    Mock Write-HdaAuditEvent { [pscustomobject]@{ status = $Status; action = $Action } }
}

Describe 'New-Employee.ps1' {
    It 'creates a user, adds the requested group, assigns the requested license, and audits success' {
        Mock Resolve-HdaGraphGroup { [pscustomobject]@{ id = 'group-1'; displayName = $Identity } }
        Mock Resolve-HdaLicenseSku { [pscustomobject]@{ skuId = 'sku-1'; skuPartNumber = $Identity } }
        Mock Invoke-HdaGraphRequest {
            param($Method, $Uri, $Body, $Headers)
            if ($Method -eq 'POST' -and $Uri -eq 'https://graph.microsoft.com/v1.0/users') {
                return [pscustomobject]@{ id = 'new-user-1'; userPrincipalName = 'jordan.lee@contoso.onmicrosoft.com' }
            }
            return [pscustomobject]@{}
        }

        & (Join-Path $script:Root 'scripts/New-Employee.ps1') `
            -DisplayName 'Jordan Lee' `
            -UserPrincipalName 'jordan.lee@contoso.onmicrosoft.com' `
            -GivenName 'Jordan' `
            -Surname 'Lee' `
            -Department 'IT Lab' `
            -JobTitle 'Automation Test User' `
            -UsageLocation 'US' `
            -Groups 'All Employees' `
            -LicenseSkuPartNumbers 'O365_BUSINESS_PREMIUM' `
            -TemporaryPassword 'Correct-Horse-9!Battery' `
            -Confirm:$false

        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'https://graph.microsoft.com/v1.0/users'
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*/groups/group-1/members/*'
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*/users/new-user-1/assignLicense'
        }
        Should -Invoke Write-HdaAuditEvent -Times 1 -ParameterFilter {
            $Action -eq 'Employee onboarding' -and $Status -eq 'Success'
        }
    }

    It 'does not perform Graph writes when -WhatIf is used' {
        Mock Resolve-HdaGraphGroup { [pscustomobject]@{ id = 'group-1'; displayName = $Identity } }
        Mock Invoke-HdaGraphRequest { throw 'Graph write should not run under WhatIf.' }

        & (Join-Path $script:Root 'scripts/New-Employee.ps1') `
            -DisplayName 'Jordan Lee' `
            -UserPrincipalName 'jordan.lee@contoso.onmicrosoft.com' `
            -Groups 'All Employees' `
            -WhatIf

        Should -Invoke Invoke-HdaGraphRequest -Times 0
        Should -Invoke Write-HdaAuditEvent -Times 0
    }

    It 'requires UsageLocation when a license is requested' {
        Mock Resolve-HdaLicenseSku { [pscustomobject]@{ skuId = 'sku-1'; skuPartNumber = $Identity } }

        {
            & (Join-Path $script:Root 'scripts/New-Employee.ps1') `
                -DisplayName 'Jordan Lee' `
                -UserPrincipalName 'jordan.lee@contoso.onmicrosoft.com' `
                -LicenseSkuPartNumbers 'O365_BUSINESS_PREMIUM' `
                -WhatIf
        } | Should -Throw '*UsageLocation is required*'
    }
}

Describe 'Get-UserSupportSnapshot.ps1' {
    It 'writes the Graph snapshot to JSON and records an audit event' {
        $out = Join-Path $TestDrive 'snapshot.json'
        Mock Get-HdaGraphUserSnapshot { $script:FakeSnapshot }

        $result = & (Join-Path $script:Root 'scripts/Get-UserSupportSnapshot.ps1') `
            -UserId 'jordan.lee@contoso.onmicrosoft.com' `
            -OutputPath $out `
            -IncludeSignInActivity `
            -IncludeIntuneDevices

        Test-Path $out | Should -BeTrue
        (Get-Content $out -Raw | ConvertFrom-Json).source | Should -Be 'Microsoft Graph'
        $result.user.userPrincipalName | Should -Be 'jordan.lee@contoso.onmicrosoft.com'
        Should -Invoke Get-HdaGraphUserSnapshot -Times 1 -ParameterFilter {
            $Identity -eq 'jordan.lee@contoso.onmicrosoft.com' -and $IncludeSignInActivity -and $IncludeIntuneDevices
        }
        Should -Invoke Write-HdaAuditEvent -Times 1 -ParameterFilter {
            $Action -eq 'User support snapshot' -and $Status -eq 'Success'
        }
    }
}

Describe 'Reset-UserAccess.ps1' {
    It 'resets the password, enables a disabled account, revokes sessions, and audits success' {
        $disabled = $script:FakeUser.PSObject.Copy()
        $disabled.accountEnabled = $false
        Mock Resolve-HdaGraphUser { $disabled }
        Mock Invoke-HdaGraphRequest { [pscustomobject]@{} }

        & (Join-Path $script:Root 'scripts/Reset-UserAccess.ps1') `
            -UserId $disabled.userPrincipalName `
            -NewTemporaryPassword 'Correct-Horse-9!Battery' `
            -EnableAccount `
            -RevokeSessions `
            -Confirm:$false

        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*/users/*' -and $Body.passwordProfile
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*/users/*' -and $Body.ContainsKey('accountEnabled') -and $Body.accountEnabled
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*/revokeSignInSessions'
        }
        Should -Invoke Write-HdaAuditEvent -Times 1 -ParameterFilter {
            $Action -eq 'Access recovery / password reset' -and $Status -eq 'Success'
        }
    }

    It 'does not mutate Graph when -WhatIf is used' {
        Mock Resolve-HdaGraphUser { $script:FakeUser }
        Mock Invoke-HdaGraphRequest { throw 'Graph write should not run under WhatIf.' }

        & (Join-Path $script:Root 'scripts/Reset-UserAccess.ps1') `
            -UserId $script:FakeUser.userPrincipalName `
            -NewTemporaryPassword 'Correct-Horse-9!Battery' `
            -RevokeSessions `
            -WhatIf

        Should -Invoke Invoke-HdaGraphRequest -Times 0
        Should -Invoke Write-HdaAuditEvent -Times 0
    }
}

Describe 'Offboard-Employee.ps1' {
    BeforeEach {
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'data/offboarding') -Force | Out-Null
        Mock Get-HdaProjectRoot { $TestDrive }
        Mock Resolve-HdaGraphUser { $script:FakeUser }
        Mock Get-HdaGraphUserGroups { @([pscustomobject]@{ id = 'group-1'; displayName = 'All Employees' }) }
        Mock Get-HdaGraphUserLicenses {
            @(
                [pscustomobject]@{ skuId = 'sku-1'; skuPartNumber = 'O365_BUSINESS_PREMIUM' },
                [pscustomobject]@{ skuId = 'sku-group'; skuPartNumber = 'ENTERPRISEPACK' }
            )
        }
    }

    It 'captures evidence, disables the account, revokes sessions, removes requested access, and audits success' {
        Mock Invoke-HdaGraphRequest { [pscustomobject]@{} }

        & (Join-Path $script:Root 'scripts/Offboard-Employee.ps1') `
            -UserId $script:FakeUser.userPrincipalName `
            -RemoveDirectGroupMemberships `
            -RemoveLicenses `
            -Confirm:$false

        (Get-ChildItem (Join-Path $TestDrive 'data/offboarding') -Filter '*-preoffboarding.json').Count | Should -Be 1
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.ContainsKey('accountEnabled') -and -not $Body.accountEnabled
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*/revokeSignInSessions'
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*/groups/group-1/members/*'
        }
        Should -Invoke Invoke-HdaGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -like '*/assignLicense' -and
            @($Body.removeLicenses).Count -eq 1 -and
            @($Body.removeLicenses)[0] -eq 'sku-1'
        }
        Should -Invoke Write-HdaAuditEvent -Times 1 -ParameterFilter {
            $Action -eq 'Employee offboarding' -and $Status -eq 'Success'
        }
    }

    It 'captures pre-offboarding evidence but makes no tenant changes under -WhatIf' {
        Mock Invoke-HdaGraphRequest { throw 'Graph write should not run under WhatIf.' }

        & (Join-Path $script:Root 'scripts/Offboard-Employee.ps1') `
            -UserId $script:FakeUser.userPrincipalName `
            -RemoveDirectGroupMemberships `
            -RemoveLicenses `
            -WhatIf

        (Get-ChildItem (Join-Path $TestDrive 'data/offboarding') -Filter '*-preoffboarding.json').Count | Should -Be 1
        Should -Invoke Invoke-HdaGraphRequest -Times 0
        Should -Invoke Write-HdaAuditEvent -Times 0
    }
}

Describe 'Export-HelpDeskAudit.ps1' {
    It 'renders a populated HTML report from mocked Graph and audit data' {
        $output = Join-Path $TestDrive 'report.html'
        Mock Invoke-HdaGraphRequest {
            [pscustomobject]@{ id = 'me-1'; displayName = 'Admin User'; userPrincipalName = 'admin@contoso.onmicrosoft.com' }
        }
        Mock Get-HdaGraphOrganization {
            [pscustomobject]@{
                id = 'tenant-id'
                displayName = 'Contoso Lab'
                verifiedDomains = @([pscustomobject]@{ name = 'contoso.onmicrosoft.com'; isVerified = $true })
            }
        }
        Mock Get-HdaAuditEvents {
            @([pscustomobject]@{
                timestamp  = '2026-09-13T20:00:00Z'
                targetUser = 'jordan.lee@contoso.onmicrosoft.com'
                action     = 'User support snapshot'
                status     = 'Success'
                ticketId   = 'INC-10001'
                details    = [pscustomobject]@{ groupCount = 1; licenseCount = 1 }
            })
        }
        Mock Get-HdaGraphUserSnapshot { $script:FakeSnapshot }

        & (Join-Path $script:Root 'scripts/Export-HelpDeskAudit.ps1') `
            -UserId $script:FakeUser.userPrincipalName `
            -OutputPath $output `
            -IncludeSignInActivity `
            -IncludeIntuneDevices

        Test-Path $output | Should -BeTrue
        $html = Get-Content $output -Raw
        $html | Should -Match 'IT Support Operations Report'
        $html | Should -Match 'Contoso Lab'
        $html | Should -Match 'Jordan Lee'
        $html | Should -Match 'LT-JLEE-01'
        $html | Should -Match 'INC-10001'
        $html | Should -Not -Match '__[A-Z_]+__'
    }
}
