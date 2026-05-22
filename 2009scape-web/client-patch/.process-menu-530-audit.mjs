import fs from "fs";
import path from "path";

const root = path.dirname(new URL(import.meta.url).pathname);
const source = fs.readFileSync(path.join(root, "osrs/Game.ts"), "utf8");
const start = source.indexOf("public processMenuActions(id: number)");

if (start < 0) {
    console.error("[ProcessMenu530Audit] could not locate processMenuActions");
    process.exit(1);
}

const body = source.slice(start);
const deniedLegacyOpcodes = [
    165, 126, 157, 222, 95,
    177, 91, 231, 158, 79, 226, 230, 227, 141, 160, 120, 217,
    176, 75, 206, 56, 184, 163,
];
let failures = 0;

for (const opcode of deniedLegacyOpcodes) {
    const pattern = new RegExp(`putOpcode\\(${opcode}\\)`);
    if (pattern.test(source)) {
        console.error(`[ProcessMenu530Audit] legacy opcode leak in Game.ts: ${opcode}`);
        failures++;
    }
}

for (const opcode of [165, 126, 157, 222, 95]) {
    const pattern = new RegExp(`skipLegacyRandomActionPacket\\(${opcode}\\)`);
    if (!pattern.test(body)) {
        console.error(`[ProcessMenu530Audit] missing documented no-op for legacy random packet: ${opcode}`);
        failures++;
    }
}

if (failures > 0) process.exit(1);
console.log("[ProcessMenu530Audit] processMenuActions has no audited legacy opcode leaks");
