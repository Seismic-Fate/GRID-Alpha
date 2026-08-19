# CLAUDE.md — GRID-Alpha

## Authority Order
1. Alpha specification (`alpha-spec.md`)
2. Final build specification (`final-build-spec.md`)
3. `docs/authority-index.md`
4. `docs/adr/` (Architecture Decision Records)
5. `docs/contracts/` (Provider schemas, FFI contracts)
6. `docs/model-specs/` (Statistical equations)
7. `docs/work-packages/` (Active implementation scope)

## Architecture Non-Negotiables
- Native Flutter Windows UI only. No WebView, Electron, browser layer.
- Rust owns all business logic, persistence, and model state.
- `flutter_rust_bridge` v2 is the sole UI/core boundary.
- SQLite + SQLx with compile-time checked queries (`cargo sqlx prepare`).
- No Python runtime in the installed application.
- Deterministic versioning: Data → Feature → Model → Prediction.
- Once-daily external fetch; no continuous polling.

## Statistical Engine First-Class
Ridge, RAPM (sparse CG), Kalman (online + RTS), Empirical-Bayes, Affine, Gradient Boosting (trait-abstracted).

## Concurrency
- Tokio for async I/O, job coordination, scheduling.
- Rayon / `spawn_blocking` for CPU-heavy math. Never block the async runtime.
- CPU-heavy work never runs on the Flutter isolate.

## Data & Identity
- nflverse is primary. CFBD is NCAA supplement.
- `gsis_id` is canonical NFL player key.
- Three-season NFL window strictly enforced.
- NCAA-to-NFL linking: conservative tiers, no auto-promote ambiguous matches.

## Verification & Evidence
- Linux smoke: `just verify` (or `./scripts/verify.sh`)
- Windows authoritative: `.\scripts\verify.ps1 -Scope Full`
- Every work package needs evidence manifest before claiming done.
- No deleting tests to pass. No hand-editing generated FFI code.
- No post-lock data in training features. No competitor data in model training.

## Crate Boundaries
- `domain`: IDs, types, errors, DTOs. No external deps.
- `persistence`: SQLx, migrations, SQLite. No business logic.
- `ingestion`: nflverse, CFBD adapters. Raw data retention.
- `identity`: Player registry, cross-source linking, review queue.
- `features`: Deterministic feature generation, schema versioning.
- `models`: Ridge, RAPM, Kalman, EB, Affine, Boosting trait.
- `simulation`: Correlated Monte Carlo, stat-to-points.
- `scoring`: Fantasy profile transforms, versioned affine mapping.
- `evaluation`: Rolling-origin backtests, PB-MAE, benchmark comparison.
- `governance`: Model promotion, rollback, snapshot, job queue.
- `application`: Commands, queries, events, app services. Orchestrates crates.
- `ffi`: `flutter_rust_bridge` bindings. Thin adapter only.

## Work Package Protocol
1. Read authority and active work package.
2. Read-only exploration (no edits).
3. Plan (file-level, contract impact, test plan).
4. Human gate if architecture/statistical/security change.
5. Implement on isolated branch `wp/P1-XX-description`.
6. Verify incrementally (`cargo test -p grid-<crate>`).
7. Run canonical suite (`just verify`).
8. Generate evidence (`just evidence`).
9. Prepare PR. Do not merge.

## Prohibited Shortcuts
- Inventing provider fields, crates, or Flutter APIs from memory.
- Adding unapproved production dependencies inside feature PRs.
- Regenerating golden files without semantic review.
- Converting typed errors into silent defaults in critical paths.
- Merging, signing, publishing, or deploying autonomously.
- Changing `rust-toolchain.toml` inside a feature PR.
- Rewriting migrations to hide incompatibility.
- Using `sudo` or `rm -rf /` in scripts.