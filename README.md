# azd-risk-based-ca

[![Validation](https://github.com/nathanmcnulty/azd-risk-based-ca/actions/workflows/validate.yml/badge.svg)](https://github.com/nathanmcnulty/azd-risk-based-ca/actions/workflows/validate.yml)
[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](LICENSE)

An idempotent Azure Developer CLI solution for nine Microsoft Entra Conditional Access risk policies, optional Teams notifications, and a supported operator-guided migration from legacy Identity Protection policies.

The five baseline payloads are normalized from [nathanmcnulty/Entra conditional-access risk policies](https://github.com/nathanmcnulty/Entra/tree/main/conditional-access/risk-policies): response metadata, object IDs, and tenant-specific OData links are not used in requests. Built-in directory role template IDs are discovered from the target tenant on every plan instead of retaining the source export's role snapshot.

## Safety model

- `azd provision` defaults all nine policies to `enabledForReportingButNotEnforced`.
- `preprovision` performs Graph reads and writes `reports/azd-risk-ca-plan.json`; policy changes occur only in `postprovision`.
- `enabled` requires an interactive tenant-ID confirmation. An existing emergency-access group is strongly preferred; if omitted, the authenticated delegated operator is resolved through `/me` and excluded from every policy as a single-user failsafe. There is no pilot mode.
- Every configured group is resolved in the connected tenant before planning. The emergency group and additional exception groups are excluded from every policy.
- A matching name is not ownership. An unrecorded match stops the plan unless `AZD_CA_ADOPT_EXISTING=true`; adopted state is saved for cleanup restoration.
- The requested `mfa` plus `riskRemediation` `AND` grant is sent as-is through the Graph beta Conditional Access endpoint because v1.0 returns errors 1037/1038 for this portal-supported preview policy. The other eight policies and non-preview resources remain on v1.0. A Graph rejection stops deployment; the solution does not substitute password change or authentication strength and does not continue legacy cutover.
- `azd down` preserves Entra objects. `AZD_CA_CLEANUP=true` explicitly deletes created policies, restores adopted policies, and deletes a created TAP strength only when no policy still references it.
- Existing Teams Workflow callback URLs are secure deployment parameters/application settings, excluded from plan and status reports, and never deployment outputs. The default guided mode creates a tenant-local Teams API connection and never emits its generated Logic App callback.

## Policies

| Name | Target | Risk condition | Grant/session behavior |
| --- | --- | --- | --- |
| `Admin-SignInRisk-High-Block` | All live built-in roles; optional admin group | Sign-in: high | Block; every time |
| `Admin-SignInRisk-LowMedium-RequireMFA` | Same admin target | Sign-in: low, medium | MFA; every time |
| `Admin-UserRisk-MediumHigh-Block` | Same admin target | User: medium, high | Block; every time |
| `User-SignInRisk-MediumHigh-RequireMFA` | All users | Sign-in: medium, high | MFA; every time |
| `User-UserRisk-High-RiskRemediation` | Internal users; guests excluded | User: high | `mfa` + `riskRemediation`, `AND`; every time |
| `User-UserRisk-Any-Block-SecurityInfoRegistration` | All users; security-info registration | User: low, medium, high | Block; no session controls |
| `User-SignInRisk-Any-Block-SecurityInfoRegistration` | All users; security-info registration | Sign-in: low, medium, high | Block; no session controls |
| `User-UserRisk-Any-RequireStrongAuth-DeviceRegistration` | All users; device registration | User: low, medium, high | Authentication strength; no session controls |
| `User-SignInRisk-Any-RequireStrongAuth-DeviceRegistration` | All users; device registration | Sign-in: low, medium, high | Authentication strength; no session controls |

Device registration uses Microsoft's built-in phishing-resistant strength by default; it never uses Block. Set `AZD_CA_USE_TAP_AUTH_STRENGTH=true` to create or explicitly adopt a custom `Temporary Access Pass` strength containing only `temporaryAccessPassOneTime` and `temporaryAccessPassMultiUse`.

## Prerequisites and deployment

Requirements: PowerShell 7.4+, Azure CLI, Azure Developer CLI 1.23+, Node.js 22 for Graph notification packaging, and `Microsoft.Graph.Authentication` 2.30+. The tenant needs Entra ID P2 or Entra Suite licensing. The signed-in operator must be allowed to consent to and use the requested delegated Graph permissions.

```powershell
azd init --template nathanmcnulty/azd-risk-based-ca
Install-PSResource Microsoft.Graph.Authentication -Scope CurrentUser
azd auth login
az login

azd env set AZD_CA_EMERGENCY_ACCESS_GROUP_ID '<group-object-id>'
azd env set AZD_CA_ADMIN_COVERAGE_GROUP_ID '<optional-admin-coverage-group-id>'
azd env set AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS '<group-id>;<group-id>'
azd provision
```

The base delegated scopes are `Policy.Read.All`, `Policy.ReadWrite.ConditionalAccess`, `Group.Read.All`, `RoleManagement.Read.Directory`, and `User.Read`. `User.Read` resolves only the signed-in operator when the emergency group is omitted. Azure Deployment Studio checks these manifest-declared scopes before preview and its Microsoft Graph connection uses ordinary `Connect-MgGraph`, allowing the OS broker/browser to show the administrator-consent prompt when required. CLI-only deployment performs the same scoped connection in `preprovision`.

Graph notifications additionally request `Application.Read.All` and `AppRoleAssignment.ReadWrite.All` during `preprovision` so `postprovision` can grant the Function identity the `IdentityRiskEvent.Read.All` application role. This is an incremental browser consent request only when Graph notifications are selected; optional permissions are not requested in other modes. The Function identity grant is then made explicitly and verified after Azure deployment.

`preprovision` checks `Get-MgContext` for the selected tenant and granted scopes, then performs a minimal `/me?$select=id` read. The API read is intentional: Graph PowerShell can expose persisted context metadata before the current hook process has acquired a usable WAM token. This makes a canceled broker or incomplete consent fail before policy discovery or any deployment write.

After reviewing report-only results and Conditional Access What If outcomes:

```powershell
azd env set AZD_CA_POLICY_STATE enabled
azd provision # type the exact tenant ID when prompted
./scripts/Status.ps1
```

Review sign-in logs for at least the organization's normal access cycle before enablement. Verify all nine objects in the Conditional Access portal, use What If for administrators, internal users, guests, registration actions, and emergency accounts, and retain a tested emergency account outside normal policy dependencies.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `AZD_CA_POLICY_STATE` | `reportOnly` | `reportOnly` or confirmation-gated `enabled` |
| `AZD_CA_EMERGENCY_ACCESS_GROUP_ID` | empty | Preferred durable exclusion group; when omitted, the signed-in operator is excluded from every policy as a single-user failsafe; still mandatory for legacy migration |
| `AZD_CA_ADMIN_COVERAGE_GROUP_ID` | empty | Optional coverage for custom and administrative-unit-scoped administrators; absence produces a warning |
| `AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS` | empty | JSON, comma-, or semicolon-delimited group object IDs |
| `AZD_CA_USE_TAP_AUTH_STRENGTH` | `false` | Use a managed TAP-only strength for device registration |
| `AZD_CA_ADOPT_EXISTING` | `false` | Permit reviewed adoption of same-name policies/strength |
| `AZD_CA_GRAPH_AUTHENTICATION_METHOD` | `browser` | Standard cached WAM/OS broker or interactive browser authentication; device-code flow is not supported |
| `AZD_CA_NOTIFICATION_MODE` | `none` | `none`, `graph`, or `logAnalytics`; exactly one backend per environment |
| `AZD_CA_ADMIN_TEAMS_DELIVERY_MODE` | `adminConfigured` | Guided `Microsoft.Web/connections` OAuth authorization, or `workflowWebhook` to reuse a callback |
| `AZD_CA_ADMIN_TEAMS_CHANNEL_LINK` | empty | Teams channel link used to tenant-validate and resolve the guided connection target |
| `AZD_CA_ADMIN_TEAMS_WORKFLOW_URL` | empty | Required bearer-secret callback only for `workflowWebhook` delivery |
| `AZD_CA_USER_TEAMS_WORKFLOW_URL` | empty | Optional callback accepting a minimized card and `recipientUpn` |
| `AZD_CA_TEST_TEAMS_DELIVERY` | `false` | Send a labeled card and require a successful Logic App run on every deployment |
| `AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` | empty | Required existing workspace for `logAnalytics`; no workspace is created by that mode |
| `AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION` | empty | Region of the existing workspace |
| `AZD_CA_CLEANUP` | `false` | Explicit tenant-object cleanup during `azd down` |

## Notifications

`graph` deploys a five-minute Flex Consumption Function, its checkpoint/dead-letter Storage account, and workspace-backed Application Insights. It polls `identityProtection/riskDetections` with a 24-hour overlap, follows pagination, seeds the first run without delivery, and records delivery independently for each event and destination. Transient/429 responses use exponential retry; five failed runs dead-letter that destination without blocking other destinations.

`logAnalytics` requires an existing workspace already receiving `RiskyUsers` and `UserRiskEvents` into `AADRiskyUsers` and `AADUserRiskEvents`. It creates a five-minute scheduled query alert, Consumption Logic App, action group, and managed-identity blob checkpoints/dead letters. It neither creates a workspace nor requires Sentinel. Its first workflow invocation creates a seed marker without posting the triggering historical event.

Both paths use a versioned envelope containing event ID, detection time, user identifiers, risk type/level/state, source, and investigation URL. By default, deployment creates a Teams managed API connection and a disabled HTTP-triggered delivery Logic App. Postprovision requests a short-lived authorization link through `listConsentLinks`, opens the normal browser OAuth flow for the durable notification account, verifies the connection, enables the Logic App, and sends one labeled card on first authorization. The callback stays inside the deployment and the delivery endpoint returns success only after the Teams connector action succeeds.

Set the target before deployment:

```powershell
azd env set AZD_CA_ADMIN_TEAMS_CHANNEL_LINK '<link copied from Teams>'
```

For unattended or centrally managed scenarios, set `AZD_CA_ADMIN_TEAMS_DELIVERY_MODE=workflowWebhook` and supply `AZD_CA_ADMIN_TEAMS_WORKFLOW_URL` instead. A pre-existing webhook remains a bearer secret and its downstream connector health must be verified separately.

The optional user workflow is limited to internal UPNs and receives only generic account-security guidance—no IP, location, detection mechanics, or investigation detail. See [Teams delivery setup](docs/teams-workflow-setup.md), then run:

```powershell
./scripts/Test-TeamsDelivery.ps1 -Destination admin
./scripts/Test-TeamsDelivery.ps1 -Destination user -UserPrincipalName 'you@contoso.com'
./scripts/Test-GraphPoller.ps1 # graph mode only; invokes the timer and verifies checkpoint state
```

The admin test retrieves the generated callback without displaying it and waits for a successful Logic App run. Set `AZD_CA_TEST_TEAMS_DELIVERY=true` to repeat that end-to-end test during every deployment; otherwise it runs automatically only after initial guided authorization.

Five-minute Graph polling is about 8,640 executions/month and normally fits within shared Flex Consumption grants at low volume. Log Analytics is economical when the risk tables are already ingested, but ingestion and alert evaluation remain billable.

## Legacy migration

Microsoft's supported Graph API does not expose legacy Identity Protection policy configuration or disablement, so the workflow intentionally records portal observations and operator attestation rather than claiming API verification.

1. Open both legacy policy pages. Copy [the capture example](docs/legacy-capture.example.json) to `.azure/<environment>/legacy-capture.json`, record assignments, exclusions, risk levels, controls, session controls, and whether each policy is enabled. Then run `./scripts/Stage-LegacyMigration.ps1`. Only enabled captures produce `LEGACY MIGRATED` replicas, initially report-only. The mandatory emergency exclusion is the sole intentional difference.
2. Review `reports/legacy-cutover-comparison.json` and the replicas. Run `./scripts/Complete-LegacyMigration.ps1`, type the tenant ID, and let the script re-read and hash-compare the replicas. It enables replacements first, opens both portal pages, and waits for `DISABLED`. If the attestation is omitted, replacement coverage stays enabled and migration remains incomplete.
3. Review and explicitly enable all nine recommended policies with `azd provision`. Then run `./scripts/Retire-LegacyMigration.ps1`. It re-reads all nine and refuses to continue unless every one is enabled, after which it disables—but does not delete—the rollback replicas.

Microsoft retires legacy risk policies on October 1, 2026. A cancelled or failed operation never disables replacement coverage. Deletion of rollback replicas is deliberately outside this workflow.

## Validation

Tenant-independent checks:

```powershell
az bicep build --file infra/main.bicep --stdout | Out-Null
Invoke-Pester ./tests -CI
Push-Location ./src/risk-notification-poller
npm ci
npm test
Pop-Location
```

Postprovision re-reads every managed policy by recorded object ID and compares the normalized desired request shape with actual Graph state. It writes `reports/azd-risk-ca-applied.json` and fails if any object differs. Policy application is compensating-transactional: if a later Graph write fails, objects changed during that run are restored in reverse order. If compensation itself is incomplete, the checkpoint is preserved for explicit cleanup and the deployment reports the affected actions. No live tenant deployment is performed by the test suite or CI.

## Microsoft references

- [Create Conditional Access policy and permissions](https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies)
- [Conditional Access user actions and device-registration limitations](https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps)
- [Conditional Access identity targeting](https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-users-groups)
- [Grant-control considerations](https://learn.microsoft.com/graph/api/resources/conditionalaccessgrantcontrols)
- [Legacy risk-policy migration](https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies)
- [Teams Workflows incoming webhooks](https://support.microsoft.com/office/send-messages-in-teams-using-incoming-webhooks-8ae491c7-0394-4861-ba59-055e33f75498)
