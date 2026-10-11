#!/usr/bin/env bash
# Builds a PERSONAL Android APK with the optional Claude Haiku coach switched on.
#
# This is for side-loading to one trusted phone. The API key is compiled into
# the APK, and anyone holding the file could extract it, so:
#   1. Create a dedicated Anthropic workspace for it and set a hard monthly
#      spend limit on that workspace (Console -> Settings -> Limits).
#   2. Create the API key inside that workspace only.
#   3. Never upload this APK anywhere or attach it to the store listing.
# Store builds are unaffected: no key, and no INTERNET permission.
#
# Usage:
#   tool/build_personal_apk.sh
# The key is read from (in order): $EXPND_CLAUDE_KEY, the macOS Keychain item
# "expnd-gf-claude", or a hidden prompt. To store it once:
#   security add-generic-password -U -s expnd-gf-claude -a expnd -w
# (macOS asks for the key without echoing it).
set -euo pipefail
cd "$(dirname "$0")/.."

key="${EXPND_CLAUDE_KEY:-}"
if [[ -z "$key" ]]; then
  key="$(security find-generic-password -s expnd-gf-claude -a expnd -w 2>/dev/null || true)"
fi
if [[ -z "$key" ]]; then
  read -r -s -p "Anthropic API key (hidden): " key
  echo
fi
if [[ "$key" != sk-ant-* ]]; then
  echo "That doesn't look like an Anthropic API key (sk-ant-...)." >&2
  exit 1
fi

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export EXPND_PERSONAL_BUILD=1

# arm64 only: every Samsung phone of the last several years. Extra
# --dart-define flags can be passed through, e.g. for an emulator demo copy.
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --no-pub --dart-define=EXPND_CLAUDE_KEY="$key" "$@"

echo
echo "Personal APK:"
ls -lh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
