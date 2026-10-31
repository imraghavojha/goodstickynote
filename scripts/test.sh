#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks
swiftc -parse-as-library Sources/GoodSticky/NoteHistory.swift Sources/GoodSticky/LibraryLocation.swift Sources/GoodSticky/Model.swift Sources/GoodSticky/NoteStore.swift Sources/GoodSticky/ResidentLock.swift Tests/ModelTests.swift -o .build/checks/ModelTests
.build/checks/ModelTests

CHECK_APP="$PWD/.build/checks/GoodStickyChecks.app"
mkdir -p "$CHECK_APP/Contents/MacOS"
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GoodStickyChecks</string>
<key>CFBundleIdentifier</key><string>app.goodsticky.checks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc -O -D GOODSTICKY_TESTING Sources/GoodSticky/*.swift Tests/AppKitTests.swift Tests/UndoTests.swift -o "$CHECK_APP/Contents/MacOS/GoodStickyChecks"
codesign --force --sign - "$CHECK_APP"
"$CHECK_APP/Contents/MacOS/GoodStickyChecks" --smoke-test
