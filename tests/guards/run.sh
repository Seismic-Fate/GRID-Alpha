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
mk_parity() {
    local d="$1" extra="${2:-}"
    printf 'verify:\n    just check-a\n    just check-b\n\ncheck-a:\n    cargo fmt --all -- --check\n\ncheck-b:\n    typos\n' > "$d/justfile"
    { printf '#!/bin/bash\nset -euo pipefail\nSCOPE="${1:-full}"\nif [[ "$SCOPE" == "full" ]]; then\n'
      printf '    cargo fmt --all -- --check\n    typos\n'
      [[ -n "$extra" ]] && printf '    %s\n' "$extra"
      printf 'fi\n'; } > "$d/scripts/verify.sh"
    git -C "$d" add -A; git -C "$d" commit -qm "P1-00 parity fixture"
}
d="$(new_repo parity-agree)";  mk_parity "$d"
expect 0 "matching implementations agree" "$d" ./scripts/check-verify-parity.sh

d="$(new_repo parity-drift)";  mk_parity "$d" "cargo audit"
expect 1 "a step added to verify.sh only is caught" "$d" ./scripts/check-verify-parity.sh

# Two silently-empty extractions compare EQUAL. A broken parser must fail, not report
# agreement on zero steps -- the fail-open shape this whole suite exists for.
d="$(new_repo parity-empty)"
printf 'verify:\n    just check-a\n\ncheck-a:\n' > "$d/justfile"
printf '#!/bin/bash\necho hi\n' > "$d/scripts/verify.sh"
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

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
