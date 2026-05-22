#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SPIKE_DIR/../.." && pwd)"
RT4_DIR="$REPO_ROOT/reference/rt4-client"
PUBLIC_DIR="$SPIKE_DIR/public"
JAR_PATH="$RT4_DIR/client/build/libs/client-1.0.0.jar"
SPIKE_CLASSES="$SPIKE_DIR/build/classes"
SPIKE_JAR="$PUBLIC_DIR/rt4-spike-launcher.jar"

cd "$RT4_DIR"
./gradlew :client:jar

mkdir -p "$PUBLIC_DIR"
cp "$JAR_PATH" "$PUBLIC_DIR/client-1.0.0.jar"
cp "$RT4_DIR/client/config.json" "$PUBLIC_DIR/config.json"

rm -rf "$SPIKE_CLASSES"
mkdir -p "$SPIKE_CLASSES"
javac \
  -source 8 \
  -target 8 \
  -cp "$JAR_PATH" \
  -d "$SPIKE_CLASSES" \
  "$SPIKE_DIR/java-src/spike/Rt4SpikeLauncher.java"
jar cf "$SPIKE_JAR" -C "$SPIKE_CLASSES" .

cat <<EOF
Prepared RT4 wrapper spike:
  $PUBLIC_DIR/client-1.0.0.jar
  $PUBLIC_DIR/config.json
  $SPIKE_JAR

Run:
  cd $PUBLIC_DIR
  python3 ../scripts/serve.py --port 8787

Open:
  http://127.0.0.1:8787/
EOF
