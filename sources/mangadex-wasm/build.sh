#!/bin/bash
# Build script for MangaDex WASM addon

set -e

echo "Building MangaDex WASM addon..."

# Check for wasm32 target
if ! rustup target list --installed | grep -q wasm32-unknown-unknown; then
    echo "Installing wasm32-unknown-unknown target..."
    rustup target add wasm32-unknown-unknown
fi

# Build the addon
cargo build --release --target wasm32-unknown-unknown

# Copy to output
cp target/wasm32-unknown-unknown/release/mangadex_wasm.wasm mangadex.wasm

echo "Build complete: mangadex.wasm"
ls -la mangadex.wasm
