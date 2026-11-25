#!/usr/bin/env bash
# The full check: run before every commit and in CI. Fails on the first problem.
#   1. swift-format lint (strict: warnings fail)
#   2. CofreKit tests (swift test)
#   3. unsigned build of the app, warnings as errors
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

step "Lint"
xcrun swift-format lint --strict --parallel --recursive Cofre CofreKit/Sources CofreKit/Tests CofreKit/Package.swift

step "Tests"
# Show failures (✘ and the lines after them) and each run's summary.
swift test --package-path CofreKit 2>&1 | grep -E -A3 "✘|error:|Test run with|➜ Suite"

step "Build (unsigned)"
xcodebuild \
  -project Cofre.xcodeproj \
  -scheme Cofre \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  build

printf '\n\033[32m✔ All checks passed\033[0m\n'
