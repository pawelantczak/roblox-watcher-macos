#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

BUILD_DIR="$DIR/.build"
mkdir -p "$BUILD_DIR"
TEST_EXEC="$BUILD_DIR/watcher-tests"

echo "==> Compiling Roblox Watcher Unit Test Suite..."
swiftc -O \
    Sources/Core/*.swift \
    Tests/WatcherTests.swift \
    -o "$TEST_EXEC"

echo "==> Running tests..."
"$TEST_EXEC"
