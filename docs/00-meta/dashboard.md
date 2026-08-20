# Work-package dashboard

Requires the Obsidian Dataview plugin. Fields come from the frontmatter in
`docs/99-templates/template-work-package.md`; keys are hyphenated to match this query.

```dataview
TABLE status, risk-class, owner, implementer, reviewer
FROM "01-work-packages"
WHERE file.name != "README"
SORT status ASC, file.name ASC
```

## Phase 1 sequence (alpha-spec.md 9.5)

| WP | Scope | Status |
|----|-------|--------|
| P1-00 | Agent-ready repository, authority index, CI, verify scripts | In Progress |
| P1-01 | Domain IDs, time/as-of types, errors, FFI contract skeleton | Blocked on P1-00 |
| P1-02 | SQLite schema, migrations, durable jobs, version primitives | Blocked on P1-01 |
| P1-03 | nflverse provider contracts and ingestion | Blocked on P1-02 |
| P1-04 | Player registry, NFL identity, NCAA adapter and linking | Blocked on P1-03 |
| P1-05 | Point-in-time feature store and leakage test harness | Blocked on P1-04 |
| P1-06 | Numerical primitives: scoring, ridge, Kalman, EB, affine, boosting | Blocked on P1-01 |
| P1-07 | Team environment, opportunity allocation, efficiency, rookie priors | Blocked on P1-05 |
| P1-08 | Correlated simulation, distributions, explanation payloads | Blocked on P1-07 |
| P1-09 | Rolling-origin backtest, player pool, PB-MAE, calibration | Blocked on P1-08 |
| P1-10 | Flutter board, detail views, status, settings, CSV export | Blocked on P1-01 |
| P1-11 | Recovery, installer, clean-machine acceptance evidence | Blocked on P1-10 |
