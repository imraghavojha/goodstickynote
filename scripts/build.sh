#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
APP="$PWD/dist/GoodSticky.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp assets/GoodSticky.icns "$APP/Contents/Resources/GoodSticky.icns"
cp .build/release/GoodSticky "$APP/Contents/MacOS/GoodSticky"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GoodSticky</string>
<key>CFBundleIdentifier</key><string>app.goodsticky.mac</string>
<key>CFBundleName</key><string>GoodSticky</string>
<key>CFBundleDisplayName</key><string>GoodSticky</string>
<key>CFBundleIconFile</key><string>GoodSticky</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Built $APP"
