#!/usr/bin/env bash
# Authority documents must not fork.
#
# alpha-spec.md exists twice: at the repo root (authority level 2) and mirrored into the
# Obsidian vault at docs/00-meta/specs/. Nothing stops the two drifting, and a forked
# authority document is the worst possible failure mode for an authority-driven repository.
#
# Exits non-zero if they differ. Fix by making the vault copy match the root, never the
# other way round: the root file is the one the specs and CLAUDE.md cite.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

CANONICAL="alpha-spec.md"
MIRROR="docs/00-meta/specs/alpha-spec.md"

status=0

for f in "$CANONICAL" "$MIRROR"; do
    if [[ ! -f "$f" ]]; then
        echo "check-authority-sync: FAIL missing authority document: $f" >&2
        exit 1
    fi
done

if cmp -s "$CANONICAL" "$MIRROR"; then
    echo "check-authority-sync: OK $CANONICAL == $MIRROR ($(wc -c < "$CANONICAL") bytes)"
else
    echo "check-authority-sync: FAIL authority document has forked" >&2
    echo "  $CANONICAL  $(cksum < "$CANONICAL")" >&2
    echo "  $MIRROR  $(cksum < "$MIRROR")" >&2
    echo "  first difference:" >&2
    diff "$CANONICAL" "$MIRROR" | head -10 >&2
    echo "  Resolve by copying the root file over the mirror, then re-review." >&2
    status=1
fi

exit "$status"
