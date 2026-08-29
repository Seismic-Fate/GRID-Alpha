#!/usr/bin/env bash
# Re-derive every mechanically-checkable claim in the evidence record from the artifact it
# describes, and fail on any mismatch.
#
# WHY THIS EXISTS. Round 2's M2 was "six checkably-false statements in the completion record".
# The remedy was a claim-verification pass -- which worked, and caught several more over the
# following rounds. But it was a routine the implementer ran from memory over nine facts, so a
# tenth fact ("All 65 non-trivial paths traced", actually 66) sat permanently outside it and
# survived three rounds. A pass you have to remember to extend is not a control. Round 3, min-1.
#
# WHY IT IS NOT PART OF `just verify`. The manifest records the OUTPUT of `just verify`. If
# verify required the manifest to already be current, neither could ever converge: you would
# need the manifest to run verify, and verify's result to write the manifest. So this runs
# separately -- from `just evidence`, from CI's guards job, and by hand before committing
# evidence. Keeping it out of the frozen chain is deliberate, not an oversight, and it needs no
# D5 amendment for the same reason.
#
# WHAT IT DELIBERATELY DOES NOT CHECK. That the manifest's commit equals HEAD. A manifest cannot
# record its own SHA, so the evidence commit always follows the commit it attests to. Asserting
# equality here would encode a falsehood as a rule.
#
# Usage: check-evidence-claims.sh [base-ref]     (default: origin/main)
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BASE="${1:-${BASE_REF:-origin/main}}"
WP="P1-00"
BODY=".ai/evidence/$WP/PR-BODY.md"
MANIFEST=".ai/evidence/$WP/manifest.json"

for f in "$BODY" "$MANIFEST"; do
    [[ -f "$f" ]] || { echo "check-evidence-claims: FAIL missing $f" >&2; exit 1; }
done

status=0
checked=0

# claim <label> <claimed> <actual> -- every comparison goes through here so the count of checks
# performed is itself reported. A pass that silently checked nothing is the failure mode this
# whole file is about.
claim() {
    local label="$1" claimed="$2" actual="$3"
    checked=$((checked + 1))
    if [[ "$claimed" != "$actual" ]]; then
        echo "check-evidence-claims: FAIL $label" >&2
        echo "    record says : $claimed" >&2
        echo "    artifact says: $actual" >&2
        status=1
    fi
}

# Pull a single capture group out of the body; empty if the phrasing moved.
# Delimiter is \x01, not /, because several of the patterns below contain a literal slash
# ("(16/16)") and a / delimiter turns those into "unknown option to `s'".
from_body() { sed -n $'s\x01.*'"$1"$'.*\x01\\1\x01p' "$BODY" | head -1; }

# 1. Parity step count.
parity_actual="$(./scripts/check-verify-parity.sh | sed -n 's/.*agree on \([0-9]\+\) verification step.*/\1/p')"
claim "parity step count in $BODY" "$(from_body 'agree at \*\*\([0-9]\+\) steps\*\*')" "$parity_actual"

# 2. Guard-suite case count. Run the suite and read its own verdict; nothing else knows it.
suite_actual="$(./tests/guards/run.sh | tail -1 | sed -n 's/^\([0-9]\+\) passed.*/\1/p')"
claim "guard-suite case count in $BODY" "$(from_body 'carries \([0-9]\+\) committed behaviour cases')" "$suite_actual"

# 3. Recipes in the verify chain.
recipes_actual="$(awk '/^verify:/{i=1;next} i&&/^[^[:space:]]/{i=0} i&&/just [a-z-]+/{n++} END{print n+0}' justfile)"
claim "verify recipe count in $BODY" "$(from_body 'runs \*\*\([0-9]\+\) recipes\*\*')" "$recipes_actual"

# 4. Dependency graph: crate count, and the RUSTSEC-2023-0071 remediation (ADR-003).
claim "Cargo.lock crate count in $BODY" \
      "$(from_body 'resolves \([0-9]\+\) crates')" \
      "$(grep -c '^\[\[package\]\]' Cargo.lock)"
claim "rsa crates in Cargo.lock (ADR-003 must keep this at 0)" "0" "$(grep -c '^name = "rsa"$' Cargo.lock || true)"

# 5. Assert-Ok coverage (ADR-009).
claim "Assert-Ok count in $BODY" \
      "$(from_body '(\([0-9]\+\)/16)')" \
      "$(grep -c 'Assert-Ok "' scripts/verify.ps1)"

# 6. The manifest hash the body quotes must be the hash of the manifest beside it.
claim "manifest hash quoted in $BODY" \
      "$(sed -n 's/.*sha256:\([0-9a-f]\{64\}\).*/\1/p' "$BODY" | head -1)" \
      "$(sha256sum "$MANIFEST" | cut -d' ' -f1)"

# 7. The traceability count in the manifest's own narrative. THE claim that started this file:
# it is derived from the diff against the base, so it moves with every commit and is exactly the
# kind of number prose gets wrong.
trace_actual="$(./scripts/check-traceability.sh "$BASE" 2>/dev/null | sed -n 's/.*all \([0-9]\+\) non-trivial path.*/\1/p')"
if [[ -n "$trace_actual" ]]; then
    claim "non-trivial path count in $MANIFEST" \
          "$(sed -n 's/.*All \([0-9]\+\) non-trivial paths traced.*/\1/p' "$MANIFEST" | head -1)" \
          "$trace_actual"
else
    echo "check-evidence-claims: NOTE traceability count not checked ('$BASE' unresolvable here)"
fi

# A checker that compared nothing would exit 0 and look identical to a clean record.
if [[ "$checked" -lt 7 ]]; then
    echo "check-evidence-claims: FAIL only $checked claim(s) compared; expected at least 7." >&2
    echo "  A phrasing change in $BODY silently drops claims from this pass -- which is the exact" >&2
    echo "  way the traceability count escaped it for three rounds. Fix the extractor, not this bound." >&2
    exit 1
fi

if [[ "$status" -eq 0 ]]; then
    echo "check-evidence-claims: OK $checked claim(s) re-derived and matched"
else
    echo "check-evidence-claims: the completion record must be true against the artifacts it describes" >&2
    echo "  (alpha-spec.md 12.8). Regenerate with 'just evidence $WP' and correct the prose." >&2
fi
exit "$status"
