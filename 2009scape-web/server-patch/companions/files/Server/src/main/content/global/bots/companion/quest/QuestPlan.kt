package content.global.bots.companion.quest

import content.data.Quests
import core.game.node.entity.player.Player
import core.game.world.map.Location

/**
 * A quest written as an ordered list of rules, modelled on Quest Helper's ConditionalStep:
 * every tick the first rule whose condition holds is the step to work on. Steps name their
 * targets by in-game name (plus optional ids) and a location, so a step ported from Quest
 * Helper only needs its OSRS ids swapped for names or rev-530 ids.
 */
class QuestPlan(
    val quest: Quests,
    val aliases: List<String>,
    private val rules: List<Rule>,
) {
    class Rule(val condition: (Player) -> Boolean, val step: QuestStep)

    fun isComplete(player: Player): Boolean = player.questRepository.getStage(quest) >= 100

    fun currentStep(player: Player): QuestStep? {
        if (isComplete(player)) return null
        return rules.firstOrNull { it.condition(player) }?.step
    }

    val displayName: String get() = quest.questName
}

/** What to act on: an NPC, scenery or ground item, matched by name and/or id. */
data class Target(val names: List<String> = emptyList(), val ids: Set<Int> = emptySet()) {
    fun matches(name: String?, id: Int): Boolean =
        (ids.isNotEmpty() && id in ids) || (name != null && names.any { it.equals(name, ignoreCase = true) })

    override fun toString(): String = names.firstOrNull() ?: ids.joinToString(",")
}

fun named(vararg names: String) = Target(names.toList())
fun ids(vararg ids: Int) = Target(ids = ids.toSet())

sealed class QuestStep(val text: String, val at: Location) {
    /** Talk to an NPC and pick dialogue options whose text contains one of [options], in priority order. */
    class TalkTo(val npc: Target, at: Location, val options: List<String>, text: String) : QuestStep(text, at)

    /** Click an option ("Pick", "Milk", "Operate") on scenery or an NPC. */
    class Interact(val target: Target, val option: String, at: Location, text: String, val isNpc: Boolean = false, val options: List<String> = emptyList()) : QuestStep(text, at)

    /** Use an inventory item on scenery or an NPC. */
    class UseItemOn(val itemId: Int, val target: Target, at: Location, text: String, val isNpc: Boolean = false) : QuestStep(text, at)

    /** Buy one of [itemId] from a shopkeeper NPC (opens the shop with "Trade"). */
    class BuyFromShop(val shopkeeper: Target, val itemId: Int, at: Location, text: String) : QuestStep(text, at)

    /** Pick up a ground item spawn; waits nearby for it to respawn if someone took it. */
    class TakeGroundItem(val itemId: Int, at: Location, text: String) : QuestStep(text, at)
}

/** Small DSL so plans read top to bottom like a quest guide. */
class QuestPlanBuilder(private val quest: Quests, private val aliases: List<String>) {
    private val rules = ArrayList<QuestPlan.Rule>()
    fun step(condition: (Player) -> Boolean, step: QuestStep) { rules += QuestPlan.Rule(condition, step) }
    fun build() = QuestPlan(quest, aliases, rules)
}

fun questPlan(quest: Quests, vararg aliases: String, block: QuestPlanBuilder.() -> Unit): QuestPlan =
    QuestPlanBuilder(quest, aliases.toList()).apply(block).build()

object QuestPlans {
    val all: List<QuestPlan> by lazy { listOf(CooksAssistantPlan.plan) }

    fun find(query: String): QuestPlan? {
        val q = query.trim().lowercase().replace("'", "")
        return all.firstOrNull { plan ->
            plan.displayName.lowercase().replace("'", "") == q || plan.aliases.any { it == q }
        } ?: all.firstOrNull { it.displayName.lowercase().replace("'", "").contains(q) }
    }
}
