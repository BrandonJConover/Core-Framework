#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function arg(name, fallback) {
  const idx = process.argv.indexOf("--" + name);
  return idx >= 0 && idx + 1 < process.argv.length ? process.argv[idx + 1] : fallback;
}

function requireFromClient(pkg) {
  const root = path.resolve(__dirname, "..");
  return require(path.join(root, "client", "node_modules", pkg));
}

function readGroup(idxArchiveId, dat, idx, groupId) {
  const entry = groupId * 6;
  if (entry + 6 > idx.length) return null;
  const size = (idx[entry] << 16) | (idx[entry + 1] << 8) | idx[entry + 2];
  let sector = (idx[entry + 3] << 16) | (idx[entry + 4] << 8) | idx[entry + 5];
  if (size <= 0 || sector <= 0) return null;

  const large = groupId >= 65536;
  const header = large ? 10 : 8;
  const payload = 520 - header;
  const out = Buffer.alloc(size);
  let written = 0;
  let chunk = 0;

  while (written < size) {
    const base = sector * 520;
    if (base + 520 > dat.length) return null;

    let headerGroup;
    let off;
    if (large) {
      headerGroup = dat.readUInt32BE(base);
      off = 4;
    } else {
      headerGroup = dat.readUInt16BE(base);
      off = 2;
    }
    const headerChunk = dat.readUInt16BE(base + off);
    const next = (dat[base + off + 2] << 16) | (dat[base + off + 3] << 8) | dat[base + off + 4];
    const archive = dat[base + off + 5];
    if (headerGroup !== groupId || headerChunk !== chunk || archive !== idxArchiveId) return null;

    const n = Math.min(payload, size - written);
    dat.copy(out, written, base + header, base + header + n);
    written += n;
    sector = next;
    chunk++;
  }

  return new Uint8Array(out);
}

function decompress(blob) {
  if (!blob || blob.length < 5) return null;
  const type = blob[0];
  const compressedLen = (blob[1] << 24) | (blob[2] << 16) | (blob[3] << 8) | blob[4];
  if (compressedLen < 0 || 5 + compressedLen > blob.length) return null;
  if (type === 0) return blob.slice(5, 5 + compressedLen);
  if (blob.length < 9) return null;

  const uncompressedLen = (blob[5] << 24) | (blob[6] << 16) | (blob[7] << 8) | blob[8];
  if (type === 1) {
    const Bunzip = requireFromClient("seek-bzip");
    const bz = Buffer.alloc(4 + compressedLen);
    bz[0] = 0x42; bz[1] = 0x5A; bz[2] = 0x68; bz[3] = 0x31;
    Buffer.from(blob.slice(9, 9 + compressedLen)).copy(bz, 4);
    return new Uint8Array(Bunzip.decode(bz, uncompressedLen));
  }
  if (type === 2) {
    const pako = requireFromClient("pako");
    const headerLen = 10;
    const trailerLen = 8;
    const innerLen = compressedLen - headerLen - trailerLen;
    if (innerLen <= 0) return null;
    return pako.inflate(blob.slice(9 + headerLen, 9 + headerLen + innerLen), { raw: true });
  }
  return null;
}

function isMidi(bytes) {
  return bytes && bytes.length >= 4 &&
    bytes[0] === 0x4D && bytes[1] === 0x54 && bytes[2] === 0x68 && bytes[3] === 0x64;
}

function signed(bytes, pos) {
  const v = bytes[pos] & 0xFF;
  return v > 127 ? v - 256 : v;
}

function gVarInt(reader) {
  let value = 0;
  let b;
  do {
    b = reader.data[reader.offset++] & 0xFF;
    value = (value << 7) | (b & 0x7F);
  } while ((b & 0x80) !== 0);
  return value;
}

