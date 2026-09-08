#!/bin/bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd)
wine_source=${1:?Usage: apply-wine-patches.sh WINE_SOURCE_DIRECTORY}
for change in "$repository"/runtime/patches/*.patch; do
    if patch -d "$wine_source" -p1 -R -f --dry-run < "$change" >/dev/null 2>&1; then
        echo "Already applied: $(basename "$change")"
    else
        patch -d "$wine_source" -p1 --forward < "$change"
    fi
done
