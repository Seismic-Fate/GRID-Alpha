#!/usr/bin/env bash
# Scan the diff for secret material.
#
# Scans the DIFF, not the tree: the goal is to stop a secret entering history, and a
# whole-tree scan would re-flag anything already present forever.
#
# Patterns live in scripts/secret-patterns.txt. That file and this one are excluded from
# the scan so the detector cannot trigger on its own pattern definitions.
#
# Usage: check-secrets.sh [base-ref]     (default: origin/main, or the empty tree)
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

PATTERNS="scripts/secret-patterns.txt"
[[ -f "$PATTERNS" ]] || { echo "check-secrets: FAIL missing $PATTERNS" >&2; exit 1; }

BASE="${1:-${BASE_REF:-origin/main}}"
git rev-parse --verify --quiet "$BASE" >/dev/null \
    || BASE="$(git hash-object -t tree /dev/null)"   # empty tree: scan everything

# Added lines only, excluding the detector's own files.
added="$(git diff "$BASE"...HEAD --unified=0 -- . \
            ':(exclude)scripts/check-secrets.sh' \
            ':(exclude)scripts/secret-patterns.txt' \
         | grep -E '^\+' | grep -vE '^\+\+\+' || true)"

# Include staged and unstaged work so a secret is caught before it is ever committed.
for extra in "$(git diff --unified=0 -- . ':(exclude)scripts/check-secrets.sh' ':(exclude)scripts/secret-patterns.txt' || true)" \
             "$(git diff --cached --unified=0 -- . ':(exclude)scripts/check-secrets.sh' ':(exclude)scripts/secret-patterns.txt' || true)"; do
    added+=$'\n'"$(printf '%s' "$extra" | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
done

# Untracked files are not in any diff, but a new file full of secrets is exactly the case
# this guard exists for. Treat every line of an untracked, non-ignored file as added.
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" == "scripts/check-secrets.sh" || "$f" == "scripts/secret-patterns.txt" ]] && continue
    [[ -f "$f" ]] || continue
    # Skip binaries.
    grep -Iq . "$f" 2>/dev/null || continue
    added+=$'\n'"$(sed 's/^/+/' "$f")"
done < <(git ls-files --others --exclude-standard)

if [[ -z "${added//[[:space:]]/}" ]]; then
    echo "check-secrets: OK no added lines to scan (base $BASE)"
    exit 0
fi

status=0
while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    if hits="$(printf '%s\n' "$added" | grep -nE -e "$pattern" || true)"; [[ -n "$hits" ]]; then
        echo "check-secrets: FAIL pattern matched: $pattern" >&2
        printf '%s\n' "$hits" | head -3 | sed 's/^/    /' >&2
        status=1
    fi
done < "$PATTERNS"

if [[ "$status" -eq 0 ]]; then
    echo "check-secrets: OK no secret patterns in the diff (base $BASE)"
else
    echo "check-secrets: secrets must never be committed (alpha-spec.md 14.1)." >&2
    echo "  If this is a false positive, narrow the pattern in $PATTERNS — do not delete the check." >&2
fi
exit "$status"