class MidiWriter {
  constructor() {
    this.data = [];
  }
  get offset() { return this.data.length; }
  p1(v) { this.data.push(v & 0xFF); }
  p2(v) { this.p1(v >>> 8); this.p1(v); }
  p4(v) { this.p1(v >>> 24); this.p1(v >>> 16); this.p1(v >>> 8); this.p1(v); }
  pVarInt(value) {
    let tmp = value & 0x7F;
    while ((value >>>= 7) > 0) {
      tmp <<= 8;
      tmp |= ((value & 0x7F) | 0x80);
    }
    while (true) {
      this.p1(tmp);
      if ((tmp & 0x80) !== 0) tmp >>>= 8;
      else break;
    }
  }
  psize4(size) {
    const pos = this.offset - size - 4;
    this.data[pos] = (size >>> 24) & 0xFF;
    this.data[pos + 1] = (size >>> 16) & 0xFF;
    this.data[pos + 2] = (size >>> 8) & 0xFF;
    this.data[pos + 3] = size & 0xFF;
  }
  bytes() { return Uint8Array.from(this.data); }
}

function songToMidi(bytes) {
  if (isMidi(bytes)) return bytes;
  if (!bytes || bytes.length < 3) return null;
  const inr = {
    data: bytes,
    offset: bytes.length - 3,
    g1() { return this.data[this.offset++] & 0xFF; },
    g2() { return ((this.g1() << 8) | this.g1()) & 0xFFFF; },
  };

  const tracks = inr.g1();
  const division = inr.g2();
  inr.offset = 0;

  let tempoChanges = 0, controllerEvents = 0, noteOnEvents = 0, noteOffEvents = 0;
  let pitchWheelEvents = 0, channelPressureEvents = 0, keyPressureEvents = 0, bankSelectEvents = 0;

  for (let track = 0; track < tracks; track++) {
    let status = -1;
    while (true) {
      const statusAndChannel = inr.g1();
      status = statusAndChannel & 0xF;
      if (statusAndChannel === 7) break;
      if (statusAndChannel === 23) tempoChanges++;
      else if (status === 0) noteOnEvents++;
      else if (status === 1) noteOffEvents++;
      else if (status === 2) controllerEvents++;
      else if (status === 3) pitchWheelEvents++;
      else if (status === 4) channelPressureEvents++;
      else if (status === 5) keyPressureEvents++;
      else if (status === 6) bankSelectEvents++;
      else return null;
    }
  }

  const deltaTimePos = inr.offset;
  const varIntCount = tracks + tempoChanges + controllerEvents + noteOnEvents + noteOffEvents +
    pitchWheelEvents + channelPressureEvents + keyPressureEvents + bankSelectEvents;
  for (let i = 0; i < varIntCount; i++) gVarInt(inr);
  let statusAndChannel = inr.offset;

  let modulationWheelMsbEvents = 0, modulationWheelLsbEvents = 0;
  let channelVolumeMsbEvents = 0, channelVolumeLsbEvents = 0;
  let panMsbEvents = 0, panLsbEvents = 0;
  let nonRegisteredMsbEvents = 0, nonRegisteredLsbEvents = 0;
  let registeredMsbEvents = 0, registeredLsbEvents = 0;
  let otherKnownControllerEvents = 0, unknownControllerEvents = 0;
  let controller = 0;

  for (let i = 0; i < controllerEvents; i++) {
    controller = (controller + inr.g1()) & 0x7F;
    if (controller === 0 || controller === 32) bankSelectEvents++;
    else if (controller === 1) modulationWheelMsbEvents++;
    else if (controller === 33) modulationWheelLsbEvents++;
    else if (controller === 7) channelVolumeMsbEvents++;
    else if (controller === 39) channelVolumeLsbEvents++;
    else if (controller === 10) panMsbEvents++;
    else if (controller === 42) panLsbEvents++;
    else if (controller === 99) nonRegisteredMsbEvents++;
    else if (controller === 98) nonRegisteredLsbEvents++;
    else if (controller === 101) registeredMsbEvents++;
    else if (controller === 100) registeredLsbEvents++;
    else if (controller === 64 || controller === 65 || controller === 120 || controller === 121 || controller === 123) otherKnownControllerEvents++;
    else unknownControllerEvents++;
  }

  let otherKnownControllerPos = inr.offset; inr.offset += otherKnownControllerEvents;
  let keyPressurePos = inr.offset; inr.offset += keyPressureEvents;
  let channelPressurePos = inr.offset; inr.offset += channelPressureEvents;
  let pitchWheelMsbPos = inr.offset; inr.offset += pitchWheelEvents;
  let modulationWheelMsbPos = inr.offset; inr.offset += modulationWheelMsbEvents;
  let channelVolumeMsbPos = inr.offset; inr.offset += channelVolumeMsbEvents;
  let panMsbPos = inr.offset; inr.offset += panMsbEvents;
  let keyPos = inr.offset; inr.offset += noteOnEvents + noteOffEvents + keyPressureEvents;
  let onVelocityPos = inr.offset; inr.offset += noteOnEvents;
  let unknownControllerPos = inr.offset; inr.offset += unknownControllerEvents;
  let offVelocityPos = inr.offset; inr.offset += noteOffEvents;
  let modulationWheelLsbPos = inr.offset; inr.offset += modulationWheelLsbEvents;
  let channelVolumeLsbPos = inr.offset; inr.offset += channelVolumeLsbEvents;
  let panLsbPos = inr.offset; inr.offset += panLsbEvents;
  let bankSelectPos = inr.offset; inr.offset += bankSelectEvents;
  let pitchWheelLsbPos = inr.offset; inr.offset += pitchWheelEvents;
  let nonRegisteredMsbPos = inr.offset; inr.offset += nonRegisteredMsbEvents;
  let nonRegisteredLsbPos = inr.offset; inr.offset += nonRegisteredLsbEvents;
  let registeredMsbPos = inr.offset; inr.offset += registeredMsbEvents;
  let registeredLsbPos = inr.offset; inr.offset += registeredLsbEvents;
  let tempoPos = inr.offset; inr.offset += tempoChanges * 3;

  const out = new MidiWriter();
  out.p4(0x4D546864); // MThd
  out.p4(6);
  out.p2(tracks > 1 ? 1 : 0);
  out.p2(tracks);
  out.p2(division);

  inr.offset = deltaTimePos;
  let i = 0;
  let channel = 0, local532 = 0, local534 = 0, local536 = 0, local538 = 0, local540 = 0, local542 = 0;
  const values = new Array(128).fill(0);
  controller = 0;

  for (let track = 0; track < tracks; track++) {
    out.p4(0x4D54726B); // MTrk
    out.p4(0);
    const trackStart = out.offset;
    let local567 = -1;
    while (true) {
      const deltaTime = gVarInt(inr);
      out.pVarInt(deltaTime);
      const local583 = bytes[i++] & 0xFF;
      const statusChanged = local583 !== local567;
      local567 = local583 & 0xF;
      if (local583 === 7) {
        if (statusChanged) out.p1(255);
        out.p1(47); out.p1(0);
        out.psize4(out.offset - trackStart);
        break;
      }
      if (local583 === 23) {
        if (statusChanged) out.p1(255);
        out.p1(81); out.p1(3);
        out.p1(bytes[tempoPos++]); out.p1(bytes[tempoPos++]); out.p1(bytes[tempoPos++]);
        continue;
      }

      channel ^= local583 >> 4;
      if (local567 === 0) {
        if (statusChanged) out.p1(channel + 144);
        local532 += signed(bytes, keyPos++);
        local534 += signed(bytes, onVelocityPos++);
        out.p1(local532 & 0x7F); out.p1(local534 & 0x7F);
      } else if (local567 === 1) {
        if (statusChanged) out.p1(channel + 128);
        local532 += signed(bytes, keyPos++);
        local536 += signed(bytes, offVelocityPos++);
        out.p1(local532 & 0x7F); out.p1(local536 & 0x7F);
      } else if (local567 === 2) {
        if (statusChanged) out.p1(channel + 176);
        controller = (controller + (bytes[statusAndChannel++] & 0xFF)) & 0x7F;
        out.p1(controller);
        let valueDelta;
        if (controller === 0 || controller === 32) valueDelta = signed(bytes, bankSelectPos++);
        else if (controller === 1) valueDelta = signed(bytes, modulationWheelMsbPos++);
        else if (controller === 33) valueDelta = signed(bytes, modulationWheelLsbPos++);
        else if (controller === 7) valueDelta = signed(bytes, channelVolumeMsbPos++);
        else if (controller === 39) valueDelta = signed(bytes, channelVolumeLsbPos++);
        else if (controller === 10) valueDelta = signed(bytes, panMsbPos++);
        else if (controller === 42) valueDelta = signed(bytes, panLsbPos++);
        else if (controller === 99) valueDelta = signed(bytes, nonRegisteredMsbPos++);
        else if (controller === 98) valueDelta = signed(bytes, nonRegisteredLsbPos++);
        else if (controller === 101) valueDelta = signed(bytes, registeredMsbPos++);
        else if (controller === 100) valueDelta = signed(bytes, registeredLsbPos++);
        else if (controller === 64 || controller === 65 || controller === 120 || controller === 121 || controller === 123) valueDelta = signed(bytes, otherKnownControllerPos++);
        else valueDelta = signed(bytes, unknownControllerPos++);
        const value = valueDelta + values[controller];
        values[controller] = value;
        out.p1(value & 0x7F);
      } else if (local567 === 3) {
        if (statusChanged) out.p1(channel + 224);
        local538 += signed(bytes, pitchWheelLsbPos++);
        local538 += signed(bytes, pitchWheelMsbPos++) << 7;
        out.p1(local538 & 0x7F); out.p1((local538 >> 7) & 0x7F);
      } else if (local567 === 4) {
        if (statusChanged) out.p1(channel + 208);
        local540 += signed(bytes, channelPressurePos++);
        out.p1(local540 & 0x7F);
      } else if (local567 === 5) {
        if (statusChanged) out.p1(channel + 160);
        local532 += signed(bytes, keyPos++);
        local542 += signed(bytes, keyPressurePos++);
        out.p1(local532 & 0x7F); out.p1(local542 & 0x7F);
      } else if (local567 === 6) {
        if (statusChanged) out.p1(channel + 192);
        out.p1(bytes[bankSelectPos++]);
      } else {
        return null;
      }
    }
  }
  return out.bytes();
}

