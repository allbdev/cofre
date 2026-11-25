#!/usr/bin/env bash
# Rewrites every Swift file with the repo's swift-format settings.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format format --in-place --parallel --recursive Cofre CofreKit/Sources CofreKit/Tests CofreKit/Package.swift
