#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
runtime_root=${1:?usage: package-runtime.sh RUNTIME_ROOT [OUTPUT.tar.xz]}
output=${2:-dist/OpenGame-Runtime-11.0-macos-arm64.tar.xz}
source_directory=${3:-build/sources}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/OpenGame.app/Contents/Resources"
scripts/embed-runtime.sh "$temporary/OpenGame.app" "$runtime_root"
scripts/fetch-sources.sh "$source_directory"
scripts/install-font-pack.sh "$temporary/OpenGame.app/Contents/Resources/Runtime" "$source_directory"
scripts/audit-runtime.py "$temporary/OpenGame.app/Contents/Resources/Runtime"
mkdir -p "$(dirname "$output")"
tar -cJf "$output" -C "$temporary/OpenGame.app/Contents/Resources" Runtime
shasum -a 256 "$output" > "$output.sha256"
echo "Created $output"
