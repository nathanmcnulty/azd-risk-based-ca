# Identity and permissions

## Azure access

The operator needs Azure CLI access to the target subscription and permission to create or update the selected resource group. Notification modes deploy managed identities and Azure role assignments, so the operator also needs `Microsoft.Authorization/roleAssignments/write`, such as through Owner, User Access Administrator, or Role Based Access Control Administrator in addition to resource deployment permission. The Azure subscription tenant and the Microsoft Graph tenant must match.

## Microsoft Graph access

The baseline delegated scopes are `Policy.Read.All`, `Policy.ReadWrite.ConditionalAccess`, `Group.Read.All`, `RoleManagement.Read.Directory`, `User.Read`, `AuditLog.Read.All`, and `IdentityRiskyUser.Read.All`. The last two count historical sign-in risk events and current actionable risky users for the risk-exposure summary; the deployment does not enumerate identities for that report. Notification mode `graph` additionally requests `Application.Read.All` and `AppRoleAssignment.ReadWrite.All` to grant the Function identity `IdentityRiskEvent.Read.All`. Notification-only scopes are not requested for other modes.

Conditional Access policy and authentication-strength writes support Conditional Access Administrator or Security Administrator as the least-privileged built-in roles. Security Administrator can also read the sign-in and risky-user APIs used by the exposure summary. A Conditional Access Administrator needs an additional supported read role: Reports Reader for sign-ins and Security Reader for risky users.

Graph notification mode has a separate consent boundary. It assigns the Microsoft Graph application permission `IdentityRiskEvent.Read.All` to the Function service principal. Tenant-wide consent or assignment for that Microsoft Graph app role must be completed by a **Global Administrator or Privileged Role Administrator**; Security Administrator, Conditional Access Administrator, and Azure RBAC roles do not confer that authority. The postprovision hook also requests delegated `Application.Read.All` and `AppRoleAssignment.ReadWrite.All` in the deploying administrator's Graph context to inspect and assign the role. Those client permissions are a separate consent prerequisite and are not supplied by the feature-operation roles.

The hooks reuse a valid cached Graph context when its tenant, account, cloud, and scopes match. Otherwise Microsoft Graph PowerShell uses the normal operating-system broker or browser flow. A read-only `/me` probe confirms that the current process has a usable token before planning.

## Emergency access

Prepare and test at least one emergency access path that is independent of the policies being deployed. A dedicated exclusion group is preferred. Treat group membership and existing policy adoption as security decisions, not convenience settings.

## Boundaries

Runtime notification resources use managed identity where applicable. Callback URLs are bearer secrets. Do not commit them, print them, or place them in deployment outputs.

## Microsoft references

- [Create a Conditional Access policy](https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies)
- [Create an authentication strength policy](https://learn.microsoft.com/graph/api/authenticationstrengthroot-post-policies)
- [Grant an app role to a service principal](https://learn.microsoft.com/graph/api/serviceprincipal-post-approleassignments)
- [Combine Graph requests with JSON batching](https://learn.microsoft.com/graph/json-batching)
- [List sign-ins](https://learn.microsoft.com/graph/api/signin-list)
- [List risky users](https://learn.microsoft.com/graph/api/riskyuser-list)
