package content.global.bots.companion

import content.global.bots.companion.quest.QuestPlans
import core.api.Commands
import core.game.system.command.Privilege
import core.game.world.GameWorld

/**
 * ::companion                    summon your companion (or show what it's doing)
 * ::companion follow | stay      change what it's doing
 * ::companion work [job]         woodcutting, fishing or lobsters; it banks what it gets
 * ::companion quest <name>       do a quest together (e.g. "cook")
 * ::companion gather <quest>     fetch a quest's items, then sell them to you
 * ::companion quests             list quests it knows
 * ::companion stock              what it has for sale
 * ::companion buy <n> <item>     get a price; trade it the coins to buy
 * ::companion return <item>      give back something you handed it
 * ::companion inv                list what it's carrying
 * ::companion dismiss            send it away (it is saved and comes back next time)
 * ::companion debug              toggle step-by-step debug messages
 * Anything else is read like a chat request, and you can also just say these in public chat
 * ("I'd like to buy 200 lobsters", "go fishing", "follow me").
 */
class CompanionCommands : Commands {
    override fun defineCommands() {
        define("companion", Privilege.STANDARD, "::companion [follow|stay|work <job>|quest <name>|gather <quest>|stock|buy <n> <item>|return <item>|inv|dismiss|debug]",
            "Summon and command your AI companion") { player, args ->
            if (GameWorld.settings?.enabled_botting != true) {
                reject(player, "Companions need enable_bots = true in the world's config.")
            }
            val sub = args.getOrNull(1)?.lowercase()
            val rest = args.drop(2).joinToString(" ").replace("_", " ").trim()
            val existing = Companions.of(player)
            if (sub == null) {
                if (existing == null) {
                    val c = Companions.summon(player)
                    c.say("Hi ${player.username}! Where are we off to?")
                    notify(player, "Try ::companion quest cook, ::companion work fishing, or say \"what do you have\".")
                } else {
                    notify(player, "${existing.name}: ${CompanionRequests.status(existing)}")
                }
                return@define
            }
            if (sub == "quests") {
                notify(player, "Quests I know: " + QuestPlans.all.joinToString { it.displayName })
                return@define
            }
            val c = existing ?: reject(player, "You don't have a companion. Type ::companion to call one.") as Nothing
            when (sub) {
                "follow" -> c.follow()
                "stay", "wait" -> c.stay()
                "dismiss", "bye" -> c.dismiss()
                "debug" -> { c.verbose = !c.verbose; notify(player, "Companion debug ${if (c.verbose) "on" else "off"}.") }
                "inv", "inventory" -> {
                    val items = c.bot.inventory.toArray().filterNotNull().joinToString { "${it.amount} x ${it.name}" }
                    notify(player, if (items.isBlank()) "${c.name} is carrying nothing." else "${c.name} has: $items")
                }
                "stock", "bank" -> CompanionRequests.listStock(c)
                "balance" -> CompanionRequests.handle(c, "balance", fromChat = false)
                "work" -> {
                    val job = if (rest.isBlank()) (c.job ?: WorkJob.bestFor(c.bot)) else WorkJob.find(rest)
                        ?: reject(player, "Jobs: " + WorkJob.values().joinToString { it.label }) as Nothing
                    c.startWork(job)
                }
                "quest" -> {
                    if (rest.isBlank()) reject(player, "Usage: ::companion quest <name>. Known: " + QuestPlans.all.joinToString { it.displayName })
                    val plan = QuestPlans.find(rest) ?: reject(player, "I don't know \"$rest\" yet. Known: " + QuestPlans.all.joinToString { it.displayName }) as Nothing
                    c.startQuest(plan)
                }
                "gather" -> {
                    val plan = QuestPlans.findGather(rest) ?: reject(player, "I can gather for: " + QuestPlans.gather.joinToString { it.quest.questName }) as Nothing
                    c.startQuest(plan)
                }
                "buy" -> CompanionRequests.handle(c, "buy $rest", fromChat = false)
                "return", "give" -> CompanionRequests.handle(c, "give back $rest", fromChat = false)
                else -> CompanionRequests.handle(c, args.drop(1).joinToString(" "), fromChat = false)
            }
        }
    }
}
