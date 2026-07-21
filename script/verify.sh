#!/bin/bash
# verify.sh — build/test harness for Seal Note (iOS + macOS).
# Subcommands: ios-build | ios-test | mac-build | mac-test | all
# Logs are tee'd to the session scratchpad. iOS simulator is discovered at runtime.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="SealNote.xcodeproj"
IOS_SCHEME="SealNote"
MAC_SCHEME="SealNoteMac"

LOG_DIR="${VERIFY_LOG_DIR:-/private/tmp/claude-501/-Users-wally-Documents-EncryptNotes-for-TRAE/4f0eee76-98d1-42d1-bf59-41f3fa74e2d9/scratchpad}"
mkdir -p "$LOG_DIR"

log_path() { echo "$LOG_DIR/verify-$1-$(date +%Y%m%d-%H%M%S).log"; }

discover_sim() {
  local id
  id=$(xcrun simctl list devices available \
    | grep -m1 -E 'iPhone' \
    | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true)
  if [ -z "$id" ]; then
    id=$(xcrun simctl create "SealNoteCI" "iPhone 17" 2>/dev/null || true)
  fi
  if [ -z "$id" ]; then
    echo "ERROR: no iPhone simulator available and could not create one" >&2
    exit 1
  fi
  echo "$id"
}

ios_build() {
  local sim; sim=$(discover_sim)
  local lg; lg=$(log_path ios-build)
  echo "== ios-build (sim=$sim) -> $lg =="
  xcodebuild -project "$PROJECT" -scheme "$IOS_SCHEME" \
    -destination "platform=iOS Simulator,id=$sim" build 2>&1 | tee "$lg"
}

ios_test() {
  local sim; sim=$(discover_sim)
  # Pre-boot to avoid transient EINTR boot failures under xcodebuild.
  xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1 || true
  local lg; lg=$(log_path ios-test)
  echo "== ios-test (sim=$sim) -> $lg =="
  xcodebuild -project "$PROJECT" -scheme "$IOS_SCHEME" \
    -destination "platform=iOS Simulator,id=$sim" test 2>&1 | tee "$lg"
}

mac_build() {
  local lg; lg=$(log_path mac-build)
  echo "== mac-build -> $lg =="
  xcodebuild -project "$PROJECT" -scheme "$MAC_SCHEME" \
    -destination 'platform=macOS' build 2>&1 | tee "$lg"
}

mac_test() {
  local lg; lg=$(log_path mac-test)
  echo "== mac-test -> $lg =="
  xcodebuild -project "$PROJECT" -scheme "$MAC_SCHEME" \
    -destination 'platform=macOS' test 2>&1 | tee "$lg"
}

case "${1:-}" in
  ios-build) ios_build ;;
  ios-test)  ios_test ;;
  mac-build) mac_build ;;
  mac-test)  mac_test ;;
  all)       ios_build; mac_build; ios_test; mac_test ;;
  *) echo "usage: $0 {ios-build|ios-test|mac-build|mac-test|all}" >&2; exit 2 ;;
esac
