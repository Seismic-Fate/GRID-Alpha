# P1-00 — Agent-Ready Repository, Authority Index, CI, Verification Scripts, Templates

Implements [`docs/01-work-packages/p1-00-work-package.md`](docs/01-work-packages/p1-00-work-package.md).

## Outcome

The repository is self-describing: a fresh session can enter it, discover authority, and extend
it without prior chat context. `just verify` exits 0 across **9 recipes** — from this tree and
from a clean checkout with no `target/`.

**Non-goals honoured:** no ingestion, models, features, or simulation; no Flutter code beyond
`pubspec.yaml`; no provider fixtures; no branch-protection changes; no `cargo-deny` policy
finalization; no `rust-toolchain.toml` channel change.

## The starting state did not match the work package's preconditions

Read-only exploration found that **no `.rs`, `.dart`, or `.sql` file had ever existed in this
repository**. `crates/` was absent, so all 12 workspace members were dangling and every cargo
command failed at manifest-parse time. Four of five templates were 0 bytes; the fifth was
truncated and backslash-corrupted. `docs/CLAUDE.md` and the authority index both inverted
alpha-spec §1.5. `LICENSE` was GPL-3.0 while `Cargo.toml` declared `MIT OR Apache-2.0`.

## Obstacles escalated rather than worked around

Each became an ADR with an owner ruling on the record.

| ADR | Found |
|---|---|
| **002** | `check-sqlx` and `test-rust` cannot pass against an empty workspace (`cargo nextest` exits **4** on zero tests) → minimal SQLx toolchain moved P1-02 → P1-00 |
| **002** | Environment presets a stale `DATABASE_URL` from the predecessor `nfl-alpha` name; a committed `.env` cannot override it |
| **003** | `cargo audit` red on RUSTSEC-2023-0071 (`rsa`, no fix available) via `sqlx-mysql`; feature narrowing tested and ineffective → sqlx 0.8 → 0.9 |
| **004** | Every file CRLF, leaving `scripts/verify.sh` **unparsable by bash** — the §8.11 canonical Linux command could not run |
| **005** | `check-sqlx` unsatisfiable: sqlx-cli 0.9 refuses a virtual workspace root without `--workspace` |
| **006** | §8.7/§9.2 deliverables absent without a recorded deviation |
| **007** | §8.11's secret scanning, traceability and doctests absent from the canonical command |
| **008** | `scripts/verify.sh` accepted any scope and exited 0 having run nothing |

## Architecture, contract, schema, model, FFI impact

- **FFI:** none. No FFI surface exists; `crates/ffi/src/generated/` is an empty placeholder. `grid-ffi` gains only `[features] flutter-bridge-tests = []`, named by the frozen `test-ffi` recipe.
- **Public Rust API:** two items, both in `grid-persistence` — `schema_meta_value()` and `applied_schema_version()`. (An earlier revision of this body named `SCHEMA_VERSION_KEY`, deleted in `a37e49f`.)
- **Schema:** one infrastructure migration, `0001_schema_meta.sql`. Not a domain table; all domain schema remains P1-02, which is pre-approved to retire it by forward migration (ADR-002).
- **Version impact: none.** Workspace stays `0.1.0-alpha.1` — nothing has been published.
- **Model/statistical semantics:** untouched.

## Verification recipes are frozen (ADR-001 D5) — full audit

`verify` runs **9 recipes**. Across the branch, **three command lines changed**, each under an
owner ruling recorded in its own ADR:

```diff
- cargo sqlx prepare --check -- --lib
+ cargo sqlx prepare --check --workspace -- --lib     # ADR-005
+ cargo test --workspace --doc                        # ADR-007
+ just check-guards                                   # ADR-007
```

ADR-008 adds scope validation to `scripts/verify.sh` and **changes no command at all** — it
replaces the argument dispatcher above the checks. `check-verify-parity.sh` confirms the
justfile and `verify.sh` agree at **16 steps**, order-sensitively.

**D5 has now been amended three times.** All three *increased* coverage: a gate that always
errored during argument parsing became one that verifies cache freshness; two checks §8.11
requires were absent from the canonical command; and an entry point that could pass without
running now cannot. An amendment that *reduces* coverage should be refused outright rather than
weighed against these.

