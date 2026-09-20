# Security policy and safe-use notes

This repository performs real Microsoft Entra ID / Microsoft 365 changes through Microsoft Graph when you run the mutating scripts without `-WhatIf`.

## Rules for safe use

1. Use a Microsoft 365 developer/test tenant first.
2. Use delegated authentication and only the scopes required by the workflow.
3. The signed-in operator must have the Microsoft Entra role needed for the action; Graph scopes alone do not grant administrative authority.
4. Run `-WhatIf` before onboarding, offboarding, or password/access changes.
5. Never commit tenant-derived output, employee data, audit logs, passwords, access tokens, tenant secrets, or private CSV files.
6. Treat generated temporary passwords as secrets. Transfer them using an approved secure channel and do not paste them into tickets or GitHub.
7. Review group/license actions before running bulk onboarding or offboarding.
8. The local JSONL audit log is a project audit trail; it is **not** a replacement for Microsoft Purview / Entra audit logs or an organization's SIEM.

## Data intentionally ignored by Git

- `data/audit-log.jsonl`
- `data/snapshots/*.json`
- `data/offboarding/*.json`
- `reports/*.html`
- `config/*.private.csv`

## Reporting a security issue

For a portfolio repository, disable public issue disclosure for any vulnerability that could expose real tenant information. If you fork this project for organizational use, replace this section with your organization's private security-contact process.
