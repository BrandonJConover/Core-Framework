#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const handlerPath = path.join(root, "osrs", "PacketHandler530.ts");
const handler = fs.readFileSync(handlerPath, "utf8");

function assertIncludes(pattern, label) {
  if (!handler.includes(pattern)) {
    console.error(`[CombatTrace530] missing ${label}: ${pattern}`);
    process.exit(1);
  }
  console.log(`[CombatTrace530] ${label} OK`);
}

assertIncludes("private static traceCombat(game: any, entry: any)", "combat trace helper");
assertIncludes("game.combatTrace530", "combat trace store");
assertIncludes('kind: "npcHit"', "npc hit trace");
assertIncludes('kind: "npcHit", id, type, damage, ratio', "npc hit ratio trace");
assertIncludes('kind: "npcSecondaryHit", id, type, damage', "npc secondary hit damage trace");
assertIncludes('kind: "npcAnimation"', "npc animation trace");
assertIncludes('kind: "npcTarget"', "npc target trace");
assertIncludes('kind: "npcSpotAnim", id, graphic: npc.graphic, height: heightAndDelay >> 16, delay', "npc spotanim height trace");
assertIncludes('kind: "playerHit"', "player hit trace");
assertIncludes('kind: "playerHit", id, target: id === 2047 ? "local" : "player", type, damage, ratio', "player hit damage/ratio trace");
assertIncludes('kind: "playerAnimation"', "player animation trace");
assertIncludes('kind: "playerTarget"', "player target trace");
assertIncludes('kind: "playerSpotAnim", id, graphic: player.graphic, height: heightAndDelay >> 16, delay', "player spotanim height trace");
assertIncludes('kind: "playerSecondaryHit", id, target: id === 2047 ? "local" : "player", type, damage', "player secondary hit damage trace");

console.log("[CombatTrace530] all tests passed");
