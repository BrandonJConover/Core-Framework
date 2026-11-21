package content.global.bots.companion

import content.global.bots.companion.quest.BotWorld
import content.global.bots.companion.quest.DialogueDriver
import core.game.bots.AIPlayer
import core.game.bots.ScriptAPI
import core.game.node.Node
import core.game.node.entity.skill.Skills
import core.game.node.item.Item
import core.game.node.scenery.Scenery
import core.game.world.map.Location
import org.rs09.consts.Items

/**
 * A gathering job the companion does on its own, mostly while its owner is offline.
 * Each job has a spot to work, a bank to unload at, and the tool it needs.
 */
enum class WorkJob(
    val label: String,
    val skill: Int,
    val tools: List<Int>,
    val starterTool: Int,
    val minLevel: Int,
    val area: Location,
    val bankStand: Location,
    val startMessage: String,
    val aliases: List<String>,
) {
    WOODCUTTING(
        "woodcutting", Skills.WOODCUTTING,
        listOf(Items.BRONZE_AXE_1351, Items.IRON_AXE_1349, Items.STEEL_AXE_1353, Items.BLACK_AXE_1361,
            Items.MITHRIL_AXE_1355, Items.ADAMANT_AXE_1357, Items.RUNE_AXE_1359, Items.DRAGON_AXE_6739),
        Items.BRONZE_AXE_1351, 1,
        Location(3087, 3240, 0), Location(3093, 3243, 0),
        "I'll go chop trees in Draynor and bank the logs.",
        listOf("woodcutting", "woodcut", "wc", "chop", "chopping", "logs", "trees", "wood"),
    ),
    FISHING(
        "fishing", Skills.FISHING,
        listOf(Items.SMALL_FISHING_NET_303),
        Items.SMALL_FISHING_NET_303, 1,
        Location(3087, 3229, 0), Location(3093, 3243, 0),
        "I'll go net shrimp in Draynor and bank them.",
        listOf("fishing", "fish", "shrimp", "shrimps", "net"),
    ),
    LOBSTERS(
        "lobster fishing", Skills.FISHING,
        listOf(Items.LOBSTER_POT_301),
        Items.LOBSTER_POT_301, 40,
        Location(2837, 3433, 0), Location(2809, 3438, 0),
        "Off to Catherby to catch lobsters.",
        listOf("lobster", "lobsters", "lobstering", "cage"),
    );

    fun cannotStart(bot: AIPlayer): String? {
        val level = bot.skills.getStaticLevel(skill)
        if (level < minLevel) return "I need level $minLevel ${Skills.SKILL_NAME[skill]} for that. I'm only $level."
        return null
    }

    companion object {
        fun find(query: String): WorkJob? {
            val q = query.trim().lowercase()
            return values().firstOrNull { q == it.name.lowercase() || q in it.aliases }
                ?: values().firstOrNull { job -> job.aliases.any { q.contains(it) } }
        }

        /** What to do while the owner is away if they never picked: the lower of its two skills. */
        fun bestFor(bot: AIPlayer): WorkJob {
            val wc = bot.skills.getStaticLevel(Skills.WOODCUTTING)
            val fish = bot.skills.getStaticLevel(Skills.FISHING)
            return if (fish < wc) FISHING else WOODCUTTING
        }
    }
}

/** Runs a [WorkJob]: gather until the inventory is full, bank, repeat. */
class WorkRunner(private val companion: CompanionBot, val job: WorkJob) {
    private val bot = companion.bot
    private val api = ScriptAPI(bot)
    private var banking = false
    private var stillTicks = 0
    private var lastXp = bot.skills.getExperience(job.skill)
    private var lastSpot: Location? = null
    var status = "Starting ${job.label}"
        private set

    fun tick() {
        if (DialogueDriver.isOpen(bot) || bot.interfaceManager.isOpened) {
            // Level-up messages and the like: nobody needs to read them.
            bot.dialogueInterpreter.close()
            bot.interfaceManager.closeChatbox()
            bot.interfaceManager.close()
            return
        }
        if (busy()) { watchdog(); return }
        stillTicks = 0
        ensureTool()
        if (bot.inventory.freeSlots() == 0) banking = true
        if (banking) bank() else gather()
    }

    private fun busy(): Boolean = bot.pulseManager.hasPulseRunning() || bot.walkingQueue.isMoving

    /** A gathering pulse that earns no XP for a long time is stuck (e.g. target out of reach). */
    private fun watchdog() {
        val xp = bot.skills.getExperience(job.skill)
        if (xp != lastXp || bot.walkingQueue.isMoving) { lastXp = xp; stillTicks = 0; return }
        if (++stillTicks > 60) {
            companion.debug("no ${job.label} xp for 60 ticks, resetting")
            bot.pulseManager.clear()
            bot.walkingQueue.reset()
            stillTicks = 0
            lastSpot = null
        }
    }

