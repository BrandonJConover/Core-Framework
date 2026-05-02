---
active: true
iteration: 1
session_id: 
max_iterations: 30
completion_promise: "INTERFACE_COMPONENT_PORTED"
started_at: "2026-05-02T10:59:24Z"
---

Port the rev-530 interface component byte format to TypeScript as InterfaceComponent530.ts. This is the foundation for the entire UI layer (chatbox, inventory, bank, shop, options menus, right-click context menus, login screen) plus the CS2 script runtime which reads/writes interface state.

Each interface (idx3) is a group of components. Each component is a record: type tag + position + dimensions + optional CS2 click/load scripts + optional sub-component table. The byte format has TWO variants in 530:
  - 'IF1' (legacy 377-style): single fixed-size record with 7-13 type-specific layouts
  - 'IF3' (rev-530-native, opcode-based): variable-length record with 50+ opcodes

The 530 server uses IF3 for all new interfaces. We need both decoders so legacy interfaces keep working.

Goal: pure offline-verifiable. Synthesize hand-crafted IF1 + IF3 fixtures, run the parser, assert the parsed component records have the expected fields populated.

Source of truth (read-only):
  - reference/rt4-client/client/src/main/java/rt4/Component.java (the rt4 interface-component class — has BOTH decode paths)
  - reference/rt4-client/client/src/main/java/rt4/IfXType.java or InterfaceComponent.java if present
  - 2009scape-web/client-patch/osrs/cache/def/RawModel530.ts (target shape pattern for the file)
  - 2009scape-web/client-patch/osrs/Js5Cache.ts (idx3 = interfaces; group=interfaceId; file=componentId within that interface)

Target file: 2009scape-web/client-patch/osrs/cache/def/InterfaceComponent530.ts

Required surface:
  1. InterfaceComponent530Data — strongly-typed interface with every field rt4's Component.java tracks. Group fields by type:
       - id, parentId, type, ifVersion (1 = IF1, 3 = IF3)
       - layout: x, y, width, height, parentRelativeX, parentRelativeY
       - visibility: hidden, alpha, modelType
       - Type-specific: scripts (cs2onload, cs2onclick, etc.), modelData (modelId, anim, color), textData (text, font, color, halign, valign), inventoryData (slotCount, items[], itemAmounts[])
  2. parseIF1Component(bytes) — legacy fixed-record parser (mirrors the rt4 'this.aBoolean83' branch in Component.decode)
  3. parseIF3Component(bytes) — opcode-based parser (the rt4 op-loop, opcodes 1..200ish)
  4. parseInterfaceComponent(bytes) — top-level entry that detects the format from byte[0] (0xFF = IF3, else IF1) and dispatches
  5. InterfaceComponent530.load(js5Cache, interfaceId, componentId) — Js5Cache integration

Sub-agents to use IN PARALLEL (read-only research only):
  - subagent_type=Explore, very thorough: 'Read reference/rt4-client/client/src/main/java/rt4/Component.java thoroughly. Report (a) the full byte format of BOTH the IF1 (legacy fixed-record) and IF3 (530 opcode-based) decode paths — list every g1/g2/g3/g4/gjstr read in order, with what each byte means. (b) The complete opcode list for IF3 (typically opcodes 1..150) — what each opcode reads. (c) The dispatch byte: at what byte offset does the parser detect IF1 vs IF3? Cite [Component.java#Lnnn] for every claim.'
  - subagent_type=Explore, medium: 'Search 2009scape-web/client-patch/osrs/ for any existing interface/component parser code (likely in scene/ or net/ or cache/). Report any existing partial implementation we should NOT duplicate, plus the field names already used by Game.ts for interface state (likely Game.aClass50_xxx fields). Also report the byte read pattern for IF1 in any existing 377-era client code (the file may be called InterfaceDecoder.ts or similar).'
Send these in a single message with multiple Agent tool calls so they run concurrently. Do not delegate writes to sub-agents.

Verification gates (all must pass before promise):
  1. cp 2009scape-web/client-patch/osrs/cache/def/InterfaceComponent530.ts 2009scape-web/client/osrs/cache/def/InterfaceComponent530.ts
  2. cd 2009scape-web/client && npx tsc --noEmit osrs/cache/def/InterfaceComponent530.ts 2>&1 must show no errors originating from InterfaceComponent530.ts.
  3. Build a Node ESM trace harness at 2009scape-web/client-patch/.interface-component-test.mjs that:
       (a) hand-rolls TWO IF3 component fixtures: one inventory-type (type=2) with 28 slots, one text-type (type=4) with sample text + font ref
       (b) hand-rolls ONE IF1 component fixture (legacy fixed record)
       (c) inline-mirrors parseIF1Component / parseIF3Component (same pattern as the prior tests)
       (d) asserts: each parsed record has id, type, x, y, width, height set; the inventory record has slotCount=28 and a slots array of length 28; the text record has the expected text string; format detection picks IF3 vs IF1 from byte[0]
       (e) writes the captured trace to 2009scape-web/client-patch/.interface-component-trace.txt with the line  '[InterfaceComponent530] parsed format=IFx type=N id=N width=N height=N'  per fixture
  4. node 2009scape-web/client-patch/.interface-component-test.mjs runs to completion with exit 0 and the trace file contains the marker lines for all three fixtures.

Constraints:
  - Edit only inside 2009scape-web/. Do NOT commit.
  - Mirror every edit: client-patch/ is source of truth, client/ is the tsc target.
  - Do not modify any other file outside cache/def/InterfaceComponent530.ts and the test harness.
  - Use parallel sub-agents only for read-only research. NEVER delegate writes to sub-agents.

When all four verification gates demonstrably pass, output:
  <promise>INTERFACE_COMPONENT_PORTED</promise>

Otherwise keep iterating. Never lie to escape the loop.
