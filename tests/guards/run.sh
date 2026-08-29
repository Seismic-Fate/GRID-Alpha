#!/usr/bin/env bash
# Behaviour tests for the repository guard scripts.
#
# The guards are the largest body of new logic in P1-00 and had no committed tests. Both
# check-secrets.sh defects — ignoring untracked files, then FAILING OPEN over a committed
# secret — were found by ad-hoc testing that nothing re-ran. Adversarial review of PR #1
# recommended this suite; these are the cases that would have caught them.
#
# Each case builds a throwaway git repository, copies the guard in, and asserts an exit code.
# No network, no dependence on this repository's own history.
#
# Usage: tests/guards/run.sh
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  BAD  %s\n%s\n' "$1" "$(sed 's/^/         /' <<< "${2:-}")"; fail=$((fail+1)); }

# new_repo <name> -> echoes a fresh repo path with an initial commit
new_repo() {
    local d="$TMP/$1"; mkdir -p "$d/scripts"
    git -C "$d" init -q .
    git -C "$d" config user.email t@t; git -C "$d" config user.name t
    cp "$ROOT"/scripts/check-*.sh "$ROOT"/scripts/secret-patterns.txt "$d/scripts/" 2>/dev/null
    echo "seed" > "$d/seed.txt"; git -C "$d" add -A; git -C "$d" commit -qm "P1-00 seed"
    echo "$d"
}

# expect <want-exit> <label> <dir> <script> [args...]
expect() {
    local want="$1" label="$2" dir="$3"; shift 3
    local out; out="$(cd "$dir" && "$@" 2>&1)"; local got=$?
    if [[ "$got" -eq "$want" ]]; then ok "$label"; else bad "$label (want exit $want, got $got)" "$out"; fi
}

# expect_env <want-exit> <label> <dir> <env-spec...> -- <script> [args...]
# Same, with explicit environment. Needed for the CI-mode and SQLX_OFFLINE cases, where the
# variable under test is exactly what changes the verdict.
#
# `-u NAME` and `NAME=value` may be given in any order here and are reordered before the call:
# env(1) stops parsing options at the first assignment, so `env CI=true -u PR_BODY cmd` tries
# to execute a program literally named `-u`. That mistake has now been made three times in
# this project; the harness absorbs it so a test can never fail for that reason again.
expect_env() {
    local want="$1" label="$2" dir="$3"; shift 3
    local unsets=() assigns=()
    while [[ "$1" != "--" ]]; do
        if [[ "$1" == "-u" ]]; then unsets+=(-u "$2"); shift 2; else assigns+=("$1"); shift; fi
    done
    shift
    local out; out="$(cd "$dir" && env "${unsets[@]}" "${assigns[@]}" "$@" 2>&1)"; local got=$?
    if [[ "$got" -eq "$want" ]]; then ok "$label"; else bad "$label (want exit $want, got $got)" "$out"; fi
}

echo "check-secrets"
d="$(new_repo secrets-committed)"
printf 'token = "ghp_%s"\n' "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > "$d/leak.txt"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 add"
# THE M1 REGRESSION: no origin/main, secret is committed. Must NOT report OK.
expect 1 "committed secret with no base ref is caught (M1 regression)" "$d" ./scripts/check-secrets.sh

d="$(new_repo secrets-untracked)"
# Assembled at runtime, never written as a literal: check-secrets.sh scans tests/ too, and a
# literal here would make the guard fire on its own test suite. Excluding tests/ from the scan
# would be the wrong fix -- a real secret in a test file must still be caught.
scheme="post""gres"; cred="u:p"
printf 'db = "%s://%s@h/db"\n' "$scheme" "$cred" > "$d/untracked.txt"
expect 1 "credentialed connection string in an untracked file is caught" "$d" ./scripts/check-secrets.sh

d="$(new_repo secrets-clean)"
expect 0 "clean tree passes" "$d" ./scripts/check-secrets.sh

