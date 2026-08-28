# azd-risk-based-ca

[![Validation](https://github.com/nathanmcnulty/azd-risk-based-ca/actions/workflows/validate.yml/badge.svg)](https://github.com/nathanmcnulty/azd-risk-based-ca/actions/workflows/validate.yml)
[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](LICENSE)

Deploy a safe, report-only-first baseline of nine Microsoft Entra Conditional Access risk policies with Azure Developer CLI. Optional Teams notifications and a guided migration from the legacy Identity Protection risk policies are included.

This template helps an administrator:

- establish a report-only baseline for nine risk policies;
- review tenant-specific impact before enabling enforcement;
- deliver optional administrator and user notifications; and
- migrate from legacy Identity Protection risk policies with rollback coverage.

> This template changes tenant security policy. Read the [safety and policy guide](docs/policies-and-safety.md), prepare an emergency access path, and test the report-only results before enabling enforcement.

## Quickstart

### Before you begin

Install:

- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- PowerShell 7.4 or later
- Microsoft Graph PowerShell authentication:

```powershell
Install-PSResource Microsoft.Graph.Authentication -Scope CurrentUser
```

Use a Conditional Access Administrator or Security Administrator who can deploy to the selected subscription and consent to the Microsoft Graph permissions requested by the chosen features. Notification modes also create Azure role assignments and therefore need permission to assign roles. Review [identity and permissions](docs/identity-and-permissions.md) before production use. Entra ID P2 or Entra Suite licensing is required for risk-based Conditional Access.

### Deploy

```powershell
azd init -t nathanmcnulty/azd-risk-based-ca && azd up
```

The first run uses report-only policy state, walks through the required tenant and exclusion settings, shows the plan before changes, and uses the normal Azure and Microsoft Graph browser sign-in. Rerun `azd up` to continue or reconcile an existing environment. Device-code authentication is not supported.

After deployment, review the plan and applied report, inspect sign-in logs and Conditional Access What If results, and verify the emergency access path. Follow [operations and cleanup](docs/operations-and-cleanup.md) for verification and teardown.

## What this deploys

- Nine normalized Conditional Access policies covering administrator sign-in risk, user risk remediation, security-info registration, and device registration.
- Optional Teams delivery through a tenant-local managed connection or an existing Teams Workflow webhook.
- Optional Graph risk-detection polling through an Azure Functions Flex Consumption app, or Log Analytics scheduled alerting when the workspace already receives the required risk tables.
- Local deployment reports and ownership-aware state for reconciliation and cleanup.

The default is report-only policy state and no notification backend. See [configuration](docs/configuration.md) to choose notification and enforcement settings.

## Documentation

| Guide | Purpose |
| --- | --- |
| [Policies and safety](docs/policies-and-safety.md) | Policy behavior, report-only defaults, exclusions, adoption, and enablement gates |
| [Identity and permissions](docs/identity-and-permissions.md) | Azure roles, Graph consent, authentication, and emergency access expectations |
| [Configuration](docs/configuration.md) | Environment values, notification choices, and common deployment examples |
| [Notifications](docs/notifications.md) | Graph polling, Log Analytics, Teams delivery, consent, and testing |
| [Legacy migration](docs/legacy-migration.md) | Capture, stage, cut over, and retire the legacy risk policies |
| [Operations and cleanup](docs/operations-and-cleanup.md) | Verification, troubleshooting, reruns, and safe teardown |
| [Development](docs/development.md) | Local validation, packaging model, release, and publishing guidance |
| [Agent-assisted deployment](docs/agent-assisted-deployment.md) | Guardrails for using an agent to inspect or operate this template |

## Cleanup

```powershell
azd down
```

This preserves Entra policies and other tenant objects by default. Set `AZD_CA_CLEANUP=true` only after reviewing the recorded ownership state and explicitly approving deletion. See [operations and cleanup](docs/operations-and-cleanup.md).

## Security and license

Keep at least one tested emergency access path outside normal Conditional Access dependencies. Report vulnerabilities through [SECURITY.md](SECURITY.md). This project is released under the [Unlicense](LICENSE).