    private fun ensureTool() {
        if (job.tools.any { bot.inventory.contains(it, 1) || bot.equipment.contains(it, 1) }) return
        // A basic tool appears like a starter kit. Tools are never sold, so this can't be farmed.
        bot.inventory.add(Item(job.starterTool))
        companion.debug("picked up a ${Item(job.starterTool).name}")
    }

    private fun travel(to: Location) {
        val d = BotWorld.dist(bot.location, to)
        if (d > 120 || bot.location.z != to.z) {
            // Too far to walk sensibly (e.g. Draynor to Catherby): use the home teleport, as a player would.
            bot.properties.teleportLocation = to
            return
        }
        api.walkTo(to)
    }

    private fun gather() {
        if (BotWorld.dist(bot.location, job.area) > 14) {
            status = "Walking to the ${job.label} spot"
            travel(job.area)
            return
        }
        val target = findTarget()
        if (target == null) {
            status = "Waiting for a ${job.label} spot"
            api.walkTo(job.area.transform((-4..4).random(), (-4..4).random(), 0))
            return
        }
        status = "${job.label.replaceFirstChar { it.uppercase() }} at ${target.location}"
        lastSpot = target.location
        when (job) {
            WorkJob.WOODCUTTING -> api.interact(bot, target, "Chop down")
            WorkJob.FISHING -> api.interact(bot, target, "Net")
            WorkJob.LOBSTERS -> api.interact(bot, target, "Cage")
        }
    }

    private fun findTarget(): Node? = when (job) {
        WorkJob.WOODCUTTING -> {
            val level = bot.skills.getStaticLevel(Skills.WOODCUTTING)
            val names = buildList {
                if (level >= 30) add("Willow")
                if (level >= 15) add("Oak")
                add("Tree")
            }
            // Best tree it can cut; fall back to lesser trees when they're all chopped.
            names.firstNotNullOfOrNull { n ->
                BotWorld.nearestScenery(bot, 18) { s -> s.name.equals(n, true) && BotWorld.hasOption(s, "Chop down") && BotWorld.dist(s.location, job.area) <= 20 }
            }?.let { BotWorld.displayed(bot, it as Scenery) }
        }
        WorkJob.FISHING -> spot(316, "Net")
        WorkJob.LOBSTERS -> spot(333, "Cage")
    }

    private fun spot(id: Int, option: String): Node? =
        core.game.world.repository.Repository.npcs
            .filter { it.isActive && (it.id == id || it.name.equals("Fishing spot", true)) && BotWorld.hasOption(it, option) }
            .filter { BotWorld.dist(it.location, job.area) <= 12 && it.location.z == bot.location.z }
            .minByOrNull { BotWorld.dist(it.location, bot.location) }

    private fun bank() {
        val booth = BotWorld.nearestScenery(bot, 2) { it.name.equals("Bank booth", true) }
        if (booth == null) {
            status = "Walking to the bank"
            travel(job.bankStand)
            return
        }
        var banked = 0
        for (item in bot.inventory.toArray()) {
            if (item == null || item.id == COINS || item.id in job.tools || CompanionShop.isTool(item.id)) continue
            val id = CompanionShop.unnoted(item.id)
            if (bot.inventory.remove(item)) {
                bot.bank.add(Item(id, item.amount))
                companion.lifetimeGathered.merge(id, item.amount, Int::plus)
                banked += item.amount
            }
        }
        companion.debug("banked $banked items")
        banking = false
        status = "Banked $banked items"
    }
}

/** What the companion had when its owner logged out, to report on when they return. */
class AwayReport(val levels: IntArray, val gathered: Map<Int, Int>) {
    companion object {
        fun start(bot: AIPlayer, gathered: Map<Int, Int>) =
            AwayReport(IntArray(Skills.NUM_SKILLS) { bot.skills.getStaticLevel(it) }, HashMap(gathered))
    }

    fun describe(bot: AIPlayer, now: Map<Int, Int>): String? {
        val got = now.mapNotNull { (id, n) -> (n - (gathered[id] ?: 0)).takeIf { it > 0 }?.let { id to it } }
        val levels = (0 until Skills.NUM_SKILLS).mapNotNull { s ->
            val before = levels[s]
            val after = bot.skills.getStaticLevel(s)
            if (after > before) "${Skills.SKILL_NAME[s]} $before to $after" else null
        }
        if (got.isEmpty() && levels.isEmpty()) return null
        val parts = ArrayList<String>()
        if (got.isNotEmpty()) parts += "I banked " + got.joinToString { (id, n) -> CompanionShop.describe(id, n) }
        if (levels.isNotEmpty()) parts += "levelled " + levels.joinToString()
        return "While you were away " + parts.joinToString(" and ") + "."
    }
}