d="$(new_repo secrets-selfscan)"
expect 0 "the pattern file itself does not self-trigger" "$d" ./scripts/check-secrets.sh

# minor 4: the detector's own two files used to be excluded from every scan path, making them
# the one place in the repository where a secret was never looked for. They now get their own
# always-on pass, and only a line marked `# nosecret` is exempt inside it.
d="$(new_repo secrets-blindspot)"
printf 'ghp_%s\n' "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" >> "$d/scripts/secret-patterns.txt"
expect 1 "a secret hidden in the pattern file itself is caught (minor 4)" "$d" ./scripts/check-secrets.sh

d="$(new_repo secrets-nosecret)"
printf 'ghp_%s # nosecret\n' "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC" >> "$d/scripts/secret-patterns.txt"
expect 0 "a '# nosecret' line in the pattern file is exempt" "$d" ./scripts/check-secrets.sh

# THE WINDOWS FAIL-OPEN. On the merge-authoritative job both ls-files scan loops examined ZERO
# of the listed files, so the guard printed "OK no secret patterns found" over a committed
# ghp_ token -- and verify.ps1 discarded the non-zero exit, so the job went green. A carriage
# return on a path is enough to do it: -f fails, the file is skipped, the corpus stays empty.
d="$(new_repo secrets-crlf-paths)"
printf 'token = "ghp_%s"\n' "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD" > "$d/leak.txt"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 add"
sed -i 's/$/\r/' "$d/scripts/secret-patterns.txt"   # CRLF pattern file, as Windows checks out
expect 1 "a CRLF pattern file does not disarm the scanner" "$d" ./scripts/check-secrets.sh

# An empty scan is not a clean tree. Whatever the platform-specific cause, the scanner must
# refuse to report OK when git listed files and it opened none of them.
#
# The fixture carries NO secret on purpose. With one, the case would exit 1 whether or not the
# empty-scan guard exists, and would pass for the wrong reason -- the exact failure this round
# is about. Here the ONLY thing that can produce exit 1 is the guard.
d="$(new_repo secrets-empty-scan)"
expect 0 "control: the unmodified scanner reports a clean tree here" "$d" ./scripts/check-secrets.sh
# Break path resolution the way the Windows job did: every listed path gains a carriage return
# AFTER the scanner's own CR-stripping, so -f fails and nothing is opened.
sed -i 's|^        f="\${f%\$.\\r.}"|        f="${f}\\r"|' "$d/scripts/check-secrets.sh"
grep -q 'f="${f}\\r"' "$d/scripts/check-secrets.sh" \
    || bad "empty-scan fixture did not apply" "sed did not patch the copied scanner"
expect 1 "zero files scanned over a non-empty tree fails closed" "$d" ./scripts/check-secrets.sh

# The same empty-scan guard, on the OTHER arm of the if -- diff mode, which is the arm CI takes.
# The full-tree arm got its guard when the Windows fail-open was found; this one went a round
# without, sitting untouched next to its own fix.
d="$(new_repo secrets-empty-diff)"
git -C "$d" branch -q base HEAD
echo "// a real change" > "$d/changed.rs"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 change a file"
expect 0 "control: diff mode reports a clean diff here" "$d" ./scripts/check-secrets.sh base
# Make the added-line extractor yield nothing while the diff still touches files.
sed -i "s|^plus() .*|plus() { grep -E '^ZZZNOMATCHZZZ' \|\| true; }|" "$d/scripts/check-secrets.sh"
grep -q 'ZZZNOMATCHZZZ' "$d/scripts/check-secrets.sh" \
    || bad "empty-diff fixture did not apply" "sed did not patch the copied scanner"
expect 1 "changed files with zero added lines collected fails closed" "$d" ./scripts/check-secrets.sh base

