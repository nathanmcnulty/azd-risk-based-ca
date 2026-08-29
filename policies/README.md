# Conditional Access policy definitions

These nine JSON files are the policy source of truth used by the deployment. `manifest.json` fixes their deployment order and prevents an unlisted file from being applied accidentally.

Each definition contains the stable, reviewable policy intent: display name, target scope, risk condition, grant control, and target resource. During deployment, `scripts/AzdRiskCa.Graph.psm1` reads these files and materializes the Microsoft Graph request bodies with tenant-specific built-in role IDs, configured groups and exclusions, report-only or enabled state, and the resolved authentication-strength ID.

The files are deliberately definitions rather than exported tenant objects. They contain no tenant metadata, object IDs, or stale role snapshots, and the deployment does not download policy content from another repository.
