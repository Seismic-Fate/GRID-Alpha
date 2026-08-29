# Architecture Decision Records

Accepted ADRs are **authority level 3** (`alpha-spec.md` §1.5) — above contracts, model specs,
and work packages; **below** `final-build-spec.md` and `alpha-spec.md`. An ADR can resolve an
ambiguity or record a deviation ratified by the product owner. It can never override either
specification.

## Numbering

`NNN-kebab-case-title.md`, zero-padded, allocated in order and never reused. An ADR is
immutable once Accepted: to change a decision, write a new ADR and set `superseded-by` on
the old one and `supersedes` on the new one.

Start from `docs/99-templates/template-adr.md`.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-repo-bootstrap-decisions.md) | Repository bootstrap decisions | Accepted | 2026-08-20 |
| [002](002-sqlx-offline-cache.md) | SQLx offline cache and database provisioning | Accepted | 2026-08-20 |
| [003](003-sqlx-0-9-upgrade.md) | Upgrade sqlx 0.8 to 0.9 | Accepted | 2026-08-20 |
| [004](004-line-ending-policy.md) | Line-ending policy | Accepted | 2026-08-20 |
| [005](005-check-sqlx-workspace-flag.md) | Amend check-sqlx with --workspace | Accepted | 2026-08-20 |
| [006](006-deferred-deliverables.md) | Deferred 8.7/9.2 deliverables | Accepted | 2026-08-20 |
| [007](007-verify-covers-guards-and-doctests.md) | verify covers guards and doctests | Accepted | 2026-08-20 |
| [008](008-verify-scope-guard.md) | Validate the scope argument in verify.sh | Accepted | 2026-08-20 |
| [009](009-verify-ps1-exit-codes.md) | verify.ps1 must propagate native exit codes | Accepted | 2026-08-20 |
| [010](010-guard-the-shape-not-the-instance.md) | Fix the shape, not the instance: where a fail-closed guard belongs | Accepted | 2026-08-29 |