# ---------------------------------------------------------------------------------------------
# Round 3 C1. The untracked scan is the THIRD instance of the empty-scan shape, and it was
# unguarded in BOTH arms: diff mode never checked it, and in full-tree mode the old call-site
# guard ran several lines earlier, counting only the tracked pass.
#
# These cases are written against the FUNCTION, not against either arm, because the fix is that
# scan_files guards itself. Both arms are exercised so neither can regress alone, and both carry
# a control -- a token planted in an UNTRACKED file, which the intact scanner must catch. That
# control is what proves the case can fail: without it, a scanner that opened nothing would
# "pass" the fixture for the wrong reason.
plant_untracked_token() {
    # A deny-tier ghp_ token, assembled at runtime so this file never contains a literal one.
    printf 'token = "ghp_%s"\n' "$(printf 'A%.0s' $(seq 36))" > "$1/untracked_secret.rs"
}
break_scan_files() {
    sed -i 's|^        f="\${f%\$.\\r.}"|        f="${f}\\r"|' "$1/scripts/check-secrets.sh"
    grep -q 'f="${f}\\r"' "$1/scripts/check-secrets.sh" \
        || bad "untracked-scan fixture did not apply" "sed did not patch the copied scanner"
}

d="$(new_repo secrets-untracked-diff)"
git -C "$d" branch -q base HEAD
echo "// a real change" > "$d/changed.rs"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 change a file"
plant_untracked_token "$d"
expect 1 "control: diff mode catches a token in an UNTRACKED file" "$d" ./scripts/check-secrets.sh base
break_scan_files "$d"
expect 1 "diff mode: untracked paths listed but none opened fails closed" "$d" ./scripts/check-secrets.sh base

d="$(new_repo secrets-untracked-full)"
plant_untracked_token "$d"
expect 1 "control: full-tree mode catches a token in an UNTRACKED file" "$d" ./scripts/check-secrets.sh no-such-base
# Break resolution for the untracked paths ONLY, leaving the tracked pass healthy. That is the
# case the old call-site guard could not see: it had already run and counted a non-zero scan.
sed -i 's|^.*# UNRESOLVABLE.*$|        case "$f" in untracked_*) continue ;; esac|' \
    "$d/scripts/check-secrets.sh"
grep -q 'untracked_\*' "$d/scripts/check-secrets.sh" \
    || bad "untracked-only fixture did not apply" "sed did not patch the copied scanner"
expect 1 "full-tree mode: untracked scan broken alone fails closed" "$d" ./scripts/check-secrets.sh no-such-base

# The guard must not fire on a legitimately unopenable set. An all-binary untracked corpus opens
# zero files for a deliberate reason, and reporting OK there is correct -- so this case proves
# the guard discriminates rather than simply refusing whenever it opened nothing.
d="$(new_repo secrets-untracked-binary)"
printf '\x00\x01\x02\x03binary\x00' > "$d/blob.bin"
expect 0 "an all-binary untracked set is a deliberate skip, not a broken scan" "$d" ./scripts/check-secrets.sh no-such-base

# minor 3: the deny patterns require realistic token lengths, so a truncated or short test
# token sits in the gap. The warn tier reports it without failing the build.
d="$(new_repo secrets-warn)"
printf 'token = "ghp_%s"\n' "SHORT123" > "$d/short.txt"
expect 0 "a short/truncated token warns but does not fail (minor 3)" "$d" ./scripts/check-secrets.sh

echo "check-migrations"
d="$(new_repo mig-add)"; mkdir -p "$d/migrations"
echo "CREATE TABLE a(x TEXT);" > "$d/migrations/0001_a.sql"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 first migration"
git -C "$d" branch -q base HEAD
echo "CREATE TABLE b(y TEXT);" > "$d/migrations/0002_b.sql"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 add 0002"
expect 0 "adding a migration passes" "$d" ./scripts/check-migrations.sh base

