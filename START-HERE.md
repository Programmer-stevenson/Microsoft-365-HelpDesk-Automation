# Start here

This repository is a **Microsoft Graph-backed Microsoft 365 / Entra ID help-desk automation portfolio project**. The operational scripts are not a fake tenant simulator: they authenticate to the tenant you sign in to.

Use an **authorized developer/test Microsoft 365 tenant** for write testing. Do not point the write workflows at an employer/customer production tenant unless you have explicit approval.

## What is included

- `New-Employee.ps1` — create a user, set core attributes, add direct groups, assign direct licenses
- `Offboard-Employee.ps1` — export pre-change evidence, disable account, revoke sessions, optionally remove direct groups and direct licenses
- `Get-UserSupportSnapshot.ps1` — identity, manager, groups, licensing, Entra devices, optional Intune devices/sign-in activity
- `Reset-UserAccess.ps1` — reset password, force change at next sign-in, optionally enable account and revoke sessions
- `Export-HelpDeskAudit.ps1` — generate the polished HTML operations report
- shared PowerShell module for Graph authentication, paging, lookups, snapshots, audit logging, and password generation
- Pester unit/workflow tests and PowerShell AST syntax tests
- real test-tenant integration runner
- PSScriptAnalyzer configuration and GitHub Actions workflow
- sanitized architecture/report-preview assets
- setup, permissions, troubleshooting, security, portfolio, and demo documentation

## First 15 minutes

Open PowerShell 7 in the repository root:

```powershell
.\scripts\Install-Prerequisites.ps1 -IncludeQualityTools
.\scripts\Test-Prerequisites.ps1
python .\tests\run-local-validation.py
Invoke-Pester .\tests -Output Detailed
```

Then verify Graph authentication:

```powershell
.\scripts\Test-GraphConnection.ps1 -TenantId 'YOUR-TENANT-ID'
```

## First Graph test — read only

Use a safe test account:

```powershell
.\scripts\Get-UserSupportSnapshot.ps1 `
  -UserId 'test.user@yourtenant.onmicrosoft.com' `
  -TicketId 'INC-LAB-001' `
  -TenantId 'YOUR-TENANT-ID'
```

If your tenant supports it:

```powershell
.\scripts\Get-UserSupportSnapshot.ps1 `
  -UserId 'test.user@yourtenant.onmicrosoft.com' `
  -TicketId 'INC-LAB-002' `
  -TenantId 'YOUR-TENANT-ID' `
  -IncludeSignInActivity `
  -IncludeIntuneDevices
```

## Test every write workflow safely first

```powershell
.\scripts\Reset-UserAccess.ps1 `
  -UserId 'test.user@yourtenant.onmicrosoft.com' `
  -RevokeSessions `
  -TenantId 'YOUR-TENANT-ID' `
  -WhatIf
```

```powershell
.\scripts\Offboard-Employee.ps1 `
  -UserId 'test.user@yourtenant.onmicrosoft.com' `
  -RemoveDirectGroupMemberships `
  -RemoveLicenses `
  -TenantId 'YOUR-TENANT-ID' `
  -WhatIf
```

```powershell
.\scripts\New-Employee.ps1 `
  -DisplayName 'Jordan Lee' `
  -UserPrincipalName 'jordan.lee@yourtenant.onmicrosoft.com' `
  -GivenName 'Jordan' `
  -Surname 'Lee' `
  -Department 'IT Lab' `
  -JobTitle 'Automation Test User' `
  -UsageLocation 'US' `
  -TenantId 'YOUR-TENANT-ID' `
  -WhatIf
```

## Recommended real test-tenant validation

Read-only + WhatIf validation:

```powershell
.\tests\Invoke-TestTenantValidation.ps1 `
  -ExistingTestUser 'test.user@yourtenant.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID'
```

Complete disposable-user lifecycle in a developer/test tenant:

```powershell
.\tests\Invoke-TestTenantValidation.ps1 `
  -ExistingTestUser 'test.user@yourtenant.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID' `
  -RunWriteTests `
  -TestDomain 'yourtenant.onmicrosoft.com'
```

Add `-TestGroup` and `-LicenseSkuPartNumber` if you also want the integration runner to verify group and license operations.

## Generate the HTML report

After running some workflows:

```powershell
.\scripts\Export-HelpDeskAudit.ps1 `
  -UserId 'test.user@yourtenant.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID' `
  -IncludeSignInActivity `
  -IncludeIntuneDevices
```

Open:

```text
reports\IT-Support-Operations-Report.html
```

Do **not** commit a live report containing tenant/user information. The generated report path is ignored by Git.

## Read next

1. `docs/SETUP-GUIDE.md`
2. `docs/TESTING.md`
3. `docs/GRAPH-PERMISSIONS.md`
4. `docs/TROUBLESHOOTING.md`
5. `SECURITY.md`
