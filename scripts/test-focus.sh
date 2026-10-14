#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-focus-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  -module-cache-path "$test_dir/module-cache" \
  NotchFlow/Models/*.swift \
  NotchFlow/Focus/NotificationService.swift \
  NotchFlow/Design/Color+Hex.swift \
  NotchFlow/Focus/FocusTimer.swift \
  Tests/FocusTimerTests.swift \
  -o "$test_dir/focus-tests"
"$test_dir/focus-tests"
