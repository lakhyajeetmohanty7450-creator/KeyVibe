#!/bin/bash
# ==============================================================================
# KeyVibe: Velocity-Sensitive Mechanical Keyboard Sound Utility for macOS
# Build & Bundle Packaging Script
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/KeyVibe.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="/tmp/clang-module-cache"

echo "🔨 Building KeyVibe (macOS arm64)..."

# Ensure output directories exist
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE"

# 1. Compile C real-time Core Audio renderer
echo "  [1/4] Compiling C real-time audio renderer (AudioRenderer.c)..."
clang -c "$PROJECT_ROOT/KeyVibe/Audio/AudioRenderer.c" \
  -o "$BUILD_DIR/AudioRenderer.o" \
  -O3 \
  -std=c11 \
  -arch arm64 \
  -target arm64-apple-macos14.0 \
  -isysroot "$(xcrun --show-sdk-path)"

# 2. Compile Swift sources with Bridging Header
echo "  [2/4] Compiling Swift application layers with sub-millisecond Core Audio graph..."
find "$PROJECT_ROOT/KeyVibe" -name "*.swift" -print0 | xargs -0 swiftc -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -import-objc-header "$PROJECT_ROOT/KeyVibe/Audio/KeyVibe-Bridging-Header.h" \
  -framework AppKit \
  -framework SwiftUI \
  -framework IOKit \
  -framework AVFoundation \
  -framework AudioToolbox \
  -framework Security \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -O \
  -target arm64-apple-macos14.0 \
  "$BUILD_DIR/AudioRenderer.o" \
  -o "$MACOS_DIR/KeyVibe"

# 3. Bundle Resources & Info.plist
echo "  [3/4] Packaging application bundle (KeyVibe.app)..."
cp "$PROJECT_ROOT/KeyVibe/App/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy sound pack directory structure
if [ -d "$PROJECT_ROOT/KeyVibe/SoundPacks/Packs" ]; then
    rm -rf "$RESOURCES_DIR/SoundPacks"
    mkdir -p "$RESOURCES_DIR/SoundPacks"
    cp -R "$PROJECT_ROOT/KeyVibe/SoundPacks/Packs/"* "$RESOURCES_DIR/SoundPacks/"
fi

# 4. Code Sign with explicit Bundle Identifier
echo "  [4/4] Ad-hoc code signing with identifier com.keyvibe.app..."
codesign -s - --force --deep --identifier "com.keyvibe.app" -r="designated => identifier \"com.keyvibe.app\"" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"

echo "✅ Build successful!"
echo "📍 Application created at: $APP_BUNDLE"
