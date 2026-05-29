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

const gameSource = fs.readFileSync(path.join(__dirname, "osrs/Game.ts"), "utf8");
const smokeSource = fs.readFileSync(path.join(__dirname, "..", "e2e", "smoke-test.js"), "utf8");
const packetConstants = loadTsModule("osrs/net/PacketConstants.ts");
const { ClientOpcode } = packetConstants;
const { Outgoing530 } = loadTsModule("osrs/net/Outgoing530.ts", {
    "./PacketConstants": packetConstants,
});

function encode(write) {
    const buf = new TestBuffer();
    write(buf);
    return buf.bytes;
}

function findActionBlock(actionExpression) {
    const needle = `if (action === ${actionExpression})`;
    const start = gameSource.indexOf(needle);
    if (start < 0) return null;
    const braceStart = gameSource.indexOf("{", start);
    let depth = 0;
    for (let i = braceStart; i < gameSource.length; i++) {
        const ch = gameSource[i];
        if (ch === "{") depth++;
        else if (ch === "}") {
            depth--;
            if (depth === 0) return gameSource.slice(start, i + 1);
        }
    }
    return null;
}

let failures = 0;
const trace = [];

function assertBlockContains(flow, actionExpression, expectedCall) {
    const block = findActionBlock(actionExpression);
    if (!block) {
        trace.push(`[MenuActionFlow] ${flow} FAILED missing action block ${actionExpression}`);
        failures++;
        return;
    }
    if (!block.includes(expectedCall)) {
        trace.push(`[MenuActionFlow] ${flow} FAILED missing ${expectedCall}`);
        failures++;
        return;
    }
    trace.push(`[MenuActionFlow] ${flow} dispatch OK (${actionExpression} -> ${expectedCall})`);
}

function assertSourceContains(flow, expectedText) {
    if (!gameSource.includes(expectedText)) {
        trace.push(`[MenuActionFlow] ${flow} FAILED missing ${expectedText}`);
        failures++;
        return;
    }
    trace.push(`[MenuActionFlow] ${flow} source OK (${expectedText})`);
}

function assertBytes(flow, actual, expected) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) {
        trace.push(`[MenuActionFlow] ${flow} bytes OK ${actual.map((b) => b.toString(16).padStart(2, "0")).join(" ")}`);
        return;
    }
    trace.push(`[MenuActionFlow] ${flow} bytes FAILED expected=${e} actual=${a}`);
    failures++;
}

const slot = 0x0102;
const obj = 0x0304;
const component = 0x12345678;
const selectedSlot = 0x0506;
const selectedObj = 0x0708;
const selectedComponent = 0x55667788;
const baseX = 3200;
const baseZ = 3200;
const localX = 10;
const localZ = 20;
const sceneX = baseX + localX;
const sceneZ = baseZ + localZ;
const groundObj = 0x0789;
const locClick = 0x0789 << 14;
const npcIndex = 0x1234;
const playerIndex = 0x1234;
const name37 = { high: 0x11223344, low: 0x55667788 };

assertBlockContains("dialogue continue", "575 && !this.aBoolean1239", "Outgoing530.continueDialogue");
assertBytes("dialogue continue", encode((buf) => Outgoing530.continueDialogue(buf, component, slot)), [
    ClientOpcode.CONTINUE_DIALOGUE, 0x34, 0x12, 0x78, 0x56, 0x02, 0x01,
]);
assertSourceContains("CS2 dialog action hook", "Outgoing530.dialogAction(game.outBuffer, actionId)");
assertBytes("CS2 dialog action", encode((buf) => Outgoing530.dialogAction(buf, npcIndex)), [
    ClientOpcode.DIALOG_ACTION, 0x12, 0x34,
]);

assertBlockContains("settings toggle", "Actions.TOGGLE_SETTING_WIDGET", "Outgoing530.ifCs2");
assertBlockContains("settings reset", "Actions.RESET_SETTING_WIDGET", "Outgoing530.ifCs2");
assertBytes("settings component click", encode((buf) => Outgoing530.ifCs2(buf, component)), [
    ClientOpcode.IF_CS2, 0x12, 0x34, 0x56, 0x78,
]);
assertSourceContains("native IF button helper", "sendNativeIfButtonAction(action: number, componentId: number, slot: number");
assertSourceContains("native IF button helper encoder", "Outgoing530.ifButton(this.outBuffer, action | 0, componentId | 0, slot | 0)");
if (!smokeSource.includes("g.sendNativeIfButtonAction(option, chosen.componentId, chosen.slot)")) {
    trace.push("[MenuActionFlow] bank IF smoke helper call FAILED");
    failures++;
} else {
    trace.push("[MenuActionFlow] bank IF smoke helper call OK");
}
assertBytes("IF action 1 bank-style click", encode((buf) => Outgoing530.ifButton(buf, 1, component, slot)), [
    ClientOpcode.IF_ACTION_1, 0x12, 0x34, 0x56, 0x78, 0x01, 0x02,
]);

