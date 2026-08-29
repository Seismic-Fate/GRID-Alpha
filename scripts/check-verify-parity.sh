#!/usr/bin/env bash
# The justfile, scripts/verify.sh and scripts/verify.ps1 must run the SAME verification steps.
#
# alpha-spec.md 8.11 defines one canonical verification interface, but the repository ships
# THREE independent implementations: the `verify` recipe chain in the justfile, the inline
# command list in scripts/verify.sh, and the same list again in scripts/verify.ps1. All three
# are a frozen contract (ADR-001 D5), so they cannot be unified by making one call another.
# This guard asserts they stay in lockstep instead.
#
# verify.ps1 was added to the comparison by the third adversarial review (M2). Until then this
# script read two of the three, so a step added to the justfile and verify.sh and forgotten in
# verify.ps1 passed every guard in the repository — and verify.ps1 is the MERGE-AUTHORITATIVE
# gate (§8.11), which would then have run one check fewer than the smoke gate, silently.
# Not drifted when found; latent. A guard that covers two of three is how it stops being latent.
#
# This script is a guard, not one of the three frozen implementations, so extending it needs no
# D5 amendment.
#
# If this fails, the implementations have drifted. Fix by bringing them back into agreement —
# deliberately, and with the owner's approval, because all three files are frozen.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

JUSTFILE="justfile"
VERIFY_SH="scripts/verify.sh"
VERIFY_PS1="scripts/verify.ps1"
for f in "$JUSTFILE" "$VERIFY_SH" "$VERIFY_PS1"; do
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

# verify.ps1's command list. Extracted by the same inverted rule tests/guards/run.sh uses for
# Assert-Ok coverage: a line is a command UNLESS it is a recognised PowerShell construct. A
# "looks like a command" pattern misses `& $tool`, `.\tool.exe` and column 0 (round 3, M1), and
# a parity check that cannot see a step is a parity check that will not notice it going missing.
ps1_cmds="$(awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*(if|elseif|else|switch|foreach|for|while|do|try|catch|finally|function|param|return|throw|break|continue|begin|process|end)([^[:alnum:]_-]|$)/ { next }
    /^[[:space:]]*[{}]/ { next }
    /^[[:space:]]*\[/   { next }
    /^[[:space:]]*\)/   { next }
    /^[[:space:]]*\$/   { next }
    /Write-Host/ { next }
    /Assert-Ok/  { next }
    { print }
' "$VERIFY_PS1" | norm || true)"

# Windows cannot execute a .sh directly, so verify.ps1 spells the seven guard steps
# `bash ./scripts/x.sh` where verify.sh spells them `./scripts/x.sh`. That prefix is a platform
# necessity, not a difference in WHAT is run, so it is normalised away before comparing.
# Normalised on one side only, and only at the start of a line: `bash` appearing anywhere else
# would be a genuine difference and must still show up as drift.
ps1_cmds="$(printf '%s\n' "$ps1_cmds" | sed -e 's|^bash ||')"

# Silently-empty extractions compare equal, so a broken parser would report agreement on
# zero steps -- the same fail-open shape as the check-secrets defect this suite exists for.
# This guard is load-bearing: D5 forbids unifying the implementations, so this script is
# the only thing keeping them in step. Second adversarial review, finding M8.
for side in just:"$just_cmds" sh:"$sh_cmds" ps1:"$ps1_cmds"; do
    if [[ -z "${side#*:}" ]]; then
        echo "check-verify-parity: FAIL extracted ZERO commands from the ${side%%:*} side." >&2
        echo "  The parser is broken, or a verification implementation is empty. Either way this" >&2
        echo "  is not agreement: two empty lists compare equal and would report a false pass." >&2
        exit 1
    fi
done

# Compared pairwise against the justfile so the failure message can name WHICH implementation
# drifted. A single three-way equality would report "they disagree" without saying where.
status=0
for pair in "$VERIFY_SH":"$sh_cmds" "$VERIFY_PS1":"$ps1_cmds"; do
    other_name="${pair%%:*}"
    other_cmds="${pair#*:}"
    if ! diff_out="$(diff <(printf '%s\n' "$just_cmds") <(printf '%s\n' "$other_cmds"))"; then
        echo "check-verify-parity: FAIL justfile and $other_name have drifted" >&2
        echo "  '<' only in justfile      '>' only in $other_name" >&2
        printf '%s\n' "$diff_out" | sed 's/^/    /' >&2
        status=1
    fi
done

if [[ "$status" -ne 0 ]]; then
    echo "  All three implementations are a frozen contract (ADR-001 D5): reconcile deliberately," >&2
    echo "  with owner approval. Do not 'fix' this by editing whichever file the diff blames." >&2
    exit 1
fi

n=$(printf '%s\n' "$just_cmds" | grep -c . || true)
echo "check-verify-parity: OK justfile, $VERIFY_SH and $VERIFY_PS1 agree on $n verification step(s)"
exit 0
