# AI companions for 2009scape

Player-like bots that belong to you. While you're online a companion follows you, fights what
you fight, does quests alongside you, and answers what you say in chat. While you're offline it
works a gathering job and banks what it gets, and you buy its goods from it at Grand Exchange
prices. It runs inside the 2009scape server, using its own bot system (`AIPlayer`, `ScriptAPI`),
so no outside code or network service is involved.

## Install

```bash
./apply.sh /path/to/2009scape     # the folder that contains Server/
```

`setup.sh` runs this automatically after cloning the server. On a server you cloned by hand
(for example `~/2009scape` on the Linux box), run it once, rebuild, and restart. The world
config needs `enable_bots = true` (the default).

`apply.sh` copies the files under `files/` into the server and adds two one-line hooks:

- `core/net/packet/PacketRepository.java` (`bot-packet-tap.patch`). Bots have no client, so the
  server normally drops every packet sent to them. The hook hands interface text to
  `BotPacketTap` first, which is how a bot reads dialogue options. It only stores text for bots
  that opt in.
- `core/net/packet/PacketProcessor.kt` (`bot-chat-hook.patch`). Passes each public chat line to
  `BotPacketTap.heard`, so a companion can answer its owner. Only the owner's lines are read.

## In game

| Command | What it does |
|---|---|
| `::companion` | Summon your companion (your saved one if you have one), or show what it's doing |
| `::companion follow` / `stay` | Follow you (and help in fights) or wait where it is |
| `::companion work fishing` | Work a job: `woodcutting`, `fishing` (Draynor shrimp) or `lobsters` (Catherby, Fishing 40) |
| `::companion quest cook` | Do a quest together. `::companion quests` lists the ones it knows |
| `::companion gather cook` | Fetch the quest's items, then offer them to you for sale |
| `::companion stock` | What it has for sale (inventory and bank) |
| `::companion buy 200 lobsters` | Get a price quote |
| `::companion balance` | Coins you have left with it |
| `::companion return egg` | Give back something you handed it |
| `::companion inv` | What it's carrying |
| `::companion dismiss` | Send it away. It's saved, and `::companion` brings it back |
| `::companion debug` | Show each decision it makes in your chatbox |

You can also just talk to it in public chat. It understands requests like these and ignores
everything else:

- "I'd like to buy 200 lobsters" quotes a price: "I only have 100 lobsters. You can have them
  for 15k (150 each)." Say "deal" or trade it the coins.
- "how many logs do you have", "what do you have", "what's my balance"
- "I'm out of lobsters, can you bring me 12?" It charges your balance, comes to you (teleporting
  if you're far away), trades them over, and goes back to what it was doing.
- "follow me", "stay here", "go fishing", "go chop trees", "catch lobsters", "let's do cook's
  assistant", "gather items for cook's assistant", "give me back my egg"

### Buying from it

Its goods aren't free. Prices are the Grand Exchange guide price. A sale only goes through once
your side of the trade holds the coins due; until then it won't accept.

Coins you trade it without buying anything go into your **balance**, like money left with a
shopkeeper. Purchases come out of the balance first, and any extra coins you put in a trade are
added to it. Items you hand it are yours: "give me back my egg" returns them for free. Its own
200 starter coins, its tools, and anything it gathered can't be taken without paying.

### While you're offline

When you log out the companion stays in the world and works its job (the last one you gave it,
or whichever of Woodcutting and Fishing is lower). It banks at the nearest bank, picks better
trees as it levels (Willow at 30, Oak at 15), and gets a basic tool if it has none. When you log
back in it comes to you and says what it banked and which levels it gained.

Everything is saved to `data/companions/<your name>.json`: name, skills, inventory, equipment,
bank, job, your balance and deposits. It saves on logout, on dismiss, every five minutes and at
shutdown, and companions that were working are put back to work when the server starts.

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

## Headless tests

```bash
cd Server
COMPANION_SELFTEST=cook COMPANION_SELFTEST_EXIT=1 java -jar target/server-1.0.0-jar-with-dependencies.jar
```

`COMPANION_SELFTEST` picks the scenario:

- `cook`: do Cook's Assistant together (below).
- `gather-cook`: fetch an egg, milk and flour, then offer them for sale.
- `work`: the owner logs out, the companion fishes and banks, the owner logs back in, buys
  "200 shrimps" by chat (paying in a trade), leaves a 50k balance, and asks it to "bring me 12"
  from across the map. Then it checks the save file.

Cook's Assistant passes this test in about 778 game ticks (roughly 8 minutes). The companion
talks to the Cook, takes the kitchen pot, buys a bucket at the general store, collects an egg,
milks the dairy cow, picks wheat, uses the mill on three floors, and hands everything in, opening
doors and gates along the way.

This test boots the server, spawns a stand-in owner and a companion in Lumbridge, and runs the
quest. It logs each step and ends with `COMPANION SELFTEST PASS` or `FAIL`. When
`COMPANION_SELFTEST` isn't set, this does nothing.

## Files

```
files/Server/src/main/
  core/game/bots/BotPacketTap.kt                      dialogue text for bots, public chat listeners
  content/global/bots/companion/
    CompanionBot.kt          the companion: follow, stay, combat assist, trading, balance, delivery
    CompanionCommands.kt     ::companion
    CompanionRequests.kt     understands chat requests ("buy 200 lobsters", "go fishing")
    CompanionShop.kt         stock, Grand Exchange prices, item name matching, filling a trade
    CompanionWork.kt         offline jobs: woodcutting, fishing, lobsters, banking
    CompanionStore.kt        save/load, login/logout/startup/shutdown listeners
    CompanionSelfTest.kt     headless tests, off unless COMPANION_SELFTEST is set
    quest/QuestPlan.kt       step model, plan builder, quest registry
    quest/QuestRunner.kt     executes a plan: walking, doors, floors, acting, dialogue
    quest/BotWorld.kt        finding NPCs/scenery/ground items, DialogueDriver
    quest/CooksAssistantPlan.kt
```
