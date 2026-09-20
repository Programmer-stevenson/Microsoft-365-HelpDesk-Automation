BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../module/HelpDeskAutomation.psm1'
    Import-Module $modulePath -Force
}

Describe 'HelpDeskAutomation shared module' {
    It 'creates an operation ID with the expected prefix' {
        $id = New-HdaOperationId
        $id | Should -Match '^HDA-\d{8}-\d{6}-\d{4}$'
    }

    It 'generates a temporary password at the requested length' {
        $password = New-HdaTemporaryPassword -Length 20
        $password.Length | Should -Be 20
    }

    It 'generates a password containing upper, lower, number and symbol characters' {
        $password = New-HdaTemporaryPassword -Length 24
        $password | Should -Match '[A-Z]'
        $password | Should -Match '[a-z]'
        $password | Should -Match '[0-9]'
        $password | Should -Match '[!@#$%*\-_+]'
    }

    It 'does not return the same generated password repeatedly' {
        $a = New-HdaTemporaryPassword
        $b = New-HdaTemporaryPassword
        $a | Should -Not -Be $b
    }
}