const root = path.resolve(__dirname, "..");
const cache = path.resolve(arg("cache", path.join(root, "client", "client_cache")));
const idxNum = Number(arg("idx", "6"));
const out = path.resolve(arg("out", path.join(root, "client", "music", "midi")));
const datPath = path.join(cache, "main_file_cache.dat");
const idxPath = path.join(cache, "main_file_cache.idx" + idxNum);

if (!fs.existsSync(datPath) || !fs.existsSync(idxPath)) {
  console.error("[music] cache files not found under " + cache);
  process.exit(1);
}

fs.mkdirSync(out, { recursive: true });
const dat = fs.readFileSync(datPath);
const idx = fs.readFileSync(idxPath);
const capacity = Math.floor(idx.length / 6);
let extracted = 0;
let skipped = 0;

for (let groupId = 0; groupId < capacity; groupId++) {
  const raw = readGroup(idxNum, dat, idx, groupId);
  const bytes = raw ? decompress(raw) : null;
  const midi = bytes ? songToMidi(bytes) : null;
  if (!isMidi(midi)) {
    if (bytes) skipped++;
    continue;
  }
  fs.writeFileSync(path.join(out, groupId + ".mid"), Buffer.from(midi));
  extracted++;
}

console.log("[music] extracted " + extracted + " MIDI group(s) from idx" + idxNum + " (" + skipped + " groups skipped)");
if (extracted === 0) {
  console.error("[music] no MIDI files were found or converted.");
  process.exit(2);
}
