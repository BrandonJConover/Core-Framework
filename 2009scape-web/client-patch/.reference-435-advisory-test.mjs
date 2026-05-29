#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(process.cwd(), "../..");
const referenceDir = path.join(repoRoot, "reference", "refactored-client-435", "src", "main");
const rt4Dir = path.join(repoRoot, "reference", "rt4-client", "client", "src", "main");
const leverageDoc = path.join(repoRoot, "docs", "rt4-435-reference-leverage.md");
const matrixDoc = path.join(repoRoot, "docs", "rt4-web-parity-matrix.md");

function assert(condition, message) {
  if (!condition) {
    console.error(`[Reference435Advisory] ${message}`);
    process.exit(1);
  }
}

function read(file) {
  return fs.readFileSync(file, "utf8");
}

assert(fs.existsSync(referenceDir) && fs.statSync(referenceDir).isDirectory(), "missing reference/refactored-client-435/src/main");
assert(fs.existsSync(rt4Dir) && fs.statSync(rt4Dir).isDirectory(), "missing reference/rt4-client/client/src/main");
assert(fs.existsSync(leverageDoc), "missing docs/rt4-435-reference-leverage.md");

const leverage = read(leverageDoc);
const matrix = read(matrixDoc);

for (const forbidden of ["opcodes", "packet sizes", "cache layouts", "interface ids", "update masks", "combat packet details"]) {
  assert(leverage.includes(forbidden), `leverage doc does not guard against copying 435 ${forbidden}`);
}

assert(leverage.includes("reference/rt4-client remains authoritative") || leverage.includes("rt4-client` remains authoritative"), "leverage doc must keep rt4-client authoritative");
assert(leverage.includes("continue-dialogue opcode `132`"), "leverage doc must keep dialogue continue tied to native 530 evidence");
assert(matrix.includes("reference/refactored-client-435"), "parity matrix must mention the 435 advisory reference");
assert(matrix.includes("Reference-use rule"), "parity matrix must keep the 435 reference-use rule visible");

console.log("[Reference435Advisory] advisory reference guard passed");
