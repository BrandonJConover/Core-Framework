import path from "path";
import vm from "vm";
import { createRequire } from "module";
import { fileURLToPath } from "url";
import fs from "fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const requireFromClient = createRequire(path.join(__dirname, "../client/package.json"));
const ts = requireFromClient("typescript");

class TestBuffer {
    bytes = [];

    putOpcode530(value) { this.putByte(value); }
    putOpcode(value) { this.putByte(value); }
    putByte(value) { this.bytes.push(value & 0xff); }
    putShort(value) { this.putByte(value >> 8); this.putByte(value); }
    putShortAdded(value) { this.putByte(value >> 8); this.putByte(value + 128); }
    putLEShort(value) { this.putByte(value); this.putByte(value >> 8); }
    putLEShortAdded(value) { this.putByte(value + 128); this.putByte(value >> 8); }
    putInt(value) { this.putByte(value >> 24); this.putByte(value >> 16); this.putByte(value >> 8); this.putByte(value); }
    putLEInt(value) { this.putByte(value); this.putByte(value >> 8); this.putByte(value >> 16); this.putByte(value >> 24); }
    putString(value) { for (let i = 0; i < value.length; i++) this.putByte(value.charCodeAt(i)); this.putByte(0); }
}

function loadTsModule(relativePath, extraRequire = {}) {
    const sourcePath = path.join(__dirname, relativePath);
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
        require(request) {
            if (extraRequire[request]) return extraRequire[request];
            return {};
        },
    };
    vm.runInNewContext(js, sandbox, { filename: sourcePath });
    return module.exports;
}

const packetConstants = loadTsModule("osrs/net/PacketConstants.ts");
const { ClientOpcode, PacketConstants } = packetConstants;
const { Outgoing530 } = loadTsModule("osrs/net/Outgoing530.ts", {
    "./PacketConstants": packetConstants,
});
const name37 = { high: 0x11223344, low: 0x55667788 };

function encode(write) {
    const buf = new TestBuffer();
    write(buf);
    return buf.bytes;
}

let failures = 0;
const lines = [];

function assertBytes(label, actual, expected) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) {
        lines.push(`[Outgoing530Golden] ${label} OK`);
        return;
    }
    failures++;
    lines.push(`[Outgoing530Golden] ${label} FAILED expected=${e} actual=${a}`);
}

function assertEqual(label, actual, expected) {
    if (actual === expected) {
        lines.push(`[Outgoing530Golden] ${label} OK`);
        return;
    }
    failures++;
    lines.push(`[Outgoing530Golden] ${label} FAILED expected=${expected} actual=${actual}`);
}

assertBytes("npc actions 1/2", [
    ...encode((buf) => Outgoing530.npcAction1(buf, 0x1234)),
    ...encode((buf) => Outgoing530.npcAction2(buf, 0x1234)),
], [
    ClientOpcode.NPC_ACTION_1, 0x34, 0x12,
    ClientOpcode.NPC_ACTION_2, 0xb4, 0x12,
]);

assertBytes("loc action 2", encode((buf) => Outgoing530.locAction2(buf, 0x0123, 0x0456, 0x0789)), [
    ClientOpcode.SCENERY_ACTION_2, 0xd6, 0x04, 0x23, 0x01, 0x07, 0x89,
]);

assertBytes("item action 3", encode((buf) => Outgoing530.objAction3(buf, 0x09ab, 0x0cde, 0x12345678)), [
    ClientOpcode.ITEM_ACTION_3, 0x78, 0x56, 0x34, 0x12, 0xab, 0x09, 0xde, 0x0c,
]);

assertBytes("use item on item", encode((buf) => Outgoing530.useOnItem(
    buf, 0x0102, 0x0304, 0x11223344, 0x0506, 0x0708, 0x55667788,
)), [
    ClientOpcode.USE_ON_ITEM,
    0x01, 0x02, 0x88, 0x77, 0x66, 0x55, 0x06, 0x05,
    0x44, 0x33, 0x22, 0x11, 0x84, 0x03, 0x88, 0x07,
]);

