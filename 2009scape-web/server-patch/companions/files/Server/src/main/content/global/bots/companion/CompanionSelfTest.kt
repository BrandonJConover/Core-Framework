package content.global.bots.companion

import content.global.bots.companion.quest.QuestPlan
import content.global.bots.companion.quest.QuestPlans
import core.api.StartupListener
import core.api.log
import core.game.bots.AIPlayer
import core.game.node.entity.player.Player
import core.game.node.entity.player.link.request.RequestType
import core.game.node.entity.player.link.request.trade.TradeModule
import core.game.node.item.Item
import core.game.system.task.Pulse
import core.game.world.GameWorld
import core.game.world.map.Location
import core.tools.Log
import kotlin.system.exitProcess

/**
 * Headless end-to-end checks, off unless COMPANION_SELFTEST is set:
 *   COMPANION_SELFTEST=cook         do Cook's Assistant together
 *   COMPANION_SELFTEST=gather-cook  fetch the Cook's Assistant items and offer them for sale
 *   COMPANION_SELFTEST=work         work while the owner is away, then sell, take a balance, deliver, save
 * A stand-in owner bot plays the player. Logs "COMPANION SELFTEST PASS" or "FAIL".
 * COMPANION_SELFTEST_EXIT=1 stops the server afterwards.
 */
class CompanionSelfTest : StartupListener {
    override fun startup() {
        val scenario = System.getenv("COMPANION_SELFTEST")?.takeIf { it.isNotBlank() } ?: return
        val exit = System.getenv("COMPANION_SELFTEST_EXIT") == "1"
        val limit = System.getenv("COMPANION_SELFTEST_TICKS")?.toIntOrNull() ?: 3000
        val test = when {
            scenario == "work" -> WorkScenario()
            scenario.startsWith("gather-") -> QuestScenario(scenario.removePrefix("gather-"), gather = true)
            else -> QuestScenario(scenario, gather = false)
        }
        GameWorld.Pulser.submit(object : Pulse(1) {
            var ticks = 0
            override fun pulse(): Boolean {
                ticks++
                if (ticks < 20) return false
                val result = try { test.tick(ticks) } catch (e: Exception) { e.printStackTrace(); "FAIL exception $e" }
                if (result == null && ticks > limit) return finish("FAIL timeout: ${test.where()}")
                return result?.let { finish(it) } ?: false
            }

            private fun finish(result: String): Boolean {
                log(CompanionSelfTest::class.java, Log.INFO, "COMPANION SELFTEST $result")
                if (exit) Thread { Thread.sleep(500); exitProcess(if (result.startsWith("PASS")) 0 else 1) }.start()
                return true
            }
        })
    }
}

private fun say(message: String) = log(CompanionSelfTest::class.java, Log.INFO, "COMPANION SELFTEST $message")

private abstract class Scenario {
    /** Returns null while running, or "PASS ..." / "FAIL ...". */
    abstract fun tick(t: Int): String?
    abstract fun where(): String
}

private class QuestScenario(val name: String, val gather: Boolean) : Scenario() {
    var companion: CompanionBot? = null
    var plan: QuestPlan? = null

    override fun where() = companion?.quest?.status ?: "not started"

    override fun tick(t: Int): String? {
        if (companion == null) {
            val plan = (if (gather) QuestPlans.findGather(name) else QuestPlans.find(name)) ?: return "FAIL unknown quest $name"
            this.plan = plan
            val owner = AIPlayer(Location(3222, 3218, 0))
            val c = Companions.spawnForTesting(owner, Location(3221, 3219, 0))
            c.verbose = true
            c.startQuest(plan)
            companion = c
            say("started ${plan.displayName} with ${c.name}")
            return null
        }
        val c = companion!!
        if (t % 50 == 0) say("t=$t at ${c.bot.location} status='${c.quest?.status}' inv=[${c.bot.inventory.toArray().filterNotNull().joinToString { it.name }}]")
        if (c.quest != null) return null
        if (plan?.isComplete(c.bot) != true) return "FAIL quest stopped"
        if (gather && c.sale == null) return "FAIL gathered but no sale was offered"
        return "PASS after $t ticks" + (c.sale?.let { " (offered for ${it.total} coins)" } ?: "")
    }
}

/** The owner trades like a player would: answers the companion's request, pays, and accepts. */
private fun ownerTrades(owner: Player, bot: Player, coins: Int) {
    val trade = TradeModule.getExtension(owner)
    if (trade == null) {
        if (bot.requestManager.target === owner && bot.getAttribute<RequestType?>("lastRequest", null) === RequestType.TRADE)
            owner.requestManager.request(bot, RequestType.TRADE)
        return
    }
    val container = trade.container ?: return
    if (trade.stage == 0 && coins > 0 && container.getAmount(COINS) < coins) {
        val slot = owner.inventory.getSlot(Item(COINS))
        if (slot >= 0) container.offer(slot, coins - container.getAmount(COINS))
        return
    }
    if (!trade.isAccepted) trade.setAccepted(true, true)
}

private fun plural(id: Int): String {
    val name = CompanionShop.name(id).lowercase().removePrefix("raw ")
    return if (name.endsWith("s")) name else name + "s"
}

