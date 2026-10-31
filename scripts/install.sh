#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
DEST="$HOME/Applications/GoodSticky.app"
if pgrep -f "^$DEST/Contents/MacOS/GoodSticky([[:space:]]|$)" >/dev/null; then
    print -u2 "Quit GoodSticky from its menu bar before installing an update."
    exit 1
fi
./scripts/build.sh
mkdir -p .build/checks
swiftc -parse-as-library Sources/GoodSticky/LibraryLocation.swift Sources/GoodSticky/ResidentLock.swift scripts/install-app.swift -o .build/checks/InstallApp
.build/checks/InstallApp "$PWD/dist/GoodSticky.app" "$DEST"
open "$DEST" --args --enable-login
print "Installed $DEST"
