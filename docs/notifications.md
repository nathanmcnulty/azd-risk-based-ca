# Notifications

Notifications are optional. The default `none` mode deploys no notification backend.

## Choose a backend

| Mode | Use when | Additional prerequisite |
| --- | --- | --- |
| `none` | You only need Conditional Access policies | None |
| `graph` | You need five-minute risk-detection polling | Browser consent for application permissions and a Teams destination if enabled |
| `logAnalytics` | Risk tables are already ingested | Existing workspace receiving `AADRiskyUsers` and `AADUserRiskEvents` |

Teams delivery can use a guided tenant-local managed connection or an existing Workflow webhook. Follow [Teams delivery setup](teams-workflow-setup.md) for the channel-link and consent flow. Treat webhook URLs as bearer credentials and verify the workflow run, not only the HTTP response.

Graph polling deploys a five-minute Flex Consumption Function, checkpoint/dead-letter storage, and workspace-backed Application Insights. It polls `identityProtection/riskDetections` with a 24-hour overlap, follows pagination, seeds the first run without delivery, and records delivery independently for each event and destination. Transient and 429 responses use exponential retry; five failed runs dead-letter that destination without blocking other destinations.

Log Analytics mode requires an existing workspace receiving `RiskyUsers` and `UserRiskEvents` in `AADRiskyUsers` and `AADUserRiskEvents`. It creates a five-minute scheduled query alert, Consumption Logic App, action group, and managed-identity blob checkpoints/dead letters. It does not create a workspace or require Sentinel; its first workflow invocation creates a seed marker without posting the triggering historical event.

Both paths use a versioned envelope containing event ID, detection time, user identifiers, risk type/level/state, source, and investigation URL. The default guided path creates a Teams managed API connection and disabled HTTP-triggered delivery Logic App. Postprovision requests a short-lived `listConsentLinks` authorization URL, opens normal browser OAuth, verifies the connection, enables the Logic App, and sends one labeled card after authorization. The callback stays inside deployment and the endpoint returns success only after the connector action succeeds. Five-minute Graph polling is about 8,640 executions per month; shared Flex grants may cover low volume, while Log Analytics ingestion and alert evaluation remain billable.

Graph mode packages the checked-in Function source and asks Azure Functions Flex to build `package-lock.json` dependencies remotely. Administrators do not install Node.js for deployment. Node.js is needed only for contributor tests described in [development](development.md).

During postprovision, the remote Function publish completes first, the managed identity is granted `IdentityRiskEvent.Read.All`, and only then are Conditional Access policies applied. A build failure therefore leaves neither the app-role grant nor policy changes behind.

Use the included scripts after deployment:

```powershell
./scripts/Test-TeamsDelivery.ps1 -Destination admin
./scripts/Test-GraphPoller.ps1
```
