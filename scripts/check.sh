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
swift test --package-path CofreKit 2>&1 | tail -n 25
test "${PIPESTATUS[0]}" -eq 0

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
