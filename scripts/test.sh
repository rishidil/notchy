#!/bin/bash
# Runs Notchy's test suite: ./scripts/test.sh
# Works with just the Xcode Command Line Tools (points the compiler at their bundled Swift Testing framework).
# Live tests are opt-in:
#   NOTCHY_LIVE_CLAUDE=1 ANTHROPIC_API_KEY=sk-ant-… ./scripts/test.sh   # real Claude API calls (costs a few cents)
#   NOTCHY_LIVE_T3=1 ./scripts/test.sh                                    # talks to the running T3 Code server
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
F="$DEV/Library/Developer/Frameworks"
L="$DEV/Library/Developer/usr/lib"
if [ -d "$F/Testing.framework" ]; then
  swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
else
  swift test "$@"
fi
