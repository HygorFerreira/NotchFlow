#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-update-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -D UPDATE_TESTING -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/App/UpdateChecker.swift Tests/UpdateCheckerTests.swift -o "$test_dir/update-tests"
"$test_dir/update-tests"
swiftc -D UPDATE_TESTING -D APPSTORE -parse-as-library -module-cache-path "$test_dir/module-cache" \
  NotchFlow/App/UpdateChecker.swift Tests/UpdateCheckerTests.swift -o "$test_dir/appstore-update-tests"
"$test_dir/appstore-update-tests"
