# Teams delivery setup

## Guided API connection

The default `adminConfigured` mode follows the same supported Azure managed-connector authorization pattern as `azd-emergency-access`:

1. In Teams, right-click the administrator-notification channel and select **Copy link**.
2. Set `AZD_CA_ADMIN_TEAMS_CHANNEL_LINK` to that link. The deployment verifies its tenant ID and extracts the team and channel IDs.
3. Run `azd provision`. Infrastructure creates a `Microsoft.Web/connections` Teams connection and a disabled delivery Logic App.
4. Postprovision opens Azure's short-lived OAuth consent link. Sign in as the durable notification account that should appear as the card sender, complete authorization, and return to the terminal.
5. Postprovision verifies the connection status, enables the workflow, sends a labeled synthetic card on first authorization, and requires the Logic App run to succeed.

The Logic App callback is used only inside the deployment and is never returned as an output. At the time this template was validated, Azure's first-party Teams managed connector requested delegated `User.Read.All`, `Group.ReadWrite.All`, and `Group.Read.All`; review the live consent screen because Microsoft can change a managed connector independently of this template. The API connection remains user-bound: record its durable owner and renewal contact, and use `AZD_CA_TEST_TEAMS_DELIVERY=true` for periodic live validation because a connection resource can appear connected after its refresh token is revoked.

`azd down` deletes the solution-created API connection and Logic App. It does not revoke the authorizing account's underlying first-party connector OAuth grant: that grant may be shared with other Logic Apps or Power Automate flows, so automatic revocation could break unrelated automation. Review and revoke it manually only after confirming there are no remaining dependencies.

## Existing Workflow webhook

If policy or operations require a pre-existing Teams Workflow, set `AZD_CA_ADMIN_TEAMS_DELIVERY_MODE=workflowWebhook`, then create its callback under a durable service owner or service account—not a departing individual.

1. Create a workflow using **Post to a channel when a webhook request is received** for administrator notifications. Copy its HTTPS callback into `AZD_CA_ADMIN_TEAMS_WORKFLOW_URL`.
2. Optionally create a second workflow that accepts `recipientUpn` and `card`, then uses **Post card in a chat or channel** to send `card` to the named internal user. Store its callback in `AZD_CA_USER_TEAMS_WORKFLOW_URL`.
3. Restrict editing of both workflows. Treat callback URLs as bearer credentials; do not commit, log, paste into tickets, or expose as deployment outputs.
4. Run `./scripts/Test-TeamsDelivery.ps1 -Destination admin`. If configured, also run `./scripts/Test-TeamsDelivery.ps1 -Destination user -UserPrincipalName you@contoso.com`.

The Teams connector authorization belongs to the workflow owner and is separate from Microsoft Graph administrator consent used for Conditional Access deployment. If Power Automate reports **Invalid connection**, use **Change connection**, finish the normal browser OAuth prompt, save the flow, and verify a successful run. An accepted webhook response proves only that the trigger received the request; verify the workflow run and resulting Teams card.

The user card intentionally omits risk mechanics, IP address, location, and investigative detail. The source templates are in `templates/`. Teams webhook workflows do not require a premium Power Automate license, but ownership and connector policies remain tenant responsibilities.
