#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const gamePath = path.join(root, "osrs", "Game.ts");
const smokePath = path.join(root, "..", "e2e", "smoke-test.js");
const game = fs.readFileSync(gamePath, "utf8");
const smoke = fs.readFileSync(smokePath, "utf8");

function assertIncludes(source, pattern, label) {
  if (!source.includes(pattern)) {
    console.error(`[GroundItemMenuFallback] missing ${label}: ${pattern}`);
    process.exit(1);
  }
  console.log(`[GroundItemMenuFallback] ${label} OK`);
}

assertIncludes(game, "let bestGroundItem:", "ground item fallback search");
assertIncludes(game, "this.groundItems?.[this.plane]?.[x]?.[y]", "ground item tile lookup");
assertIncludes(game, "this.addSceneGroundItemMenuRows(bestGroundItem.x, bestGroundItem.y);", "fallback menu dispatch");
assertIncludes(game, "private addSceneGroundItemMenuRows", "ground item menu helper");
assertIncludes(game, "Take @lre@", "default take row");
assertIncludes(game, "this.menuActionTypes[this.menuActionRow] = 684;", "take action type");
assertIncludes(game, "this.menuActionTypes[this.menuActionRow] = 100;", "use-with ground item action");
assertIncludes(game, "this.menuActionTypes[this.menuActionRow] = 199;", "component-with ground item action");
assertIncludes(smoke, "DROP_TAKE_TAKE_MODE", "drop/take menu mode flag");
assertIncludes(smoke, "takeMode === 'menu'", "server-backed menu take branch");
assertIncludes(smoke, "g.addSceneGroundItemMenuRows(dropResult.localX, dropResult.localY);", "drop/take uses generated ground item rows");

console.log("[GroundItemMenuFallback] all tests passed");
