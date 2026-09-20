BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:OperationalScripts = @(
        'New-Employee.ps1',
        'Offboard-Employee.ps1',
        'Get-UserSupportSnapshot.ps1',
        'Reset-UserAccess.ps1',
        'Export-HelpDeskAudit.ps1',
        'Test-GraphConnection.ps1'
    )
}

Describe 'PowerShell syntax' {
    $files = @(
        Get-ChildItem (Join-Path $script:Root 'scripts') -Filter '*.ps1' -File
        Get-ChildItem (Join-Path $script:Root 'module') -Include '*.psm1','*.psd1' -File
        Get-ChildItem (Join-Path $script:Root 'tests') -Filter '*.ps1' -File |
            Where-Object Name -ne 'SyntaxAndContracts.Tests.ps1'
    )

    foreach ($file in $files) {
        It "parses $($file.Name) without PowerShell parser errors" {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
        }
    }
}

Describe 'Graph-only repository contracts' {
    foreach ($name in $script:OperationalScripts) {
        It "$name authenticates through the shared Microsoft Graph connection helper" {
            $content = Get-Content (Join-Path $script:Root "scripts/$name") -Raw
            $content | Should -Match 'Connect-HdaGraph'
        }

        It "$name does not contain a fake/demo tenant execution switch" {
            $content = Get-Content (Join-Path $script:Root "scripts/$name") -Raw
            $content | Should -Not -Match '(?i)DemoMode|UseDemoTenant|sample-users\.json|fake tenant'
        }
    }

    foreach ($name in @('New-Employee.ps1','Offboard-Employee.ps1','Reset-UserAccess.ps1')) {
        It "$name implements ShouldProcess safety" {
            $content = Get-Content (Join-Path $script:Root "scripts/$name") -Raw
            $content | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
            $content | Should -Match '\$PSCmdlet\.ShouldProcess\('
        }
    }

    It 'the onboarding workflow calls Graph users, group members, and assignLicense endpoints' {
        $content = Get-Content (Join-Path $script:Root 'scripts/New-Employee.ps1') -Raw
        $content | Should -Match "graph\.microsoft\.com/v1\.0/users'"
        $content | Should -Match '/groups/\$\(\$group\.id\)/members/'
        $content | Should -Match '/assignLicense'
    }

    It 'the offboarding workflow disables the account and revokes sign-in sessions' {
        $content = Get-Content (Join-Path $script:Root 'scripts/Offboard-Employee.ps1') -Raw
        $content | Should -Match 'accountEnabled\s*=\s*\$false'
        $content | Should -Match '/revokeSignInSessions'
    }

    It 'the access recovery workflow resets passwordProfile and supports session revocation' {
        $content = Get-Content (Join-Path $script:Root 'scripts/Reset-UserAccess.ps1') -Raw
        $content | Should -Match 'passwordProfile'
        $content | Should -Match 'forceChangePasswordNextSignIn'
        $content | Should -Match '/revokeSignInSessions'
    }

    It 'the snapshot workflow can request sign-in and Intune data' {
        $content = Get-Content (Join-Path $script:Root 'scripts/Get-UserSupportSnapshot.ps1') -Raw
        $content | Should -Match 'AuditLog\.Read\.All'
        $content | Should -Match 'DeviceManagementManagedDevices\.Read\.All'
    }
}

Describe 'Repository safety' {
    It 'ignores tenant-derived audit, snapshot, offboarding, report, and private CSV output' {
        $ignore = Get-Content (Join-Path $script:Root '.gitignore') -Raw
        $ignore | Should -Match 'audit-log\.jsonl'
        $ignore | Should -Match 'data/snapshots'
        $ignore | Should -Match 'data/offboarding'
        $ignore | Should -Match 'reports/'
        $ignore | Should -Match '\*\.private\.csv'
    }

    It 'does not log temporary passwords in audit detail payloads' {
        $content = Get-Content (Join-Path $script:Root 'scripts/New-Employee.ps1') -Raw
        $auditBlock = ($content -split 'Write-HdaAuditEvent', 2)[1]
        $auditBlock | Should -Not -Match '(?i)temporaryPassword\s*='
    }
}
