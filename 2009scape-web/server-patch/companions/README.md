# AI companions for 2009scape

Player-like bots that belong to you: they follow you, fight what you fight, trade with you,
and can do quests alongside you. They run inside the 2009scape server, using its own bot
system (`AIPlayer`, `ScriptAPI`), so no outside code or network service is involved.

## Install

```bash
./apply.sh /path/to/2009scape     # the folder that contains Server/
```

`setup.sh` runs this automatically after cloning the server. On a server you cloned by hand
(for example `~/2009scape` on the Linux box), run it once, rebuild, and restart. The world
config needs `enable_bots = true` (the default).

`apply.sh` copies the files under `files/` into the server and makes one one-line change to
`core/net/packet/PacketRepository.java` (`bot-packet-tap.patch`). Bots have no client, so the
server normally drops every packet sent to them. The change hands interface text to
`BotPacketTap` first, which is how a bot reads dialogue options. It only stores text for bots
that opt in.

## In game

| Command | What it does |
|---|---|
| `::companion` | Summon your companion, or show what it's doing |
| `::companion follow` / `stay` | Follow you (and help in fights) or wait where it is |
| `::companion quest cook` | Do a quest together. `::companion quests` lists the ones it knows |
| `::companion give egg` | It opens a trade and hands you that item (`give coins 100` for an amount) |
| `::companion inv` | What it's carrying |
| `::companion dismiss` | Send it away (it also leaves when you log out) |
| `::companion debug` | Show each decision it makes in your chatbox |

To give it items, trade it like any other player. It accepts once you accept.

## How quests work

A quest is a `QuestPlan`: an ordered list of rules, each a condition plus a step, just like
Quest Helper's `ConditionalStep`. Every tick the companion works on the first step whose
condition holds, so it picks up where it left off after a fight, a death, or a step you did for
it. Step types:

- `TalkTo(npc, location, options)`: talk to an NPC, choosing dialogue options that contain the given text
- `Interact(target, option, location)`: click an option such as `Pick`, `Milk` or `Operate`
- `UseItemOn(item, target, location)`: use an inventory item on scenery or an NPC
- `TakeGroundItem(item, location)`: pick up a ground spawn, waiting for it to respawn if needed
- `BuyFromShop(shopkeeper, item, location)`: buy one from a shop (companions start with 200 coins)

Targets are matched by in-game name and/or rev-530 id, and searched for near the step's location.
The runner walks there (opening doors that block the path), climbs ladders or stairs to reach the
right floor, and answers dialogues.

### Porting a quest from Quest Helper

[Quest Helper](https://github.com/Zoinkwiz/quest-helper) (BSD 2-Clause) has steps for 185 OSRS
quests. To port one, open `src/main/java/com/questhelper/helpers/quests/<quest>/<Quest>.java`,
then follow these steps:

1. Copy each step's text, location (`WorldPoint`) and dialogue choices (`addDialogStep`).
2. Replace OSRS ids with names or rev-530 ids. OSRS and 530 ids often differ (the Lumbridge flour
   bin is 1782 in OSRS and 36878 here). `org.rs09.consts.Items/NPCs/Scenery` have the 530 ids.
3. Replace OSRS varbit conditions with this server's quest stage
   (`player.questRepository.getStage(...)`) and attributes. The quest's own code under
   `content/region/.../quest/` shows which stages and attributes it uses.
4. Add the plan to `QuestPlans.all`.

`CooksAssistantPlan.kt` is the worked example.

## Headless test

```bash
cd Server
COMPANION_SELFTEST=cook COMPANION_SELFTEST_EXIT=1 java -jar target/server-1.0.0-jar-with-dependencies.jar
```

Cook's Assistant passes this test in about 775 game ticks (roughly 8 minutes). The companion
talks to the Cook, takes the kitchen pot, buys a bucket at the general store, collects an egg,
milks the dairy cow, picks wheat, uses the mill on three floors, and hands everything in, opening
doors and gates along the way.

This test boots the server, spawns a stand-in owner and a companion in Lumbridge, and runs the
quest. It logs each step and ends with `COMPANION SELFTEST PASS` or `FAIL`. When
`COMPANION_SELFTEST` isn't set, this does nothing.

## Files

```
files/Server/src/main/
  core/game/bots/BotPacketTap.kt                      captures dialogue text for bots
  content/global/bots/companion/
    CompanionBot.kt          the companion: follow, stay, combat assist, trading, quest mode
    CompanionCommands.kt     ::companion
    CompanionSelfTest.kt     headless test, off unless COMPANION_SELFTEST is set
    quest/QuestPlan.kt       step model, plan builder, quest registry
    quest/QuestRunner.kt     executes a plan: walking, doors, floors, acting, dialogue
    quest/BotWorld.kt        finding NPCs/scenery/ground items, DialogueDriver
    quest/CooksAssistantPlan.kt
```
