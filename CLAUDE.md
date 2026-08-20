# CLAUDE.md — GRID-Alpha

Durable project rules. Detail lives in versioned docs, not here.
Full map: `docs/00-meta/authority-index.md`. Module rules: `docs/CLAUDE.md`.

## Authority order (alpha-spec.md §1.5)

1. `final-build-spec.md`
2. `alpha-spec.md`
3. `docs/02-adr/` — accepted ADRs
4. `docs/03-contracts/`, `docs/05-model-specs/`, `docs/04-providers/`
5. the approved work package in `docs/01-work-packages/`
6. tests and fixtures implementing approved contracts
7. existing source code and local conventions

Existing code is not authoritative merely because it exists. Tests are not authoritative if
they contradict a higher requirement. On a conflict or a missing decision that changes
behavior: **stop at a clean boundary and raise a decision request.** Do not pick silently.

## Commands

```bash
just bootstrap    # once per fresh environment: dev tools + local SQLite dev database
just verify       # Linux smoke
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1 -Scope Full   # authoritative for merge
```

**Verification recipes are a frozen contract.** Make the repository satisfy them. Never edit a
recipe, weaken a lint, or skip a check to make a failure disappear — if a recipe cannot pass,
stop and report. `scripts/check-verify-parity.sh` keeps `justfile` and `scripts/verify.sh` in
lockstep.

Requires `DATABASE_URL=sqlite:target/grid-dev.db` and `SQLX_OFFLINE` unset for local work; see
`docs/02-adr/002-sqlx-offline-cache.md`. `scripts/check-env-contract.sh` verifies this.

## Architecture non-negotiables

- Native Flutter Windows UI only. No WebView, Electron, or browser layer.
- **Rust owns all authoritative state.** In-memory state is a cache rebuildable from SQLite.
- `flutter_rust_bridge` v2 is the sole UI/core boundary; no business logic in generated code.
- SQLite via SQLx with compile-time-checked queries.
- No Python runtime in the installed application.
- Tokio for async I/O; Rayon or `spawn_blocking` for CPU-heavy math. Never block the runtime.
- Once-daily external fetch. No continuous polling.
- Deterministic versioning: Data → Feature → Model → Prediction.

## Generated files — never hand-edit

| Artifact | Regenerate with |
|---|---|
| `.sqlx/` | `cargo sqlx prepare` |
| `crates/ffi/src/generated/` | the `flutter_rust_bridge` generator |
| `Cargo.lock` | `cargo generate-lockfile` |

Change the source definition and re-run the generator. Golden files are never regenerated
without a reviewed semantic explanation.

## Dependencies and migrations

- No new production dependency without written justification and owner approval. Prefer what
  is already in `[workspace.dependencies]`.
- Verify crate names and APIs against pinned docs or source. Never from memory.
- Major upgrades are their own work package, never folded into feature work.
- `rust-toolchain.toml` is not touched inside a feature PR.
- **Migrations are append-only.** Never rewrite, squash, or delete one to make a build pass.
  Enforced by `scripts/check-migrations.sh`.

## Prohibited (alpha-spec.md Appendix D)

Claiming a command passed when it was not run against the final commit; inventing a provider
field, crate, or API; weakening a test, lint, leakage rule, or security control; converting
malformed data to a healthy default; using post-lock information, competitor projections, or
target outcomes as features; exposing credentials or private data; merging, signing, publishing,
or deploying on the agent's own authority; leaving a critical path stubbed while marking a
package done.

## Branch, commit, PR

- One work package per branch: `wp/P1-XX-description`.
- Atomic commits. The human reviews the diff before each commit.
- PR body follows Appendix C and covers every §12.8 item.
- **The agent never merges.** A fresh-context reviewer who is not the implementer is required.

## Before claiming done

Evidence, not assertion. A completion claim needs the verification command, its exit status,
a test summary, and `.ai/evidence/<WP-ID>/manifest.json`. Generate it with
`just evidence <WP-ID>` — never hand-write it. No unexplained `TODO`, skipped test, or
placeholder may remain in scope.
