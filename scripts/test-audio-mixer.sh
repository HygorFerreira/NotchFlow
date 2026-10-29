#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-audio-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/Audio/AudioMixerEngine.swift Tests/AudioMixerTests.swift -o "$test_dir/audio-tests"
"$test_dir/audio-tests"
