#!/bin/sh
#
# Runs the unit tests.
#
# Why this wrapper exists: when CommandLineTools is the active developer directory, SwiftPM does
# not pass `-plugin-path` for the Swift Testing macro plugin. The plugin ships in a `testing/`
# subdirectory that the default plugin search does not cover, so the `@Test` / `@Suite` / `#expect`
# macros fail to expand on rebuilds with "plugin for module 'TestingMacros' not found".
#
# Package.swift passes the flag too, which covers clean builds, but SwiftPM drops it on some
# incremental rebuilds. Passing it here applies it to every compile job, every time.
set -eu

cd "$(dirname "$0")/.."

# Walk up from the compiler to the toolchain root, then look for the plugin where it lives.
plugin_path=""
directory=$(xcrun --find swiftc)
while [ "$directory" != "/" ] && [ -n "$directory" ]; do
    directory=$(dirname "$directory")
    if [ -d "$directory/usr/lib/swift/host/plugins/testing" ]; then
        plugin_path="$directory/usr/lib/swift/host/plugins/testing"
        break
    fi
done

if [ -n "$plugin_path" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$plugin_path" "$@"
fi

echo "Scripts/test.sh: Swift Testing plugin not found; falling back to plain 'swift test'" >&2
exec swift test "$@"
