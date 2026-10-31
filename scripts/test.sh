#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks
swiftc -parse-as-library Sources/GoodSticky/Model.swift Sources/GoodSticky/ResidentLock.swift Tests/ModelTests.swift -o .build/checks/ModelTests
.build/checks/ModelTests
