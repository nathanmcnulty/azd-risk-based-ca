# Optional notification validation and permissions

PowerShell validation targets 7.6 or later. Notification settings are independent
of Conditional Access policy state, which defaults to report-only. This matrix
describes current source behavior; it does not authorize consent or deployment.

| Notification mode | Admin route | Additional deployment authority | Runtime authority and resources | Pending or failure gates |
| --- | --- | --- | --- | --- |
| `none` (default) | Neither route | Baseline delegated Graph scopes only | No notification Function, workflow, action group or notification Blob role | Optional notification receiver/workspace inputs are not required |
| `graph` | `workflowWebhook` | Adds delegated `Application.Read.All` and `AppRoleAssignment.ReadWrite.All`; Graph application consent is a separate operator boundary | Function identity: application `IdentityRiskEvent.Read.All` and `Storage Blob Data Contributor` on its own storage account | Required admin HTTPS callback; Graph/state errors fail the invocation; failed checkpoint write does not log successful completion |
| `graph` | `adminConfigured` | Same Graph additions plus separate Teams connector consent | Same Function plus a Teams connection and initially disabled adapter workflow | Missing channel selection requires the guided preprovision path; connector authorization precedes enabling; unqualified receipt remains pending |
| `logAnalytics` | `workflowWebhook` | Existing workspace and Azure Monitor deployment authority; no extra delegated Graph scopes | Logic App identity: `Storage Blob Data Contributor` on its own notification storage account; action group and scheduled-query rule | Missing workspace ID/location fails configuration; callback must be HTTPS; Storage MSI audience must be `https://storage.azure.com/` |
| `logAnalytics` | `adminConfigured` | Same workspace/Monitor requirements plus separate Teams connector consent | Same notification workflow/alert resources plus Teams connection and disabled adapter | Connector authorization is an independent gate; configured resources alone do not prove delivery |

Optional user delivery uses `AZD_CA_USER_TEAMS_WORKFLOW_URL`. An empty value adds
no user destination to the Graph delivery plan; it does not disable the admin
route. Webhook URLs are bearer secrets and never belong in validation receipts.
Graph and Log Analytics are mutually exclusive modes, not a combined grant set.
The poller preserves existing replay, deduplication and ETag concurrency behavior.
A checkpoint failure after a send can cause replay; local fixtures do not promise
exactly-once delivery or prove a recipient saw the card.

`azd-permissions.json` records source-derived Graph and Blob requirements and
documented operator-role alternatives. Its partial coverage explicitly retains
connector, workspace, deployment/cleanup and shared-key gaps. Baseline scopes are
`AuditLog.Read.All`, `Group.Read.All`, `IdentityRiskyUser.Read.All`, `Policy.Read.All`,
`Policy.ReadWrite.ConditionalAccess`, `RoleManagement.Read.Directory`, `User.Read`.
Graph's two additional delegated scopes are bootstrap consent authority, never
runtime identity permissions. Role alternatives are not cumulative grants.

The current immutable Azure Monitor and Flex locks remain unchanged. Their
existing resource wrappers preserve solution-owned KQL, cards and CA logic.
No deployment-validation component is added: the repository's registered offline
validator plus actual configuration/handler fixtures cover this local packet.
No receipt is used to imply endpoint or recipient acceptance.

Run `pwsh -File ./scripts/Test-Repository.ps1`. It validates the actual workflow's
Storage MSI audience, permission schema/source hashes, configuration receiver and
workspace boundaries, and the real exported poller handler using offline HTTP
fixtures. Negative fixtures include missing/wrong nested audience, bad receiver,
state read rejection, Graph read rejection and checkpoint 403/412/500.
Live workspace/query, connector consent, Graph collection, sender and recipient
acceptance remain separate under RISK-002; this local work changes no grants,
policies, KQL, thresholds or rollout state.
