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
Final commit:                    bab9dfa3ab21892094a5f3d839d4ca95fc312b4c
                                 (code head; the evidence commit follows, not self-covered)
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
Fresh-context reviewer:          DONE - independent adversarial agent, PR #2.
                                 Verdict CONDITIONAL: 6 blockers, 10 major, 9 minor.
Reviewer findings resolved:      6/6 blockers + highest-value major, each reproduced
                                 before fixing. Remaining major/minor NOT triaged.
Human approvals:                 TWO DIFFERENT THINGS, previously conflated (review finding C5).
                                 DECISION RULINGS OBTAINED - given by the owner in-session, each
                                 answering an explicit question naming the alternatives:
                                   D1 branch naming; D2 remediate skeleton inside P1-00;
                                   D3 numbered vault; D4 MIT OR Apache-2.0; D5 frozen recipes;
                                   D6 environment fix; ADR-003; ADR-004; ADR-005.
                                 ROLE-SCOPED SIGN-OFFS OBTAINED - none. A ruling on a question
                                 is not a review of a diff. Still required:
                                   Architecture owner  authority order, crate boundaries,
                                                       the P1-02 -> P1-00 rework
                                   Security/Release    .claude/settings.json
                                   Data/Licensing      D4, which was outside P1-00's stated scope
                                   Merge reviewer      CI skeleton and the final diff
                                 The owner holds every role per the authority index, so both
                                 statements are true at once - but not interchangeable.
Known limitations:               (1) scripts/verify.ps1 -Scope Full NOT RUN - authoritative for
                                     merge but Windows-only; has never completed anywhere.
                                 (2) Remaining 10 major / 9 minor review findings NOT triaged.
                                     Only the 6 blockers and the top major are resolved.
                                 (3) An evidence manifest cannot record its own commit SHA. It
                                     attests to 4de62ec774a6; the manifest commit follows.
                                     CI is authoritative on the true final commit (12.8).
                                 (4) -Scope Changed still unimplemented in both verify scripts
                                     though 8.11 cites it as canonical. Deferred to P1-11.
                                 (5) justfile and verify.sh remain duplicate implementations;
                                     unification barred by D5, drift guarded by parity check.
                                 (6) Cargo.toml, ai-toolchain.lock, rust-toolchain.toml and
                                     justfile retain CRLF. Normalization deferred to P1-11.
                                 (7) No fixtures. 9.5 lists them under P1-00; deferred to
                                     P1-03/P1-04 and recorded in ADR-001.
                                 (8) The stale grid-alpha-opus5 environment is still uncorrected;
                                     .env now supplies correct values when the environment does
                                     not override, so CI and fresh clones are unaffected.
Evidence manifest hash:          sha256:d90ccdc3f1471f2a9262cdd1ccd927f9a384d893fbe9d83c835a9469006cdeda
                                 (.ai/evidence/P1-00/manifest.json — regenerate after commit)
```

## Independent adversarial review — PR #2

A fresh-context reviewer examined the branch at `7787921` and returned **CONDITIONAL: 6
blockers, 10 major, 9 minor**. Every blocker was reproduced here before being fixed. Findings
and dispositions are in the evidence manifest under `review`, per §8.12.

| | Finding | Disposition |
|---|---|---|
| **M1** | `check-secrets.sh` **failed open** — invalid empty-tree git expression, fatal swallowed by a fallback, printed OK having scanned nothing tracked | Fixed. Fails closed; regression-tested against a committed `ghp_` token with no `origin/main` |
| **C1** | `just bootstrap` fails on a fresh checkout (SQLite code 14) | Already fixed in `d35a905`; CI reached the same diagnosis independently |
| **C2** | Fresh clone would not compile: `.env` set `DATABASE_URL` without `SQLX_OFFLINE`, so the committed cache was never consulted (exit 101) | Fixed. ADR-002 corrected — it had stated the opposite |
| **C3** | Manifest attested to a commit 4 behind HEAD, two of them touching CI-gating code | Fixed. Regenerated against `bab9dfa` |
| **C4** | PR body claimed `commit_info.state` reads `clean`; the artifact read `uncommitted: 3 path(s)` | Fixed. **I asserted what I intended the artifact to say without re-reading it.** Removed |
| **C5** | Approvals read as contradictory: role sign-offs "not obtained" beside ADRs asserting owner acceptance | Fixed. Rulings and sign-offs separated; a ruling on a question is not a review of a diff |
| **C6** | Licence change out of stated scope, attributed to the wrong role | Fixed. Re-attributed to Data/Licensing owner; scope deviation recorded. D4 touches only `LICENSE*` and is independently revertible |

**The remaining major and minor findings are not yet triaged** — outstanding work on this PR,
recorded as a known limitation rather than quietly closed.

The reviewer also confirmed what holds: the §1.5 authority-order correction, ADR-004's
whitespace-only claim for `verify.sh`, the manifest hash, a 172-crate licence census against
`deny.toml`, and `cargo fmt` / `clippy -D warnings` / both tests. `cargo deny`, `cargo audit`
and `typos` were unavailable in their environment, so RUSTSEC remediation was confirmed there
only indirectly; it is confirmed directly here (`cargo audit` exit 0).

## Commit sequencing

An evidence manifest cannot record the SHA of its own commit. This one attests to **`bab9dfa`**,
the head of every code and documentation change; the manifest commit follows it.
`commit_info.state` reads `uncommitted: 1 path(s)` — the manifest file itself at generation
time, inherent to the ordering. Per §12.8, **CI is authoritative on the true final commit.**

## Before merging

**Do not merge on the agent's authority** (§1.3, Appendix D). Outstanding:

- **Triage of the remaining major and minor review findings** — the 6 blockers are fixed, the rest are not.
- **Role-scoped sign-offs**: Security/Release on `.claude/settings.json`; Data/Licensing on the
  out-of-scope D4 licence change; Merge reviewer on the final diff.
- **`windows-authoritative` CI must pass** — `verify.ps1 -Scope Full` is authoritative for merge
  and has never completed successfully anywhere.

Owner follow-ups: correct the `grid-alpha-opus5` environment per ADR-002, and configure branch
protection on `main` (an explicit P1-00 non-goal).

---
_Generated by [Claude Code](https://claude.ai/code)_
