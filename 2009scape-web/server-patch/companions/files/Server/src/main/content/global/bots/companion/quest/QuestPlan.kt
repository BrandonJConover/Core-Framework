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
    /** For a gather plan: done when it holds the items, not when the quest is finished. */
    private val done: ((Player) -> Boolean)? = null,
    private val title: String? = null,
    /** Runs on the companion when the plan finishes (a gather plan offers the items for sale). */
    val onFinished: ((content.global.bots.companion.CompanionBot) -> Unit)? = null,
) {
    class Rule(val condition: (Player) -> Boolean, val step: QuestStep)

    fun isComplete(player: Player): Boolean = done?.invoke(player) ?: (player.questRepository.getStage(quest) >= 100)

    fun currentStep(player: Player): QuestStep? {
        if (isComplete(player)) return null
        return rules.firstOrNull { it.condition(player) }?.step
    }

    val displayName: String get() = title ?: quest.questName
    val isGather: Boolean get() = done != null

    val startMessage: String get() =
        if (isGather) "I'll go get $displayName. Back soon!" else "Let's do $displayName! Follow me."
    val alreadyDoneMessage: String get() =
        if (isGather) "I already have $displayName." else "I've already done $displayName."
    val doneMessage: String get() =
        if (isGather) "Got $displayName!" else "We did it! $displayName is complete."
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
    fun buildGather(title: String, done: (Player) -> Boolean, onFinished: (content.global.bots.companion.CompanionBot) -> Unit) =
        QuestPlan(quest, aliases, rules, done, title, onFinished)
}

fun questPlan(quest: Quests, vararg aliases: String, block: QuestPlanBuilder.() -> Unit): QuestPlan =
    QuestPlanBuilder(quest, aliases.toList()).apply(block).build()

/** A plan that collects a quest's items without doing the quest, so the owner can buy them. */
fun gatherPlan(quest: Quests, title: String, aliases: List<String>, done: (Player) -> Boolean,
               onFinished: (content.global.bots.companion.CompanionBot) -> Unit, block: QuestPlanBuilder.() -> Unit): QuestPlan =
    QuestPlanBuilder(quest, aliases).apply(block).buildGather(title, done, onFinished)

object QuestPlans {
    val all: List<QuestPlan> by lazy { listOf(CooksAssistantPlan.plan) }
    val gather: List<QuestPlan> by lazy { listOf(CooksAssistantPlan.gather) }

    fun find(query: String): QuestPlan? = find(query, all)
    fun findGather(query: String): QuestPlan? = find(query, gather)

    private fun find(query: String, plans: List<QuestPlan>): QuestPlan? {
        val q = query.trim().lowercase().replace("'", "").removePrefix("the ").removeSuffix(" quest").trim()
        if (q.isEmpty()) return null
        return plans.firstOrNull { plan ->
            plan.quest.questName.lowercase().replace("'", "") == q || plan.aliases.any { it == q }
        } ?: plans.firstOrNull { it.quest.questName.lowercase().replace("'", "").contains(q) }
    }
}