assertBlockContains("inventory operate", "225", "Outgoing530.objOperate");
assertBytes("inventory operate", encode((buf) => Outgoing530.objOperate(buf, slot, obj, component)), [
    ClientOpcode.ITEM_OPERATE, 0x03, 0x84, 0x02, 0x01, 0x78, 0x56, 0x34, 0x12,
]);

assertSourceContains("bank component options source", "if (child.options != null)");
assertSourceContains("legacy inventory widget offset padding", "while (widget.imageX.length < 20) widget.imageX.push(0)");
assertSourceContains("legacy inventory widget y-offset padding", "while (widget.imageY.length < 20) widget.imageY.push(0)");
assertSourceContains("bank component option 1 menu action", "this.menuActionTypes[this.menuActionRow] = 9");
assertSourceContains("bank component option 2 menu action", "this.menuActionTypes[this.menuActionRow] = 225");
assertSourceContains("bank component option 3 menu action", "this.menuActionTypes[this.menuActionRow] = 444");
assertSourceContains("bank component option 4 menu action", "this.menuActionTypes[this.menuActionRow] = 564");
assertSourceContains("bank component option 5 menu action", "this.menuActionTypes[this.menuActionRow] = 894");
assertSourceContains("bank component option 1 dispatch", "if (action === 9) {\n            Outgoing530.objInComponentAction1");
assertBlockContains("bank component option 2 dispatch", "225", "Outgoing530.objOperate");
assertBlockContains("bank component option 3 dispatch", "444", "Outgoing530.objInComponentAction2");
assertBlockContains("bank component option 4 dispatch", "564", "Outgoing530.objInComponentAction3");
assertBlockContains("bank component option 5 dispatch", "894", "Outgoing530.objInComponentAction5");
assertBytes("bank component item option sequence", [
    ...encode((buf) => Outgoing530.objInComponentAction1(buf, slot, obj, component)),
    ...encode((buf) => Outgoing530.objOperate(buf, slot, obj, component)),
    ...encode((buf) => Outgoing530.objInComponentAction2(buf, slot, obj, component)),
    ...encode((buf) => Outgoing530.objInComponentAction3(buf, slot, obj, component)),
    ...encode((buf) => Outgoing530.objInComponentAction5(buf, slot, obj, component)),
], [
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_1, 0x01, 0x82, 0x03, 0x04, 0x34, 0x12, 0x78, 0x56,
    ClientOpcode.ITEM_OPERATE, 0x03, 0x84, 0x02, 0x01, 0x78, 0x56, 0x34, 0x12,
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_2, 0x02, 0x01, 0x34, 0x12, 0x78, 0x56, 0x84, 0x03,
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_3, 0x34, 0x12, 0x78, 0x56, 0x01, 0x02, 0x03, 0x84,
    ClientOpcode.ITEM_IN_COMPONENT_ACTION_5, 0x12, 0x34, 0x56, 0x78, 0x01, 0x82, 0x04, 0x03,
]);

assertBlockContains("inventory equip", "399", "Outgoing530.objAction2");
assertBytes("inventory equip", encode((buf) => Outgoing530.objAction2(buf, slot, obj, component)), [
    ClientOpcode.ITEM_ACTION_2, 0x04, 0x03, 0x01, 0x82, 0x34, 0x12, 0x78, 0x56,
]);

assertBlockContains("inventory drop", "227", "Outgoing530.objAction4");
assertBytes("inventory drop", encode((buf) => Outgoing530.objAction4(buf, slot, obj, component)), [
    ClientOpcode.ITEM_ACTION_4, 0x78, 0x56, 0x34, 0x12, 0x84, 0x03, 0x82, 0x01,
]);

assertBlockContains("inventory use on item", "903", "Outgoing530.useOnItem");
assertBytes("inventory use on item", encode((buf) => Outgoing530.useOnItem(buf, selectedSlot, selectedObj, selectedComponent, slot, obj, component)), [
    ClientOpcode.USE_ON_ITEM,
    0x05, 0x06, 0x78, 0x56, 0x34, 0x12, 0x02, 0x01,
    0x88, 0x77, 0x66, 0x55, 0x88, 0x07, 0x84, 0x03,
]);

