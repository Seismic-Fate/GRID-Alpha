#!/usr/bin/env bash
# Migrations are append-only.
#
# alpha-spec.md Appendix D #4 and final-build-spec.md 8.2: never rewrite, squash, or delete a
# historical migration to make a build pass. Only additions are permitted.
#
# Usage: check-migrations.sh [base-ref]     (default: origin/main)
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

DIR="migrations"
BASE="${1:-${BASE_REF:-origin/main}}"

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "check-migrations: SKIP base ref '$BASE' not available; nothing to compare against"
    exit 0
fi

# D=deleted, M=modified, R=renamed. Additions (A) are the only permitted change.
violations="$(git diff --name-status --diff-filter=DMR "$BASE"...HEAD -- "$DIR" || true)"
# Also catch uncommitted tampering.
violations+=$'\n'"$(git diff --name-status --diff-filter=DMR -- "$DIR" || true)"
violations+=$'\n'"$(git diff --cached --name-status --diff-filter=DMR -- "$DIR" || true)"
violations="$(printf '%s\n' "$violations" | grep -vE '^[[:space:]]*$' || true)"

if [[ -n "$violations" ]]; then
    echo "check-migrations: FAIL migrations are append-only; these were modified or removed:" >&2
    printf '%s\n' "$violations" | sed 's/^/    /' >&2
    echo "  Add a new forward migration instead of editing history (alpha-spec.md Appendix D #4)." >&2
    exit 1
fi

count=$(find "$DIR" -name '*.sql' 2>/dev/null | wc -l)
echo "check-migrations: OK append-only satisfied ($count migration(s), base $BASE)"