## Migration and rollback

`migrations/0001_schema_meta.sql` creates one table. Forward path `sqlx migrate run`, tested
against a blank database. Rollback: revert the branch — the database lives in gitignored
`target/`. The directory is append-only from here, enforced by `check-migrations.sh`.

## Tests added and why

| Test | Why |
|------|-----|
| `migrations_apply_to_a_blank_database` | Proves the migration toolchain end-to-end (FBS §8.2: "use sqlx migrate from day one") |
| `absent_key_is_none_not_an_error` | A missing key is `Ok(None)`, never conflated with failure (§12.7 forbids silent-default conversion) |
| `schema_meta_round_trips` | The applied version is derived from the migrator, not a hand-written literal that would go stale at `0002` |

Three tests — the first in the repository, and the reason `cargo nextest run --workspace` can
pass at all. **`tests/guards/run.sh` carries 35 committed behaviour cases** covering all six
guard scripts and the `verify.sh` scope guard, run inside `just verify` (ADR-007).

That suite has now caught four defects that reading did not. `check-secrets.sh` needed two
fixes: it first ignored untracked files, then — found by the first adversarial review — **failed
open** on an invalid git expression, reporting OK over a committed secret. Writing the parity
cases for this round exposed that two silently-empty extractions would have compared equal, and
that the script did not even fail cleanly when they did. And an over-broad ancestor match in the
traceability fix was caught by the suite on its first run.

## Data, licensing, security

- **License corrected** to `MIT OR Apache-2.0` (ADR-001 D4); texts copied verbatim from canonical sources, not reproduced from memory. See the licensing note under the review section below.
- **Security fix:** RUSTSEC-2023-0071 removed from the graph (ADR-003). Verified: `Cargo.lock` resolves 172 crates and contains zero `rsa` entries.
- **Build tooling is pinned** in `toolchains/dev-tools.lock` and in both installers; both CI jobs echo their resolved versions. `--locked` pins a tool's dependencies, only `--version` pins the tool.
- **`.claude/settings.json`** adds a least-privilege profile per §14.1 — **requires Security/Release owner approval.**
- **No secrets committed.** `.env` holds a credential-free relative SQLite path plus `SQLX_OFFLINE=true`, which is what lets a fresh clone compile against the committed cache. That property is now a CI regression gate.
- **No new dependencies.** `sqlx` is a version bump of an existing declaration; no crate was added.
- CI uses only `actions/checkout` — no third-party actions in a security-boundary file. `cargo audit`'s advisory-database fetch is a recorded, accepted network dependency (ADR-002).

---

## Completion record (Appendix C)

