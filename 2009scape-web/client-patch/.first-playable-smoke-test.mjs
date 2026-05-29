#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = path.join(process.cwd(), "..");
const smokePath = path.join(root, "e2e", "smoke-test.js");
const smoke = fs.readFileSync(smokePath, "utf8");

function assertIncludes(pattern, label) {
  if (!smoke.includes(pattern)) {
    console.error(`[FirstPlayableSmoke] missing ${label}: ${pattern}`);
    process.exit(1);
  }
  console.log(`[FirstPlayableSmoke] ${label} OK`);
}

assertIncludes("const assertFirstPlayable = process.env.ASSERT_FIRST_PLAYABLE === '1';", "aggregate flag");
assertIncludes("const assertFirstPlayableExtended = process.env.ASSERT_FIRST_PLAYABLE_EXTENDED === '1';", "extended aggregate flag");
assertIncludes("assertFirstPlayable ? 'rt4bankfx4' : 'playtest2'", "fixture account default");
assertIncludes("process.env.SEND_COMMAND !== '0' && !assertFirstPlayable", "default command suppression");
assertIncludes("process.env.ASSERT_WALK === '1' || assertFirstPlayable", "walk gate");
assertIncludes("process.env.ASSERT_MINIMAP_WALK === '1' || assertFirstPlayable", "minimap gate");
assertIncludes("process.env.ASSERT_GROUND_ITEM_MENU_PROBE === '1' || assertFirstPlayable", "ground menu gate");
assertIncludes("process.env.ASSERT_COMBAT_CONTACT_SMOKE === '1' || assertFirstPlayable", "combat contact gate");
assertIncludes("process.env.ASSERT_DROP_TAKE_SMOKE === '1' || assertFirstPlayable", "drop take gate");
assertIncludes("process.env.ASSERT_KEEPALIVE === '1' || assertFirstPlayable", "keepalive gate");
assertIncludes("process.env.ASSERT_NPC_DIALOGUE_SMOKE === '1' || assertFirstPlayable", "NPC dialogue gate");
assertIncludes("process.env.ASSERT_BANK_INVENTORY_PROBE === '1' || assertFirstPlayable", "bank inventory gate");
assertIncludes("process.env.ASSERT_BANK_ACTION_PROBE === '1' || assertFirstPlayable", "bank action gate");
assertIncludes("process.env.ASSERT_LOGOUT_RELOG === '1' || assertFirstPlayableExtended", "extended logout/relog gate");
assertIncludes("process.env.ASSERT_SERVER_RESTART_RECONNECT === '1' || assertFirstPlayableExtended", "extended restart reconnect gate");
assertIncludes("assertFirstPlayable ? '::bank' : ''", "bank fixture default");
assertIncludes("assertFirstPlayable ? '93,95' : ''", "bank container default");
assertIncludes("assertFirstPlayable ? 93 : undefined", "bank action container default");
assertIncludes("assertFirstPlayable ? 'menu' : 'direct'", "drop take menu default");
assertIncludes("assertFirstPlayable ? 60000 : 45000", "stability default");
assertIncludes("const effectiveSmokeConfig = {", "effective config summary");
assertIncludes("console.log('>>> Effective smoke config: ' + JSON.stringify(effectiveSmokeConfig));", "effective config log");
assertIncludes("assertBankActionProbe", "effective gate names");
assertIncludes("lastPartialPacketReason", "partial parser wait reason diagnostics");
assertIncludes("lastRt4KeepaliveReason", "keepalive reason diagnostics");
assertIncludes("lastFlushOutgoingOpcodeCount", "flush opcode count diagnostics");
assertIncludes("const runSmokeGate = async (label, fn) => {", "gate marker helper");
assertIncludes("First playable gate start: ", "gate start log");
assertIncludes("First playable gate pass: ", "gate pass log");
assertIncludes("First playable gate fail: ", "gate fail log");
assertIncludes("runSmokeGate('ground-item menu'", "ground item gate marker");
assertIncludes("runSmokeGate('NPC dialogue'", "NPC dialogue gate marker");
assertIncludes("runSmokeGate('combat contact'", "combat gate marker");
assertIncludes("runSmokeGate('drop/take'", "drop take gate marker");
assertIncludes("runSmokeGate('bank inventory/action'", "bank gate marker");

console.log("[FirstPlayableSmoke] all tests passed");
