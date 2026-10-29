#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-tools-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/Models/*.swift NotchFlow/Focus/NotificationService.swift \
  NotchFlow/Design/Color+Hex.swift NotchFlow/Tools/ClipboardMonitor.swift \
  NotchFlow/Tools/FileShelf.swift Tests/ToolsTests.swift -o "$test_dir/tools-tests"
"$test_dir/tools-tests"
