#!/usr/bin/env bash
# The justfile and scripts/verify.sh must run the SAME verification steps.
#
# alpha-spec.md 8.11 defines one canonical verification interface, but the repository ships
# two independent implementations: the `verify` recipe chain in the justfile, and the inline
# command list in scripts/verify.sh. Both are a frozen contract (ADR-001 D5), so they cannot
# be unified by making one call the other. This guard asserts they stay in lockstep instead.
#
# If this fails, the two have drifted. Fix by bringing them back into agreement — deliberately,
# and with the owner's approval, because both files are frozen.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

JUSTFILE="justfile"
VERIFY_SH="scripts/verify.sh"
for f in "$JUSTFILE" "$VERIFY_SH"; do
    [[ -f "$f" ]] || { echo "check-verify-parity: FAIL missing $f" >&2; exit 1; }
done

# tr -d '\r': the justfile is still CRLF by design (ADR-004), so strip CR before comparing.
#
# ORDER-SENSITIVE and duplicate-sensitive: an earlier revision ended in `sort -u`, so a
# reordered or duplicated step was invisible. Review finding "minor 5".
#
# `|| true` on the extractions and on the final grep: with `set -euo pipefail` an empty extraction made grep exit 1
# and killed the script with no diagnostic at all -- fail-closed by accident, exit 1 with an
# empty message, and impossible to tell apart from a real drift. Empty extractions are now
# tolerated by the pipeline and diagnosed explicitly below instead.
norm() { tr -d '\r' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' | { grep -vE '^$' || true; }; }

# Recipes the `verify` chain invokes, then the commands inside each of them.
targets="$(awk '
    /^verify:/         { inv = 1; next }
    inv && /^[^[:space:]]/ { inv = 0 }
    inv && /just [a-z-]+/  { for (i = 1; i <= NF; i++) if ($i == "just") print $(i+1) }
' "$JUSTFILE" | tr -d '\r')"

[[ -n "$targets" ]] || { echo "check-verify-parity: FAIL could not parse the verify chain from $JUSTFILE" >&2; exit 1; }

just_cmds="$(for t in $targets; do
    awk -v target="^$t:" '
        $0 ~ target        { inr = 1; next }
        inr && /^[^[:space:]]/ { inr = 0 }
        inr && /^[[:space:]]+[^#]/ { print }
    ' "$JUSTFILE"
done | norm || true)"

# Every command in verify.sh, not just cargo/typos: an earlier revision matched only those two
# binaries, so a step invoking anything else was silently outside the comparison entirely.
# Excludes comments, blanks, echo, and shell scaffolding. Review finding "minor 5".
sh_cmds="$(grep -vE '^[[:space:]]*(#|$)' "$VERIFY_SH" \
           | grep -vE '^[[:space:]]*(echo|set|if|fi|then|else|elif|SCOPE=|exit)\b' \
           | grep -vE '^#!' \
           | grep -E '^[[:space:]]+[a-zA-Z._/]' | norm || true)"

# Two silently-empty extractions compare equal, so a broken parser would report agreement on
# zero steps -- the same fail-open shape as the check-secrets defect this suite exists for.
# This guard is load-bearing: D5 forbids unifying the two implementations, so this script is
# the only thing keeping them in step. Second adversarial review, finding M8.
for side in just:"$just_cmds" sh:"$sh_cmds"; do
    if [[ -z "${side#*:}" ]]; then
        echo "check-verify-parity: FAIL extracted ZERO commands from the ${side%%:*} side." >&2
        echo "  The parser is broken, or a verification implementation is empty. Either way this" >&2
        echo "  is not agreement: two empty lists compare equal and would report a false pass." >&2
        exit 1
    fi
done

if diff_out="$(diff <(printf '%s\n' "$just_cmds") <(printf '%s\n' "$sh_cmds"))"; then
    n=$(printf '%s\n' "$just_cmds" | grep -c . || true)
    echo "check-verify-parity: OK justfile and $VERIFY_SH agree on $n verification step(s)"
    exit 0
fi

echo "check-verify-parity: FAIL the two verification implementations have drifted" >&2
echo "  '<' only in justfile      '>' only in $VERIFY_SH" >&2
printf '%s\n' "$diff_out" | sed 's/^/    /' >&2
echo "  Both files are a frozen contract (ADR-001 D5): reconcile deliberately, with owner approval." >&2
exit 1
