# Backlog: nathanmcnulty/azd-risk-based-ca

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-risk-based-ca
- **Source revision:** `7b62f0c15102bfa298c035c21c5eaae60db7e6dd`
- **Captured:** 2026-10-04
- **Items:** 5

## RISK-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Plans and implementation evidence are spread across files; the captured source can change while other tasks work.

**Scope:**

- docs/backlog.json
- docs/backlog.md
- Existing roadmap, execution status, open issues and pull requests &lpar;read-only&rpar;

**Acceptance:**

- Classify each candidate as implemented, still open, superseded or awaiting evidence; retain source links and reasons.
- Inspect dirty state, remotes, worktrees and local environment presence without reading secrets; avoid duplicate work with active owners.
- Resolve the actual offline validation commands and record exact current default-branch/working-tree provenance; do not copy historical live passes to newer code.

**Validation:**

- git status --short
- git remote -v
- git worktree list --porcelain
- Read the applicable instructions and validation workflow; read gh issue list and gh pr list for the named repository using nathanmcnulty. Do not create or modify issues/PRs.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md
- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/pull/19
- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/pull/16
- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/pull/22
- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/pull/23

**Evidence:**

- Reconciled against current main 7b62f0c15102bfa298c035c21c5eaae60db7e6dd in a clean worktree. Issues &num;20 and &num;21 are closed by merged PRs &num;22 and &num;23; PRs &num;16 and &num;19 remain open Dependabot updates. The canonical permission-tracking checkout and its .azure directory were preserved without reading values; no .env path was present.
- Current-base scripts/Test-Repository.ps1 passed&colon; 101/101 Pester, 19/19 Node, production npm audit with zero vulnerabilities, PowerShell analysis, schema-constrained JSON, pinned Bicep and whitespace checks. No tenant, Graph or delivery operation ran.

**Review and authorization note:**

Review RISK-001 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## RISK-004: Record an explicit recovery gap after notification poller outages over 24 hours

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/issues/21
- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/pull/23

**Evidence:**

- Issue &num;21 is fixed by merged PR &num;23 at current main&colon; core.js and index.js query from the last successful checkpoint and oldest pending destination within a seven-day bound, retain explicit older/unknown recovery gaps and do not advance after failed query/state writes. The PR reports 101 Pester and 19 Node tests, validator, Bicep/schema and audit checks; no live Graph or delivery operation ran.

**Review and authorization note:**

Review RISK-004 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## RISK-005: Validate Graph continuation authority before attaching managed identity token

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/issues/20
- https&colon;//github.com/nathanmcnulty/azd-risk-based-ca/pull/22

**Evidence:**

- Issue &num;20 is fixed by merged PR &num;22 at 55a14c6bb281a24143775b6120daf78aed3d377b&colon; core.js validates HTTPS Graph origin and exact risk-detection route, rejecting userinfo, fragments, cycles and excessive pages before forwarding the managed identity token. Hostile continuation fixtures and the reported 101 Pester/13 Node full gate passed; no live Graph request ran.

**Review and authorization note:**

Review RISK-005 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## RISK-002: Qualify report-only canary, routes and migration rollback

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Policy creation does not establish safe report-only impact, real notifications or legacy-policy migration recovery.

**Scope:**

- docs/policies-and-safety.md
- scripts/
- tests/

**Acceptance:**

- Use exact selected tenant and emergency exclusions; analyze report-only results before any enabled state.
- Record administrator/user route receipts and retry/deduplication outcomes.
- Test legacy migration/rollback and adopted-object cleanup without treating the backlog as enforcement authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md
- AGENTS.md
- docs/policies-and-safety.md

**Evidence:**

- _none_

**Review and authorization note:**

Review RISK-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## RISK-003: Improve optional-feature validation and permission comparison

- **Kind:** maintenance
- **Priority:** P2
- **Status:** done
- **Wave:** 2
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Existing pilot components should make disabled, pending and unhealthy features visible without changing CA policy.

**Scope:**

- scripts/
- infra/
- tests/
- docs/
- azd-permissions.json

**Acceptance:**

- Keep a feature matrix for baseline, poller and Azure Monitor route choices with exact permission additions.
- Fixtures prove absent workspace, bad receiver, empty audience and state checkpoint failures are explicit.
- Use current component locks; KQL, migration logic and policy behavior remain local.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- deployment-validation
- notification-contracts
- azure-monitor-scheduled-query-notifications
- flex-scheduled-poller-host

**Sources:**

- README.md

**Evidence:**

- Local implementation reviewed from published main 1028ba8f0fbaacd9c7d09807c36cf4e9207a1e3d on 2026-10-10. docs/notification-feature-matrix.md maps current none, graph and logAnalytics modes and both admin delivery routes, including explicit optional Graph consent and scoped Blob role additions. Current immutable component locks, policy/KQL/migration behavior and rollout state are unchanged.
- Added a canonical-schema partial azd-permissions.json with current-source SHA-256 evidence. Tests compare selected delegated scopes with the actual Get-AzdRiskCaGraphPermissionScope function for all three modes and keep bootstrap consent separate from optional runtime identities. Connector, workspace, deployment/cleanup, role alternatives and shared-key authority gaps remain explicit; the inventory does not approve grants.
- The actual workflow Storage MSI audience gate rejects empty/wrong/missing audiences including nested user actions. Actual configuration fixtures prove absent workspace ID/location, bad receiver URL and disabled optional paths. The real exported Graph poller handler propagates state-read and Graph-read errors, rejects checkpoint writes including ETag conflict without a success log, and omits an absent user destination while preserving admin delivery. All HTTP operations in these fixtures are mocked.
- Registered offline validator passed on PowerShell 7.6.6 with 117 Pester and 25 Node tests, PowerShell parser/analyzer, JSON/component schema, npm audit zero vulnerabilities, Bicep 0.46.1 and Git whitespace checks. The initial attempt failed correctly on host Bicep 0.42.1; rerun used a copied pinned binary in a task-private Azure CLI config, with no authentication or service mutation.
- This item completes the original local feature matrix, permission comparison and failure fixture acceptance. It does not establish live Graph/workspace visibility, connector consent, enabled resource health, sender completion or recipient receipt. Those selected-target live gates remain in RISK-002; no tenant, Azure, connector or notification operation ran.

**Review and authorization note:**

Review RISK-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
