package content.global.bots.companion

import core.ServerConstants
import core.api.LoginListener
import core.api.LogoutListener
import core.api.ShutdownListener
import core.api.StartupListener
import core.api.log
import core.game.bots.AIPlayer
import core.game.node.entity.player.Player
import core.game.node.item.Item
import core.game.system.task.Pulse
import core.game.world.GameWorld
import core.game.world.map.Location
import core.tools.Log
import org.json.simple.JSONArray
import org.json.simple.JSONObject
import org.json.simple.parser.JSONParser
import java.io.File

/**
 * Saves each companion to data/companions/<owner>.json: name, skills, inventory, equipment,
 * bank, job, and the owner's deposits. A companion that was working when the server stopped
 * is put back to work at startup.
 */
object CompanionStore {
    private val dir: File get() = File((ServerConstants.DATA_PATH ?: "data") + File.separator + "companions")

    private fun file(ownerName: String) = File(dir, ownerName.lowercase().replace(Regex("[^a-z0-9_ -]"), "_") + ".json")

    private fun items(items: Array<Item?>): JSONArray {
        val out = JSONArray()
        items.forEachIndexed { slot, item ->
            if (item != null && item.id > 0 && item.amount > 0) out.add(JSONObject().apply {
                put("slot", slot); put("id", item.id); put("amount", item.amount)
            })
        }
        return out
    }

    private fun counts(map: Map<Int, Int>): JSONObject = JSONObject().apply { map.forEach { (k, v) -> put(k.toString(), v) } }

    fun save(c: CompanionBot, working: Boolean = true, dropInventory: Boolean = false) {
        try {
            val bot = c.bot
            val skills = JSONArray()
            for (i in 0 until core.game.node.entity.skill.Skills.NUM_SKILLS) {
                skills.add(JSONObject().apply {
                    put("id", i)
                    put("static", bot.skills.getStaticLevel(i))
                    put("dynamic", bot.skills.getStaticLevel(i))
                    put("experience", bot.skills.getExperience(i))
                    if (i == core.game.node.entity.skill.Skills.HITPOINTS) put("lifepoints", bot.skills.getStaticLevel(i))
                    if (i == core.game.node.entity.skill.Skills.PRAYER) put("prayerPoints", bot.skills.getStaticLevel(i).toDouble())
                })
            }
            val json = JSONObject()
            json["owner"] = c.ownerName
            json["name"] = c.name
            json["working"] = working
            json["job"] = c.job?.name
            json["x"] = bot.location.x; json["y"] = bot.location.y; json["z"] = bot.location.z
            json["skills"] = skills
            json["inventory"] = if (dropInventory) JSONArray() else items(bot.inventory.toArray())
            json["equipment"] = items(bot.equipment.toArray())
            json["bank"] = items(bot.bank.toArray())
            json["deposits"] = counts(c.deposits)
            json["gathered"] = counts(c.lifetimeGathered)
            c.awaySince?.let { away ->
                json["away_levels"] = JSONArray().apply { away.levels.forEach { add(it) } }
                json["away_gathered"] = counts(away.gathered)
            }
            dir.mkdirs()
            val f = file(c.ownerName)
            val tmp = File(f.path + ".tmp")
            tmp.writeText(json.toJSONString())
            if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        } catch (e: Exception) {
            log(CompanionStore::class.java, Log.ERR, "Couldn't save companion for ${c.ownerName}: $e")
        }
    }

    fun load(ownerName: String): JSONObject? {
        val f = file(ownerName)
        if (!f.exists()) return null
        return try { JSONParser().parse(f.readText()) as JSONObject } catch (e: Exception) {
            log(CompanionStore::class.java, Log.ERR, "Couldn't read ${f.path}: $e"); null
        }
    }

    fun allSaved(): List<JSONObject> =
        (dir.listFiles { f -> f.name.endsWith(".json") } ?: emptyArray()).mapNotNull { load(it.nameWithoutExtension) }

    private fun int(o: Any?): Int = (o as? Number)?.toInt() ?: o?.toString()?.toIntOrNull() ?: 0

