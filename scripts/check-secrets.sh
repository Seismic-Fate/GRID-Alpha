#!/usr/bin/env bash
# Scan for secret material.
#
# A security control MUST FAIL CLOSED. Every git invocation below aborts the run on error
# rather than reporting a clean scan over content that was never examined.
#
# Regression (found by adversarial review of PR #1): the base fallback used an empty-tree
# sentinel with `git diff <tree>...HEAD`. `...` requires two COMMITS, so git aborted with
# "Invalid symmetric difference expression"; a `|| true` swallowed the fatal and the guard
# printed OK with exit 0 while a committed ghp_ token sat in the tree. When no base commit
# is available the script now scans the ENTIRE tracked tree instead.
#
# Patterns live in scripts/secret-patterns.txt. That file and this one are excluded from the
# diff/tree/untracked passes so the detector cannot trigger on its own definitions -- but they
# are NOT unscanned. They were, and that made them the one place in the repository where a
# secret was never looked for (second adversarial review, minor 4). They now get a dedicated
# pass of their own, in full, on every run and in every mode. Inside that pass only, a line
# carrying the marker `# nosecret` is skipped, so a pattern that legitimately matches itself
# can be exempted line by line instead of exempting two whole files.
#
# The marker has no effect anywhere else: it is applied only to these two paths, so it cannot
# become a way to smuggle a secret past the scanner from ordinary source.
#
# Usage: check-secrets.sh [base-ref]     (default: origin/main)
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

PATTERNS="scripts/secret-patterns.txt"
[[ -f "$PATTERNS" ]] || { echo "check-secrets: FAIL missing $PATTERNS" >&2; exit 1; }

BASE="${1:-${BASE_REF:-origin/main}}"
SELF=(':(exclude)scripts/check-secrets.sh' ':(exclude)scripts/secret-patterns.txt')

die() { echo "check-secrets: FAIL $*" >&2; exit 1; }
plus() { grep -E '^\+' | grep -vE '^\+\+\+' || true; }   # added lines only; no match is fine

added=""
scanned=0

# Append every readable text file in a newline-separated list to the scan corpus.
#
# `f="${f%$'\r'}"`: a carriage return on a path silently fails the -f test, so the file is
# skipped and the scan reports a clean tree over content it never opened. Both ls-files loops
# had this shape and both examined zero files on the Windows merge gate.
scan_files() {
    local list="$1" f
    while IFS= read -r f; do
        f="${f%$'\r'}"
        [[ -z "$f" ]] && continue
        case "$f" in scripts/check-secrets.sh|scripts/secret-patterns.txt) continue ;; esac
        [[ -f "$f" ]] || continue
        grep -Iq . "$f" 2>/dev/null || continue    # skip binaries
        added+=$'\n'"$(sed 's/^/+/' "$f")"
        scanned=$((scanned + 1))
    done <<< "$list"
}

if git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
    mode="diff vs $BASE"
    d="$(git diff "$BASE"...HEAD --unified=0 -- . "${SELF[@]}")" \
        || die "git diff ${BASE}...HEAD failed — refusing to report a clean scan"
    added+=$'\n'"$(printf '%s\n' "$d" | plus)"
else
    # No usable base: fresh clone, shallow checkout, or an unborn branch. Scan everything
    # tracked. Scanning less than the diff would be a silent downgrade of the control.
    mode="FULL tracked tree (base '$BASE' unresolvable)"
    files="$(git ls-files)" || die "git ls-files failed — refusing to report a clean scan"
    scan_files "$files"
    listed=$(printf '%s\n' "$files" | grep -c . || true)
    # A scan that examined nothing is not a clean tree, it is a broken scanner. On the Windows
    # merge gate this loop silently examined ZERO of the listed files and the guard printed OK
    # over a committed ghp_ token; only the guard suite caught it, and only because verify.ps1
    # was fixed to propagate exit codes. Never infer "clean" from an empty scan again.
    if [[ "$listed" -gt 0 && "$scanned" -eq 0 ]]; then
        die "git ls-files listed $listed path(s) but ZERO were scanned.
       The scanner examined nothing; that is not a clean tree. Refusing to report OK."
    fi
fi

# Staged and unstaged work, so a secret is caught before it is ever committed.
u="$(git diff --unified=0 -- . "${SELF[@]}")"        || die "git diff (unstaged) failed"
s="$(git diff --cached --unified=0 -- . "${SELF[@]}")" || die "git diff --cached failed"
added+=$'\n'"$(printf '%s\n' "$u" | plus)"
added+=$'\n'"$(printf '%s\n' "$s" | plus)"

# The detector's own two files, always and in full. `# nosecret` exempts a single line here.
for f in scripts/check-secrets.sh "$PATTERNS"; do
    [[ -f "$f" ]] || continue
    added+=$'\n'"$(grep -v '# nosecret' "$f" | sed 's/^/+/')"
done

# Untracked files are in no diff, but a new file full of secrets is exactly this guard's job.
untracked="$(git ls-files --others --exclude-standard)" || die "git ls-files --others failed"
scan_files "$untracked"

# Two tiers, separated by the #WARN# line in the pattern file. Deny fails; warn reports.
# The warn tier exists because the deny patterns require realistic token lengths, so a
# truncated or short test token slips through -- narrower than the acceptance criterion's
# literal "patterns matching ghp_, sk-ant-". Reporting it is better than either gating on a
# noisy pattern or pretending the gap is not there.
status=0
warned=0
tier="deny"
while IFS= read -r pattern; do
    pattern="${pattern%$'\r'}"   # a CRLF pattern file would append \r to every regex
    if [[ "$pattern" == "#WARN#" ]]; then tier="warn"; continue; fi
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    if hits="$(printf '%s\n' "$added" | grep -nE -e "$pattern" || true)"; [[ -n "$hits" ]]; then
        if [[ "$tier" == "deny" ]]; then
            echo "check-secrets: FAIL pattern matched: $pattern" >&2
            printf '%s\n' "$hits" | head -3 | sed 's/^/    /' >&2
            status=1
        else
            echo "check-secrets: WARN low-confidence match (not failing): $pattern" >&2
            printf '%s\n' "$hits" | head -3 | sed 's/^/    /' >&2
            warned=$((warned+1))
        fi
    fi
done < "$PATTERNS"

if [[ "$status" -eq 0 ]]; then
    # The file count is part of the verdict: "OK" over an empty corpus is what the Windows
    # fail-open looked like, and an unqualified OK gives a reader no way to notice.
    echo "check-secrets: OK no secret patterns found ($mode; $scanned whole file(s) read)$([[ "$warned" -gt 0 ]] && echo ", $warned warn-tier match(es) above")"
else
    echo "check-secrets: secrets must never be committed (alpha-spec.md 14.1)." >&2
    echo "  If this is a false positive, narrow the pattern in $PATTERNS — never delete the check." >&2
fi
exit "$status"
