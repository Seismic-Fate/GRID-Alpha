# P1-00 — Agent-Ready Repository, Authority Index, CI, Verification Scripts, Templates

Implements [`docs/01-work-packages/p1-00-work-package.md`](docs/01-work-packages/p1-00-work-package.md).

## Outcome

The repository is now self-describing: a fresh session can enter it, discover authority, and
extend it without prior chat context. `just verify` exits 0 — from this tree and from a clean
76-file checkout with no `target/`.

**Non-goals honoured:** no ingestion, models, features, or simulation; no Flutter code beyond
`pubspec.yaml`; no provider fixtures; no branch-protection changes; no `cargo-deny` policy
finalization; no `rust-toolchain.toml` channel change.

## The starting state did not match the work package's preconditions

Read-only exploration found that **no `.rs`, `.dart`, or `.sql` file had ever existed in this
repository**. `crates/` was absent, so all 12 workspace members were dangling and every cargo
command failed at manifest-parse time. Four of five templates were 0 bytes; the fifth was
truncated and backslash-corrupted. `docs/CLAUDE.md` and the authority index both inverted
alpha-spec §1.5. `LICENSE` was GPL-3.0 while `Cargo.toml` declared `MIT OR Apache-2.0`.

## Five obstacles escalated rather than worked around

Each became an ADR with an owner ruling on the record.

| # | Found | Resolution |
|---|-------|-----------|
| 1 | `check-sqlx` and `test-rust` cannot pass against an empty workspace (`cargo nextest` exits **4** on zero tests) | **ADR-002** — minimal SQLx toolchain bootstrap moved P1-02 → P1-00 |
| 2 | Environment presets a stale `DATABASE_URL` from the predecessor `nfl-alpha` name; a committed `.env` cannot override it | **ADR-002** contract + `check-env-contract.sh` |
| 3 | `cargo audit` red on RUSTSEC-2023-0071 (`rsa`, no fix available) via `sqlx-mysql`; feature narrowing tested and ineffective | **ADR-003** — sqlx 0.8 → 0.9 (one-line diff) |
| 4 | Every file CRLF, leaving `scripts/verify.sh` **unparsable by bash** — the §8.11 canonical Linux command could not run | **ADR-004** + `.gitattributes` |
| 5 | `check-sqlx` unsatisfiable: sqlx-cli 0.9 refuses a virtual workspace root without `--workspace` | **ADR-005** amending D5 |

## Architecture, contract, schema, model, FFI impact

- **FFI:** none. No FFI surface exists; `crates/ffi/src/generated/` is an empty placeholder. `grid-ffi` gains only `[features] flutter-bridge-tests = []`, named by the frozen `test-ffi` recipe.
- **Public Rust API:** two items, both in `grid-persistence` — `SCHEMA_VERSION_KEY` and `schema_meta_value()`.
- **Schema:** one infrastructure migration, `0001_schema_meta.sql`. Not a domain table; all domain schema remains P1-02.
- **Version impact: none.** Workspace stays `0.1.0-alpha.1` — nothing has been published, so no bump is required.
- **Model/statistical semantics:** untouched.

## Verification recipes are frozen (ADR-001 D5) — full audit

Across all three implementations, **exactly one command changed**:

```diff
- cargo sqlx prepare --check -- --lib
+ cargo sqlx prepare --check --workspace -- --lib
```

Applied identically to `justfile`, `scripts/verify.sh`, and `scripts/verify.ps1`;
`check-verify-parity.sh` proves they agree. Every other `justfile` change is inside
`bootstrap`, which is not a verify recipe. `scripts/verify.sh` is otherwise byte-identical to
`origin/main` modulo line endings:
`diff <(git show origin/main:scripts/verify.sh | tr -d '\r') scripts/verify.sh` shows only that line.

This **strengthens** the gate: it went from always erroring during argument parsing to actually
verifying cache freshness. Proven by mutation — editing the query gives exit 1
(`missing one or more queries`), restoring gives exit 0.

## Migration and rollback

`migrations/0001_schema_meta.sql` creates one table. Forward path `sqlx migrate run`, tested
against a blank database. Rollback: revert the branch — the database lives in gitignored
`target/`. The directory is append-only from here, enforced by `check-migrations.sh`.

## Tests added and why

| Test | Why |
|------|-----|
| `migrations_apply_to_a_blank_database` | Proves the migration toolchain end-to-end (FBS §8.2: "use sqlx migrate from day one") |
| `absent_key_is_none_not_an_error` | A missing key is `Ok(None)`, never conflated with failure (§12.7 forbids silent-default conversion) |

These are the first tests in the repository and the reason `cargo nextest run --workspace` can
pass at all. Six guard scripts are behaviour-tested against synthetic git ranges — including a
false-negative found and fixed in `check-secrets.sh`, which initially ignored untracked files.

## Data, licensing, security