private fun count(p: Player, id: Int): Int {
    val noted = core.cache.def.impl.ItemDefinition.forId(id)?.noteId ?: -1
    return p.inventory.getAmount(id) + (if (noted > 0) p.inventory.getAmount(noted) else 0)
}

private class WorkScenario : Scenario() {
    lateinit var owner: AIPlayer
    lateinit var c: CompanionBot
    var phase = "spawn"
    var wait = 0
    var item = 0
    var amount = 0
    var coinsBefore = 0
    var ownerHad = 0
    var price = 0

    override fun where() = "phase $phase, companion ${c.mode} ${c.work?.status} at ${c.bot.location}"

    private fun next(p: String, delay: Int = 3) { phase = p; wait = delay; say("phase $p") }

    override fun tick(t: Int): String? {
        if (wait > 0) { wait--; return null }
        when (phase) {
            "spawn" -> {
                owner = AIPlayer(Location(3093, 3243, 0))
                c = Companions.spawnForTesting(owner, Location(3092, 3244, 0))
                c.verbose = true
                c.job = WorkJob.FISHING
                c.ownerLoggedOut()
                if (c.mode != CompanionBot.Mode.WORK) return "FAIL didn't start work on logout"
                next("working", 0)
            }
            "working" -> {
                if (t % 50 == 0) say("t=$t ${c.work?.status} free=${c.bot.inventory.freeSlots()} fishing=${c.bot.skills.getStaticLevel(core.game.node.entity.skill.Skills.FISHING)}")
                if (c.lifetimeGathered.values.sum() >= 20) {
                    say("banked ${c.lifetimeGathered}")
                    c.ownerLoggedIn(owner)
                    next("quote")
                }
            }
            "quote" -> {
                val stock = CompanionShop.stock(c)
                item = stock.maxByOrNull { it.value }!!.key
                CompanionRequests.simulateChat(owner, "I'd like to buy 200 ${plural(item)}")
                next("check-quote")
            }
            "check-quote" -> {
                val s = c.sale ?: return "FAIL no quote after buy request"
                val have = CompanionShop.stock(c)[item] ?: 0
                if (s.items.single() != item to minOf(200, have)) return "FAIL quote ${s.items} vs stock $have"
                amount = s.items.single().second
                price = s.total
                owner.inventory.add(Item(COINS, 200_000))
                coinsBefore = c.bot.inventory.getAmount(COINS)
                ownerHad = count(owner, item)
                CompanionRequests.simulateChat(owner, "deal")
                next("buy-trade", 1)
            }
            "buy-trade" -> {
                ownerTrades(owner, c.bot, price)
                if (c.sale == null) {
                    val got = count(owner, item) - ownerHad
                    val paid = c.bot.inventory.getAmount(COINS) - coinsBefore
                    if (got != amount || paid != price) return "FAIL sale: owner got $got/$amount, companion got $paid/$price coins"
                    say("bought $amount ${CompanionShop.name(item)} for $price")
                    owner.requestManager.request(c.bot, RequestType.TRADE)
                    next("deposit", 1)
                }
            }
            "deposit" -> {
                ownerTrades(owner, c.bot, 50_000)
                if (c.balance == 50_000) { say("balance ${c.balance}"); next("deliver-setup") }
            }
            "deliver-setup" -> {
                c.startWork(WorkJob.FISHING)
                owner.properties.teleportLocation = Location(3222, 3218, 0)
                next("deliver", 5)
            }
            "deliver" -> {
                // It sold everything earlier; let it fish a dozen more first.
                if ((CompanionShop.stock(c)[item] ?: 0) < 12) return null
                ownerHad = count(owner, item)
                CompanionRequests.simulateChat(owner, "I'm out of ${plural(item)} can you bring me 12?")
                next("deliver-trade", 2)
            }
            "deliver-trade" -> {
                if (c.sale == null && !c.delivering) {
                    val got = count(owner, item) - ownerHad
                    val expectBalance = 50_000 - CompanionShop.price(item) * 12
                    if (got != 12 || c.balance != expectBalance) return "FAIL delivery: got $got/12, balance ${c.balance} vs $expectBalance"
                    if (c.mode != CompanionBot.Mode.WORK) return "FAIL didn't go back to work after delivering"
                    say("delivered 12 from balance; balance now ${c.balance}")
                    next("save")
                    return null
                }
                ownerTrades(owner, c.bot, 0)
            }
            "save" -> {
                CompanionStore.save(c)
                val json = CompanionStore.load(owner.username) ?: return "FAIL no save file"
                val restoredBank = (json["bank"] as org.json.simple.JSONArray).sumOf { ((it as org.json.simple.JSONObject)["amount"] as Number).toInt() }
                val bank = c.bot.bank.toArray().filterNotNull().sumOf { it.amount }
                val deposits = (json["deposits"] as org.json.simple.JSONObject)[COINS.toString()]
                if (restoredBank != bank || (deposits as Number).toInt() != c.balance) return "FAIL save mismatch bank $restoredBank/$bank deposits $deposits"
                return "PASS after $t ticks"
            }
        }
        return null
    }
}
