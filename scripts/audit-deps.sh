#!/bin/sh
set -eu

fail() {
  echo "audit-deps: $*" >&2
  exit 1
}

if grep -E 'url:[[:space:]]*"https?://' Package.swift >/dev/null 2>&1; then
  fail "Package.swift must not declare third-party packages"
fi

if grep -E '\.package\(' Package.swift | grep -v 'Package.swift' | grep -E 'url:' >/dev/null 2>&1; then
  fail "Package.swift must not declare third-party packages"
fi

if [ -f Package.resolved ]; then
  fail "Package.resolved is not allowed (third-party pins would live there)"
fi

if [ -f FreeOllee2.xcodeproj/project.pbxproj ]; then
  if grep -q XCRemoteSwiftPackageReference FreeOllee2.xcodeproj/project.pbxproj; then
    fail "Xcode project must not reference remote Swift packages"
  fi
fi

echo "third-party Swift dependencies: 0"
