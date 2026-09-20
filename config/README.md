# Configuration templates

This folder contains **templates only**. Do not commit a CSV containing real employee data, passwords, private group names, or tenant identifiers.

## `sample-new-hires.csv`

Fields:

| Column | Required | Purpose |
|---|---:|---|
| `DisplayName` | Yes | User display name |
| `UserPrincipalName` | Yes | New Microsoft Entra UPN |
| `GivenName` | No | First name |
| `Surname` | No | Last name |
| `Department` | No | Department attribute |
| `JobTitle` | No | Job title attribute |
| `UsageLocation` | Required for licensing | Two-letter usage location such as `US` |
| `OfficeLocation` | No | Office/location label |
| `TemporaryPassword` | No | Leave blank to generate a strong temporary password |
| `Groups` | No | Semicolon-separated group names or object IDs |
| `LicenseSkuPartNumbers` | No | Semicolon-separated tenant SKU part numbers |
| `TicketId` | No | Request/change ticket for the local audit trail |

Before using the template, copy it to a private working file that is ignored by Git, for example:

```powershell
Copy-Item .\config\sample-new-hires.csv .\config\new-hires.private.csv
```

The repository `.gitignore` ignores `config/*.private.csv`.