assertBlockContains("ground item option 1", "68", "Outgoing530.objstackAction1");
assertBlockContains("ground item option 2", "26", "Outgoing530.objstackAction2");
assertBlockContains("ground item option 3/take", "684", "Outgoing530.objstackAction1");
assertBlockContains("ground item option 4", "930", "Outgoing530.objstackAction2");
assertBlockContains("ground item option 5", "270", "Outgoing530.objstackAction5");
assertBlockContains("inventory use on ground item", "100", "Outgoing530.useOnGroundItem");
assertBytes("ground item action sequence", [
    ...encode((buf) => Outgoing530.objstackAction1(buf, sceneX, sceneZ, groundObj)),
    ...encode((buf) => Outgoing530.objstackAction2(buf, sceneX, sceneZ, groundObj)),
    ...encode((buf) => Outgoing530.objstackAction5(buf, sceneX, sceneZ, groundObj)),
    ...encode((buf) => Outgoing530.useOnGroundItem(buf, selectedSlot, selectedObj, selectedComponent, sceneX, sceneZ, groundObj)),
], [
    ClientOpcode.GROUND_ITEM_ACTION_1, 0x8a, 0x0c, 0x07, 0x89, 0x14, 0x0c,
    ClientOpcode.GROUND_ITEM_ACTION_2, 0x07, 0x89, 0x0c, 0x8a, 0x94, 0x0c,
    ClientOpcode.GROUND_ITEM_ACTION_5, 0x0c, 0x0a, 0x09, 0x07, 0x94, 0x0c,
    ClientOpcode.USE_ON_GROUND_ITEM, 0x0a, 0x0c, 0x06, 0x05, 0x08, 0x07, 0x89, 0x07, 0x14, 0x0c, 0x77, 0x88, 0x55, 0x66,
]);
assertBytes("ground item option 5", encode((buf) => Outgoing530.objstackAction5(buf, sceneX, sceneZ, groundObj)), [
    ClientOpcode.GROUND_ITEM_ACTION_5, 0x0c, 0x0a, 0x09, 0x07, 0x94, 0x0c,
]);

assertBlockContains("npc action 1", "318", "Outgoing530.npcAction1");
assertBlockContains("npc action 2", "921", "Outgoing530.npcAction2");
assertBlockContains("npc action 3", "118", "Outgoing530.npcAction3");
assertBlockContains("npc action 4", "553", "Outgoing530.npcAction4");
assertBlockContains("npc action 5", "432", "Outgoing530.npcAction5");
assertBytes("npc action sequence", [
    ...encode((buf) => Outgoing530.npcAction1(buf, npcIndex)),
    ...encode((buf) => Outgoing530.npcAction2(buf, npcIndex)),
    ...encode((buf) => Outgoing530.npcAction3(buf, npcIndex)),
    ...encode((buf) => Outgoing530.npcAction4(buf, npcIndex)),
    ...encode((buf) => Outgoing530.npcAction5(buf, npcIndex)),
], [
    ClientOpcode.NPC_ACTION_1, 0x34, 0x12,
    ClientOpcode.NPC_ACTION_2, 0xb4, 0x12,
    ClientOpcode.NPC_ACTION_3, 0x12, 0xb4,
    ClientOpcode.NPC_ACTION_4, 0x12, 0x34,
    ClientOpcode.NPC_ACTION_5, 0x34, 0x12,
]);

assertBlockContains("player action 1", "200", "Outgoing530.playerAction1");
assertBlockContains("player follow", "876", "Outgoing530.playerFollow");
assertBlockContains("player trade", "677", "Outgoing530.playerTrade");
assertBlockContains("player request assist", "408", "Outgoing530.playerRequestAssist");
assertBlockContains("player action 5", "493", "Outgoing530.playerAction5");
assertBytes("player action sequence", [
    ...encode((buf) => Outgoing530.playerAction1(buf, playerIndex)),
    ...encode((buf) => Outgoing530.playerFollow(buf, playerIndex)),
    ...encode((buf) => Outgoing530.playerTrade(buf, playerIndex)),
    ...encode((buf) => Outgoing530.playerRequestAssist(buf, playerIndex)),
    ...encode((buf) => Outgoing530.playerAction5(buf, playerIndex)),
], [
    ClientOpcode.PLAYER_ACTION_1, 0xb4, 0x12,
    ClientOpcode.PLAYER_ACTION_FOLLOW, 0xb4, 0x12,
    ClientOpcode.PLAYER_ACTION_TRADE, 0xb4, 0x12,
    ClientOpcode.PLAYER_REQ_ASSIST, 0xb4, 0x12,
    ClientOpcode.PLAYER_ACTION_5, 0x12, 0xb4,
]);

