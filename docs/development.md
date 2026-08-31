# Development

## Local validation

PowerShell tests and Bicep validation do not authenticate to or mutate a tenant:

```powershell
./scripts/Test-Repository.ps1
```

The validation entry point parses and analyzes PowerShell, validates tracked JSON and the component inventory against its checked-in schema, runs the Pester and Node test suites, audits production npm dependencies, compiles Bicep without restoring external modules, and checks both committed and working changes for whitespace errors. It requires PowerShell 7, Node.js 22, Azure CLI with exactly Bicep v0.46.1, Pester 5.7.1 or later, and PSScriptAnalyzer 1.25.0 or later. These are contributor/test dependencies and are not administrator deployment prerequisites.

The repository-level `azd-components.lock.json` is the inventory used by `azd-reference` governance tooling. An empty `components` array is intentional until this solution adopts exact, versioned component files; do not list similar solution-owned code as an adopted component.

## Function packaging

The postprovision hook creates a temporary ZIP from the checked-in Function source and excludes any local `node_modules` or `dist` directory. Azure Functions Flex receives `package.json` and `package-lock.json` and performs the remote build through `az functionapp deployment source config-zip --build-remote true`. The remote publish completes before the `IdentityRiskEvent.Read.All` app-role grant and both happen before Conditional Access reconciliation.

Keep release tags and the public quickstart aligned. Run the full local validation and inspect the final diff before opening a pull request or publishing a release.

## Microsoft references

- [Legacy risk-policy migration](https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies)
- [Teams Workflows incoming webhooks](https://support.microsoft.com/office/send-messages-in-teams-using-incoming-webhooks-8ae491c7-0394-4861-ba59-055e33f75498)
