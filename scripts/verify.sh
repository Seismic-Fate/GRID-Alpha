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
    cargo sqlx prepare --check --workspace -- --lib

    echo "[verify] Rust tests..."
    cargo nextest run --workspace

    echo "[verify] Doctests..."
    cargo test --workspace --doc

    echo "[verify] FFI round-trip..."
    cargo test -p grid-ffi --features flutter-bridge-tests

    echo "[verify] Audit..."
    cargo deny check
    cargo audit

    echo "[verify] Repository guards..."
    ./tests/guards/run.sh
    ./scripts/check-migrations.sh
    ./scripts/check-secrets.sh
    ./scripts/check-traceability.sh
    ./scripts/check-authority-sync.sh
    ./scripts/check-verify-parity.sh
    ./scripts/check-env-contract.sh

    echo "[verify] Typos..."
    typos
fi

echo "[verify] All checks passed."