assertBlockContains("loc action 1", "35", "Outgoing530.locAction1");
assertBlockContains("loc action 2", "389", "Outgoing530.locAction2");
assertBlockContains("loc action 3", "888", "Outgoing530.locAction3");
assertBlockContains("loc action 4", "892", "Outgoing530.locAction4");
assertBlockContains("loc action 5", "1280", "Outgoing530.locAction5");
assertBytes("loc action sequence", [
    ...encode((buf) => Outgoing530.locAction1(buf, sceneX, sceneZ, (locClick >> 14) & 32767)),
    ...encode((buf) => Outgoing530.locAction2(buf, sceneX, sceneZ, (locClick >> 14) & 32767)),
    ...encode((buf) => Outgoing530.locAction3(buf, sceneX, sceneZ, (locClick >> 14) & 32767)),
    ...encode((buf) => Outgoing530.locAction4(buf, sceneX, sceneZ, (locClick >> 14) & 32767)),
    ...encode((buf) => Outgoing530.locAction5(buf, sceneX, sceneZ, (locClick >> 14) & 32767)),
], [
    ClientOpcode.SCENERY_ACTION_1, 0x8a, 0x0c, 0x07, 0x09, 0x0c, 0x94,
    ClientOpcode.SCENERY_ACTION_2, 0x14, 0x0c, 0x8a, 0x0c, 0x07, 0x89,
    ClientOpcode.SCENERY_ACTION_3, 0x09, 0x07, 0x14, 0x0c, 0x8a, 0x0c,
    ClientOpcode.SCENERY_ACTION_4, 0x94, 0x0c, 0x0a, 0x0c, 0x07, 0x89,
    ClientOpcode.SCENERY_ACTION_5, 0x09, 0x07, 0x0a, 0x0c, 0x14, 0x0c,
]);

assertBlockContains("component on npc", "67", "Outgoing530.componentNpcAction");
assertBlockContains("component on item", "361", "Outgoing530.componentObjAction");
assertBlockContains("component on loc", "376 && this.method80(second, 0, first, clicked)", "Outgoing530.componentLocAction");
assertBlockContains("component on player", "918", "Outgoing530.componentPlayerAction");
assertBlockContains("component on ground item", "199", "Outgoing530.componentGroundItemAction");
assertBytes("component target sequence", [
    ...encode((buf) => Outgoing530.componentNpcAction(buf, selectedSlot, selectedComponent, npcIndex)),
    ...encode((buf) => Outgoing530.componentObjAction(buf, selectedSlot, selectedComponent, slot, obj, component)),
    ...encode((buf) => Outgoing530.componentLocAction(buf, selectedSlot, selectedComponent, sceneX, sceneZ, (locClick >> 14) & 32767)),
    ...encode((buf) => Outgoing530.componentPlayerAction(buf, selectedSlot, selectedComponent, playerIndex)),
    ...encode((buf) => Outgoing530.componentGroundItemAction(buf, selectedSlot, selectedComponent, sceneX, sceneZ, groundObj)),
], [
    ClientOpcode.COMPONENT_NPC_ACTION, 0x88, 0x77, 0x66, 0x55, 0x05, 0x86, 0xb4, 0x12,
    ClientOpcode.COMPONENT_ITEM_ACTION, 0x88, 0x77, 0x66, 0x55, 0x82, 0x01, 0x78, 0x56, 0x34, 0x12, 0x03, 0x84, 0x06, 0x05,
    ClientOpcode.COMPONENT_SCENERY_ACTION, 0x14, 0x0c, 0x0c, 0x0a, 0x86, 0x05, 0x66, 0x55, 0x88, 0x77, 0x07, 0x09,
    ClientOpcode.COMPONENT_PLAYER_ACTION, 0x05, 0x86, 0x88, 0x77, 0x66, 0x55, 0xb4, 0x12,
    ClientOpcode.COMPONENT_GROUND_ITEM_ACTION, 0x66, 0x55, 0x88, 0x77, 0x0c, 0x94, 0x09, 0x07, 0x0a, 0x0c, 0x06, 0x05,
]);

assertBlockContains("close widgets menu action", "Actions.CLOSE_WIDGETS", "this.closeWidgets");
assertSourceContains("close widgets encoder", "Outgoing530.closeModal(this.outBuffer)");
assertBytes("close modal", encode((buf) => Outgoing530.closeModal(buf)), [
    ClientOpcode.CLOSE_IFACE,
]);

