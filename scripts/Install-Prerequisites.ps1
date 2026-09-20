[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',
    [switch]$IncludeQualityTools
)

$ErrorActionPreference = 'Stop'

$modules = @('Microsoft.Graph.Authentication')
if ($IncludeQualityTools) {
    $modules += @('Pester', 'PSScriptAnalyzer')
}

foreach ($module in $modules) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host "$module is already installed." -ForegroundColor DarkGray
        continue
    }

    if ($PSCmdlet.ShouldProcess($module, "Install PowerShell module for $Scope")) {
        Install-Module -Name $module -Scope $Scope -Repository PSGallery -Force -AllowClobber
        Write-Host "Installed $module." -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Prerequisite installation complete.' -ForegroundColor Green
Write-Host 'Next: .\scripts\Test-GraphConnection.ps1' -ForegroundColor Cyan