- **License corrected** to `MIT OR Apache-2.0` (ADR-001 D4); texts copied verbatim from canonical sources, not reproduced from memory.
- **Security fix:** RUSTSEC-2023-0071 removed from the graph (ADR-003).
- **`.claude/settings.json`** adds a least-privilege profile per §14.1 — **requires Security/Release owner approval.**
- **No secrets committed.** `.env` holds only a credential-free relative SQLite path.
- **No new dependencies.** `sqlx` is a version bump of an existing declaration; no crate was added.
- CI uses only `actions/checkout` — no third-party actions in a security-boundary file.

---

## Completion record (Appendix C)

```text
Work package:                    P1-00
Final commit:                    f5d0d8bb41675a715e37353373f2e5d0629a4824
                                 (code series head; the evidence commit follows it)
Model/harness identifier:        claude-opus-5 (project alias; provider id and harness version
                                 read from ai-toolchain.lock, per alpha-spec 1.3)
Environment:                     grid-alpha-opus5 (Linux 6.18.5; rustc 1.94.1; cargo 1.94.1)
Authority documents read:        final-build-spec.md 2,3,7,8,19,21,22,23
                                 alpha-spec.md 1.1-1.6, 4.6, 8.1, 8.7-8.12, 9.2, 9.4, 9.5,
                                   12.7-12.9, 14, 17.1, 17.3, Appendices B/C/D/E
                                 docs/CLAUDE.md; docs/00-meta/authority-index.md
                                 docs/01-work-packages/p1-00-work-package.md
                                 docs/adr/ (empty — no ADRs existed)
Contracts changed:               None. No FFI DTO, no provider schema, no model spec.
                                 New public API: grid-persistence::{SCHEMA_VERSION_KEY,
                                 schema_meta_value}. Workspace version unchanged (0.1.0-alpha.1).
Migrations changed:              migrations/0001_schema_meta.sql (added; append-only)
Dependencies changed:            sqlx 0.8 -> 0.9 (ADR-003, security). No crate added or removed.
Targeted tests:                  cargo test -p grid-persistence --lib   -> 2 passed
                                 cargo test -p grid-ffi --features flutter-bridge-tests -> 0 tests, ok
                                 6 guard scripts behaviour-tested on synthetic git ranges
Canonical verification command:  just verify
Verification exit status:        0
Golden files changed:            N/A — no golden files exist (P1-06)
Performance evidence:            N/A — no performance target is affected (no code to measure)
Security/licensing review:       RUSTSEC-2023-0071 remediated (ADR-003). License corrected to
                                 MIT OR Apache-2.0 (ADR-001 D4). .claude/settings.json
                                 least-privilege profile AWAITS Security/Release owner approval.
Fresh-context reviewer:          PENDING — not performed. alpha-spec 1.4 and 8.8.2 require a
                                 reviewer who is not the implementer.
Reviewer findings resolved:      PENDING
Human approvals:                 Obtained: D1 branch naming; D2 remediate skeleton in P1-00;
                                 D3 numbered vault; D4 MIT OR Apache-2.0; D5 frozen recipes;
                                 D6 environment fix; ADR-003; ADR-004; ADR-005.
                                 Outstanding: Security/Release owner on .claude/settings.json;
                                 Merge reviewer on the CI skeleton.
Known limitations:               (1) scripts/verify.ps1 -Scope Full NOT RUN — authoritative for
                                     merge but Windows-only; runs in the windows-authoritative job.
                                 (2) check-env-contract.sh fails in-session: the stale
                                     DATABASE_URL/SQLX_OFFLINE are baked into the running
                                     process. Needs the owner's environment fix plus a new
                                     session. CI unaffected.
                                 (3) -Scope Changed still unimplemented in both verify scripts
                                     though 8.11 cites it as canonical. Deferred to P1-11.
                                 (4) justfile and verify.sh remain duplicate implementations;
                                     unification barred by D5, drift guarded by parity check.
                                 (5) Cargo.toml, ai-toolchain.lock, rust-toolchain.toml and
                                     justfile retain CRLF. Normalization deferred to P1-11.
                                 (6) No fixtures. 9.5 lists them under P1-00; deferred to
                                     P1-03/P1-04 and recorded in ADR-001.
                                 (7) No fresh-context review performed.
Evidence manifest hash:          sha256:a9be52b5fe811f6ebfed705012b936e4f5352f3a831466c5c5a9fae518d57384
                                 (.ai/evidence/P1-00/manifest.json — regenerate after commit)
```

## Commit sequencing — read before merging

The manifest records `commit` and `files_changed`, but is itself part of the commit, so it
cannot contain its own final SHA. It currently records
`commit_info.state: "uncommitted: 72 path(s) not yet in 48ee320…"` — deliberately, so no one
mistakes it for evidence against a final commit.

Proposed: commit the atomic series, then regenerate the manifest as the **last** commit so it
records the preceding SHA. §12.8 forbids claiming a command passed unless it was run against
the final commit — so `just verify` must be re-run after the series lands, and the manifest
hash above will change.

---
_Generated by [Claude Code](https://claude.ai/code)_
