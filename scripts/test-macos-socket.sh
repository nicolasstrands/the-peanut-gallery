#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/peanut-socket-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc \
  "$REPO_ROOT/apps/macos-overlay/Sources/PeanutGallery/ReactionSocket.swift" \
  "$REPO_ROOT/apps/macos-overlay/Sources/PeanutGallery/RealtimeSettings.swift" \
  "$REPO_ROOT/apps/macos-overlay/Sources/PeanutGallery/DisplayCredentialStore.swift" \
  "$REPO_ROOT/apps/macos-overlay/Tests/ReactionSocketSmoke.swift" \
  -o "$TEST_DIR/socket-smoke"
"$TEST_DIR/socket-smoke"
