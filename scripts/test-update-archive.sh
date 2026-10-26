#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 3 ]] || { echo 'Usage: bash scripts/test-update-archive.sh App.app appcast.xml update.zip' >&2; exit 1; }
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/notchflow-archive-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  Tests/UpdateArchiveTests.swift -o "$test_dir/archive-tests"
"$test_dir/archive-tests" "$@"
