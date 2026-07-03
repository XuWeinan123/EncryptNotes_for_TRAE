#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="EncryptNotesMac"
PROJECT="EncryptNotes.xcodeproj"
SCHEME="EncryptNotesMac"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

cd "$ROOT_DIR"

stop_running_app() {
  local pid
  local ppid
  local parent_command

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)

  sleep 0.3

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
    parent_command="$(ps -o command= -p "$ppid" 2>/dev/null || true)"
    if [[ "$parent_command" == *"/LLDB.framework/Resources/debugserver"* ]]; then
      kill -9 "$ppid" >/dev/null 2>&1 || true
    fi
    kill -9 "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

stop_running_app

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" --args "$@"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.xuweinan.sealnote\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --verify-recent|verify-recent)
    open_app --open-recent-note
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --review-windows|review-windows)
    open_app --open-review-windows
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-recent|--review-windows]" >&2
    exit 2
    ;;
esac
