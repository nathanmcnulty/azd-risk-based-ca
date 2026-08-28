# Legacy migration

Microsoft's supported Graph API does not expose the legacy Identity Protection policy configuration or disablement state. This workflow records portal observations and operator attestation instead of claiming API verification.

1. Copy [legacy-capture.example.json](legacy-capture.example.json) to `.azure/<environment>/legacy-capture.json`, record both portal policies, and run `./scripts/Stage-LegacyMigration.ps1`.
   Record assignments, exclusions, risk levels, controls, session controls, and whether each policy is enabled. Only enabled captures produce `LEGACY MIGRATED` replicas, initially report-only. The mandatory emergency exclusion is the sole intentional difference.
2. Review `reports/legacy-cutover-comparison.json` and the report-only replicas. Run `./scripts/Complete-LegacyMigration.ps1`, type the tenant ID, disable the applicable legacy policies in both portal pages, and enter `DISABLED` when verified. If attestation is omitted, replacement coverage stays enabled and migration remains incomplete.
3. Review and explicitly enable all nine replacement policies, then run `./scripts/Retire-LegacyMigration.ps1`. It rereads all nine and refuses to continue unless every one is enabled; it then disables, but does not delete, rollback replicas.

A failed or cancelled step never disables replacement coverage. Legacy risk policies are scheduled for retirement by Microsoft on October 1, 2026; verify the current Microsoft guidance before scheduling a cutover.

The supported Graph API cannot verify legacy portal disablement, so operator attestation is deliberately retained. Deletion of rollback replicas is outside this workflow. See Microsoft's [legacy risk-policy migration guidance](https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies).
