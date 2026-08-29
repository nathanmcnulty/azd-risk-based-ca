# Policies and safety

The template manages nine Conditional Access policies. Their checked-in JSON definitions live in [`policies/`](../policies/), and the deployment reads those files directly. It then materializes tenant-specific Graph request bodies by discovering built-in directory role template IDs and applying the configured groups, exclusions, state, and authentication strength. No policy definition is downloaded from another repository.

## Policy catalog

| Name | Target | Risk condition | Grant/session behavior |
| --- | --- | --- | --- |
| `Admin-SignInRisk-High-Block` | All live built-in roles; optional admin group | Sign-in: high | Block; every time |
| `Admin-SignInRisk-LowMedium-RequireMFA` | Same administrator target | Sign-in: low, medium | MFA; every time |
| `Admin-UserRisk-MediumHigh-Block` | Same administrator target | User: medium, high | Block; every time |
| `User-SignInRisk-MediumHigh-RequireMFA` | All users | Sign-in: medium, high | MFA; every time |
| `User-UserRisk-High-RiskRemediation` | Internal users; guests excluded | User: high | `mfa` + `riskRemediation`, `AND`; every time |
| `User-UserRisk-Any-Block-SecurityInfoRegistration` | All users; security-info registration | User: low, medium, high | Block; no session controls |
| `User-SignInRisk-Any-Block-SecurityInfoRegistration` | All users; security-info registration | Sign-in: low, medium, high | Block; no session controls |
| `User-UserRisk-Any-RequireStrongAuth-DeviceRegistration` | All users; device registration | User: low, medium, high | Built-in phishing-resistant strength; no session controls |
| `User-SignInRisk-Any-RequireStrongAuth-DeviceRegistration` | All users; device registration | Sign-in: low, medium, high | Built-in phishing-resistant strength; no session controls |

Device registration never uses Block. Set `AZD_CA_USE_TAP_AUTH_STRENGTH=true` to create or explicitly adopt a custom Temporary Access Pass strength containing only `temporaryAccessPassOneTime` and `temporaryAccessPassMultiUse`.

## Safe rollout

Provisioning defaults every policy to `enabledForReportingButNotEnforced`. Review the generated plan, the [risk-exposure summary](historical-impact.md), its linked Identity Protection reports, and the applied report; inspect sign-in logs across a normal access cycle; and use Conditional Access What If for administrators, internal users, guests, registration actions, and emergency accounts. Only then set `AZD_CA_POLICY_STATE=enabled`; the hook requires an exact tenant-ID confirmation.

An existing emergency-access group is preferred. If it is omitted, the signed-in operator is excluded as a temporary single-user failsafe. A same-name object is never treated as owned automatically; set `AZD_CA_ADOPT_EXISTING=true` only after reviewing it.

## Policy coverage

The baseline includes administrator high-risk block, administrator low/medium-risk MFA, administrator medium/high user-risk block, user sign-in-risk MFA, high user-risk remediation, security-info registration blocks, and phishing-resistant device-registration requirements. The device-registration policies never use Block. The `mfa` plus `riskRemediation` grant is a portal-supported Graph beta preview shape and is not silently replaced with password change or another control.

The `mfa` plus `riskRemediation` `AND` grant is sent through the Graph beta Conditional Access endpoint because v1.0 returns errors 1037/1038 for this portal-supported preview policy. The other eight policies and non-preview resources use v1.0. A Graph rejection stops deployment; the solution does not substitute password change or authentication strength and does not continue legacy cutover.

## Ownership and rollback

`azd down` preserves tenant objects by default. Explicit cleanup uses recorded ownership and restores adopted objects where supported. If a later policy write fails, the apply phase compensates in reverse order and preserves a checkpoint when compensation is incomplete.

## References

- [Create Conditional Access policy and permissions](https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies)
- [Conditional Access user actions and device-registration limitations](https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps)
- [Conditional Access identity targeting](https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-users-groups)
- [Grant-control considerations](https://learn.microsoft.com/graph/api/resources/conditionalaccessgrantcontrols)
