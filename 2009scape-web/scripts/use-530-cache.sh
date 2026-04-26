#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/2009scape/Server/data/cache"
DEST_DIR="$ROOT_DIR/client/client_cache"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Missing 2009scape cache directory: $SRC_DIR" >&2
  echo "Run setup.sh or clone the 2009scape server into $ROOT_DIR/2009scape first." >&2
  exit 1
fi

if [[ ! -d "$DEST_DIR" ]]; then
  echo "Missing web client cache directory: $DEST_DIR" >&2
  echo "Run setup.sh or clone the upstream web client into $ROOT_DIR/client first." >&2
  exit 1
fi

rm -f "$DEST_DIR"/main_file_cache.dat "$DEST_DIR"/main_file_cache.idx*
cp "$SRC_DIR/main_file_cache.dat2" "$DEST_DIR/main_file_cache.dat"

for idx in "$SRC_DIR"/main_file_cache.idx*; do
  cp "$idx" "$DEST_DIR/$(basename "$idx")"
done

echo "Copied 530 cache into $DEST_DIR"
