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
| **009** | `scripts/verify.ps1` — the §8.11 merge gate — discarded every command's exit code |

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

ADR-008 (scope validation in `verify.sh`) and ADR-009 (exit-code propagation in `verify.ps1`)
**change no command at all** — both fix the harness *around* the checks. `check-verify-parity.sh`
confirms the justfile and `verify.sh` agree at **16 steps**, order-sensitively.

**D5 has now been amended four times.** All four *increased* coverage; none relaxed a check. Worth
naming the pattern rather than just the count: **two of the four — 008 and 009 — were defects in
the harness, not the checks.** An entry point that accepted any scope and ran nothing, and a merge
gate that threw away every exit code. D5 froze the check list and left the code deciding whether a
check counts unexamined; both fail-opens survived multiple green CI runs and two adversarial
reviews. An amendment that *reduces* coverage should still be refused outright.

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
pass at all. **`tests/guards/run.sh` carries 42 committed behaviour cases** covering all six
guard scripts and the `verify.sh` scope guard, run inside `just verify` (ADR-007).

That suite has now caught seven defects that reading did not — including the three most serious
in the branch, all found after the second review had finished. `check-secrets.sh` needed two
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
Final commit:                    a61c35300152  (code head; the evidence commit follows
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
                                   the nine in docs/02-adr/ were written by this package)
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
                                 ./tests/guards/run.sh          -> 42 passed, 0 failed
Canonical verification command:  just verify
Verification exit status:        0, run against a61c35300152 -- the commit this record and the
                                 manifest both name.
Golden files changed:            N/A -- no golden files exist (P1-06)
Performance evidence:            N/A -- no performance target is affected (no code to measure)
Security/licensing review:       RUSTSEC-2023-0071 remediated (ADR-003); Cargo.lock resolves 172
                                 crates with zero rsa entries. 14.2's maintenance assessment is
                                 recorded there. 14.2's WINDOWS COMPATIBILITY CHECK IS WITHDRAWN
                                 and NOT YET ESTABLISHED: it cited a verify.ps1 run, and ADR-009
                                 shows that script could not fail. License is MIT OR Apache-2.0
                                 (ADR-001 D4), recorded by the owner on this PR.
                                 .claude/settings.json least-privilege profile AWAITS
                                 Security/Release owner approval.
