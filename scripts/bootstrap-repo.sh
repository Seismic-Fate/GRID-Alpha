#!/bin/bash
set -euo pipefail

# Create crate directories
mkdir -p crates/{domain,persistence,ingestion,identity,features,models,simulation,scoring,evaluation,governance,application,ffi}

# Create root Cargo.toml for each crate
for crate in domain persistence ingestion identity features models simulation scoring evaluation governance application ffi; do
    cat > "crates/$crate/Cargo.toml" <<EOF
[package]
name = "grid-$crate"
version.workspace = true
edition.workspace = true
authors.workspace = true
license.workspace = true

[dependencies]
EOF
done

# Add lib.rs stubs
for crate in domain persistence ingestion identity features models simulation scoring evaluation governance application ffi; do
    mkdir -p "crates/$crate/src"
    echo "// grid-$crate" > "crates/$crate/src/lib.rs"
done

# Application binary stub
mkdir -p crates/application/src/bin

# FFI generated directory
mkdir -p crates/ffi/src/generated

# SQLx migrations
mkdir -p migrations

# Data directory
mkdir -p data

# Docs structure
mkdir -p docs/{adr,contracts,model-specs,providers/{nflverse,cfbd},work-packages,sessions,templates}

# App directory
mkdir -p app/lib app/test

# Scripts
mkdir -p scripts

echo "[bootstrap] GRID-Alpha repository skeleton created."
echo "[bootstrap] Next: edit app/pubspec.yaml, create root alpha-spec.md, and run 'just verify'."