assertBytes("if button 10", encode((buf) => Outgoing530.ifButton(buf, 10, 0x12345678, 0x09ab)), [
    ClientOpcode.IF_ACTION_10, 0x12, 0x34, 0x56, 0x78, 0x09, 0xab,
]);

assertBytes("if cs2", encode((buf) => Outgoing530.ifCs2(buf, 0x12345678)), [
    ClientOpcode.IF_CS2, 0x12, 0x34, 0x56, 0x78,
]);

assertBytes("continue dialogue", encode((buf) => Outgoing530.continueDialogue(buf, 0x12345678, 0x0102)), [
    ClientOpcode.CONTINUE_DIALOGUE, 0x34, 0x12, 0x78, 0x56, 0x02, 0x01,
]);

assertBytes("dialog action", encode((buf) => Outgoing530.dialogAction(buf, 0x1234)), [
    ClientOpcode.DIALOG_ACTION, 0x12, 0x34,
]);

assertBytes("component item actions 1/operate/2/3/5", [
    ...encode((buf) => Outgoing530.objInComponentAction1(buf, 0x0102, 0x0304, 0x12345678)),
    ...encode((buf) => Outgoing530.objOperate(buf, 0x0102, 0x0304, 0x12345678)),
    ...encode((buf) => Outgoing530.objInComponentAction2(buf, 0x0102, 0x0304, 0x12345678)),
    ...encode((buf) => Outgoing530.objInComponentAction3(buf, 0x0102, 0x0304, 0x12345678)),
    ...encode((buf) => Outgoing530.objInComponentAction5(buf, 0x0102, 0x0304, 0x12345678)),
], [
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_1, 0x01, 0x82, 0x03, 0x04, 0x34, 0x12, 0x78, 0x56,
    ClientOpcode.ITEM_OPERATE, 0x03, 0x84, 0x02, 0x01, 0x78, 0x56, 0x34, 0x12,
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_2, 0x02, 0x01, 0x34, 0x12, 0x78, 0x56, 0x84, 0x03,
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_3, 0x34, 0x12, 0x78, 0x56, 0x01, 0x02, 0x03, 0x84,
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_5, 0x12, 0x34, 0x56, 0x78, 0x01, 0x82, 0x04, 0x03,
]);

assertBytes("ground item actions 2/5", [
    ...encode((buf) => Outgoing530.objstackAction2(buf, 0x0123, 0x0456, 0x0789)),
    ...encode((buf) => Outgoing530.objstackAction5(buf, 0x0123, 0x0456, 0x0789)),
], [
    ClientOpcode.GROUND_ITEM_ACTION_2, 0x07, 0x89, 0x01, 0x23, 0x56, 0x04,
    ClientOpcode.GROUND_ITEM_ACTION_5, 0x01, 0xa3, 0x09, 0x07, 0x56, 0x04,
]);

const passthroughHuffman = {
    encode(len, src, srcOffset, dst, dstOffset) {
        for (let i = 0; i < len; i++) dst[dstOffset + i] = src[srcOffset + i];
        return len;
    },
};
assertBytes("public chat", encode((buf) => Outgoing530.publicChat(buf, 2, 3, "hi", passthroughHuffman)), [
    ClientOpcode.CHAT_MESSAGE, 5, 2, 3, 2, "h".charCodeAt(0), "i".charCodeAt(0),
]);

assertBytes("social list packets", [
    ...encode((buf) => Outgoing530.addFriend(buf, name37)),
    ...encode((buf) => Outgoing530.removeFriend(buf, name37)),
    ...encode((buf) => Outgoing530.addIgnore(buf, name37)),
    ...encode((buf) => Outgoing530.removeIgnore(buf, name37)),
], [
    ClientOpcode.ADD_FRIEND, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    ClientOpcode.REMOVE_FRIEND, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    ClientOpcode.ADD_IGNORE, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    ClientOpcode.REMOVE_IGNORE, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
]);

assertBytes("private message", encode((buf) => Outgoing530.privateMessage(buf, name37, "hi", passthroughHuffman)), [
    ClientOpcode.PRIVATE_MESSAGE, 11,
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    2, "h".charCodeAt(0), "i".charCodeAt(0),
]);