echo "ALTER TABLE a ADD COLUMN z TEXT;" >> "$d/migrations/0001_a.sql"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 tamper"
expect 1 "modifying an existing migration fails" "$d" ./scripts/check-migrations.sh base

d="$(new_repo mig-del)"; mkdir -p "$d/migrations"
echo "CREATE TABLE a(x TEXT);" > "$d/migrations/0001_a.sql"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 first"
git -C "$d" branch -q base HEAD
git -C "$d" rm -q "$d/migrations/0001_a.sql" 2>/dev/null || (cd "$d" && git rm -q migrations/0001_a.sql)
git -C "$d" commit -qm "P1-00 delete"
expect 1 "deleting a migration fails" "$d" ./scripts/check-migrations.sh base

# Append-only protects migrations already in the base; a draft added by this branch may still
# be amended. Over-strictness here would block anyone correcting their own unmerged migration.
d="$(new_repo mig-draft)"; mkdir -p "$d/migrations"
git -C "$d" branch -q base HEAD
echo "CREATE TABLE new(x TEXT);" > "$d/migrations/0001_new.sql"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 add draft migration"
echo "-- amended while still unmerged" >> "$d/migrations/0001_new.sql"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 amend the draft"
expect 0 "amending a migration absent from the base is allowed" "$d" ./scripts/check-migrations.sh base

echo "check-traceability"
d="$(new_repo trace)"; mkdir -p "$d/docs/01-work-packages"
printf '# P1-00\n\n## Scope\n- src/covered.rs\n' > "$d/docs/01-work-packages/p1-00-work-package.md"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 wp"
git -C "$d" branch -q base HEAD
mkdir -p "$d/src"; echo "// x" > "$d/src/covered.rs"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 covered change"
expect 0 "a path named in the work package passes" "$d" ./scripts/check-traceability.sh base

echo "// y" > "$d/src/unmentioned.rs"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 sneak"
expect 1 "a path absent from every referenced doc fails (M3 regression)" "$d" ./scripts/check-traceability.sh base

echo "check-authority-sync"
d="$(new_repo authsync)"; mkdir -p "$d/docs/00-meta/specs"
printf 'spec\n' > "$d/alpha-spec.md"; printf 'spec\n' > "$d/docs/00-meta/specs/alpha-spec.md"
expect 0 "identical spec copies pass" "$d" ./scripts/check-authority-sync.sh
printf 'spec drifted\n' > "$d/docs/00-meta/specs/alpha-spec.md"
expect 1 "a one-line fork is caught" "$d" ./scripts/check-authority-sync.sh

# The base-ref SKIP path. Both guards degrade to "NOT VERIFIED, exit 0" when the base cannot be
# resolved -- correct for a shallow local checkout, and fail-open in CI, where the second
# adversarial review found both build jobs hitting it at fetch-depth 1 (finding M1). Under $CI
# an unresolvable base is now a failure. This is the same fail-open shape as the original M1.
echo "base-ref SKIP path (M1 regression)"
d="$(new_repo skip-mig)"
expect_env 0 "no base ref outside CI skips" "$d" -u CI -- ./scripts/check-migrations.sh nope/nope
expect_env 1 "no base ref under CI fails"   "$d" CI=true -- ./scripts/check-migrations.sh nope/nope
expect_env 0 "traceability: no base ref outside CI skips" "$d" -u CI -u PR_BODY -- ./scripts/check-traceability.sh nope/nope
expect_env 1 "traceability: no base ref under CI fails"   "$d" CI=true -u PR_BODY -- ./scripts/check-traceability.sh nope/nope

