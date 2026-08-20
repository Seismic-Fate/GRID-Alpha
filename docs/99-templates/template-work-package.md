---
work-package-id:
status: Draft            # Draft | Ready | In Progress | Review | Done | Blocked
risk-class: Medium       # Low | Medium | High | Release-critical
owner:
implementer:
reviewer:
alpha-phase: 1
---

<!--
Structure follows alpha-spec.md Appendix B exactly, in order, with two documented additions
ratified in P1-00 (see docs/02-adr/001-repo-bootstrap-decisions.md):
  1. YAML frontmatter — Appendix B has none, but docs/00-meta/dashboard.md queries these
     fields via Dataview. Keys are hyphenated to match that query.
  2. "Security and licensing considerations" — required by alpha-spec.md 8.8's contents
     list, which Appendix B omits.
Copy this file to docs/01-work-packages/<work-package-id>.md and fill every section.
A section that does not apply says "Not applicable" plus one line of justification.
-->

# <WORK_PACKAGE_ID> — <Title>

## Status
Draft | Ready | In Progress | Review | Done | Blocked

## Ownership and risk
- Owner:
- Implementer:
- Reviewer:
- Risk class: Low | Medium | High | Release-critical
- Required human approvals:
- Agent budget (alpha-spec.md 8.10.1): max turns, wall-clock timeout, concurrent writers, cost ceiling

## Authority
- `final-build-spec.md`: <sections>
- Alpha spec: <sections>
- ADRs/contracts/model specs/provider manifests:

## Objective
One measurable outcome.

## User-visible outcome
What a user or operator can observe, or "none" for infrastructure work.

## Preconditions
Merged packages, fixtures, decisions, and environment requirements.
A package is Ready only when dependencies are **merged and passing** (alpha-spec.md 8.8.1).

## Scope
- Modules/files expected to change
- Contracts consumed
- Contracts changed

## Non-goals
Explicitly excluded work.

## Inputs and fixtures
Named, versioned, sanitized inputs.

## Implementation constraints
Architecture, dependency, timing, determinism, security, and licensing rules.

## Security and licensing considerations
Secrets touched, permission changes, new hosts, provider license and retention terms,
redistribution limits. "None" is an acceptable answer; silence is not.

## Acceptance criteria
- [ ] Criterion with objective evidence
- [ ] Criterion with objective evidence

## Verification
```text
<targeted commands>
<canonical verify command>
```
Verification recipes are a frozen contract. Make the repository satisfy them; never edit a
recipe to make a failure disappear.

## Numerical/performance tolerances
Declared units, error bands, machine/dataset assumptions, or "not applicable."

## Migration and rollback
Forward path, upgrade fixtures, backup/rollback behavior, or "not applicable."
Migrations are append-only.

## Evidence required
Test output, screenshots, benchmark results, hashes, generated files, and review report.
Generate with `just evidence <WORK_PACKAGE_ID>`; never hand-write the manifest.

## Stop/decision conditions
Questions the implementer must escalate rather than decide silently.

## Follow-up
Deferred work with risk statement.
