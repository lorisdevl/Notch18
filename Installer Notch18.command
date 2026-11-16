#!/bin/bash
# Compile Notch18, l'installe dans /Applications et la lance.
cd "$(dirname "$0")" || exit 1
LOG="$(pwd)/build.log"
exec > >(tee "$LOG") 2>&1

echo "=============================================="
echo "  Notch18 — compilation et installation"
echo "=============================================="

fail() {
  echo ""
  echo "❌ ÉCHEC : $1"
  echo "Le détail est dans build.log (même dossier)."
  echo "BUILD_STATUS=FAILED"
  exit 1
}

# Les macros SwiftUI (@State…) ne sont fournies qu'avec Xcode, pas avec les Command Line Tools.
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
if ! xcrun swiftc --version >/dev/null 2>&1; then
  echo "$(xcrun swiftc --version 2>&1 | head -3)"
  fail "Xcode n'est pas prêt : ouvre Xcode une fois et accepte la licence, puis relance ce script"
fi

command -v xcrun >/dev/null 2>&1 || fail "outils de développement Apple introuvables (installe Xcode ou lance : xcode-select --install)"

ARCH="$(uname -m)"
# On compile hors d'iCloud Drive (ses attributs étendus empêchent la signature).
BUILD="${TMPDIR:-/tmp}/Notch18-build"
APP="$BUILD/Notch18.app"
rm -rf "$BUILD" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/AppIcon.iconset"

echo "→ Outils : ${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)} — $(xcrun swiftc --version 2>&1 | head -1)"
PLUGIN_ARGS=()
DEV="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)}"
SWIFTC_DIR="$(dirname "$(xcrun -f swiftc)")"
for d in "$SWIFTC_DIR/../lib/swift/host/plugins" \
         "$DEV/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
         "$DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins" \
         "$(xcrun --show-sdk-path)/usr/lib/swift/host/plugins"; do
  [ -d "$d" ] && PLUGIN_ARGS+=(-plugin-path "$d")
done

echo "→ Compilation du code Swift ($ARCH)…"
xcrun swiftc -O -swift-version 5 \
  -target "$ARCH-apple-macos14.0" \
  -module-name Notch18 \
  "${PLUGIN_ARGS[@]}" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Notch18" || fail "la compilation a échoué"

echo "→ Icône…"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon_1024.png --out "$BUILD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d Resources/icon_1024.png --out "$BUILD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" || echo "(icône ignorée)"

cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Signature locale…"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP" || fail "signature impossible"

echo "→ Installation dans /Applications…"
pkill -x Notch18 >/dev/null 2>&1 && sleep 1
rm -rf /Applications/Notch18.app
ditto "$APP" /Applications/Notch18.app || fail "copie dans /Applications impossible"

echo "→ Lancement…"
open /Applications/Notch18.app

echo ""
echo "✅ Notch18 est installée et lancée. Passe la souris sous la caméra !"
echo "BUILD_STATUS=OK"
