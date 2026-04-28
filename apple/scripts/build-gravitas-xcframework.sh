#!/usr/bin/env bash
# Builds gravitas-core as a fat xcframework (iOS device + iOS sim + macOS)
# for later wiring into the Swift app. v1 doesn't need this — the Metal
# shader does its own geodesic integration on-GPU.
#
# Prereqs:
#   - rustup (install from https://rustup.rs)
#   - Xcode command-line tools
#
# Output: apple/build/Gravitas.xcframework
#
# NOTE: this script depends on a thin C-FFI crate at
#   physics-engine/gravitas-ffi
# which does not yet exist. Create it with `cargo new --lib gravitas-ffi`
# under physics-engine/, then add `gravitas-core = { path = "../gravitas-core" }`
# and a `crate-type = ["staticlib"]` entry in Cargo.toml. Expose extern "C"
# functions from gravitas-core (camera ray builder, parameter computation, etc.).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FFI_CRATE="$REPO_ROOT/physics-engine/gravitas-ffi"
BUILD_DIR="$REPO_ROOT/apple/build"
LIB_NAME="libgravitas_ffi.a"
FRAMEWORK_NAME="Gravitas"

if [ ! -d "$FFI_CRATE" ]; then
  echo "error: $FFI_CRATE does not exist."
  echo "       Create a thin C-FFI crate that re-exports gravitas-core via extern \"C\","
  echo "       with crate-type = [\"staticlib\"] in its Cargo.toml."
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install rustup from https://rustup.rs"
  exit 1
fi

TARGETS=(
  aarch64-apple-ios
  aarch64-apple-ios-sim
  x86_64-apple-ios
  aarch64-apple-darwin
  x86_64-apple-darwin
)

echo "==> Ensuring Rust targets are installed"
for t in "${TARGETS[@]}"; do
  rustup target add "$t" >/dev/null
done

echo "==> Building $FFI_CRATE"
mkdir -p "$BUILD_DIR"
cd "$FFI_CRATE"
for t in "${TARGETS[@]}"; do
  echo "    -> $t"
  cargo build --release --target "$t"
done

# Lipo simulator slices (iOS sim arm64 + x86_64) into a single fat archive
SIM_OUT="$BUILD_DIR/ios-sim/$LIB_NAME"
mkdir -p "$(dirname "$SIM_OUT")"
lipo -create \
  "$REPO_ROOT/target/aarch64-apple-ios-sim/release/$LIB_NAME" \
  "$REPO_ROOT/target/x86_64-apple-ios/release/$LIB_NAME" \
  -output "$SIM_OUT"

# Lipo macOS slices (arm64 + x86_64)
MAC_OUT="$BUILD_DIR/macos/$LIB_NAME"
mkdir -p "$(dirname "$MAC_OUT")"
lipo -create \
  "$REPO_ROOT/target/aarch64-apple-darwin/release/$LIB_NAME" \
  "$REPO_ROOT/target/x86_64-apple-darwin/release/$LIB_NAME" \
  -output "$MAC_OUT"

# iOS device
IOS_DEV="$REPO_ROOT/target/aarch64-apple-ios/release/$LIB_NAME"

# Headers — the FFI crate must produce a header at $FFI_CRATE/include/gravitas.h
# (use cbindgen, or hand-write a header that matches your extern "C" signatures).
HEADERS_DIR="$FFI_CRATE/include"
if [ ! -d "$HEADERS_DIR" ]; then
  echo "error: $HEADERS_DIR does not exist. Generate or hand-write gravitas.h there."
  exit 1
fi

XCFW_OUT="$BUILD_DIR/$FRAMEWORK_NAME.xcframework"
rm -rf "$XCFW_OUT"

xcodebuild -create-xcframework \
  -library "$IOS_DEV"  -headers "$HEADERS_DIR" \
  -library "$SIM_OUT"  -headers "$HEADERS_DIR" \
  -library "$MAC_OUT"  -headers "$HEADERS_DIR" \
  -output  "$XCFW_OUT"

echo "==> Built $XCFW_OUT"
echo "    Add it to apple/project.yml under both targets, e.g.:"
echo "      dependencies:"
echo "        - framework: build/Gravitas.xcframework"
