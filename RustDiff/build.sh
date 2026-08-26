#!/bin/bash
# ABOUTME: Builds the helix-diff Rust static library as a universal arm64 + x86_64 archive.
# ABOUTME: Generates the C header via cbindgen and copies artifacts for Swift integration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

HEADER_DEST="../Sources/CHelixDiff/include"
LIB_DEST="target/release"
TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)

# The app ships universal, so the static library has to carry both slices or the
# Release archive fails to link the x86_64 one.
for target in "${TARGETS[@]}"; do
    echo "==> Building helix-diff (release, $target)..."
    cargo build --release --target "$target"
done

echo "==> Combining slices..."
mkdir -p "$LIB_DEST"
lipo -create \
    "target/aarch64-apple-darwin/release/libhelix_diff.a" \
    "target/x86_64-apple-darwin/release/libhelix_diff.a" \
    -output "$LIB_DEST/libhelix_diff.a"

echo "==> Generating C header..."
cbindgen --config cbindgen.toml --crate helix-diff --output helix_diff.h

echo "==> Copying header to Swift module..."
mkdir -p "$HEADER_DEST"
cp helix_diff.h "$HEADER_DEST/helix_diff.h"

echo "==> Done."
lipo -info "$LIB_DEST/libhelix_diff.a"
echo "    Header:  $HEADER_DEST/helix_diff.h"
