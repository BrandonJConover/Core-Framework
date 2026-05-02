#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function arg(name, fallback) {
  const idx = process.argv.indexOf("--" + name);
  return idx >= 0 && idx + 1 < process.argv.length ? process.argv[idx + 1] : fallback;
}

const input = path.resolve(arg("in", path.resolve(__dirname, "..", "client", "music")));
const output = path.resolve(arg("out", path.join(input, "manifest.json")));
const tracks = {};

if (fs.existsSync(input)) {
  for (const file of fs.readdirSync(input).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))) {
    if (!file.toLowerCase().endsWith(".ogg")) continue;
    const id = Number(path.basename(file, ".ogg"));
    if (!Number.isFinite(id)) continue;
    tracks[String(id)] = { file, name: path.basename(file, ".ogg") };
  }
}

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify({ tracks }, null, 2) + "\n");
console.log("[music] wrote " + Object.keys(tracks).length + " track(s) to " + output);
