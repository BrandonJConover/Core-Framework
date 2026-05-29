#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const handlerPath = path.join(root, "osrs", "PacketHandler530.ts");
const handler = fs.readFileSync(handlerPath, "utf8");

function assertIncludes(pattern, label) {
  if (!handler.includes(pattern)) {
    console.error(`[PacketHandler530ChatboxState] missing ${label}: ${pattern}`);
    process.exit(1);
  }
  console.log(`[PacketHandler530ChatboxState] ${label} OK`);
}

assertIncludes("const parentInterfaceId = pointer >>> 16;", "parent interface decode");
assertIncludes("const childId = pointer & 0xFFFF;", "child id decode");
assertIncludes("parentInterfaceId === 752", "Java CHATTOP_752 classification");
assertIncludes("childId === 12", "dialogue child classification");
assertIncludes("game.dialogueId = component;", "legacy dialogue mirror");
assertIncludes("game.backDialogueId = -1;", "stale chatbox clear on dialogue");
assertIncludes("childId === 6 || childId === 8", "chatbox child classification");
assertIncludes("game.backDialogueId = component;", "legacy chatbox mirror");
assertIncludes("game.redrawChatbox = true;", "chatbox redraw marker");
assertIncludes("recordIfUpdate(game, \"IF_OPENTOP\"", "IF_OPENTOP diagnostics");

console.log("[PacketHandler530ChatboxState] all tests passed");
