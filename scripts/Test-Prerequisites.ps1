[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[object]

$results.Add([pscustomobject]@{
    Check = 'PowerShell 7+'
    Status = if ($PSVersionTable.PSVersion.Major -ge 7) { 'PASS' } else { 'WARN' }
    Details = [string]$PSVersionTable.PSVersion
})

$graph = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Sort-Object Version -Descending | Select-Object -First 1
$results.Add([pscustomobject]@{
    Check = 'Microsoft.Graph.Authentication'
    Status = if ($graph) { 'PASS' } else { 'FAIL' }
    Details = if ($graph) { "v$($graph.Version)" } else { 'Not installed' }
})

$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
$results.Add([pscustomobject]@{
    Check = 'PSScriptAnalyzer (optional)'
    Status = if ($analyzer) { 'PASS' } else { 'INFO' }
    Details = if ($analyzer) { "v$($analyzer.Version)" } else { 'Install for local linting' }
})

$pester = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
$results.Add([pscustomobject]@{
    Check = 'Pester 5+ (optional)'
    Status = if ($pester -and $pester.Version.Major -ge 5) { 'PASS' } else { 'INFO' }
    Details = if ($pester) { "v$($pester.Version)" } else { 'Install for local tests' }
})

$results | Format-Table -AutoSize

if ($results.Status -contains 'FAIL') {
    throw 'One or more required prerequisites are missing. Run .\scripts\Install-Prerequisites.ps1'
}