assertBytes("chat settings", encode((buf) => Outgoing530.chatSettings(buf, 1, 2, 0)), [
    ClientOpcode.CHAT_SETTINGS, 1, 2, 0,
]);

assertBytes("command", encode((buf) => Outgoing530.command(buf, "::noclip")), [
    ClientOpcode.COMMAND, 7,
    "n".charCodeAt(0), "o".charCodeAt(0), "c".charCodeAt(0),
    "l".charCodeAt(0), "i".charCodeAt(0), "p".charCodeAt(0), 0,
]);

assertBytes("resume count dialog", encode((buf) => Outgoing530.resumeCountDialog(buf, 0x12345678)), [
    ClientOpcode.RESUME_COUNT_DIALOG, 0x12, 0x34, 0x56, 0x78,
]);

assertBytes("resume name dialog", encode((buf) => Outgoing530.resumeNameDialog(buf, name37)), [
    ClientOpcode.RESUME_NAME_DIALOG, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
]);

assertBytes("resume string dialog", encode((buf) => Outgoing530.resumeStringDialog(buf, "hi")), [
    ClientOpcode.RESUME_STRING_DIALOG, 3, "h".charCodeAt(0), "i".charCodeAt(0), 0,
]);

assertBytes("bug report", encode((buf) => Outgoing530.bugReport(buf, name37, 3, true)), [
    ClientOpcode.BUG_REPORT, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 2, 1,
]);

for (const [opcode, size] of [
    [ClientOpcode.NPC_ACTION_1, 2],
    [ClientOpcode.NPC_ACTION_2, 2],
    [ClientOpcode.SCENERY_ACTION_2, 6],
    [ClientOpcode.ITEM_ACTION_3, 8],
    [ClientOpcode.ITEM_OPERATE, 8],
    [ClientOpcode.ITEM_IN_COMPONENT_ACTION_2, 8],
    [ClientOpcode.ITEM_IN_COMPONENT_ACTION_3, 8],
    [ClientOpcode.ITEM_IN_COMPONENT_ACTION_5, 8],
    [ClientOpcode.GROUND_ITEM_ACTION_5, 6],
    [ClientOpcode.USE_ON_ITEM, 16],
    [ClientOpcode.IF_ACTION_10, 6],
    [ClientOpcode.IF_CS2, 4],
    [ClientOpcode.DIALOG_ACTION, 2],
    [ClientOpcode.CONTINUE_DIALOGUE, 6],
    [ClientOpcode.ADD_FRIEND, 8],
    [ClientOpcode.REMOVE_FRIEND, 8],
    [ClientOpcode.ADD_IGNORE, 8],
    [ClientOpcode.REMOVE_IGNORE, 8],
    [ClientOpcode.CHAT_SETTINGS, 3],
    [ClientOpcode.RESUME_COUNT_DIALOG, 4],
    [ClientOpcode.RESUME_NAME_DIALOG, 8],
    [ClientOpcode.BUG_REPORT, 10],
]) {
    assertEqual(`packet size ${opcode}`, PacketConstants.PACKET_SIZES[opcode], size);
}
assertEqual("chat packet variable size", PacketConstants.PACKET_SIZES[ClientOpcode.CHAT_MESSAGE], -1);
assertEqual("private message packet variable size", PacketConstants.PACKET_SIZES[ClientOpcode.PRIVATE_MESSAGE], -1);
assertEqual("command packet variable size", PacketConstants.PACKET_SIZES[ClientOpcode.COMMAND], -1);
assertEqual("resume string dialog packet variable size", PacketConstants.PACKET_SIZES[ClientOpcode.RESUME_STRING_DIALOG], -1);
assertEqual("legacy character-design opcode 163 remains unmapped", PacketConstants.PACKET_SIZES[163], -3);
assertEqual("no guessed native character-design opcode", ClientOpcode.CHARACTER_DESIGN, undefined);

for (const line of lines) console.log(line);
if (failures > 0) {
    console.error(`[Outgoing530Golden] ${failures} failure(s)`);
    process.exit(1);
}
console.log("[Outgoing530Golden] all tests passed");
