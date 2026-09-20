# Testing guide

This project uses **three layers of testing** so the GitHub repository can demonstrate both code quality and real Microsoft Graph validation without pretending that mocked data is a production tenant.

## 1. Local repository validation

Run:

```powershell
python .\tests\run-local-validation.py
```

This validator does not require Microsoft Graph access. It checks:

- required project files
- Graph-only execution contracts
- expected Graph scopes and endpoint references
- `SupportsShouldProcess` / `-WhatIf` safety on mutating scripts
- audit logging hooks
- Git exclusions for tenant-derived data
- module manifest/export consistency
- sample-data hygiene
- report preview presence
- lightweight PowerShell delimiter integrity

The repository was packaged after this validator reported **104 passed / 0 failed**.

> This is a repository/static validation layer. It is not a substitute for the PowerShell AST, Pester, or a live Microsoft 365 test tenant.

## 2. Pester unit/workflow tests

Install the quality modules:

```powershell
.\scripts\Install-Prerequisites.ps1 -IncludeQualityTools
```

Run all Pester tests:

```powershell
Invoke-Pester .\tests -Output Detailed
```

The included Pester suite contains **23 test cases** across:

- shared-module behavior
- PowerShell AST parsing
- Graph-only repository contracts
- onboarding Graph request flow
- onboarding `-WhatIf` safety
- support snapshot JSON output
- password reset / account enable / session revoke flow
- reset `-WhatIf` safety
- offboarding evidence + disable + revoke + cleanup flow
- offboarding `-WhatIf` safety
- HTML operations-report generation
- repository data-protection rules

The workflow tests mock Microsoft Graph commands, so they do not modify a tenant.

## 3. Real test-tenant integration validation

The integration runner is:

```text
tests\Invoke-TestTenantValidation.ps1
```

### Read-only validation

```powershell
.\tests\Invoke-TestTenantValidation.ps1 `
  -ExistingTestUser 'test.user@contoso.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID'
```

Optional read-only Intune/sign-in checks:

```powershell
.\tests\Invoke-TestTenantValidation.ps1 `
  -ExistingTestUser 'test.user@contoso.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID' `
  -IncludeSignInActivity `
  -IncludeIntuneDevices
```

The default integration run:

- verifies Graph authentication
- runs a real support snapshot
- generates the HTML operations report
- exercises reset and offboarding with `-WhatIf`
- writes a machine-readable result file under `tests/results/`

### Full disposable-user lifecycle

Only use this in an **authorized developer/test tenant**:

```powershell
.\tests\Invoke-TestTenantValidation.ps1 `
  -ExistingTestUser 'test.user@contoso.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID' `
  -RunWriteTests `
  -TestDomain 'contoso.onmicrosoft.com'
```

Optionally verify group and license workflows too:

```powershell
.\tests\Invoke-TestTenantValidation.ps1 `
  -ExistingTestUser 'test.user@contoso.onmicrosoft.com' `
  -TenantId 'YOUR-TENANT-ID' `
  -RunWriteTests `
  -TestDomain 'contoso.onmicrosoft.com' `
  -TestGroup 'IT Automation Test' `
  -LicenseSkuPartNumber 'O365_BUSINESS_PREMIUM'
```

The write test creates a uniquely named disposable account, verifies its core attributes through Graph, optionally verifies group/license assignment, runs access recovery + session revocation, offboards it, and verifies the account is disabled.

## What was executed before packaging

Executed in the build environment:

- `tests/run-local-validation.py` — **104 passed, 0 failed**
- Python syntax compilation for the local validator
- ZIP integrity / file inventory checks
- visual inspection of the sanitized report-preview image

Not executed in the build environment:

- Pester runtime tests, because PowerShell is not installed in this runtime
- live Microsoft Graph integration tests, because no authorized Microsoft 365 tenant credentials are available here

That distinction is intentional. The repository does not claim a live tenant test that did not happen.

## GitHub Actions

`.github/workflows/powershell-quality.yml` runs on pushes and pull requests to `main`. It executes the local validator, PSScriptAnalyzer, and Pester on a GitHub-hosted Windows runner.

Live Graph integration tests are **not** run in GitHub Actions by default because they would require tenant credentials and write permissions. Run them manually in a controlled developer/test tenant.
