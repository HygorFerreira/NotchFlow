#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-productivity-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  -module-cache-path "$test_dir/module-cache" \
  NotchFlow/Models/*.swift \
  NotchFlow/Focus/NotificationService.swift \
  Tests/ProductivityTests.swift \
  -o "$test_dir/productivity-tests"
"$test_dir/productivity-tests"
