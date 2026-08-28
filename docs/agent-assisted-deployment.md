# Agent-assisted deployment

An agent may inspect this repository, explain the plan, and run local validation without tenant access. It must not authenticate to Azure or Microsoft Graph, provision resources, change Conditional Access policy state, grant permissions, send notifications, or clean up tenant objects unless the user explicitly authorizes that exact operation in the current task.

Keep deployments report-only until an administrator reviews the plan, confirms the tenant and emergency-access exclusions, and explicitly authorizes enablement. Never use device-code authentication. Do not expose Graph tokens, Teams callbacks, TAP values, passwords, or other secrets in prompts, logs, commits, or reports.
