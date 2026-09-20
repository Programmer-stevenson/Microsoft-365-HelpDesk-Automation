# Troubleshooting

## `Microsoft.Graph.Authentication is not installed`

```powershell
.\scripts\Install-Prerequisites.ps1
```

## Consent / `Insufficient privileges`

Microsoft Graph authorization has two layers:

1. The delegated scope granted to the Graph PowerShell client.
2. The Microsoft Entra role held by the signed-in operator.

Having the scope does not automatically grant an admin role.

## Wrong tenant

```powershell
Disconnect-MgGraph
.\scripts\Test-GraphConnection.ps1 -TenantId 'YOUR-TENANT-ID'
```

## Existing Graph session does not have the required scopes

The shared module checks requested scopes. If the current process token lacks them, it reconnects. You can also start a clean process or run:

```powershell
Disconnect-MgGraph
```

## License SKU not found

Run:

```powershell
.\scripts\Test-GraphConnection.ps1
```

Use the displayed `skuPartNumber` value in onboarding.

## Group name matches more than one group

Use the Microsoft Entra group **object ID** instead of the display name.

## Cannot remove a group during offboarding

Dynamic groups cannot be modified by deleting an individual membership. Role-assignable or protected groups can also require additional permissions/roles. The script records a warning and continues rather than falsely reporting success.

## Sign-in activity unavailable

`-IncludeSignInActivity` requires `AuditLog.Read.All`, an appropriate Entra role, and the tenant features/licensing necessary to expose the data.

## Intune devices unavailable

`-IncludeIntuneDevices` requires the tenant to use Intune and the delegated `DeviceManagementManagedDevices.Read.All` scope. The signed-in account must also have appropriate access.

## Script execution is blocked

For the current shell only:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Prefer your organization's normal PowerShell signing/execution policy in managed environments.
