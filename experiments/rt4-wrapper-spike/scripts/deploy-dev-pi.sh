#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_DIR="$ROOT_DIR/public"
PI_HOST="${PI_HOST:-pi}"
PI_TARGET="${PI_TARGET:-/mnt/game-usb/opt/rt4-wrapper-dev}"

node "$ROOT_DIR/scripts/rt4-wrapper-regression.mjs"

mapfile -t CONFIGURED_JARS < <(
  node --input-type=module - "$PUBLIC_DIR/wrapper-config.js" <<'NODE'
import fs from "node:fs";
import vm from "node:vm";

const configPath = process.argv[2];
const script = fs.readFileSync(configPath, "utf8");
const context = { window: {} };
vm.runInNewContext(script, context, { filename: configPath });
const config = context.window.RT4_WRAPPER_CONFIG || {};
const jars = [
  config.clientJar,
  config.launcherJar,
  config.desktopClientJar,
  config.desktopLauncherJar,
  config.mobileClientJar,
  config.mobileLauncherJar,
].filter(Boolean);
for (const jar of [...new Set(jars)]) {
  console.log(jar);
}
NODE
)

JAR_PATHS=()
for jar in "${CONFIGURED_JARS[@]}"; do
  JAR_PATHS+=("$PUBLIC_DIR/$jar")
done

ssh "$PI_HOST" "mkdir -p '$PI_TARGET'"
scp \
  "$PUBLIC_DIR/index.html" \
  "$PUBLIC_DIR/wrapper-config.js" \
  "$PUBLIC_DIR/config.json" \
  "${JAR_PATHS[@]}" \
  "$PI_HOST:$PI_TARGET/"

for jar in "${CONFIGURED_JARS[@]}"; do
  ssh "$PI_HOST" "curl -fsSI -H 'Range: bytes=0-7' 'http://127.0.0.1:8700/$jar' | grep -q '206'"
done

echo "Deployed RT4 wrapper dev build to http://192.168.0.30:8700/"
