package content.global.bots.companion.quest

import core.game.bots.ScriptAPI
import core.game.node.Node
import core.game.node.entity.player.Player
import core.game.node.item.GroundItem
import core.game.node.scenery.Scenery
import core.game.world.map.Location
import core.game.world.map.path.Pathfinder
import core.game.shops.Shop

/**
 * Drives a bot through a [QuestPlan], one small action per call to [tick] (call it every game tick).
 * Handles walking (with door opening), changing floors by ladder or stairs, and dialogue.
 */
class QuestRunner(
    private val bot: Player,
    val plan: QuestPlan,
    private val say: (String) -> Unit,
    private val log: (String) -> Unit,
) {
    enum class State { RUNNING, DONE, STUCK }

    private val api = ScriptAPI(bot)
    var state = State.RUNNING
        private set
    var status = "Starting ${plan.displayName}"
        private set

    private var current: QuestStep? = null
    private var attempts = 0
    private var wait = 0
    private var spawnWait = 0
    private var lastWalkFrom: Location? = null
    private var stuckWalks = 0
    private var climbPreference: String? = null
    private var busySince: Location? = null
    private var busyTicks = 0
    /** Set when the last action got nowhere, so the next attempt tries a door first. */
    private var blocked = false

    private fun busy(): Boolean =
        bot.pulseManager.hasPulseRunning() || bot.walkingQueue.isMoving || bot.scripts.getActiveScript() != null

    fun tick() {
        if (state != State.RUNNING) return
        if (bot.interfaceManager.isOpened) {
            if (wait-- > 0) return
            handleOpenInterface()
            wait = 1
            return
        }
        if (DialogueDriver.isOpen(bot)) {
            if (wait-- > 0) return
            val prefs = ArrayList<String>()
            climbPreference?.let { prefs += it }
            when (val s = current) {
                is QuestStep.TalkTo -> prefs += s.options
                is QuestStep.Interact -> prefs += s.options
                else -> {}
            }
            log(DialogueDriver.advance(bot, prefs))
            wait = 1
            return
        }
        if (wait > 0) { wait--; return }
        if (busy()) {
            // Watchdog: an interaction whose target can't be reached can sit in the queue forever.
            val here = bot.location
            if (busySince == null || busySince != here) { busySince = Location(here.x, here.y, here.z); busyTicks = 0 }
            if (++busyTicks > 15) {
                log("busy without moving at $here; resetting")
                bot.pulseManager.clear()
                bot.scripts.reset()
                bot.walkingQueue.reset()
                busyTicks = 0
                blocked = true
                attempts++
            }
            return
        }
        busyTicks = 0

        if (plan.isComplete(bot)) {
            state = State.DONE
            status = "Finished ${plan.displayName}"
            say("We did it! ${plan.displayName} is complete.")
            return
        }
        val step = plan.currentStep(bot)
        if (step == null) {
            fail("I don't know what to do next in ${plan.displayName}.")
            return
        }
        if (step !== current) {
            current = step
            attempts = 0
            spawnWait = 0
            stuckWalks = 0
            climbPreference = null
            triedDoors.clear()
            status = step.text
            say(step.text)
            log("step: ${step.text}")
        }
        if (attempts > 40) {
            fail("I'm stuck on: ${step.text}")
            return
        }

        // 1) Get onto the right floor, near the step's location.
        val here = bot.location
        if (here.z != step.at.z) {
            if (BotWorld.dist(here, Location(step.at.x, step.at.y, here.z)) > 6) {
                walk(Location(step.at.x, step.at.y, here.z))
            } else {
                changeFloor(step.at.z > here.z)
            }
            return
        }

        // 2) Find the thing to act on, walking closer if needed.
        val target = find(step)
        val distance = BotWorld.dist(here, step.at)
        if (target == null) {
            if (distance > 3) { walk(step.at); return }
            if (step is QuestStep.TakeGroundItem) {
                if (spawnWait++ % 60 == 0) say("Waiting for it to respawn...")
                wait = 3
                return
            }
            attempts++
            wait = 3
            log("nothing matching ${describe(step)} near ${step.at}")
            return
        }
        if (BotWorld.dist(here, target.location) > 12) { walk(target.location); return }

        // 3) Make sure we can actually reach it; a closed door is the usual reason we can't.
        if (blocked || !reachable(target)) {
            blocked = false
            if (tryDoor(target.location, "can't reach ${describe(step)}")) return
        }

        // 4) Act.
        act(step, target)
        attempts++
        wait = 2
    }

    /** A shop we opened on purpose: buy what the step wants. Anything else: close it. */
    private fun handleOpenInterface() {
        val step = current
        val shop = bot.getAttribute<Shop?>("shop", null)
        if (step is QuestStep.BuyFromShop && shop != null) {
            val (playerStock, slot) = shop.getStockSlot(step.itemId)
            if (slot >= 0 && !playerStock) {
                bot.setAttribute("shop-main", true)
                val result = shop.buy(bot, slot, 1)
                log("bought ${step.itemId} from ${shop.title}: $result")
                if (result !is Shop.TransactionStatus.Success) say("I can't afford that, or they're out of stock.")
            } else {
                log("${shop.title} doesn't sell ${step.itemId}")
            }
        }
        bot.interfaceManager.close()
    }

    private fun fail(message: String) {
        state = State.STUCK
        status = message
        say(message)
        log("STUCK: $message")
    }

    private fun describe(step: QuestStep): String = when (step) {
        is QuestStep.TalkTo -> step.npc.toString()
        is QuestStep.Interact -> "${step.target} (${step.option})"
        is QuestStep.UseItemOn -> "${step.target} (use ${step.itemId})"
        is QuestStep.TakeGroundItem -> "item ${step.itemId}"
        is QuestStep.BuyFromShop -> "${step.shopkeeper} (buy ${step.itemId})"
    }

    private fun find(step: QuestStep): Node? = when (step) {
        is QuestStep.TalkTo -> BotWorld.nearestNpc(bot, step.npc)
        is QuestStep.Interact ->
            if (step.isNpc) BotWorld.nearestNpc(bot, step.target)
            else BotWorld.nearestScenery(bot, step.target, step.option)
        is QuestStep.UseItemOn ->
            if (step.isNpc) BotWorld.nearestNpc(bot, step.target)
            else BotWorld.nearestScenery(bot, step.target)
        is QuestStep.TakeGroundItem -> BotWorld.groundItem(step.itemId, step.at)
        is QuestStep.BuyFromShop -> BotWorld.nearestNpc(bot, step.shopkeeper)
    }

    private fun act(step: QuestStep, target: Node) {
        when (step) {
            is QuestStep.TalkTo -> api.interact(bot, target, "Talk-to")
            is QuestStep.Interact -> api.interact(bot, target, step.option)
            is QuestStep.UseItemOn -> {
                if (!bot.inventory.contains(step.itemId, 1)) { log("missing item ${step.itemId}"); return }
                api.useWith(bot, step.itemId, target)
            }
            is QuestStep.BuyFromShop -> api.interact(bot, target, "Trade")
            is QuestStep.TakeGroundItem -> {
                val item = target as GroundItem
                val take = item.interaction.options.firstOrNull { it != null && it.name.equals("take", true) }
                if (take != null) item.interaction.handle(bot, take) else api.takeNearestGroundItem(step.itemId)
            }
        }
        log("act: ${describe(step)} at ${target.location}")
    }

    /** True if the path to [target] ends next to it (items on tables and NPCs behind counters count). */
    private fun reachable(target: Node): Boolean {
        if (BotWorld.dist(bot.location, target.location) <= 1) return true
        val path = Pathfinder.find(bot, target)
        if (!path.isSuccessful) return false
        val last = path.points.peekLast() ?: return true
        return BotWorld.dist(Location(last.x, last.y, bot.location.z), target.location) <= 1
    }

    private val triedDoors = HashMap<Location, Int>()

    /** Opens the closed door or gate most on the way to [goal]; each door gets two tries per step. */
    private fun tryDoor(goal: Location, why: String): Boolean {
        val door = BotWorld.closedDoorToward(bot, goal) { (triedDoors[it.location] ?: 0) < 2 } ?: return false
        triedDoors[door.location] = (triedDoors[door.location] ?: 0) + 1
        log("$why; opening ${door.name} at ${door.location}")
        api.interact(bot, door, "Open")
        attempts++
        wait = 2
        return true
    }

    private fun walk(dest: Location) {
        val here = bot.location
        if (lastWalkFrom != null && lastWalkFrom == here) stuckWalks++ else stuckWalks = 0
        lastWalkFrom = Location(here.x, here.y, here.z)
        if (stuckWalks >= 2 || blocked) {
            blocked = false
            if (tryDoor(dest, "path blocked")) { stuckWalks = 0; return }
        }
        if (stuckWalks >= 6) {
            log("stuck at $here, wandering")
            api.randomWalkTo(here, 5)
            stuckWalks = 0
            attempts++
            return
        }
        api.walkTo(dest)
    }

    private fun changeFloor(up: Boolean) {
        val direct = if (up) "Climb-up" else "Climb-down"
        val stairs: Scenery? = BotWorld.nearestScenery(bot, 12) { obj ->
            val n = obj.name?.lowercase() ?: ""
            (n.contains("ladder") || n.contains("stair")) &&
                (BotWorld.hasOption(obj, direct) || BotWorld.hasOption(obj, "Climb"))
        }
        if (stairs == null) {
            attempts++
            wait = 3
            log("no ladder or stairs near ${bot.location}")
            return
        }
        if (blocked || !reachable(stairs)) {
            blocked = false
            if (tryDoor(stairs.location, "can't reach ${stairs.name}")) return
        }
        climbPreference = if (up) "up" else "down"
        val option = if (BotWorld.hasOption(stairs, direct)) direct else "Climb"
        log("climbing ${if (up) "up" else "down"} ${stairs.name} at ${stairs.location}")
        api.interact(bot, stairs, option)
        attempts++
        wait = 2
    }
}
