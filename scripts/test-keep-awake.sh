#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-awake-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/App/KeepAwakeController.swift Tests/KeepAwakeTests.swift \
  -o "$test_dir/awake-tests"
"$test_dir/awake-tests"
