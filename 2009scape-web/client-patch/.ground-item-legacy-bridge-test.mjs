#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const handlerPath = path.join(root, "osrs", "PacketHandler530.ts");
const handler = fs.readFileSync(handlerPath, "utf8");

function assertIncludes(pattern, label) {
  if (!handler.includes(pattern)) {
    console.error(`[GroundItemLegacyBridge] missing ${label}: ${pattern}`);
    process.exit(1);
  }
  console.log(`[GroundItemLegacyBridge] ${label} OK`);
}

function assertCallInHandler(handlerName) {
  const marker = `static ${handlerName}(`;
  const start = handler.indexOf(marker);
  if (start < 0) {
    console.error(`[GroundItemLegacyBridge] missing handler: ${handlerName}`);
    process.exit(1);
  }
  const next = handler.indexOf("\n    static ", start + marker.length);
  const body = handler.slice(start, next < 0 ? handler.length : next);
  if (!body.includes("this.syncLegacyGroundItems(game,")) {
    console.error(`[GroundItemLegacyBridge] ${handlerName} does not sync legacy groundItems`);
    process.exit(1);
  }
  console.log(`[GroundItemLegacyBridge] ${handlerName} sync OK`);
}

assertIncludes('import { LinkedList } from "./util/LinkedList";', "LinkedList import");
assertIncludes('import { Item } from "./media/renderable/Item";', "Item import");
assertIncludes("static syncLegacyGroundItems(game: any, plane: number, x: number, z: number): void", "bridge helper");
assertIncludes("game.groundItems[plane][x][z] = list;", "legacy list assignment");
assertIncludes("game.groundItems[plane][x][z] = null;", "legacy clear assignment");
assertIncludes("game.processGroundItems(x, z);", "scene refresh");

for (const handlerName of ["handleObjReveal", "handleObjCount", "handleObjAdd", "handleObjDel"]) {
  assertCallInHandler(handlerName);
}

console.log("[GroundItemLegacyBridge] all tests passed");
