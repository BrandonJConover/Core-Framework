package content.global.bots.companion

import content.global.bots.companion.quest.QuestPlans
import core.api.Commands
import core.game.node.item.Item
import core.game.system.command.Privilege
import core.game.world.GameWorld

/**
 * ::companion                 summon your companion (or show its status)
 * ::companion follow | stay   change what it's doing
 * ::companion quest <name>    do a quest together (e.g. "cook")
 * ::companion quests          list quests it knows
 * ::companion give <item> [n] it trades you an item from its inventory
 * ::companion inv             list what it's carrying
 * ::companion dismiss         send it away
 * ::companion debug           toggle step-by-step debug messages
 * Trade it like any player to hand it items; it accepts once you accept.
 */
class CompanionCommands : Commands {
    override fun defineCommands() {
        define("companion", Privilege.STANDARD, "::companion [follow|stay|quest <name>|quests|give <item> [n]|inv|dismiss|debug]",
            "Summon and command your AI companion") { player, args ->
            if (GameWorld.settings?.enabled_botting != true) {
                reject(player, "Companions need enable_bots = true in the world's config.")
            }
            val sub = args.getOrNull(1)?.lowercase()
            val existing = Companions.of(player)
            if (sub == null) {
                if (existing == null) {
                    val c = Companions.summon(player)
                    c.say("Hi ${player.username}! Where are we off to?")
                    notify(player, "Try ::companion quest cook, ::companion stay, or trade ${c.name}.")
                } else {
                    notify(player, "${existing.name}: ${existing.mode.name.lowercase()}" + (existing.quest?.let { " - ${it.status}" } ?: ""))
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
                "quest" -> {
                    val query = args.drop(2).joinToString(" ")
                    if (query.isBlank()) reject(player, "Usage: ::companion quest <name>. Known: " + QuestPlans.all.joinToString { it.displayName })
                    val plan = QuestPlans.find(query) ?: reject(player, "I don't know \"$query\" yet. Known: " + QuestPlans.all.joinToString { it.displayName }) as Nothing
                    c.startQuest(plan)
                }
                "give" -> {
                    val rest = args.drop(2)
                    if (rest.isEmpty()) reject(player, "Usage: ::companion give <item name> [amount]")
                    val amount = rest.last().toIntOrNull()
                    val name = (if (amount != null) rest.dropLast(1) else rest).joinToString(" ").replace("_", " ")
                    val item: Item = c.bot.inventory.toArray().filterNotNull().firstOrNull { it.name.equals(name, true) }
                        ?: c.bot.inventory.toArray().filterNotNull().firstOrNull { it.name.contains(name, true) }
                        ?: reject(player, "${c.name} isn't carrying \"$name\".") as Nothing
                    c.give(item.id, amount ?: item.amount)
                }
                else -> reject(player, "Unknown companion command \"$sub\".")
            }
        }
    }
}
