#!/bin/bash
set -euo pipefail

SCOPE="${1:-full}"
echo "[verify] Starting verification scope: $SCOPE"

if [[ "$SCOPE" == "full" || "$SCOPE" == "changed" ]]; then
    echo "[verify] Formatting..."
    cargo fmt --all -- --check

    echo "[verify] Linting..."
    cargo clippy --all-targets --all-features -- -D warnings

    echo "[verify] SQLx offline cache..."
    cargo sqlx prepare --check -- --lib

    echo "[verify] Rust tests..."
    cargo nextest run --workspace

    echo "[verify] FFI round-trip..."
    cargo test -p grid-ffi --features flutter-bridge-tests

    echo "[verify] Audit..."
    cargo deny check
    cargo audit

    echo "[verify] Typos..."
    typos
fi

echo "[verify] All checks passed."