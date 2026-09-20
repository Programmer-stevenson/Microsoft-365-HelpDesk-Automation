# Setup guide

This is the full setup path for a clean Windows machine.

## 1. Install PowerShell 7

PowerShell 7 is recommended. Confirm:

```powershell
$PSVersionTable.PSVersion
```

## 2. Open the project

```powershell
cd C:\Path\To\Microsoft-365-HelpDesk-Automation
```

## 3. Install the Graph authentication module

Use the included helper:

```powershell
.\scripts\Install-Prerequisites.ps1
```

Or manually:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

The project intentionally uses `Invoke-MgGraphRequest`, so it only needs the Graph authentication module rather than importing the entire SDK surface.

## 4. Optional quality tools

```powershell
.\scripts\Install-Prerequisites.ps1 -IncludeQualityTools
```

This installs Pester and PSScriptAnalyzer for local quality checks.

## 5. Verify local prerequisites

```powershell
.\scripts\Test-Prerequisites.ps1
```

## 6. Authenticate to Microsoft Graph

```powershell
.\scripts\Test-GraphConnection.ps1
```

To target a specific tenant:

```powershell
.\scripts\Test-GraphConnection.ps1 -TenantId 'YOUR-TENANT-ID'
```

For device-code authentication:

```powershell
.\scripts\Test-GraphConnection.ps1 -UseDeviceCode
```

The first use of a privileged delegated scope can require administrator consent. Your signed-in account also needs an appropriate Microsoft Entra administrative role for the operation.

## 7. Test a read-only support snapshot first

```powershell
.\scripts\Get-UserSupportSnapshot.ps1 `
  -UserId 'user@yourtenant.com' `
  -TicketId 'INC-10001'
```

Optional richer data:

```powershell
.\scripts\Get-UserSupportSnapshot.ps1 `
  -UserId 'user@yourtenant.com' `
  -TicketId 'INC-10001' `
  -IncludeSignInActivity `
  -IncludeIntuneDevices
```

## 8. Test write workflows with `-WhatIf`

Onboarding:

```powershell
.\scripts\New-Employee.ps1 `
  -DisplayName 'Jordan Lee' `
  -UserPrincipalName 'jordan.lee@yourtenant.onmicrosoft.com' `
  -GivenName 'Jordan' `
  -Surname 'Lee' `
  -Department 'Operations' `
  -JobTitle 'Operations Coordinator' `
  -UsageLocation 'US' `
  -TicketId 'REQ-10010' `
  -WhatIf
```

Access reset:

```powershell
.\scripts\Reset-UserAccess.ps1 `
  -UserId 'user@yourtenant.com' `
  -RevokeSessions `
  -TicketId 'INC-10002' `
  -WhatIf
```

Offboarding:

```powershell
.\scripts\Offboard-Employee.ps1 `
  -UserId 'user@yourtenant.com' `
  -TicketId 'CHG-10020' `
  -WhatIf
```

## 9. Generate the HTML report

```powershell
.\scripts\Export-HelpDeskAudit.ps1 `
  -UserId 'user@yourtenant.com' `
  -IncludeSignInActivity `
  -IncludeIntuneDevices
```

Open:

```text
reports\IT-Support-Operations-Report.html
```

## 10. Run local quality checks

```powershell
Invoke-ScriptAnalyzer `
  -Path . `
  -Recurse `
  -Settings .\PSScriptAnalyzerSettings.psd1

Invoke-Pester .\tests
```

## 11. Disconnect when finished

```powershell
Disconnect-MgGraph
```


## Group-based licensing note

The offboarding workflow reads `licenseAssignmentStates` so direct license removal does not incorrectly treat group-inherited licensing as a direct user assignment. Review the assigning groups when inherited licensing remains.
