# Daily log

Terse running record. Per-session detail belongs in a session log
(`docs/99-templates/template-session-log.md`).

## 2026-08-20 — P1-00

Branch `wp/P1-00-repo-bootstrap`.

Authority load found the repository could not support its own work package: no `.rs`, `.dart`
or `.sql` file had ever existed, `crates/` was absent so every cargo command failed at
manifest-parse time, four of five templates were 0 bytes, and the authority index and
`docs/CLAUDE.md` both inverted alpha-spec 1.5.

Owner rulings: `wp/` branch naming; remediate the skeleton inside P1-00; keep the numbered
vault; `MIT OR Apache-2.0`; **verify recipes are frozen — rework the spec, never the recipe**;
environment defects fixed in the environment, not the repo.

Four things found during implementation that the plan had not anticipated:

- `cargo nextest run --workspace` exits 4 on an empty workspace, so the SQLx pull-forward is
  load-bearing rather than tidy — its two tests are what let `test-rust` pass.
- The environment presets a stale `DATABASE_URL` from a predecessor project name, and a
  committed `.env` cannot override it. → ADR-002 contract + `check-env-contract.sh`.
- `cargo audit` failed on RUSTSEC-2023-0071 via `sqlx 0.8 -> sqlx-mysql -> rsa`, no fix
  available. Feature narrowing does not help; sqlx 0.9 removes it. → ADR-003.
- Every committed file is CRLF, leaving `scripts/verify.sh` unparsable by bash — the 8.11
  canonical Linux command could not run at all. → ADR-004.
