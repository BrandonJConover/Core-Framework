// Offline trace harness for PacketHandler530 debug packet tracing.
// Loads the real TypeScript handler with stubs for unrelated imports so the
// tests stay focused on packet alignment and trace entries.

import fs from "fs";
import path from "path";
import vm from "vm";
import { createRequire } from "module";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const requireFromClient = createRequire(path.join(__dirname, "../client/package.json"));
const ts = requireFromClient("typescript");

class TestBuffer {
    constructor(bytes) {
        this.buffer = Int8Array.from(bytes);
        this.currentPosition = 0;
        this.bitPosition = 0;
    }
}

function loadPacketHandler530() {
    const sourcePath = path.join(__dirname, "osrs/PacketHandler530.ts");
    const source = fs.readFileSync(sourcePath, "utf8");
    const js = ts.transpileModule(source, {
        compilerOptions: {
            esModuleInterop: true,
            module: ts.ModuleKind.CommonJS,
            target: ts.ScriptTarget.ES2018,
        },
        fileName: sourcePath,
    }).outputText;

    const module = { exports: {} };
    const sandbox = {
        module,
        exports: module.exports,
        console,
        globalThis,
        require(request) {
            if (request === "./net/Buffer") return { Buffer: TestBuffer };
            if (request === "long") return { __esModule: true, default: {} };
            return {};
        },
    };

    vm.runInNewContext(js, sandbox, { filename: sourcePath });
    return module.exports.PacketHandler530;
}

const PacketHandler530 = loadPacketHandler530();
const lines = [];
let failures = 0;

function trace(msg) {
    lines.push(msg);
    console.log(msg);
}

function assertEqual(label, actual, expected) {
    if (actual === expected) return;
    failures++;
    const msg = `FAIL ${label}: expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`;
    lines.push(msg);
    console.error(msg);
}

function assertDeepEqual(label, actual, expected) {
    const actualJson = JSON.stringify(actual);
    const expectedJson = JSON.stringify(expected);
    if (actualJson === expectedJson) return;
    failures++;
    const msg = `FAIL ${label}: expected=${expectedJson} actual=${actualJson}`;
    lines.push(msg);
    console.error(msg);
}

function captureTraceEntry(game) {
    assertEqual("trace length", game.packetTrace530.length, 1);
    return game.packetTrace530[0];
}

{
    const game = { debugPackets530: true, pulseCycle: 321 };
    const buf = new TestBuffer([77]);
    const ok = PacketHandler530.handle(234, buf, 1, game);
    const entry = captureTraceEntry(game);

    assertEqual("fixed handler ok", ok, true);
    assertEqual("fixed handler consumed buffer", buf.currentPosition, 1);
    assertEqual("fixed handler run energy", game.anInt1324, 77);
    assertDeepEqual("fixed handler trace", entry, {
        opcode: 234,
        handler: "opcode_234",
        size: 1,
        consumed: 1,
        ok: true,
        error: null,
        cycle: 321,
    });
    trace(`[PacketTrace] fixed handler opcode=${entry.opcode} consumed=${entry.consumed}/${entry.size}`);
}

{
    const game = { debugPackets530: true, loopCycle: 44 };
    const buf = new TestBuffer([1, 2, 3]);
    const ok = PacketHandler530.handle(251, buf, 3, game);
    const entry = captureTraceEntry(game);

    assertEqual("unknown handler ok", ok, true);
    assertEqual("unknown handler consumed buffer", buf.currentPosition, 3);
    assertDeepEqual("unknown handler trace", entry, {
        opcode: 251,
        handler: "opcode_251",
        size: 3,
        consumed: 3,
        ok: true,
        error: null,
        cycle: 44,
    });
    trace(`[PacketTrace] unknown opcode=${entry.opcode} consumed=${entry.consumed}/${entry.size}`);
}

{
    const originalDispatch = PacketHandler530.dispatch;
    const game = { debugPackets530: true, pulseCycle: 12 };
    const buf = new TestBuffer([0, 0, 10, 20, 30, 40, 50, 60]);
    buf.currentPosition = 2;
    PacketHandler530.dispatch = function(_opcode, packetBuf) {
        packetBuf.currentPosition += 1;
        throw new Error("trace boom");
    };

    const priorLog = console.log;
    console.log = (msg) => lines.push(String(msg));
    const ok = PacketHandler530.handle(234, buf, 4, game);
    console.log = priorLog;
    PacketHandler530.dispatch = originalDispatch;
    const entry = captureTraceEntry(game);

    assertEqual("error handler ok", ok, true);
    assertEqual("error handler realigned buffer", buf.currentPosition, 6);
    assertDeepEqual("error handler trace", entry, {
        opcode: 234,
        handler: "opcode_234",
        size: 4,
        consumed: 4,
        ok: true,
        error: "trace boom",
        cycle: 12,
    });
    trace(`[PacketTrace] handler error opcode=${entry.opcode} realigned=${entry.consumed}/${entry.size}`);
}

if (failures === 0) trace("[PacketTrace] all tests passed");
else trace(`[PacketTrace] ${failures} test(s) FAILED`);

fs.writeFileSync(path.join(__dirname, ".packet-trace-trace.txt"), lines.join("\n") + "\n");
if (failures > 0) process.exit(1);
