#!/usr/bin/env bash
# Runs the unit tests. Works with full Xcode or with only the Command Line Tools,
# whose Swift Testing macro plugin lives in a folder SwiftPM doesn't search.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
