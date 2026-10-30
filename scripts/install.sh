#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
DEST="$HOME/Applications/GoodSticky.app"
if pgrep -f "^$DEST/Contents/MacOS/GoodSticky([[:space:]]|$)" >/dev/null; then
    print -u2 "Quit GoodSticky from its menu bar before installing an update."
    exit 1
fi
./scripts/build.sh
mkdir -p "$HOME/Applications"
if [[ -e "$DEST" ]]; then
    IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
    [[ "$IDENTIFIER" == "app.goodsticky.mac" ]] || { print -u2 "Refusing to replace an unrelated app at $DEST"; exit 1; }
    mkdir -p .build/install-backup
    ditto "$DEST" .build/install-backup/GoodSticky.app
fi
ditto dist/GoodSticky.app "$DEST"
codesign --verify --deep --strict "$DEST"
open "$DEST" --args --enable-login
print "Installed $DEST"
