set shell := ["bash", "-cu"]

default:
    just verify

# Bootstrap dev tools and the local development database.
# Run once per fresh environment. NOT a verify recipe: the seven recipes under
# `verify` are a frozen contract (docs/02-adr/001-repo-bootstrap-decisions.md D5).
bootstrap:
    cargo install cargo-nextest --locked
    cargo install sqlx-cli --locked
    cargo install cargo-deny --locked
    cargo install cargo-audit --locked
    cargo install typos-cli --locked
    cargo install hyperfine --locked
    cargo install cargo-mutants --locked
    # Local SQLite development database for the compile-time query cache (ADR-002).
    # target/ must exist first: sqlite cannot create a file in a missing directory,
    # and a fresh checkout has no target/ until cargo runs.
    mkdir -p target
    sqlx database create
    sqlx migrate run

# Full verification suite (Linux smoke)
verify:
    just check-fmt
    just check-lint
    just check-sqlx
    just test-rust
    just test-doc
    just test-ffi
    just audit
    just check-guards
    just check-typos

check-fmt:
    cargo fmt --all -- --check

check-lint:
    cargo clippy --all-targets --all-features -- -D warnings

check-sqlx:
    cargo sqlx prepare --check --workspace -- --lib

test-rust:
    cargo nextest run --workspace

# nextest does not run doctests at all (ADR-007). Zero exist today; this keeps the gate
# from going blind the moment P1-01 adds a doc example.
test-doc:
    cargo test --workspace --doc

test-ffi:
    cargo test -p grid-ffi --features flutter-bridge-tests

audit:
    cargo deny check
    cargo audit

# alpha-spec.md 8.11 lists secret scanning and traceability as part of the verification
# orchestration. Before ADR-007 these ran only in CI, so the canonical command provided
# neither. BASE_REF lets CI pass the PR base; locally it defaults to origin/main.
check-guards:
    ./tests/guards/run.sh
    ./scripts/check-migrations.sh
    ./scripts/check-secrets.sh
    ./scripts/check-traceability.sh
    ./scripts/check-authority-sync.sh
    ./scripts/check-verify-parity.sh
    ./scripts/check-env-contract.sh

check-typos:
    typos

# Database
db-prepare:
    cargo sqlx prepare -- --lib

db-migrate:
    sqlx migrate run

# Flutter (Linux desktop for cloud dev)
serve-ui:
    cd app && flutter run -d linux

# Evidence manifest
evidence WP_ID:
    ./scripts/generate-evidence-manifest.sh {{WP_ID}}

# Experimental: mutation testing on statistical core
mutants:
    cargo mutants --package grid-models --output mutants.out

# Bench (placeholder)
bench:
    @echo "Add hyperfine benchmarks after P1-07"