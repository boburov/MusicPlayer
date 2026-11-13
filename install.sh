#!/bin/bash
# Builds Music Widget with your own Apple developer team and installs it to /Applications.
# Usage: ./install.sh            (team ID is read from your "Apple Development" certificate)
#        DEVELOPMENT_TEAM=ABCDE12345 ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodebuild >/dev/null || { echo "Xcode topilmadi. App Store'dan Xcode'ni o'rnating."; exit 1; }
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || { echo "xcodegen kerak: avval Homebrew'ni o'rnating (https://brew.sh)."; exit 1; }
  echo "xcodegen o'rnatilmoqda..."
  brew install xcodegen
fi

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' | head -1)
fi
if [ -z "$DEVELOPMENT_TEAM" ]; then
  echo "Apple Development sertifikati topilmadi."
  echo "Xcode → Settings → Accounts'da Apple ID bilan kiring, 'Manage Certificates' → '+' → 'Apple Development'."
  echo "Yoki jamoa ID'sini qo'lda bering: DEVELOPMENT_TEAM=ABCDE12345 ./install.sh"
  exit 1
fi
# Bundle IDs are unique across Apple, so each team gets its own by default.
BUNDLE_ID="${BUNDLE_ID:-io.github.musicwidget.$(echo "$DEVELOPMENT_TEAM" | tr '[:upper:]' '[:lower:]')}"
export DEVELOPMENT_TEAM BUNDLE_ID
echo "Jamoa: $DEVELOPMENT_TEAM   Bundle ID: $BUNDLE_ID"

xcodegen generate --quiet
xcodebuild -project MusicWidget.xcodeproj -scheme MusicWidget -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build -allowProvisioningUpdates -quiet build

pkill -x MusicWidget || true
rm -rf /Applications/MusicWidget.app
cp -R build/Build/Products/Release/MusicWidget.app /Applications/
open /Applications/MusicWidget.app

echo
echo "Tayyor. Ish stolida o'ng tugma → Edit Widgets… → MusicWidget → widgetni ish stoliga torting."
echo "Birinchi marta macOS 'Music Widget Spotify'ni boshqarmoqchi' deb so'raydi — OK bosing."
