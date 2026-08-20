#!/usr/bin/env bash
# Verify the local environment satisfies the contract in docs/02-adr/002-sqlx-offline-cache.md.
#
# Exists because a stale preset DATABASE_URL produces only "error returned from database:
# (code: 14) unable to open database file", with no hint that the environment is at fault.
# A committed .env cannot help: dotenv never overrides an already-set variable.
#
# Read-only. Never mutates the environment or creates a database.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED_URL="sqlite:target/grid-dev.db"
status=0
fail() { echo "check-env-contract: FAIL $*" >&2; status=1; }

# DATABASE_URL: environment wins over .env, so report which source is in play.
if [[ -n "${DATABASE_URL:-}" ]]; then
    src="environment"
    url="$DATABASE_URL"
elif [[ -f .env ]] && grep -qE '^DATABASE_URL=' .env; then
    src=".env"
    url="$(grep -m1 -E '^DATABASE_URL=' .env | cut -d= -f2-)"
else
    fail "DATABASE_URL is not set and .env does not define it (expected $EXPECTED_URL)"
    url=""
    src="unset"
fi

if [[ -n "$url" ]]; then
    if [[ "$url" =~ ^sqlite:// ]]; then
        fail "DATABASE_URL uses the // authority form: $url
       'sqlite://target/x.db' parses 'target' as a host and resolves to /x.db at the
       filesystem root. Use the relative form instead: $EXPECTED_URL"
    elif [[ ! "$url" =~ ^sqlite: ]]; then
        fail "DATABASE_URL is not a SQLite URL (from $src): $url
       GRID-Alpha uses SQLite exclusively (final-build-spec.md 8)."
    else
        db="${url#sqlite:}"; db="${db%%\?*}"
        dir="$(dirname "$db")"
        if [[ ! -d "$dir" ]]; then
            fail "DATABASE_URL directory does not exist: $dir (from $src: $url)
       Run 'just bootstrap' to create the development database."
        else
            echo "check-env-contract: OK DATABASE_URL=$url (from $src)"
            [[ -f "$db" ]] || echo "check-env-contract: NOTE $db not created yet — run 'just bootstrap'"
        fi
    fi
fi

# SQLX_OFFLINE must agree with whether the committed cache actually exists.
if [[ "${SQLX_OFFLINE:-}" == "true" && ! -d .sqlx ]]; then
    fail "SQLX_OFFLINE=true but .sqlx/ does not exist.
       The query! macro will read a cache that is not there. Unset SQLX_OFFLINE for local
       work, or generate the cache with 'cargo sqlx prepare'."
else
    echo "check-env-contract: OK SQLX_OFFLINE=${SQLX_OFFLINE:-<unset>}, .sqlx/ $([[ -d .sqlx ]] && echo present || echo absent)"
fi

[[ "$status" -eq 0 ]] || echo "check-env-contract: see docs/02-adr/002-sqlx-offline-cache.md" >&2
exit "$status"
