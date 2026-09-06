#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/CatalogTests.swift -framework AppKit -o build/catalog-tests
build/catalog-tests
xcrun swiftc -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/ShutdownTests.swift -framework AppKit -o build/shutdown-tests
build/shutdown-tests
xcrun swiftc -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/ArchiveTests.swift -framework AppKit -o build/archive-tests
build/archive-tests
