#!/bin/bash
set -euo pipefail
payload=${1:?usage: install-font-pack.sh RUNTIME_PAYLOAD SOURCE_DIRECTORY}
source_directory=${2:?usage: install-font-pack.sh RUNTIME_PAYLOAD SOURCE_DIRECTORY}
archive="$source_directory/liberation-fonts-ttf-2.1.5.tar.gz"
test -f "$archive" || { echo "Missing $archive" >&2; exit 1; }
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
tar -xzf "$archive" -C "$temporary"
mkdir -p "$payload/Fonts/Liberation"
find "$temporary" -type f -name '*.ttf' -exec cp -p {} "$payload/Fonts/Liberation/" \;
find "$temporary" -type f -name LICENSE -exec cp -p {} "$payload/Fonts/Liberation/OFL.txt" \; -quit
test "$(find "$payload/Fonts/Liberation" -name '*.ttf' | wc -l | tr -d ' ')" = 12
