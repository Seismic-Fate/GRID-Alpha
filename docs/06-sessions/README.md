# Session logs and reviews

Canonical location for per-session traces and review reports.
Template: `docs/99-templates/template-session-log.md`.

**Not `docs/05-sessions/`.** `05` is `docs/05-model-specs/` in the authority index's alias
table and in `scripts/bootstrap-repo.sh`. The P1-00 adversarial review was written to
`docs/05-sessions/` on its own branch before the collision was noticed (review finding
"minor 8"); it should move here when that branch merges, or the numbering reconciled then.

**This has now happened twice, and needs an owner decision before either review branch
merges.** The second adversarial review was sent to the same invalid path by the same review
brief, so `docs/05-sessions/` now holds a file on each of two open branches. If both merge,
`docs/` gains a directory the authority index explicitly calls invalid, containing two files.
Second adversarial review, minor 1. Two things to fix, neither of which this branch can do
alone:

1. Move both review files to `docs/06-sessions/` as part of merging #2 and #3.
2. Fix the reviewer brief that names `docs/05-sessions/review-P1-00-adversarial.md`, so the
   next reviewer is not sent to a path this repository rejects. A brief that contradicts the
   authority index is a defect in the brief.

## Index

| Date | Session | Branch |
|------|---------|--------|
| 2026-08-20 | P1-00 implementation | `wp/P1-00-repo-bootstrap` |
| 2026-08-20 | P1-00 adversarial review — verdict CONDITIONAL | `claude/grid-alpha-adversarial-review-ikkjuk` (PR #2) |
| 2026-08-20 | P1-00 adversarial re-review at `de3b36c` — verdict CONDITIONAL | `claude/adversarial-review-p1-00-l32emp` (PR #3) |
