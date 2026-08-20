# Authority Index

Canonical map of what governs GRID-Alpha and where it lives. When documents conflict,
the lower priority number wins.

> **Corrected in P1-00.** The previous revision listed the alpha specification above
> `final-build-spec.md`. That inverted `alpha-spec.md` §1.5, which is the authority on
> its own ordering. See `docs/02-adr/001-repo-bootstrap-decisions.md`.

## Order of authority (alpha-spec.md §1.5)

| Priority | Authority | Location |
|----------|-----------|----------|
| 1 | Final Build Specification | `final-build-spec.md` (repo root) |
| 2 | Alpha Specification | `alpha-spec.md` (repo root) |
| 3 | Accepted Architecture Decision Records | `docs/02-adr/` |
| 4 | Versioned contracts, model specs, schemas, provider manifests | `docs/03-contracts/`, `docs/05-model-specs/`, `docs/04-providers/` |
| 5 | The approved work-package file | `docs/01-work-packages/` |
| 6 | Tests and fixtures implementing approved contracts | `crates/**/tests/`, `fixtures/` |
| 7 | Existing source code, comments, local conventions | `crates/`, `app/` |

Two rules that are easy to get wrong:

- **Existing code is not authoritative merely because it exists.**
- **Tests are not authoritative if they contradict a higher-level approved requirement.**

When you detect a conflict, or an absent decision that materially changes behavior, stop the
work package at a clean boundary and produce a decision request. Do not silently pick an
interpretation.

## Path aliases

`alpha-spec.md` §8.7 sketches a flat `docs/` tree. This repository uses a numbered Obsidian
vault instead, ratified by the product owner and recorded in ADR-001. Spec names resolve as:

| Name used in the specs | Actual path | Status |
|------------------------|-------------|--------|
| `docs/authority.md` | `docs/00-meta/authority-index.md` | this file |
| `docs/adr/` | `docs/02-adr/` | exists |
| `docs/work-packages/` | `docs/01-work-packages/` | exists |
| `docs/providers/` | `docs/04-providers/` | exists |
| `docs/contracts/` | `docs/03-contracts/` | created by P1-01 |
| `docs/model-specs/` | `docs/05-model-specs/` | created by P1-06 |
| `docs/templates/` | `docs/99-templates/` | exists |
| `docs/sessions/` | `docs/06-sessions/` | created on first session log |
| `docs/runbooks/`, `docs/model-cards/`, `docs/traceability/` | not yet created | P1-11 |

## Canonical verification

`scripts/verify.ps1` is **authoritative for merge and release** because the production target
is Windows. `verify.sh` and `just verify` are fast Linux/WSL feedback and cannot replace
Windows CI (alpha-spec.md §8.11).

```text
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -Scope Full   # authoritative
just verify                                                               # Linux smoke
just bootstrap                                                            # once per fresh environment
```

Verification recipes in `justfile` and `scripts/verify.*` are a **frozen contract**. Make the
repository satisfy them; never edit a recipe to make a failure disappear. `scripts/check-verify-parity.sh`
enforces that the `justfile` and `scripts/verify.sh` implementations stay in lockstep.

## Active phase

- **Alpha phase:** 1
- **Current work package:** P1-00 — Agent-Ready Repository Bootstrap
- **Workstream sequence:** alpha-spec.md §9.5 (P1-00 → P1-11)

## Human roles (alpha-spec.md §1.4)

| Role | Authority |
|------|-----------|
| Product/Architecture owner | Requirements and architecture conflicts, ADR approval, scope |
| Statistical owner | Model equations, priors, evaluation design, promotion criteria |
| Data/Licensing owner | Provider access, retention, attribution, benchmark import rights |
| Security/Release owner | Agent permissions, secrets, dependencies, signing, releases |
| Merge reviewer | Final diff and evidence bundle |

All roles are currently held by the repository owner. The implementing agent is never the sole
reviewer, and may not merge, sign, publish, or deploy (alpha-spec.md §1.3).
