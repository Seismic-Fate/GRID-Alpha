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

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
