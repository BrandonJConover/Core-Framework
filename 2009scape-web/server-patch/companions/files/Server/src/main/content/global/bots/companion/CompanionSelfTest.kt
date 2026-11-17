package content.global.bots.companion

import content.global.bots.companion.quest.QuestPlans
import core.api.StartupListener
import core.api.log
import core.game.bots.AIPlayer
import core.game.system.task.Pulse
import core.game.world.GameWorld
import core.game.world.map.Location
import core.tools.Log
import kotlin.system.exitProcess

/**
 * Headless end-to-end check, off unless the COMPANION_SELFTEST environment variable names a quest:
 *   COMPANION_SELFTEST=cook java -jar server.jar
 * Spawns a stand-in owner bot in Lumbridge plus a companion, runs the quest, and logs
 * "COMPANION SELFTEST PASS" or "FAIL". COMPANION_SELFTEST_EXIT=1 stops the server afterwards.
 */
class CompanionSelfTest : StartupListener {
    override fun startup() {
        val questName = System.getenv("COMPANION_SELFTEST")?.takeIf { it.isNotBlank() } ?: return
        val exit = System.getenv("COMPANION_SELFTEST_EXIT") == "1"
        val limit = System.getenv("COMPANION_SELFTEST_TICKS")?.toIntOrNull() ?: 3000
        GameWorld.Pulser.submit(object : Pulse(1) {
            var ticks = 0
            var companion: CompanionBot? = null
            var plan: content.global.bots.companion.quest.QuestPlan? = null
            override fun pulse(): Boolean {
                ticks++
                if (ticks == 20) {
                    val plan = QuestPlans.find(questName).also { this.plan = it }
                    if (plan == null) { finish("FAIL unknown quest $questName"); return true }
                    val owner = AIPlayer(Location(3222, 3218, 0))
                    val c = Companions.spawnForTesting(owner, Location(3221, 3219, 0))
                    c.verbose = true
                    c.startQuest(plan)
                    companion = c
                    log(this::class.java, Log.INFO, "COMPANION SELFTEST started ${plan.displayName} with ${c.name}")
                    return false
                }
                val c = companion ?: return false
                if (ticks % 50 == 0) {
                    val inv = c.bot.inventory.toArray().filterNotNull().joinToString { it.name }
                    log(this::class.java, Log.INFO, "COMPANION SELFTEST t=$ticks at ${c.bot.location} status='${c.quest?.status}' inv=[$inv]")
                }
                val runner = c.quest
                if (runner == null) {
                    finish(if (plan?.isComplete(c.bot) == true) "PASS after $ticks ticks" else "FAIL quest stopped")
                    return true
                }
                if (ticks > limit) { finish("FAIL timeout at '${runner.status}'"); return true }
                return false
            }
            private fun finish(result: String) {
                log(this::class.java, Log.INFO, "COMPANION SELFTEST $result")
                if (exit) { Thread { Thread.sleep(500); exitProcess(if (result.startsWith("PASS")) 0 else 1) }.start() }
            }
        })
    }
}