# check-verify-parity is the only thing stopping the justfile and verify.sh from drifting --
# ADR-001 D5 forbids unifying them -- and it had no tests at all (finding M8).
echo "check-verify-parity"
# Round 3 M2: the guard now reads THREE implementations, so the fixture writes three. Without a
# verify.ps1 here the drift case would still exit 1 -- on "missing scripts/verify.ps1" -- and
# would have passed for the wrong reason.
mk_parity() {
    local d="$1" sh_extra="${2:-}" ps1_extra="${3:-}"
    printf 'verify:\n    just check-a\n    just check-b\n\ncheck-a:\n    cargo fmt --all -- --check\n\ncheck-b:\n    typos\n' > "$d/justfile"
    { printf '#!/bin/bash\nset -euo pipefail\nSCOPE="${1:-full}"\nif [[ "$SCOPE" == "full" ]]; then\n'
      printf '    cargo fmt --all -- --check\n    typos\n'
      [[ -n "$sh_extra" ]] && printf '    %s\n' "$sh_extra"
      printf 'fi\n'; } > "$d/scripts/verify.sh"
    { printf '$ErrorActionPreference = "Stop"\n'
      printf 'function Assert-Ok([string]$Step) {\n    if ($LASTEXITCODE -ne 0) {\n        throw "x"\n    }\n}\n'
      printf 'if ($true) {\n'
      printf '    cargo fmt --all -- --check\n    Assert-Ok "fmt"\n    typos\n    Assert-Ok "typos"\n'
      [[ -n "$ps1_extra" ]] && printf '    %s\n    Assert-Ok "extra"\n' "$ps1_extra"
      printf '}\n'; } > "$d/scripts/verify.ps1"
    git -C "$d" add -A; git -C "$d" commit -qm "P1-00 parity fixture"
}
d="$(new_repo parity-agree)";  mk_parity "$d"
expect 0 "all three implementations agree" "$d" ./scripts/check-verify-parity.sh

d="$(new_repo parity-drift)";  mk_parity "$d" "cargo audit"
expect 1 "a step added to verify.sh only is caught" "$d" ./scripts/check-verify-parity.sh

# The M2 scenario itself: the step is present in the justfile and verify.sh and MISSING from
# verify.ps1 -- the merge-authoritative gate silently running one check fewer than the smoke
# gate. Nothing in the repository caught this before the guard went three-way.
d="$(new_repo parity-drift-ps1)"
mk_parity "$d"
printf 'check-c:\n    cargo audit\n' >> "$d/justfile"
sed -i 's|^    just check-b$|    just check-b\n    just check-c|' "$d/justfile"
sed -i 's|^    typos$|    typos\n    cargo audit|' "$d/scripts/verify.sh"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 step missing from verify.ps1"
expect 1 "a step missing from verify.ps1 only is caught (M2)" "$d" ./scripts/check-verify-parity.sh

# The `bash ` prefix verify.ps1 needs to run a .sh on Windows is a platform necessity, not
# drift, and must NOT be reported as disagreement. Proves the normalisation discriminates
# rather than simply making the ps1 side always compare equal.
d="$(new_repo parity-bash-prefix)"
printf 'verify:\n    just check-a\n\ncheck-a:\n    ./scripts/check-env-contract.sh\n' > "$d/justfile"
printf '#!/bin/bash\nset -euo pipefail\nif true; then\n    ./scripts/check-env-contract.sh\nfi\n' > "$d/scripts/verify.sh"
printf 'if ($true) {\n    bash ./scripts/check-env-contract.sh\n    Assert-Ok "env"\n}\n' > "$d/scripts/verify.ps1"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 bash-prefix fixture"
expect 0 "the bash prefix on verify.ps1 guard steps is not reported as drift" "$d" ./scripts/check-verify-parity.sh

# Silently-empty extractions compare EQUAL. A broken parser must fail, not report
# agreement on zero steps -- the fail-open shape this whole suite exists for.
d="$(new_repo parity-empty)"
printf 'verify:\n    just check-a\n\ncheck-a:\n' > "$d/justfile"
printf '#!/bin/bash\necho hi\n' > "$d/scripts/verify.sh"
printf 'if ($true) {\n    cargo fmt --all -- --check\n    Assert-Ok "fmt"\n}\n' > "$d/scripts/verify.ps1"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 empty recipes"
expect 1 "an extraction yielding zero commands fails rather than passing" "$d" ./scripts/check-verify-parity.sh

