package content.global.bots.companion

import content.global.bots.companion.quest.BotWorld
import content.global.bots.companion.quest.QuestPlan
import content.global.bots.companion.quest.QuestRunner
import core.api.LogoutListener
import core.game.bots.AIPlayer
import core.game.bots.BotPacketTap
import core.game.bots.CombatBotAssembler
import core.game.bots.ScriptAPI
import core.game.node.entity.npc.NPC
import core.game.node.entity.player.Player
import core.game.node.entity.player.link.request.RequestType
import core.game.node.entity.player.link.request.trade.TradeModule
import core.game.system.task.Pulse
import core.game.world.GameWorld
import core.game.world.map.Location
import core.game.world.repository.Repository
import core.tools.Log
import core.api.log

/**
 * A player-like bot that belongs to one player: follows them, fights what they fight,
 * trades with them, and can do quests alongside them. Created with ::companion.
 */
class CompanionBot(val owner: Player, val bot: AIPlayer) {
    enum class Mode { FOLLOW, STAY, QUEST }

    var mode = Mode.FOLLOW
        private set
    var quest: QuestRunner? = null
        private set
    private val api = ScriptAPI(bot)
    private var pendingGive: Pair<Int, Int>? = null
    private var tradeCooldown = 0
    private var dismissed = false

    val name: String get() = bot.username

    init {
        bot.setAttribute(BotPacketTap.ATTR, true)
        bot.setAttribute("companion:owner", owner.username)
        bot.isHighPriority = true
        // Pocket money for quest shopping (a bucket, a pot...). It can be spent in shops but never
        // traded to a player, otherwise summon/give/dismiss would be an infinite coin source.
        bot.inventory.add(core.game.node.item.Item(COINS, STARTER_COINS))
        GameWorld.Pulser.submit(object : Pulse(1) {
            override fun pulse(): Boolean = tick()
        })
    }

    fun say(message: String) {
        api.sendChat(message.take(80))
        owner.sendMessage("<col=0040ff>[$name] $message</col>")
        if (verbose) log(CompanionBot::class.java, Log.INFO, "[companion $name] says: $message")
    }

    /** Set by ::companion debug: echo every bot decision to the server log and the owner's chatbox. */
    var verbose = false

    private fun debug(message: String) {
        if (!verbose) return
        log(CompanionBot::class.java, Log.INFO, "[companion $name] $message")
        owner.sendMessage("<col=808080>[$name debug] $message</col>")
    }

    fun follow() { stopQuest(); mode = Mode.FOLLOW; say("Right behind you!") }
    fun stay() { stopQuest(); mode = Mode.STAY; bot.walkingQueue.reset(); say("I'll wait here.") }

    fun startQuest(plan: QuestPlan) {
        if (plan.isComplete(bot)) { say("I've already done ${plan.displayName}."); return }
        quest = QuestRunner(bot, plan, ::say, ::debug)
        mode = Mode.QUEST
        say("Let's do ${plan.displayName}! Follow me.")
    }

    fun stopQuest() { quest = null; if (mode == Mode.QUEST) mode = Mode.FOLLOW }

    /** Coins the owner may take back: anything above the starter allowance it still holds. */
    fun transferableCoins(): Int {
        val coins = bot.inventory.getAmount(COINS)
        return (coins - minOf(STARTER_COINS, coins)).coerceAtLeast(0)
    }

    fun give(itemId: Int, amount: Int) {
        var n = amount
        if (itemId == COINS) {
            n = minOf(amount, transferableCoins())
            if (n <= 0) { say("That's my quest money, I can't hand it over."); return }
        }
        pendingGive = itemId to n
        tradeCooldown = 0
    }

    fun dismiss(message: String? = "See you later!") {
        if (dismissed) return
        dismissed = true
        message?.let { say(it) }
        Companions.forget(owner)
        BotPacketTap.forget(bot)
        AIPlayer.deregister(bot.uid)
    }

