#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-music-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/Models/MusicPlayback.swift NotchFlow/Models/SyncedLyrics.swift NotchFlow/Music/MusicAutomation.swift \
  Tests/MusicTests.swift -o "$test_dir/music-tests"
"$test_dir/music-tests"