```text
Work package:                    P1-00
Final commit:                    a0a307affd86  (code head; the evidence commit follows
                                 and is not self-covered -- a manifest cannot record its own SHA)
Model/harness identifier:        claude-opus-5 (project alias; provider id and harness version
                                 read from ai-toolchain.lock, per alpha-spec 1.3)
Environment:                     grid-alpha-opus5 (Linux 6.18.5; rustc 1.94.1; cargo 1.94.1)
Authority documents read:        final-build-spec.md 2,3,7,8,19,21,22,23
                                 alpha-spec.md 1.1-1.6, 4.6, 8.1, 8.7-8.12, 9.2, 9.4, 9.5,
                                   12.7-12.9, 14, 17.1, 17.3, Appendices B/C/D/E
                                 docs/CLAUDE.md; docs/00-meta/authority-index.md
                                 docs/01-work-packages/p1-00-work-package.md
                                 docs/adr/ (empty at authority-load time -- no ADRs existed;
                                   the eight in docs/02-adr/ were written by this package)
Contracts changed:               None. No FFI DTO, no provider schema, no model spec.
                                 New public API: grid-persistence::{schema_meta_value,
                                 applied_schema_version}. Workspace version unchanged
                                 (0.1.0-alpha.1).
Migrations changed:              migrations/0001_schema_meta.sql (added; append-only)
Dependencies changed:            sqlx 0.8 -> 0.9 (ADR-003, security). No crate added or removed.
                                 Dev tooling pinned in toolchains/dev-tools.lock (not a
                                 production dependency).
Targeted tests:                  cargo nextest run --workspace  -> 3 tests run, 3 passed, 0 skipped
                                 cargo test --workspace --doc   -> 12 crate targets, 0 doctests
                                 cargo test -p grid-ffi --features flutter-bridge-tests -> 0 tests, ok
                                 ./tests/guards/run.sh          -> 35 passed, 0 failed
Canonical verification command:  just verify
Verification exit status:        0, run against a0a307affd86 -- the commit this record
                                 and the manifest both name. (An earlier revision recorded a run
                                 against a commit three behind the head it attested to; second
                                 review, M2.) Independently green in CI on the previous head,
                                 run 32332121205, all three jobs.
Golden files changed:            N/A -- no golden files exist (P1-06)
Performance evidence:            N/A -- no performance target is affected (no code to measure)
Security/licensing review:       RUSTSEC-2023-0071 remediated (ADR-003), with 14.2's maintenance
                                 assessment and Windows compatibility check now recorded there.
                                 License corrected to MIT OR Apache-2.0 (ADR-001 D4).
                                 .claude/settings.json least-privilege profile AWAITS
                                 Security/Release owner approval.
Fresh-context reviewer:          DONE, TWICE - independent adversarial agent, fresh context.
                                 Round 1 at 7787921 (PR #2): CONDITIONAL, 6 blockers, 10 major,
                                 9 minor. Round 2 at de3b36c (PR #3, comment on this PR):
                                 CONDITIONAL, 3 blockers, 9 major, 11 minor.
Reviewer findings resolved:      Round 1: 6/6 blockers, 9/10 major, 8/9 minor.
                                 Round 2: 2/3 blockers fixed outright and the third corrected on
                                 the facts and referred to the owner; 8/9 major fixed, one
                                 referred; 10/11 minor fixed or recorded, one deliberately not
                                 changed with the reasoning written down. Every finding acted on
                                 was reproduced first. All eight of the reviewer's questions are
                                 answered in the manifest under review.round_2_disposition.
Human approvals:                 TWO DIFFERENT THINGS, and the manifest's 8.12-mandated
                                 human_approvals.required / .obtained fields are now populated
                                 rather than empty (second review, M3).
                                 DECISION RULINGS OBTAINED - answers the owner gave in-session to
                                 explicit questions naming the alternatives:
                                   D1 branch naming; D2 remediate skeleton inside P1-00;
                                   D3 numbered vault; D4 MIT OR Apache-2.0; D5 frozen recipes;
                                   D6 environment fix; D7 verify.sh scope guard (ADR-008);
                                   D8 D4 stays, owner records the licensing ruling on this PR;
                                   D9 owner records the M6/M7 deviations on this PR, no split;
                                   ADR-003; ADR-004; ADR-005; ADR-007.
                                 ROLE-SCOPED SIGN-OFFS OBTAINED - none. A ruling on a question is
                                 not a review of a diff. Still required:
                                   Architecture owner  authority order, crate boundaries,
                                                       the P1-02 -> P1-00 rework
                                   Security/Release    .claude/settings.json
                                   Data/Licensing      D4, outside P1-00's stated scope
                                   Merge reviewer      CI skeleton and the final diff
                                 The owner holds every role per the authority index, so both
                                 statements are true at once - but not interchangeable.
Known limitations:               (1) Role-scoped sign-offs: NONE obtained.
                                 (2) verify.ps1 -Scope Full has NOT been re-run against this
                                     head. It is a ~32-minute Windows job and this push is the
                                     run that covers it; the recorded pass is against 6478c24.
                                     CI is authoritative on the true final commit (12.8).
                                 (3) An evidence manifest cannot record its own commit SHA.
                                 (4) Round 1's M10 (Flutter/Dart analysis) and app/pubspec.lock
                                     are NOT done. pubspec.lock is BLOCKED not deferred: Flutter
                                     is not installed here; a hand-written lockfile would be a
                                     fabrication.
                                 (5) just verify is not offline -- cargo audit fetches the
                                     RustSec database. Accepted and recorded in ADR-002; the
                                     compile-and-test path IS offline and now has a CI gate.
                                 (6) -Scope Changed still unimplemented in both verify scripts
                                     though 8.11 cites it as canonical. Deferred to P1-11 --
                                     safer now that the argument reaching it is validated.
                                 (7) justfile and verify.sh remain duplicate implementations;
                                     unification barred by D5, drift guarded by the parity check,
                                     which now has behaviour tests of its own.
                                 (8) Cargo.toml, ai-toolchain.lock, rust-toolchain.toml and
                                     justfile retain CRLF. ADR-004 now counts the workarounds
                                     this costs and sets a threshold for escalating out of P1-11.
                                 (9) No fixtures. 9.5 lists them under P1-00; deferred to
                                     P1-03/P1-04 and recorded in ADR-001.
                                (10) CI caching is deferred to P1-11 but is more than cosmetic:
                                     an uncached ~32-minute Windows job that any push cancels is
                                     a merge gate that is hard to observe passing.
                                (11) The stale grid-alpha-opus5 environment is still uncorrected;
                                     .env supplies correct values where the environment does not
                                     override, so CI and fresh clones are unaffected.
Evidence manifest hash:          sha256:4e6e00cee116cc6e53de634c217f35a1cd5a13629d58824418160f74cee72082
                                 (.ai/evidence/P1-00/manifest.json)
```

