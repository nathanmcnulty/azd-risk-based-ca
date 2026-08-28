# Safe agent-assisted deployment

- Treat all Azure, Entra, Microsoft Graph, Teams, and Conditional Access operations as external mutations. Do not authenticate, provision, enable policies, grant permissions, send notifications, or run `azd down` unless the user explicitly authorizes that exact live action.
- Read-only inspection and local validation are allowed without live authorization. Never use device-code authentication. Use the normal cached broker or browser flow only when an explicitly authorized live operation requires it.
- Default to report-only policy state. Never set `AZD_CA_POLICY_STATE=enabled`, approve tenant confirmation, adopt an existing object, or enable cleanup without explicit user direction.
- Do not print, store, commit, or repeat Teams workflow URLs, tokens, access tokens, TAP values, passwords, cookies, or other bearer credentials.
- Preserve unrelated changes. Stage and modify only files needed for the requested task, and validate locally before proposing a commit or push.
