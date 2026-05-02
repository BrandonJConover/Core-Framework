#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${CACHE:-${ROOT}/client/client_cache}"
OUT="${OUT:-${ROOT}/client/music}"
MIDI_OUT="${OUT}/midi"
SOUNDFONT="${SOUNDFONT:-${ROOT}/scripts/TimGM6mb.sf2}"
MUSIC_IDX="${MUSIC_IDX:-6}"

if ! command -v fluidsynth >/dev/null 2>&1; then
  echo "[music] fluidsynth not found. Install FluidSynth or set PATH, then rerun." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[music] ffmpeg not found. Install ffmpeg or set PATH, then rerun." >&2
  exit 1
fi
if [ ! -f "$SOUNDFONT" ]; then
  echo "[music] soundfont not found at $SOUNDFONT" >&2
  echo "[music] set SOUNDFONT=/path/to/GeneralUser.sf2 or place TimGM6mb.sf2 in 2009scape-web/scripts/." >&2
  exit 1
fi

mkdir -p "$OUT" "$MIDI_OUT"
node "${ROOT}/scripts/extract-music.js" --cache "$CACHE" --idx "$MUSIC_IDX" --out "$MIDI_OUT"

count=0
for midi in "${MIDI_OUT}"/*.mid; do
  [ -f "$midi" ] || continue
  base="$(basename "$midi" .mid)"
  wav="${OUT}/${base}.wav"
  ogg="${OUT}/${base}.ogg"
  fluidsynth -ni "$SOUNDFONT" "$midi" -F "$wav" -r 44100 >/dev/null 2>&1
  ffmpeg -y -loglevel error -i "$wav" -c:a libvorbis -q:a 4 "$ogg"
  rm -f "$wav"
  count=$((count + 1))
done

node "${ROOT}/scripts/build-music-manifest.js" --in "$OUT" --out "${OUT}/manifest.json"
echo "[music] converted ${count} MIDI file(s) to ${OUT}"
