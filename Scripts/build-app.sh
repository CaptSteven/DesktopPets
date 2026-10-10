#!/bin/sh
#
# Builds dist/DesktopPets.app — a double-clickable bundle with the runtime art inside it.
#
# Signing is ad-hoc (`--sign -`). Apple Silicon refuses to run an entirely unsigned binary, so it
# is required even for local use, but it needs no developer certificate and no notarisation. That
# means the bundle runs on this machine; copying it to someone else's will hit Gatekeeper, and
# distributing it would need a real certificate plus notarytool.
set -eu

cd "$(dirname "$0")/.."

APP_NAME=DesktopPets
CONFIGURATION=${CONFIGURATION:-release}
DIST=dist
APP="$DIST/$APP_NAME.app"

echo "==> Building $APP_NAME ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$APP_NAME"
# `--show-bin-path` prints the path without building, so it runs after the build above.
# `tail -n 1` because SwiftPM can print progress lines first.
BIN_DIR=$(swift build -c "$CONFIGURATION" --product "$APP_NAME" --show-bin-path | tail -n 1)

if [ ! -x "$BIN_DIR/$APP_NAME" ]; then
    echo "build-app.sh: expected a binary at $BIN_DIR/$APP_NAME" >&2
    exit 1
fi

echo "==> Assembling $APP"
if [ -d "$APP" ]; then
    rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

# Runtime content goes in wholesale, exactly as it sits in the repository. The app finds it via
# Bundle.main.resourceURL, which for a bundle is Contents/Resources.
cp -R Resources/Skins "$APP/Contents/Resources/Skins"
if [ -d Resources/Phrases ]; then
    cp -R Resources/Phrases "$APP/Contents/Resources/Phrases"
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/    /'

echo "==> Smoke test"
# Forces the bundle to load its own art rather than the source tree: AssetLocator checks
# Bundle.main.resourceURL before falling back to the compile-time source path.
"$APP/Contents/MacOS/$APP_NAME" --verify-skin

echo "==> Built $APP"
echo "    Drag it into /Applications, or run: open $APP"
