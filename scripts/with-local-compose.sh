#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${COMPOSE_DISK_GUARDED:-}" != 1 ]]; then
  export COMPOSE_DISK_GUARDED=1
  exec python3 "$ROOT/scripts/compose-guard.py" "$0" "$@"
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "The benchmark toolchain currently packages macOS ARM64 only." >&2
  exit 1
fi
TOOLS="$ROOT/.toolchains/compose"
reserve() {
  local available
  available=$(df -k /System/Volumes/Data | awk 'NR==2 {print $4}')
  if [[ -z "$available" ]] || (( available < 55000000 )); then
    echo "Insufficient disk headroom for Compose setup/build; preserve the 50 GB reserve." >&2
    exit 1
  fi
}
reserve
mkdir -p "$TOOLS"
fetch() {
  local url="$1" checksum="$2" file="$3"
  curl --fail --location --retry 3 "$url" -o "$file"
  echo "$checksum  $file" | shasum -a 256 -c -
}
if [[ ! -x "$TOOLS/jdk-21.0.8+9/Contents/Home/bin/java" ]]; then
  fetch 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.8%2B9/OpenJDK21U-jdk_aarch64_mac_hotspot_21.0.8_9.tar.gz' 59422c2292ae4e76b87e00d8808dbe49cffa39af731e08bb0292ddb0af4e0261 "$TOOLS/jdk.tar.gz"
  tar -xzf "$TOOLS/jdk.tar.gz" -C "$TOOLS"
  reserve
fi
if [[ ! -x "$TOOLS/gradle-8.14.3/bin/gradle" ]]; then
  fetch https://services.gradle.org/distributions/gradle-8.14.3-bin.zip bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531 "$TOOLS/gradle.zip"
  unzip -q "$TOOLS/gradle.zip" -d "$TOOLS"
  reserve
fi
export JAVA_HOME="$TOOLS/jdk-21.0.8+9/Contents/Home"
export GRADLE_USER_HOME="$TOOLS/gradle-home"
export PATH="$JAVA_HOME/bin:$PATH"
export BENCHMARK_GRAMMAR_ROOT="${BENCHMARK_GRAMMAR_ROOT:-$ROOT/.build/chat-history-benchmarks/grammar-packs/v1}"
exec "$TOOLS/gradle-8.14.3/bin/gradle" --no-daemon --max-workers=2 -p "$ROOT/shared/compose-desktop" "$@"
