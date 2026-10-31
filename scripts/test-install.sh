#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks
swiftc -parse-as-library Sources/GoodSticky/LibraryLocation.swift Sources/GoodSticky/ResidentLock.swift scripts/install-app.swift -o .build/checks/InstallApp
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
export GOODSTICKY_DATA_DIR="$FIXTURE/Library"
ditto dist/GoodSticky.app "$FIXTURE/GoodSticky.app"
print 'old bundle file' > "$FIXTURE/GoodSticky.app/Contents/Resources/old-only.txt"
codesign --force --sign - "$FIXTURE/GoodSticky.app"
.build/checks/InstallApp "$PWD/dist/GoodSticky.app" "$FIXTURE/GoodSticky.app"
[[ ! -e "$FIXTURE/GoodSticky.app/Contents/Resources/old-only.txt" ]]
[[ -e "$FIXTURE/.GoodSticky-previous.app/Contents/Resources/old-only.txt" ]]
print 'PASS: atomic replacement removes stale files and retains previous bundle'
BEFORE=$(shasum "$FIXTURE/GoodSticky.app/Contents/MacOS/GoodSticky")
ditto dist/GoodSticky.app "$FIXTURE/Bad.app"
print 'invalid signature' >> "$FIXTURE/Bad.app/Contents/MacOS/GoodSticky"
if .build/checks/InstallApp "$FIXTURE/Bad.app" "$FIXTURE/GoodSticky.app" 2>/dev/null; then
    print -u2 'FAIL: invalid app was accepted'; exit 1
fi
AFTER=$(shasum "$FIXTURE/GoodSticky.app/Contents/MacOS/GoodSticky")
[[ "$BEFORE" == "$AFTER" ]]
print 'PASS: signature failure leaves installed app untouched'
