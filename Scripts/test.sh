#!/usr/bin/env bash
# Runs the unit tests.
#
# The extra flags exist because we build against Command Line Tools rather than
# full Xcode:
#   -F …/Library/Developer/Frameworks  — CLT does not put Testing.framework on the
#       default search path. (XCTest is not shipped with CLT at all, which is why
#       these tests use swift-testing.)
#   -disable-cross-import-overlays     — CLT ships the Testing↔Foundation cross-import
#       declaration but not the _Testing_Foundation module it points at, so the
#       overlay has to be turned off or every `import Testing` fails.
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"

exec swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$@"
