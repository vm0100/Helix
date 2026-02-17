#!/bin/bash
# ABOUTME: Builds the helix-diff Rust static library for the native architecture.
# ABOUTME: Generates the C header via cbindgen and copies artifacts for Swift integration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

HEADER_DEST="../Sources/CHelixDiff/include"
LIB_DEST="../RustDiff/target/release"

echo "==> Building helix-diff (release)..."
cargo build --release

echo "==> Generating C header..."
cbindgen --config cbindgen.toml --crate helix-diff --output helix_diff.h

echo "==> Copying header to Swift module..."
mkdir -p "$HEADER_DEST"
cp helix_diff.h "$HEADER_DEST/helix_diff.h"

echo "==> Done."
echo "    Library: $LIB_DEST/libhelix_diff.a"
echo "    Header:  $HEADER_DEST/helix_diff.h"
