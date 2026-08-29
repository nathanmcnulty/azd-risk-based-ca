# Operations and cleanup

## Verify

Review `reports/azd-risk-ca-plan.json` before enablement and `reports/azd-risk-ca-applied.json` after deployment. Confirm all nine policies in the Conditional Access portal, run What If tests, review sign-in logs, and validate the emergency access path.

Preprovision writes `reports/azd-risk-ca-historical-impact.json` with batched Graph counts and Identity Protection investigation links. Unavailable count endpoints are recorded as unavailable rather than zero and do not block the report-only plan. Postprovision rereads every managed policy by recorded object ID and compares normalized desired request shape with actual Graph state. It writes `reports/azd-risk-ca-applied.json` and fails on any difference. Policy application is compensating-transactional: a later Graph write restores objects changed during that run in reverse order. If compensation is incomplete, the checkpoint remains for explicit cleanup and the deployment reports affected actions.

## Rerun and troubleshoot

Rerun `azd up` after correcting configuration or consent. A missing Graph module means the local prerequisite was not installed. A Teams connection that is not ready requires the normal browser authorization and another `azd hooks run postprovision`. A Graph notification build failure is reported before Conditional Access policy application; rerun after the local or Azure deployment issue is resolved.

## Cleanup

```powershell
azd down
```

The default preserves Entra policies and other tenant objects. For ownership-aware cleanup:

```powershell
azd env set AZD_CA_CLEANUP true
azd down
```

Review the plan and state first. Cleanup deletes only solution-owned resources and restores adopted objects where the recorded state supports it. It does not revoke an underlying Teams connector grant that may be shared by other automation.