# check-env-contract had no tests either, and its SQLX_OFFLINE half is what blocker C2 turned on.
echo "check-env-contract"
mk_env() {
    local d="$1"; printf 'DATABASE_URL=sqlite:target/grid-dev.db\nSQLX_OFFLINE=true\n' > "$d/.env"
    git -C "$d" add -A; git -C "$d" commit -qm "P1-00 env fixture"
}
d="$(new_repo env-cache-present)"; mkdir -p "$d/.sqlx"; touch "$d/.sqlx/query-x.json"; mk_env "$d"
expect_env 0 "SQLX_OFFLINE=true with .sqlx present passes" "$d" -u DATABASE_URL SQLX_OFFLINE=true -- ./scripts/check-env-contract.sh
expect_env 0 "SQLX_OFFLINE comes from .env when the environment is silent" "$d" -u DATABASE_URL -u SQLX_OFFLINE -- ./scripts/check-env-contract.sh

d="$(new_repo env-cache-absent)"; mk_env "$d"
expect_env 1 "SQLX_OFFLINE=true with no .sqlx fails" "$d" -u DATABASE_URL SQLX_OFFLINE=true -- ./scripts/check-env-contract.sh
expect_env 1 "the sqlite:// authority form is still rejected" "$d" DATABASE_URL=sqlite://target/x.db -u SQLX_OFFLINE -- ./scripts/check-env-contract.sh

# C1: verify.sh accepted any scope and exited 0 having run nothing. `Full` is the exact
# capitalization every authority document prints. cargo is stubbed so the guard is observed
# in isolation -- exit 99 proves control reached the first real check.
echo "verify.sh scope guard (C1 regression)"
d="$(new_repo scope)"; cp "$ROOT/scripts/verify.sh" "$d/scripts/"
mkdir -p "$d/stub"; printf '#!/bin/sh\nexit 99\n' > "$d/stub/cargo"; chmod +x "$d/stub/cargo"
git -C "$d" add -A; git -C "$d" commit -qm "P1-00 scope fixture"
for bad_scope in smoke --help "Fullish"; do
    expect_env 2 "scope '$bad_scope' is rejected" "$d" "PATH=$d/stub:$PATH" -- ./scripts/verify.sh "$bad_scope"
done
for good_scope in Full FULL full Changed changed; do
    expect_env 99 "scope '$good_scope' reaches the first check" "$d" "PATH=$d/stub:$PATH" -- ./scripts/verify.sh "$good_scope"
done
expect_env 99 "no argument defaults to full" "$d" "PATH=$d/stub:$PATH" -- ./scripts/verify.sh

