#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/CatalogTests.swift -framework AppKit -o build/catalog-tests
build/catalog-tests
xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/ShutdownTests.swift -framework AppKit -o build/shutdown-tests
build/shutdown-tests
xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/ArchiveTests.swift -framework AppKit -o build/archive-tests
build/archive-tests

xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/PerformanceSettingsTests.swift -framework AppKit -o build/performance-settings-tests
build/performance-settings-tests

xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/SteamSettingsTests.swift -framework AppKit -o build/steam-settings-tests
build/steam-settings-tests

xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/build/module-cache" -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift tests/SteamDiscoveryTests.swift -framework AppKit -o build/steam-discovery-tests
build/steam-discovery-tests