## Independent adversarial review — round 2, at `de3b36c`

**CONDITIONAL: 3 blockers, 9 major, 11 minor.** Every finding acted on was reproduced against
the working tree first. Full dispositions, including answers to all eight reviewer questions,
are in the evidence manifest under `review.round_2_disposition`, per §8.12.

The through-line was that this branch's green meant less than it looked: gates that did not
gate, and a record that had drifted from the code.

| | Finding | Disposition |
|---|---|---|
| **C1** | `verify.sh Full` — the capitalization every authority doc prints — ran **zero checks and exited 0**. So did `verify.sh smoke` | Fixed. Scope normalized and validated; ADR-008, third D5 amendment, no command touched. 9 regression cases |
| **C2** | Both `CLAUDE.md` files said `SQLX_OFFLINE` unset, contradicting ADR-002, and claimed an enforcement the guard does not perform | Fixed in **three** files — `check-env-contract.sh` carried the same inversion in its own advice. The guard now resolves `SQLX_OFFLINE` the way `query!` does |
| **C3** | Relicensing is irreversible, out of scope, and rests only on implementer prose | **The review's supporting fact is wrong**; see below. The irreversibility objection stands and the owner records the ruling on this PR (D8) |
| **M1** | The §8.11 merge gate's green **excluded** append-only and traceability — both SKIPped at `fetch-depth: 1` and exited 0 | Fixed. `fetch-depth: 0` on both build jobs; both SKIP paths now **fail** under `$CI` while still skipping in a local shallow checkout |
| **M2** | Six checkably-false statements; the canonical run predated HEAD by three commits | Fixed. Every number in this body re-derived from a command run against the attested head |
| **M5** | The offline-compile property — the entire reason `.sqlx` is committed — was **never exercised by CI** | Fixed. Offline `cargo check` gate added, proven to pass on a forced macro re-expansion and to fail with `.sqlx` absent |
| **M4** | Tooling unpinned in a repo whose thesis is pinned reproducibility; `deny.toml`'s own claim depended on it | Fixed. `toolchains/dev-tools.lock`; both jobs echo resolved versions. Verified `cargo-deny 0.20.2` honours the explicit keys with no warning |
| **M8** | Parity and env-contract had no tests — and parity is load-bearing because D5 forbids unifying the two implementations | Fixed, and the worry was **understated**: two empty extractions compared equal, and the script did not even fail cleanly. Suite 12 → **35** cases |
| **M9** | The permission profile had drifted from the justfile it enumerates | Fixed. Prefix forms that cannot fall behind |
| **M3** | The §8.12-mandated `human_approvals.required` said no approvals are required | Fixed. Both mandated fields populated |

