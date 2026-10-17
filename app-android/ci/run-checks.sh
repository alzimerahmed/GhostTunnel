#!/bin/bash

set -euo pipefail

# Phase 12: Android CI gate (checks.yml "Android checks" job).
# Builds the debug APK (native cpp + partout cross-android artifacts included)
# and runs the JVM unit tests. No signing required.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
app_dir=$(cd "$script_dir/.." && pwd -P)

cd "$app_dir"

# gradlew is not committed with the executable bit on this fork; ensure it is
# runnable in the CI environment.
chmod +x gradlew

./gradlew --no-daemon --stacktrace \
    :app:assembleDebug \
    :app:testDebugUnitTest
