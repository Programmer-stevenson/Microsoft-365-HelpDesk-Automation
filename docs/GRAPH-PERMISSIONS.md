# Microsoft Graph permission map

The scripts request delegated scopes per workflow instead of connecting once with broad directory-wide write permissions.

> Graph delegated scopes and Microsoft Entra administrative roles are separate controls. Both can be required.

| Workflow | Delegated scopes used by this project |
|---|---|
| Connection test | `User.Read`, `Organization.Read.All`, `LicenseAssignment.Read.All` |
| Support snapshot | `User.Read.All`, `GroupMember.Read.All`, `LicenseAssignment.Read.All`, `Device.Read.All` |
| Snapshot + sign-in activity | Above + `AuditLog.Read.All` |
| Snapshot + Intune | Above + `DeviceManagementManagedDevices.Read.All` |
| Create user | `User.Create` |
| Create user + groups | Above + `Group.Read.All`, `GroupMember.ReadWrite.All` |
| Create user + licensing | Above + `LicenseAssignment.Read.All`, `LicenseAssignment.ReadWrite.All` |
| Password reset | `User.Read.All`, `User-PasswordProfile.ReadWrite.All` |
| Password reset + revoke sessions | Above + `User.RevokeSessions.All` |
| Password reset + enable account | Above + `User.EnableDisableAccount.All` |
| Offboarding | `User.Read.All`, `GroupMember.Read.All`, `LicenseAssignment.Read.All`, `User.EnableDisableAccount.All`, `User.RevokeSessions.All` |
| Offboarding + group removal | Above + `GroupMember.ReadWrite.All` |
| Offboarding + license removal | Above + `LicenseAssignment.ReadWrite.All` |
| HTML report | `User.Read`, `User.Read.All`, `Organization.Read.All`, `GroupMember.Read.All`, `LicenseAssignment.Read.All`, `Device.Read.All` plus optional sign-in/Intune scopes |

## Microsoft documentation used when designing the permission model

- Create user: https://learn.microsoft.com/graph/api/user-post-users?view=graph-rest-1.0
- Update user / password / account state: https://learn.microsoft.com/graph/api/user-update?view=graph-rest-1.0
- Revoke sign-in sessions: https://learn.microsoft.com/graph/api/user-revokesigninsessions?view=graph-rest-1.0
- Add group member: https://learn.microsoft.com/graph/api/group-post-members?view=graph-rest-1.0
- Remove group member: https://learn.microsoft.com/graph/api/group-delete-members?view=graph-rest-1.0
- Assign user license: https://learn.microsoft.com/graph/api/user-assignlicense?view=graph-rest-1.0
- List license details: https://learn.microsoft.com/graph/api/user-list-licensedetails?view=graph-rest-1.0
- List subscribed SKUs: https://learn.microsoft.com/graph/api/subscribedsku-list?view=graph-rest-1.0
- Registered devices: https://learn.microsoft.com/graph/api/user-list-registereddevices?view=graph-rest-1.0
- Sign-in logs: https://learn.microsoft.com/graph/api/signin-list?view=graph-rest-1.0


## Direct versus group-based licensing

`Offboard-Employee.ps1` reads the user `licenseAssignmentStates` collection. A state with `assignedByGroup = null` is treated as a direct assignment and can be sent to the user `assignLicense` endpoint for removal. A non-null `assignedByGroup` value is reported as inherited and is not sent as a direct removal.
