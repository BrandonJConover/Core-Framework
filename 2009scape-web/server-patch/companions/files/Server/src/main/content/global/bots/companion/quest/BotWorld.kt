package content.global.bots.companion.quest

import core.game.bots.BotPacketTap
import core.game.node.Node
import core.game.node.entity.npc.NPC
import core.game.node.entity.player.Player
import core.game.node.item.GroundItem
import core.game.node.item.GroundItemManager
import core.game.node.scenery.Scenery
import core.game.world.map.Location
import core.game.world.map.RegionManager

/** Lookups a bot needs that ScriptAPI doesn't cover (multi-region search, ids or names, options). */
object BotWorld {
    fun dist(a: Location, b: Location): Int = maxOf(Math.abs(a.x - b.x), Math.abs(a.y - b.y))

    fun nearestNpc(bot: Player, target: Target, radius: Int = 16): NPC? =
        RegionManager.getLocalNPCs(bot.location, radius)
            .filter { it.isActive && target.matches(it.name, it.id) }
            .minByOrNull { dist(it.location, bot.location) }

    fun nearestScenery(bot: Player, radius: Int = 16, predicate: (Scenery) -> Boolean): Scenery? {
        val loc = bot.location
        val regionIds = HashSet<Int>()
        for (dx in intArrayOf(-radius, 0, radius)) for (dy in intArrayOf(-radius, 0, radius)) {
            regionIds += loc.transform(dx, dy, 0).regionId
        }
        var best: Scenery? = null
        var bestDist = Int.MAX_VALUE
        for (id in regionIds) {
            val region = RegionManager.forId(id)
            val list = try { region.assembleObjectList(loc.z) } catch (e: Exception) { continue }
            for (obj in list) {
                if (!obj.isActive) continue
                val d = dist(obj.location, loc)
                if (d > radius || d >= bestDist) continue
                if (predicate(obj)) { best = obj; bestDist = d }
            }
        }
        return best
    }

    fun nearestScenery(bot: Player, target: Target, option: String? = null, radius: Int = 16): Scenery? =
        nearestScenery(bot, radius) { obj ->
            val shown = displayed(bot, obj)
            (target.matches(shown.name, shown.id) || target.matches(obj.name, obj.id)) &&
                (option == null || hasOption(shown, option) || hasOption(obj, option))
        }

    /** Scenery whose look depends on a varbit has a per-player "child"; that's what the player sees. */
    fun displayed(bot: Player, obj: Scenery): Scenery = try { obj.getChild(bot) ?: obj } catch (e: Exception) { obj }

    fun hasOption(node: Node, option: String): Boolean =
        node.interaction.options.any { it != null && it.name.equals(option, ignoreCase = true) }

    fun groundItem(itemId: Int, near: Location, radius: Int = 6): GroundItem? =
        GroundItemManager.getItems()
            .filter { it.id == itemId && it.location.z == near.z && dist(it.location, near) <= radius && !it.isRemoved && !it.isPrivate }
            .minByOrNull { dist(it.location, near) }

    private fun isClosedDoor(obj: Scenery): Boolean {
        val n = obj.name?.lowercase() ?: ""
        return (n.contains("door") || n.contains("gate")) && hasOption(obj, "Open")
    }

    fun closedDoorNear(bot: Player, radius: Int = 3): Scenery? = nearestScenery(bot, radius) { isClosedDoor(it) }

    /** The closed door or gate within [radius] of the bot that lies most nearly on the way to [goal]. */
    fun closedDoorToward(bot: Player, goal: Location, radius: Int = 10, allowed: (Scenery) -> Boolean = { true }): Scenery? {
        val candidates = ArrayList<Scenery>()
        nearestScenery(bot, radius) { if (isClosedDoor(it) && allowed(it)) candidates += it; false }
        return candidates.minByOrNull { dist(it.location, bot.location) + dist(it.location, goal) }
    }
}

/** Reads and answers chatbox dialogues for a bot, using strings captured by [BotPacketTap]. */
object DialogueDriver {
    private const val DEFAULT_CHATBOX = 137

    fun isOpen(bot: Player): Boolean =
        bot.interfaceManager.hasChatbox() || bot.dialogueInterpreter.dialogue != null

    /** Option texts if the open chatbox is an options menu (interfaces 228/230/232/234). */
    fun options(bot: Player): List<String>? {
        val id = bot.interfaceManager.chatbox?.id ?: return null
        if (id !in 228..234 || id % 2 != 0) return null
        val count = (id - 224) / 2
        return (0 until count).map { BotPacketTap.get(bot, id, it + 2) ?: "" }
    }

    /** Text lines of the open chatbox, for logging what the bot "reads". */
    fun text(bot: Player): String {
        val id = bot.interfaceManager.chatbox?.id ?: return ""
        return BotPacketTap.lines(bot, id).toSortedMap().values.filter { it.isNotBlank() }.joinToString(" ")
    }

    /**
     * Advances one dialogue screen. On an options menu it picks the first option containing one of
     * [preferred] (in priority order), else the first option. Returns a short log line.
     */
    fun advance(bot: Player, preferred: List<String>): String {
        val chat = bot.interfaceManager.chatbox
        val id = chat?.id ?: DEFAULT_CHATBOX
        val interpreter = bot.dialogueInterpreter
        val opts = options(bot)
        if (interpreter.dialogue == null) {
            // Plain message boxes with queued actions (same path as PacketProcessor's ContinueOption).
            bot.interfaceManager.closeChatbox()
            bot.interfaceManager.openChatbox(DEFAULT_CHATBOX)
            if (interpreter.actions.isNotEmpty()) interpreter.actions.removeAt(0).handle(bot, if (opts != null) 2 else 1)
            return "closed message"
        }
        if (opts != null) {
            var index = -1
            for (want in preferred) {
                index = opts.indexOfFirst { it.contains(want, ignoreCase = true) }
                if (index >= 0) break
            }
            if (index < 0) index = 0
            interpreter.handle(id, index + 2)
            return "chose \"${opts[index]}\" from ${opts}"
        }
        val said = text(bot)
        interpreter.handle(id, 1)
        return "continue: $said"
    }
}
