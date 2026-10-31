#!/bin/zsh
# Isolated benchmark; helper compilation and fixture creation precede timing.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks
swiftc -O scripts/bench-windows.swift -o .build/checks/bench-windows
exec python3 scripts/bench.py "${1:-dist/GoodSticky.app}" "${2:-10}" "${@:3}"
