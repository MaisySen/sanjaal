#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
compiler="${KOTLIN_HOME:-/tmp/sj-kotlin-1.9.24/kotlinc}"
if [ ! -x "$compiler/bin/kotlinc" ]; then
  curl -fsSL --retry 2 -o /tmp/sj-kotlin-1.9.24.zip https://github.com/JetBrains/kotlin/releases/download/v1.9.24/kotlin-compiler-1.9.24.zip
  echo 'eb7b68e01029fa67bc8d060ee54c12018f2c60ddc438cf21db14517229aa693b  /tmp/sj-kotlin-1.9.24.zip' | sha256sum -c -
  unzip -q /tmp/sj-kotlin-1.9.24.zip -d /tmp/sj-kotlin-1.9.24
fi
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
"$compiler/bin/kotlinc" "$root"/.github/ci/native-memory-video/*.kt "$root/app/android/app/src/main/kotlin/au/fintex/sanjaal/MemoryVideoView.kt" -nowarn -include-runtime -d "$out/tests.jar"
java -jar "$out/tests.jar" "$@"
