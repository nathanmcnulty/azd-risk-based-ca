# Historical risk exposure

Before Conditional Access changes are applied, preprovision sends one read-only Microsoft Graph batch containing five filtered count requests. The result is saved to `reports/azd-risk-ca-historical-impact.json` and summarized in the terminal. No sign-in, risky-user, user-history, role, or group collections are downloaded for this report.

The batch counts:

- high-risk user sign-in events during the previous 30 days;
- low/medium-risk user sign-in events during the previous 30 days;
- medium/high-risk user sign-in events during the previous 30 days;
- currently actionable high-risk users; and
- currently actionable medium/high-risk users.

Sign-in requests filter `riskLevelDuringSignIn`, the risk available when Conditional Access evaluated the sign-in, and explicitly include interactive and noninteractive user events. Risky-user requests use the Identity Protection portal predicate: `atRisk` or `confirmedCompromised`, not deleted, and at the applicable policy risk level. Graph can execute up to 20 requests in a JSON batch; this report uses five independent GET subrequests.

This is not a crawl of the full Identity Protection reports. The implementation queries `auditLogs/signIns` for the previous 30 days and `identityProtection/riskyUsers` without a date filter, so the latter is a current snapshot. It does not query `riskyUsers/{id}/history` or enumerate identities. Microsoft currently documents default retention of 30 days for Entra audit/sign-in logs, 90 days for P2 risky sign-ins, and no limit for risky users; the 90-day portal availability (and any longer tenant-specific retention) is not automatically used by this report. A 180-day window should not be assumed.

## What the counts mean

Sign-in measurements count events, not distinct users. One person can produce several events. Risky-user measurements count the current actionable risky-user records and are not a historical list of everyone who reached that risk level during the reporting period.

All measurements are tenant-wide upper bounds. They intentionally do not enumerate identities to apply current administrator roles, group membership, internal/guest classification, or Conditional Access exclusions. Consequently, the report does not say that a specific number of users would have been blocked, prompted for MFA, or required to remediate. It shows the volume at the risk thresholds used by the generated policies and directs administrators to Identity Protection for investigation.

| Policy | Aggregate signal |
| --- | --- |
| `Admin-SignInRisk-High-Block` | Tenant-wide high-risk sign-in events during the previous 30 days |
| `Admin-SignInRisk-LowMedium-RequireMFA` | Tenant-wide low/medium-risk sign-in events during the previous 30 days |
| `Admin-UserRisk-MediumHigh-Block` | Current tenant-wide medium/high risky users |
| `User-SignInRisk-MediumHigh-RequireMFA` | Tenant-wide medium/high-risk sign-in events during the previous 30 days |
| `User-UserRisk-High-RiskRemediation` | Current tenant-wide high-risk users |

The two security-info registration policies and two device-registration policies remain unevaluable. Sign-in and risky-user reports do not reliably identify those user-action attempts, and ordinary risk events must not be treated as registration attempts.

## Investigate affected identities

The terminal and JSON report always include these administrator links:

- [Risky users report](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyUsers)
- [Risky sign-ins report](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskySignIns)

Use the portal reports to select the relevant risk levels, review the affected identities, and account for current administrator targeting and exclusions. Rerun `azd up` to refresh the aggregate exposure immediately before enabling enforcement, then use report-only Conditional Access results and What If alongside these reports.

## Availability and API boundary

The filtered `/$count` behavior is live-validated for the beta sign-in and risky-user collections, but those collection API pages do not document it as a supported query option. Every subresponse is therefore validated independently. A rejected or malformed count is recorded as unavailable and is never replaced with zero. If the outer batch fails, all five measurements are unavailable while the Identity Protection links remain in the report and terminal output.

The Graph connection requests `AuditLog.Read.All` and `IdentityRiskyUser.Read.All` in addition to the policy, role, group, and signed-in-user scopes used by deployment planning. A Security Administrator can read both data sets. A Conditional Access Administrator needs additional supported read roles such as Reports Reader for sign-ins and Security Reader for risky users.

This design does not assume Log Analytics, diagnostic settings, or exported retention. Organizations that already export `SigninLogs` and Identity Protection tables can perform richer server-side distinct-user analysis independently without adding that dependency to this template.

## Microsoft references

- [Combine Graph requests with JSON batching](https://learn.microsoft.com/graph/json-batching)
- [List sign-ins](https://learn.microsoft.com/graph/api/signin-list)
- [Sign-in risk properties](https://learn.microsoft.com/graph/api/resources/signin)
- [List risky users](https://learn.microsoft.com/graph/api/riskyuser-list)
- [Identity Protection risk reports](https://learn.microsoft.com/entra/id-protection/concept-risk-reports)
- [Microsoft Entra data retention](https://learn.microsoft.com/entra/identity/monitoring-health/reference-reports-data-retention)