assertBlockContains("logout button component action", "352", "Outgoing530.ifCs2");
assertSourceContains("logout button content-type gate", "if (type === 205)");
assertSourceContains("logout button countdown", "this.anInt873 = 250");
assertBytes("logout button component click", encode((buf) => Outgoing530.ifCs2(buf, component)), [
    ClientOpcode.IF_CS2, 0x12, 0x34, 0x56, 0x78,
]);

assertSourceContains("social add/remove menu action", "action === Actions.ADD_FRIEND");
assertSourceContains("social add/remove dispatch", "this.addFriend(l3)");
assertSourceContains("social add friend encoder", "Outgoing530.addFriend(this.outBuffer, name)");
assertSourceContains("social remove friend encoder", "Outgoing530.removeFriend(this.outBuffer, l)");
assertSourceContains("social add ignore encoder", "Outgoing530.addIgnore(this.outBuffer, name)");
assertSourceContains("social remove ignore encoder", "Outgoing530.removeIgnore(this.outBuffer, l)");
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
assertBlockContains("private-message menu prompt", "984", "this.friendsListAction = 3");
assertSourceContains("private-message encoder", "Outgoing530.privateMessage(this.outBuffer, this.aLong1141, this.chatMessage, PacketHandler530.huffman)");
assertBytes("private message", encode((buf) => Outgoing530.privateMessage(buf, name37, "hi", null)), [
    ClientOpcode.PRIVATE_MESSAGE, 11,
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
    2, "h".charCodeAt(0), "i".charCodeAt(0),
]);

assertSourceContains("chat settings encoder", "Outgoing530.chatSettings(this.outBuffer, this.publicChatMode, this.privateChatMode, this.tradeMode)");
assertBytes("chat settings", encode((buf) => Outgoing530.chatSettings(buf, 1, 2, 0)), [
    ClientOpcode.CHAT_SETTINGS, 1, 2, 0,
]);

assertSourceContains("command encoder", "Outgoing530.command(this.outBuffer, this.chatboxInput)");
assertBytes("command", encode((buf) => Outgoing530.command(buf, "::noclip")), [
    ClientOpcode.COMMAND, 7,
    "n".charCodeAt(0), "o".charCodeAt(0), "c".charCodeAt(0),
    "l".charCodeAt(0), "i".charCodeAt(0), "p".charCodeAt(0), 0,
]);

assertSourceContains("count-dialog resume encoder", "Outgoing530.resumeCountDialog(this.outBuffer, k)");
assertBytes("count-dialog resume", encode((buf) => Outgoing530.resumeCountDialog(buf, 0x12345678)), [
    ClientOpcode.RESUME_COUNT_DIALOG, 0x12, 0x34, 0x56, 0x78,
]);

assertSourceContains("name-dialog resume encoder", "Outgoing530.resumeNameDialog(this.outBuffer, TextUtils.nameToLong(this.inputInputMessage))");
assertBytes("name-dialog resume", encode((buf) => Outgoing530.resumeNameDialog(buf, name37)), [
    ClientOpcode.RESUME_NAME_DIALOG, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
]);

assertSourceContains("string-dialog resume encoder", "Outgoing530.resumeStringDialog(this.outBuffer, this.inputInputMessage)");
assertBytes("string-dialog resume", encode((buf) => Outgoing530.resumeStringDialog(buf, "hi")), [
    ClientOpcode.RESUME_STRING_DIALOG, 3, "h".charCodeAt(0), "i".charCodeAt(0), 0,
]);

assertSourceContains("report-abuse encoder", "Outgoing530.bugReport(this.outBuffer, TextUtils.nameToLong(this.reportedName), type - 600, this.reportMutePlayer)");
assertBytes("report-abuse", encode((buf) => Outgoing530.bugReport(buf, name37, 3, true)), [
    ClientOpcode.BUG_REPORT, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 2, 1,
]);

assertSourceContains("character-design legacy packet gate", "this.skipUnsupportedCharacterDesignPacket()");
assertSourceContains("character-design opcode note", "ReflectionCheck");

fs.writeFileSync(path.join(__dirname, ".menu-action-flow-trace.txt"), trace.join("\n") + "\n");
for (const line of trace) console.log(line);
if (failures > 0) {
    console.error(`[MenuActionFlow] ${failures} failure(s)`);
    process.exit(1);
}
console.log("[MenuActionFlow] all tests passed");