    private fun tick(): Boolean {
        if (dismissed) return true
        if (!owner.isActive || !Repository.players.contains(owner)) { dismiss(null); return true }
        if (!Repository.players.contains(bot)) {
            owner.sendMessage("<col=ff0000>Your companion $name has fallen. Use ::companion to call a new one.</col>")
            dismissed = true
            Companions.forget(owner)
            return true
        }
        if (tradeCooldown > 0) tradeCooldown--
        handleTrade()
        if (TradeModule.getExtension(bot) != null) return false

        when (mode) {
            Mode.QUEST -> {
                val runner = quest ?: run { mode = Mode.FOLLOW; null } ?: return false
                runner.tick()
                if (runner.state != QuestRunner.State.RUNNING) { quest = null; mode = Mode.FOLLOW }
            }
            Mode.FOLLOW -> { assistInCombat(); followOwner() }
            Mode.STAY -> assistInCombat()
        }
        return false
    }

    private fun assistInCombat() {
        val target = owner.properties.combatPulse.getVictim() as? NPC ?: return
        if (!target.isActive || target.skills.lifepoints <= 0) return
        if (bot.properties.combatPulse.getVictim() === target) return
        if (BotWorld.dist(bot.location, target.location) > 15) return
        bot.attack(target)
    }

    private fun followOwner() {
        if (bot.properties.combatPulse.isAttacking) return
        val distance = BotWorld.dist(bot.location, owner.location)
        if (bot.location.z != owner.location.z || distance > 30) {
            bot.properties.teleportLocation = owner.location.transform(1, 0, 0)
            return
        }
        if (distance <= 2 || bot.walkingQueue.isMoving || bot.pulseManager.hasPulseRunning()) return
        api.walkTo(owner.location.transform(listOf(-1, 1).random(), listOf(-1, 1).random(), 0))
    }

    private fun handleTrade() {
        val botTrade = TradeModule.getExtension(bot)
        if (botTrade == null) {
            if (tradeCooldown > 0) return
            val ownerAsked = owner.requestManager.target === bot &&
                owner.getAttribute<RequestType?>("lastRequest", null) === RequestType.TRADE
            if (ownerAsked || pendingGive != null) {
                bot.requestManager.request(owner, RequestType.TRADE)
                if (!ownerAsked) say("Accept my trade and I'll hand it over.")
                tradeCooldown = if (ownerAsked) 3 else 30
            }
            return
        }
        if (botTrade.target !== owner) { botTrade.decline(); return }
        val ownerTrade = TradeModule.getExtension(owner) ?: return
        pendingGive?.let { (id, amount) ->
            if (botTrade.stage == 0) {
                val slot = bot.inventory.getSlot(core.game.node.item.Item(id))
                val n = if (id == COINS) minOf(amount, transferableCoins()) else amount
                if (slot >= 0 && n > 0) botTrade.container?.offer(slot, n)
                pendingGive = null
            }
        }
        if (ownerTrade.isAccepted && !botTrade.isAccepted) botTrade.setAccepted(true, true)
    }
}

private const val COINS = org.rs09.consts.Items.COINS_995
private const val STARTER_COINS = 200

object Companions {
    private val byOwner = HashMap<String, CompanionBot>()

    fun of(owner: Player): CompanionBot? = byOwner[owner.username.lowercase()]

    fun forget(owner: Player) { byOwner.remove(owner.username.lowercase()) }

    fun summon(owner: Player): CompanionBot {
        of(owner)?.let { return it }
        val spot = owner.location.transform(1, 0, 0)
        val bot = CombatBotAssembler().produce(CombatBotAssembler.Type.MELEE, CombatBotAssembler.Tier.MED, spot)
            ?: AIPlayer(spot)
        val companion = CompanionBot(owner, bot)
        byOwner[owner.username.lowercase()] = companion
        return companion
    }

    @JvmStatic
    fun spawnForTesting(owner: Player, at: Location): CompanionBot {
        val bot = AIPlayer(at)
        return CompanionBot(owner, bot).also { byOwner[owner.username.lowercase()] = it }
    }
}

class CompanionLogoutListener : LogoutListener {
    override fun logout(player: Player) {
        Companions.of(player)?.dismiss(null)
    }
}
