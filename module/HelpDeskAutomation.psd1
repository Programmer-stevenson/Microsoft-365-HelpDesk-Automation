@{
    RootModule        = 'HelpDeskAutomation.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7fb40c5d-4f81-4a78-98ee-9a81c9d58a70'
    Author            = 'Brandon Stevenson'
    CompanyName       = 'Community / Portfolio Project'
    Copyright         = '(c) 2026 Brandon Stevenson. MIT License.'
    Description       = 'Shared helpers for a Microsoft Graph-backed Microsoft 365 help desk automation toolkit.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('MicrosoftGraph', 'Microsoft365', 'EntraID', 'Intune', 'HelpDesk', 'Automation')
            ProjectUri = 'https://github.com/Programmer-stevenson/Microsoft-365-HelpDesk-Automation'
            LicenseUri = 'https://opensource.org/license/mit'
        }
    }
}
