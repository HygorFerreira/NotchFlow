#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-ai-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/Models/AIUsage.swift NotchFlow/AI/AIUsageMonitor.swift \
  Tests/AIUsageTests.swift -o "$test_dir/ai-tests"
"$test_dir/ai-tests"
