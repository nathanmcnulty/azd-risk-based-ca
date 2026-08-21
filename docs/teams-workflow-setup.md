# Teams Workflow setup

Create the callbacks in Teams Workflows under a durable service owner or service account—not a departing individual. Record the owner and a renewal contact in your operations system.

1. Create a workflow using **Post to a channel when a webhook request is received** for administrator notifications. Copy its HTTPS callback into `AZD_CA_ADMIN_TEAMS_WORKFLOW_URL`.
2. Optionally create a second workflow that accepts `recipientUpn` and `card`, then uses **Post card in a chat or channel** to send `card` to the named internal user. Store its callback in `AZD_CA_USER_TEAMS_WORKFLOW_URL`.
3. Restrict editing of both workflows. Treat callback URLs as bearer credentials; do not commit, log, paste into tickets, or expose as deployment outputs.
4. Run `./scripts/Test-TeamsDelivery.ps1 -Destination admin`. If configured, also run `./scripts/Test-TeamsDelivery.ps1 -Destination user -UserPrincipalName you@contoso.com`.

The user card intentionally omits risk mechanics, IP address, location, and investigative detail. The source templates are in `templates/`. Teams webhook workflows do not require a premium Power Automate license, but ownership and connector policies remain tenant responsibilities.