# ADR-009 fixed verify.ps1 to check $LASTEXITCODE after every native command. Nothing stops a
# later command being added WITHOUT one, which would silently reopen the merge-gate fail-open --
# and the Assert-Ok convention is something no other guard can see: check-verify-parity compares
# WHICH commands each implementation runs (three-way since round 3 M2), never whether each one's
# exit code is checked. This is a text analysis, so it runs on Linux where pwsh does not.
echo "verify.ps1 exit-code coverage (ADR-009 regression)"
# Round 3 M1. The first version of this analysis asked "does the line LOOK like a command?"
# via /^[[:space:]]+[A-Za-z]/ and missed six of seven forms: `& $tool` and `.\tool.exe` (the two
# idiomatic PowerShell invocations, and `.\` is how the workflow calls this very script), and
# anything at column 0 -- none of which start with an indented letter. Worse, the construct-skip
# list was unanchored, so `ifconfig`, `paramgen` and `throwaway-tool` were skipped as if they
# were `if`, `param` and `throw`.
#
# Inverted: a line is a command UNLESS it is a recognised construct. A new invocation form is
# then caught by default, instead of needing the pattern widened to admit it first.
#
# The keyword boundary is ([^[:alnum:]_-]|$), NOT \b -- in awk \b is a backspace, not a word
# boundary (gawk spells it \y; mawk, which Ubuntu runners use, has neither). Writing \b here
# silently matched nothing and turned `param(` and `if (...)` into false positives. Measured,
# not assumed: this runner is mawk 1.3.4.
ps1_unguarded() {
    awk '
      { sub(/\r$/, "") }
      /^[[:space:]]*(#|$)/ { next }
      /^[[:space:]]*(if|elseif|else|switch|foreach|for|while|do|try|catch|finally|function|param|return|throw|break|continue|begin|process|end)([^[:alnum:]_-]|$)/ { next }
      /^[[:space:]]*[{}]/ { next }
      /^[[:space:]]*\[/   { next }
      /^[[:space:]]*\)/   { next }
      /^[[:space:]]*\$/   { next }
      /Write-Host/ { next }
      /Assert-Ok/  { next }
      {
          cmd = $0
          if ((getline nxt) <= 0 || nxt !~ /Assert-Ok/) { print "UNGUARDED:" cmd; bad++ } else { n++ }
          next
      }
      END { printf "%d guarded, %d unguarded\n", n, bad+0; exit (bad+0) > 0 }
    ' "$1"
}

ps1_plain="$TMP/verify.ps1.lf"
tr -d '\r' < "$ROOT/scripts/verify.ps1" > "$ps1_plain"
if out="$(ps1_unguarded "$ps1_plain")"; then
    ok "every native command in verify.ps1 is followed by Assert-Ok ($out)"
else
    bad "a native command in verify.ps1 has no exit-code check" "$out"
fi

# Mutation control: the analysis must actually be able to fail, or it proves nothing.
ps1_mutated="$TMP/verify.ps1.mutated"
grep -v 'Assert-Ok "cargo audit"' "$ps1_plain" > "$ps1_mutated"
if ps1_unguarded "$ps1_mutated" >/dev/null 2>&1; then
    bad "the verify.ps1 coverage check cannot fail" "removing an Assert-Ok still reported clean"
else
    ok "removing one Assert-Ok is caught (mutation control)"
fi

# Round 3 M1. The control above proves the analysis can FAIL. It does not prove it can SEE:
# the old analysis passed it while missing six of the seven ways a native command can be
# written. Each form below is inserted AFTER a complete command/Assert-Ok pair, so the insert
# stands alone and cannot be "caught" by displacing an existing pairing -- a trap that made an
# early version of this table read all-green for the wrong reason.
ps1_form_missed=0
while IFS='|' read -r label line; do
    [[ -z "$label" ]] && continue
    m="$TMP/verify.ps1.form"
    awk -v ins="$line" '
        { print }
        /Assert-Ok "cargo fmt --all -- --check"/ && !done { print ins; done = 1 }
    ' "$ps1_plain" > "$m"
    if out="$(ps1_unguarded "$m" 2>&1)"; then
        bad "unguarded command as $label is not detected" "$out"
        ps1_form_missed=1
    elif printf '%s' "$out" | grep -q 'UNGUARDED.*cargo fmt'; then
        bad "the $label case flags cargo fmt, not the insert" "$out"
        ps1_form_missed=1
    fi
done <<'FORMS'
a plain indented command|    sbom-tool generate
a call-operator invocation|    & $sbom generate
a relative-path invocation|    .\tools\sbom.exe
a command whose name starts "if"|    ifconfig
a command whose name starts "param"|    paramgen --check
a command whose name starts "throw"|    throwaway-tool
a command at column 0|sbom-tool generate
FORMS
[[ "$ps1_form_missed" -eq 0 ]] \
    && ok "an unguarded command is detected in all 7 invocation forms (M1 coverage control)"

# And the inverse: a recognised construct must never be mistaken for a command. Without this,
# "detects everything" is trivially satisfiable by flagging every line.
ps1_fp=0
while IFS= read -r construct; do
    [[ -z "$construct" ]] && continue
    m="$TMP/verify.ps1.fp"
    { printf '%s\n' "$construct"; printf '    cargo x\n    Assert-Ok "cargo x"\n'; } > "$m"
    if ps1_unguarded "$m" 2>&1 | grep -q 'UNGUARDED'; then
        bad "construct misread as a native command: $construct" "$(ps1_unguarded "$m" 2>&1)"
        ps1_fp=1
    fi
done <<'CONSTRUCTS'
if ($x) {
elseif ($y) {
else {
try {
catch {
function F {
param(
throw "x"
$v = 1
    [string]$s
)
}
CONSTRUCTS
[[ "$ps1_fp" -eq 0 ]] && ok "PowerShell constructs are not misread as commands (no false positives)"

# Round 3 M3. The CI self-test asserts on the SPECIFIC Assert-Ok message, so it is coupled to
# the first and last labels in verify.ps1: it stubs cargo to fail and expects
# "[verify] FAILED: cargo fmt", then stubs typos to fail and expects "[verify] FAILED: typos".
# Renaming either label silently turns that assertion into one that can only fail. Checked here,
# on Linux, in milliseconds, rather than 25 minutes into the Windows job.
ps1_labels="$(sed 's/\r$//' "$ROOT/scripts/verify.ps1" | sed -n 's/.*Assert-Ok "\([^"]*\)".*/\1/p')"
ps1_first="$(printf '%s\n' "$ps1_labels" | head -1)"
ps1_last="$(printf '%s\n' "$ps1_labels" | tail -1)"
if [[ "$ps1_first" == cargo\ fmt* && "$ps1_last" == "typos" ]]; then
    ok "the CI self-test's expected Assert-Ok labels still exist ('$ps1_first' … '$ps1_last')"
else
    bad "verify.ps1's first/last Assert-Ok labels moved; the ADR-009 self-test can no longer pass" \
        "first='$ps1_first' last='$ps1_last' -- update .github/workflows/alpha-ci.yml together with this"
fi

# Round 3 min-3. ADR-008's scope guard MUST stay at column 0. check-verify-parity extracts
# verify.sh's command list with `grep -E '^[[:space:]]+[a-zA-Z._/]'`, so an indented `case` arm
# would be read as a verification step and reported as drift against the justfile. That coupling
# was documented in a comment, which means a routine re-indent in one file silently changes
# another file's verdict. A comment is a note to a careful reader; this is the assertion.
echo "verify.sh scope guard indentation (ADR-008 / parity coupling)"
scope_indented="$(sed 's/\r$//' "$ROOT/scripts/verify.sh" \
    | awk '/^[[:space:]]*case[[:space:]]+"\$SCOPE"/, /^[[:space:]]*esac/' \
    | grep -cE '^[[:space:]]+' || true)"
if [[ "$scope_indented" -eq 0 ]]; then
    ok "the scope-guard case block is at column 0, where the parity extractor cannot see it"
else
    bad "the scope-guard case block in verify.sh is indented ($scope_indented line(s))" \
        "check-verify-parity would read those arms as verification steps and report false drift"
fi
# And the control: an indented arm must actually be detectable, or the check above is vacuous.
scope_ctl="$(printf 'case "$SCOPE" in\n    full) ;;\nesac\n' | awk '/^[[:space:]]*case[[:space:]]+"\$SCOPE"/, /^[[:space:]]*esac/' | grep -cE '^[[:space:]]+' || true)"
[[ "$scope_ctl" -gt 0 ]] \
    && ok "an indented case arm is detected (control)" \
    || bad "the indentation check cannot fail" "an indented arm was not counted"

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
