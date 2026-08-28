# Development

## Local validation

PowerShell tests and Bicep validation do not authenticate to or mutate a tenant:

```powershell
az bicep build --file infra/main.bicep --stdout | Out-Null
Invoke-Pester ./tests -CI
Push-Location ./src/risk-notification-poller
npm ci
npm test
Pop-Location
```

Node.js 22 is a contributor/test dependency for the notification poller. It is not an administrator deployment prerequisite.

## Function packaging

The postprovision hook creates a temporary ZIP from the checked-in Function source and excludes any local `node_modules` or `dist` directory. Azure Functions Flex receives `package.json` and `package-lock.json` and performs the remote build through `az functionapp deployment source config-zip --build-remote true`. The remote publish completes before the `IdentityRiskEvent.Read.All` app-role grant and both happen before Conditional Access reconciliation.

Keep release tags and the public quickstart aligned. Run the full local validation and inspect the final diff before opening a pull request or publishing a release.

## Microsoft references

- [Legacy risk-policy migration](https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies)
- [Teams Workflows incoming webhooks](https://support.microsoft.com/office/send-messages-in-teams-using-incoming-webhooks-8ae491c7-0394-4861-ba59-055e33f75498)