### The licensing fact, corrected

The review states the `MIT OR Apache-2.0` line "arrived in the skeleton commit and is the value
a `cargo new`-style scaffold produces", concluding the conflict "was resolved in favour of the
scaffold-shaped value and against the human's explicit act."

**Both sides are the owner's own commits, and the permissive one is the later:**

| Commit | Author | Time | Act |
|---|---|---|---|
| `f71a241` | Ethan Nelson | 2026-08-19 16:05:08 | adds `LICENSE`, GPL-3.0 |
| `2565acc` | Ethan Nelson | 2026-08-19 16:35:13 | adds `Cargo.toml` declaring `license = "MIT OR Apache-2.0"` |

`git merge-base --is-ancestor f71a241 2565acc` confirms the order. `main` shipped a
self-contradiction between two commits by one person thirty minutes apart; D4 resolved it toward
the more recent. ADR-001 D4 now records this.

**The review's actual objection survives the correction and is not dismissed.** Relicensing is
the one change here that cannot be undone in the real world, §1.5 names licence uncertainty as a
stop condition, and a change of that class should rest on an artifact the Data/Licensing owner
authored. Per ruling D8, D4 stays on the branch and **the owner records the ruling on this PR.**

### Referred to the owner rather than fixed

**M6** (the work-package non-goal amended inside the PR it constrains) and **M7** (the sqlx
semver bump folded into a bootstrap PR against §14.2) are real and are not argued away. Both are
technically forced under D5 — `cargo nextest` exits 4 on an empty workspace and
`cargo sqlx prepare --check` cannot run against a bare virtual root, which the reviewer
independently confirmed — but necessity is not authorization, and ADR-001 already says a work
package must not be the artifact authorizing exceeding itself.

Per ruling D9 the branch is unchanged and the owner records both on this PR. What this branch
*could* fix, it did: ADR-003 now carries §14.2's two missing checklist items, from evidence —
a maintenance assessment (172 crates, zero `rsa`, footprint reduced, CLI now pinned) and a
Windows compatibility check (`verify.ps1 -Scope Full` **PASSED** on `windows-latest`).

### Deliberately not changed

**minor 2** — `.cargo/config.toml [env]` is the more idiomatic committed way to set
`SQLX_OFFLINE` than a tracked `.env`, and the reviewer is right about that. It is also the exact
mechanism whose last change was a blocker, and swapping it inside the same PR that corrects the
documentation about it trades a real regression risk for a stylistic gain. Deferred to P1-11
with the reasoning recorded rather than churned now.

### What the reviewer checked and could not fault

Recorded so the next reviewer does not re-litigate it: the §1.5 authority-order correction,
stated identically in three places; crate boundaries verified per-crate from the manifests;
`.sqlx` cache integrity and the drift gate; the RUSTSEC remediation; the fail-closed rewrite of
`check-secrets.sh`; migration hygiene; and every CI claim verified against the GitHub API.

## Before merging

**Do not merge on the agent's authority** (§1.3, Appendix D). Outstanding:

- **Owner-authored records on this PR** (rulings D8, D9): the Data/Licensing ruling on D4, and
  the P1-02 → P1-00 scope amendment plus the §14.2 deviation. These are the artifacts two rounds
  of review have asked for, and implementer prose cannot substitute for them.
- **Role-scoped sign-offs — none obtained.** Security/Release on `.claude/settings.json`;
  Data/Licensing on D4; Architecture on the rework; Merge reviewer on the final diff.
- **CI must be green on this head.** `windows-authoritative` is authoritative for merge under
  §8.11 and has not yet run against these commits. Previous head `de3b36c` was green on run
  `32332121205`.
- **Governance:** reconcile `docs/05-sessions/` vs `docs/06-sessions/` before PRs #2 and #3
  merge, and fix the reviewer brief that keeps sending reviewers to a path the authority index
  calls invalid.

Owner follow-ups: correct the `grid-alpha-opus5` environment per ADR-002, and configure branch
protection on `main` (an explicit P1-00 non-goal).

---
_Generated by [Claude Code](https://claude.ai/code)_
