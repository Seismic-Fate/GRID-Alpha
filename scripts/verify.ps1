#Requires -Version 7.2
param(
    [ValidateSet("Full", "Changed")]
    [string]$Scope = "Full"
)

$ErrorActionPreference = "Stop"
Write-Host "[verify] Starting verification scope: $Scope"

if ($Scope -eq "Full" -or $Scope -eq "Changed") {
    Write-Host "[verify] Formatting..."
    cargo fmt --all -- --check

    Write-Host "[verify] Linting..."
    cargo clippy --all-targets --all-features -- -D warnings

    Write-Host "[verify] SQLx offline cache..."
    cargo sqlx prepare --check -- --lib

    Write-Host "[verify] Rust tests..."
    cargo nextest run --workspace

    Write-Host "[verify] FFI round-trip..."
    cargo test -p grid-ffi --features flutter-bridge-tests

    Write-Host "[verify] Audit..."
    cargo deny check
    cargo audit

    Write-Host "[verify] Typos..."
    typos
}

Write-Host "[verify] All checks passed."