    private fun countsFrom(o: Any?): HashMap<Int, Int> {
        val out = HashMap<Int, Int>()
        (o as? JSONObject)?.forEach { (k, v) -> k.toString().toIntOrNull()?.let { out[it] = int(v) } }
        return out
    }

    /** Spawn a companion from its save, at [at] (or where it was saved). */
    fun restore(json: JSONObject, owner: Player?, at: Location? = null): CompanionBot {
        val spot = at ?: Location(int(json["x"]), int(json["y"]), int(json["z"]))
        val bot = AIPlayer(spot)
        (json["name"] as? String)?.let { setName(bot, it) }
        (json["skills"] as? JSONArray)?.let {
            bot.skills.parse(it)
            bot.skills.updateCombatLevel()
        }
        fun fill(container: core.game.container.Container, arr: Any?) {
            container.clear()
            (arr as? JSONArray)?.forEach { o ->
                val e = o as JSONObject
                val item = Item(int(e["id"]), int(e["amount"]))
                val slot = int(e["slot"])
                if (container === bot.equipment) container.replace(item, slot) else container.add(item)
            }
        }
        fill(bot.inventory, json["inventory"])
        fill(bot.equipment, json["equipment"])
        fill(bot.bank, json["bank"])
        bot.appearance.sync()
        val c = CompanionBot(json["owner"] as String, owner, bot)
        c.deposits.putAll(countsFrom(json["deposits"]))
        c.lifetimeGathered.putAll(countsFrom(json["gathered"]))
        c.job = (json["job"] as? String)?.let { runCatching { WorkJob.valueOf(it) }.getOrNull() }
        (json["away_levels"] as? JSONArray)?.let { arr ->
            c.awaySince = AwayReport(IntArray(arr.size) { int(arr[it]) }, countsFrom(json["away_gathered"]))
        }
        Companions.register(c)
        return c
    }

    /** AIPlayer picks a random name; a saved companion keeps the one it had. */
    private fun setName(bot: AIPlayer, name: String) {
        try {
            val f = AIPlayer::class.java.getDeclaredField("username")
            f.isAccessible = true
            f.set(bot, name)
        } catch (e: Exception) {
            log(CompanionStore::class.java, Log.WARN, "Couldn't rename companion: $e")
        }
    }
}

/** Owner logs out: the companion stays and goes to work. */
class CompanionLogoutListener : LogoutListener {
    override fun logout(player: Player) {
        Companions.of(player)?.ownerLoggedOut()
    }
}

/** Owner logs in: the companion comes over and says what it did. */
class CompanionLoginListener : LoginListener {
    override fun login(player: Player) {
        if (player is AIPlayer) return
        val c = Companions.of(player) ?: return
        // Wait a moment so the welcome lands after the login messages.
        GameWorld.Pulser.submit(object : Pulse(3) {
            override fun pulse(): Boolean {
                if (player.isActive) c.ownerLoggedIn(player)
                return true
            }
        })
    }
}

class CompanionLifecycle : StartupListener, ShutdownListener {
    override fun startup() {
        CompanionRequests.install()
        if (GameWorld.settings?.enabled_botting != true) return
        // Put companions that were working back to work once the world is running.
        GameWorld.Pulser.submit(object : Pulse(10) {
            override fun pulse(): Boolean {
                for (json in CompanionStore.allSaved()) {
                    if (json["working"] != true) continue
                    val ownerName = json["owner"] as? String ?: continue
                    if (Companions.of(ownerName) != null) continue
                    val c = CompanionStore.restore(json, null)
                    if (c.awaySince == null) c.awaySince = AwayReport.start(c.bot, c.lifetimeGathered)
                    c.startWork(c.job ?: WorkJob.bestFor(c.bot), announce = false)
                    log(CompanionLifecycle::class.java, Log.INFO, "Companion ${c.name} is back at work for $ownerName")
                }
                return true
            }
        })
    }

    override fun shutdown() {
        for (c in Companions.all) CompanionStore.save(c, working = c.owner == null || c.mode == CompanionBot.Mode.WORK)
    }
}