Fresh-context reviewer:          DONE, TWICE - independent adversarial agent, fresh context.
                                 Round 1 at 7787921 (PR #2): CONDITIONAL, 6 blockers, 10 major,
                                 9 minor. Round 2 at de3b36c (PR #3, comment on this PR):
                                 CONDITIONAL, 3 blockers, 9 major, 11 minor.
                                 A THIRD ROUND IS WARRANTED: the three most serious defects in
                                 the branch were found after round 2 finished, by the implementer,
                                 and neither reviewer could have seen them -- CI reported green.
Reviewer findings resolved:      Round 1: 6/6 blockers, 9/10 major, 8/9 minor.
                                 Round 2: all 3 blockers closed (C3 by the owner's own record on
                                 this PR); 9/9 major closed or owner-recorded; 10/11 minor fixed
                                 or recorded, one deliberately not changed with reasoning.
                                 SELF-FOUND after round 2, all fail-opens, all fixed:
                                   verify.ps1 discarded every exit code (ADR-009)
                                   check-secrets scanned zero files on Windows
                                   the ADR-009 fix was itself unproven (all-green run)
                                 Every finding acted on was reproduced first. All eight of the
                                 reviewer's questions are answered in the manifest under
                                 review.round_2_disposition.
Human approvals:                 The manifest's 8.12-mandated human_approvals.required /
                                 .obtained fields are populated, not empty.
                                 DECISION RULINGS OBTAINED - answers the owner gave to explicit
                                 questions naming the alternatives:
                                   D1 branch naming; D2 remediate skeleton inside P1-00;
                                   D3 numbered vault; D4 MIT OR Apache-2.0; D5 frozen recipes;
                                   D6 environment fix; D7 verify.sh scope guard (ADR-008);
                                   D8/D9 owner records the licence and scope deviations here;
                                   D10 verify.ps1 exit-code checks (ADR-009);
                                   D11 withdraw and re-earn the Windows evidence;
                                   ADR-003; ADR-004; ADR-005; ADR-007.
                                 OWNER-AUTHORED RECORD ON THIS PR - the permissive licence
                                 (2565acc), the SQLx bootstrap moving P1-02 -> P1-00, and the
                                 sqlx 0.8 -> 0.9 bump as a consequence. This closes C3, M6 and
                                 M7, which needed an artifact implementer prose cannot supply.
                                 ROLE-SCOPED SIGN-OFFS OBTAINED - none. Still required:
                                   Architecture owner  authority order, crate boundaries
                                   Security/Release    .claude/settings.json
                                   Merge reviewer      CI skeleton and the final diff
Known limitations:               (1) Role-scoped sign-offs: NONE obtained.
                                 (2) verify.ps1 -Scope Full is NOT ESTABLISHED as passing
                                     under a gate proven capable of failing. Run 32382377066 was
                                     green on the FIXED script but every command passed, so the
                                     throw path was never exercised. The ADR-009 self-test step
                                     lands with this push and is what closes it. CI is
                                     authoritative on the true final commit (12.8).
                                 (3) THREE fail-opens were found by the implementer AFTER round 2,
                                     all invisible to CI's own conclusion and to both reviewers:
                                     the Windows gate discarded exit codes, the secret scanner
                                     examined zero files on Windows, and the fix for the first was
                                     itself unproven. All fixed and regression-tested. ADR-001 D5
                                     records the lesson: freezing a check list is not the same as
                                     trusting it.
                                 (4) check-verify-parity.sh does not read verify.ps1, so nothing
                                     cross-checks the PowerShell implementation. That is why the
                                     parity guard could not have caught ADR-009's defect.
                                 (5) An evidence manifest cannot record its own commit SHA.
                                 (6) Round 1's M10 (Flutter/Dart analysis) and app/pubspec.lock
                                     are NOT done. pubspec.lock is BLOCKED not deferred: Flutter
                                     is not installed here; a hand-written lockfile would be a
                                     fabrication.
                                 (7) just verify is not offline -- cargo audit fetches the
                                     RustSec database. Accepted, recorded in ADR-002.
                                 (8) -Scope Changed still unimplemented in both verify scripts
                                     though 8.11 cites it as canonical. Deferred to P1-11.
                                 (9) justfile and verify.sh remain duplicate implementations;
                                     unification barred by D5, drift guarded by the parity check.
                                (10) Cargo.toml, ai-toolchain.lock, rust-toolchain.toml and
                                     justfile retain CRLF. ADR-004 counts the workarounds and
                                     sets a threshold for escalating out of P1-11.
                                (11) No fixtures. 9.5 lists them under P1-00; deferred to
                                     P1-03/P1-04 and recorded in ADR-001.
                                (12) CI caching deferred to P1-11; an uncached ~25-minute Windows
                                     job that any push cancels is hard to observe passing.
                                (13) The stale grid-alpha-opus5 environment is still uncorrected;
                                     .env supplies correct values where it does not override.
Evidence manifest hash:          sha256:589fa3645de08e7447b13ef1f6d20a480067a88771db76c380d9c439ed8bfaac
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
| **M8** | Parity and env-contract had no tests — and parity is load-bearing because D5 forbids unifying the two implementations | Fixed, and the worry was **understated**: two empty extractions compared equal, and the script did not even fail cleanly. Suite 12 → **42** cases |
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

**The owner has now recorded both on this PR**, which closes them. What this branch could fix, it
did: ADR-003 carries §14.2's maintenance assessment, from evidence — 172 crates, zero `rsa`,
dependency footprint reduced, CLI now pinned.

**§14.2's Windows compatibility check is withdrawn and NOT re-established.** An earlier revision
of this body and of ADR-003 cited `verify.ps1 -Scope Full` PASSING on `windows-latest` as that
evidence. ADR-009 shows the script could not fail, so the citation proved execution, not passing —
and it was written by the same implementer who then found the defect. It is re-recorded only from
a run of the fixed script.

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

## Found after the review finished — three fail-opens, all mine

Neither reviewer could have found these. CI reported green.

They surfaced only because round 2's fixes — the `$CI` fail-closed change and 23 new guard
cases — made `windows-authoritative` print a real verdict for the first time. Run
`32376218798` then showed, twelve lines apart:

```
33 passed, 2 failed          <- tests/guards/run.sh, exited non-zero
[verify] All checks passed.  <- exit 0, job reported SUCCESS
```

**`scripts/verify.ps1` could not fail.** Sixteen native commands, zero `$LASTEXITCODE` checks.
`$ErrorActionPreference = "Stop"` governs PowerShell error records, not native exit codes, and
`#Requires -Version 7.2` pins the script to a version where
`$PSNativeCommandUseErrorActionPreference` is off by default. Every exit code was discarded —
`cargo fmt --check`, `clippy -D warnings`, `sqlx prepare --check`, `nextest`, `deny`, `audit`,
all seven guards, `typos`. **ADR-009**, fourth D5 amendment.

**`check-secrets.sh` examined zero files on Windows.** Both `git ls-files` loops opened nothing,
so the guard printed `OK no secret patterns found` over a committed `ghp_` token and a
credentialed connection string. The five cases expecting exit 0 all passed *vacuously*. The first
defect hid the second: the suite caught it and `verify.ps1` threw the verdict away.

**And the fix for the first was itself unproven** — see below. Three in total.

### What that cost, stated plainly

**Every `windows-authoritative` green before `a190e71` is withdrawn as evidence of passing** —
including the one this body and ADR-003 previously cited as §14.2's Windows compatibility check.
They show the steps *ran*. `verification_status` is `passed_with_exceptions` until a genuinely
failing gate goes green.

### And the fix itself had to be proven, not assumed

Run `32382377066` came back green with `38 passed, 0 failed` on Windows — the CR-strip fixed the
real mechanism. But **that green does not prove ADR-009 works**: every command passed, so no exit
code ever needed propagating, and an inert `Assert-Ok` produces identical output. ADR-002's own
argument — a gate that passes vacuously is a gate nobody has tested — applies to my fix too.

Two things close it, and both are visible in CI:

| | Proves |
|---|---|
| **ADR-009 self-test** step on `windows-authoritative` | Runs the real `verify.ps1` with a stub `cargo` that exits 7 and requires a non-zero exit. Fails loudly if the fix is ever inert |
| **`verify.ps1` exit-code coverage** case in the guard suite | Every native command is immediately followed by an `Assert-Ok` (16/16), with a mutation control proving the check can fail. Nothing else could catch this — `check-verify-parity` never reads `verify.ps1` |

The scanner's diff-mode branch also got the empty-scan guard its full-tree branch had, and both
verdicts now state what they measured: `6561 added line(s) from 80 changed file(s)` rather than a
bare `OK`. That number reading `0` is what a fail-open looks like.

**The pattern, recorded in ADR-001 D5.** Two of the four D5 amendments were defects in the
*harness around* the checks, not in the checks. Freezing a check list is not the same as
trusting it.

## Before merging

**Do not merge on the agent's authority** (§1.3, Appendix D). Outstanding:

- ✅ **Owner-authored records — DONE.** The owner recorded on this PR: the permissive licence
  per `2565acc`, the SQLx bootstrap moving P1-02 → P1-00, and the sqlx 0.8 → 0.9 bump as a
  consequence of that fold-in. That closes C3, M6 and M7 with the artifact two review rounds
  asked for and that no implementer-written ADR could substitute for.
- **Role-scoped sign-offs — none obtained.** Security/Release on `.claude/settings.json`;
  Architecture on the diff; Merge reviewer on the final diff.
- **`windows-authoritative` has not yet been observed passing under a gate proven capable of
  failing.** Run `32382377066` was green on the fixed script, but with everything passing it
  exercised only the happy path. The **ADR-009 self-test** step added in `6a1b350bbdf4` is what closes
  that; the evidence is re-recorded once a run carrying it is green. If that run comes back red,
  the gate is working — read it that way before treating it as a regression.
- **A third adversarial review is warranted.** The three most serious defects in this branch
  were found after round 2 had finished, by the implementer, while CI reported green. The highest-value
  things to attack: whether `Assert-Ok` covers every path through `verify.ps1`, and whether the
  empty-scan guards can themselves be fooled.
- **Governance:** reconcile `docs/05-sessions/` vs `docs/06-sessions/` before PRs #2 and #3
  merge, and fix the reviewer brief that keeps sending reviewers to a path the authority index
  calls invalid.

Owner follow-ups: correct the `grid-alpha-opus5` environment per ADR-002, and configure branch
protection on `main` (an explicit P1-00 non-goal).

---
_Generated by [Claude Code](https://claude.ai/code)_
