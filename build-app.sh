#!/bin/zsh
# Baut YTUploader und erzeugt ein fertiges YTUploader.app im Projektordner.
set -e
cd "$(dirname "$0")"

swift build -c release

# App-Icon erzeugen, falls es noch fehlt
if [[ ! -f AppIcon.icns ]]; then
    swift make-icon.swift
    mkdir -p AppIcon.iconset
    for s in 16 32 128 256 512; do
        sips -z $s $s icon-1024.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s*2))
        sips -z $d $d icon-1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

APP="YTUploader.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/YTUploader "$APP/Contents/MacOS/YTUploader"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>YTUploader</string>
    <key>CFBundleIdentifier</key>
    <string>com.fmatsch.ytuploader</string>
    <key>CFBundleName</key>
    <string>YTUploader</string>
    <key>CFBundleDisplayName</key>
    <string>YTUploader</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur, damit macOS die App ohne Warnungen startet
codesign --force --deep --sign - "$APP"

echo ""
echo "Fertig: $(pwd)/$APP"
echo "Starten mit:  open $APP"
