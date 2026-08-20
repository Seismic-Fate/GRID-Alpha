#!/usr/bin/env bash
# Every non-trivial change traces to an approved work package or ADR.
#
# alpha-spec.md 9.4: "Every merged non-trivial change is linked to an approved work package
# and evidence manifest." 12.8 requires the PR body to carry the work-package link.
#
# Looks for a reference in the commit messages in range, or in $PR_BODY / $PR_BODY_FILE.
#
# Usage: check-traceability.sh [base-ref]     (default: origin/main)
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BASE="${1:-${BASE_REF:-origin/main}}"

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "check-traceability: SKIP base ref '$BASE' not available"
    exit 0
fi

# Trivial paths: excluded by the P1-00 acceptance criteria, plus generated artifacts.
is_trivial() {
    case "$1" in
        docs/99-templates/*|.github/*|*.lock|Cargo.lock|.sqlx/*|\
        .gitignore|.gitattributes|*/.gitkeep|.gitkeep) return 0 ;;
        *) return 1 ;;
    esac
}

changed="$( { git diff --name-only "$BASE"...HEAD || true
              git diff --name-only || true
              git diff --cached --name-only || true
              git ls-files --others --exclude-standard || true; } | sort -u | grep -vE '^$' || true)"

nontrivial=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    is_trivial "$f" || nontrivial+=("$f")
done <<< "$changed"

if [[ ${#nontrivial[@]} -eq 0 ]]; then
    echo "check-traceability: OK no non-trivial changes to trace (base $BASE)"
    exit 0
fi

# Gather every place a reference may legitimately appear.
haystack="$(git log --format='%s%n%b' "$BASE"..HEAD 2>/dev/null || true)"
haystack+=$'\n'"${PR_BODY:-}"
[[ -n "${PR_BODY_FILE:-}" && -f "${PR_BODY_FILE:-}" ]] && haystack+=$'\n'"$(cat "$PR_BODY_FILE")"

REF_RE='docs/01-work-packages/[A-Za-z0-9._-]+|docs/02-adr/[A-Za-z0-9._-]+|P1-[0-9]{2}|ADR-[0-9]{3}'

if refs="$(printf '%s' "$haystack" | grep -oE "$REF_RE" | sort -u)"; [[ -n "$refs" ]]; then
    echo "check-traceability: OK ${#nontrivial[@]} non-trivial change(s) traced to:"
    printf '%s\n' "$refs" | sed 's/^/    /'
    exit 0
fi

echo "check-traceability: FAIL ${#nontrivial[@]} non-trivial change(s) with no work-package or ADR reference" >&2
printf '%s\n' "${nontrivial[@]}" | head -10 | sed 's/^/    /' >&2
[[ ${#nontrivial[@]} -gt 10 ]] && echo "    ... and $(( ${#nontrivial[@]} - 10 )) more" >&2
cat >&2 <<'HINT'
  Reference the governing work package or ADR in a commit message or the PR body, e.g.
    "P1-00: add authority index"      or      "docs/02-adr/001-repo-bootstrap-decisions.md"
  Traceability is required by alpha-spec.md 9.4 and 12.8.
HINT
exit 1
