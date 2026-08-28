# Configuration

The first `azd up` stores choices in the azd environment. Advanced operators may set values before rerunning the command.

| Variable | Default | Purpose |
| --- | --- | --- |
| `AZD_CA_POLICY_STATE` | `reportOnly` | `reportOnly` or confirmation-gated `enabled` |
| `AZD_CA_EMERGENCY_ACCESS_GROUP_ID` | empty | Durable Conditional Access exclusion group |
| `AZD_CA_ADMIN_COVERAGE_GROUP_ID` | empty | Optional custom administrator coverage group |
| `AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS` | empty | Additional group object IDs, comma- or semicolon-delimited |
| `AZD_CA_NOTIFICATION_MODE` | `none` | `none`, `graph`, or `logAnalytics` |
| `AZD_CA_ADMIN_TEAMS_DELIVERY_MODE` | `adminConfigured` | Guided managed connection or `workflowWebhook` |
| `AZD_CA_ADMIN_TEAMS_CHANNEL_LINK` | empty | Teams channel link for guided delivery |
| `AZD_CA_ADMIN_TEAMS_WORKFLOW_URL` | empty | Existing admin workflow callback when using webhook mode |
| `AZD_CA_USER_TEAMS_WORKFLOW_URL` | empty | Optional callback for minimized internal-user notifications |
| `AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` | empty | Existing workspace required for Log Analytics mode |
| `AZD_CA_USE_TAP_AUTH_STRENGTH` | `false` | Use a managed Temporary Access Pass strength for device registration |
| `AZD_CA_ADOPT_EXISTING` | `false` | Permit reviewed adoption of same-name objects |
| `AZD_CA_CLEANUP` | `false` | Permit ownership-aware tenant cleanup during `azd down` |
| `AZD_CA_GRAPH_AUTHENTICATION_METHOD` | `browser` | Standard cached WAM/OS broker or browser authentication; device code is unsupported |
| `AZD_CA_TEST_TEAMS_DELIVERY` | `false` | Repeat the labeled Teams delivery smoke test on every deployment |
| `AZD_CA_TEAMS_AUTHORIZED` | `false` | Internal marker set after the first successful guided Teams authorization |
| `AZD_CA_ADMIN_TEAMS_TEAM_ID` | empty | Resolved team ID; normally derived from the copied channel link |
| `AZD_CA_ADMIN_TEAMS_CHANNEL_ID` | empty | Resolved channel ID; normally derived from the copied channel link |
| `AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION` | empty | Region of the existing Log Analytics workspace |
| `AZD_CA_SETUP_COMPLETE` | empty | First-run wizard completion marker; set automatically after review |

For a first deployment, leave the defaults, provide the emergency group if available, and run report-only. Add notifications only after the policy report is understood. See [notifications](notifications.md) for mode-specific prerequisites.

The guided first-run wizard is skipped when its completion marker is present, when meaningful values were preconfigured, or when the process is noninteractive. An interrupted wizard leaves an `inProgress` marker so the next interactive `azd up` safely restarts the setup phase; choices are saved transactionally only after the final review. It never authenticates or changes a tenant while prompting. Invalid GUIDs, URLs, choices, and workspace IDs are reprompted interactively.
