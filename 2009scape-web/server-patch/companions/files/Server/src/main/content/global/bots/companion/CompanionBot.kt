package content.global.bots.companion

import content.global.bots.companion.quest.BotWorld
import content.global.bots.companion.quest.QuestPlan
import content.global.bots.companion.quest.QuestRunner
import core.api.log
import core.game.bots.AIPlayer
import core.game.bots.BotPacketTap
import core.game.bots.CombatBotAssembler
import core.game.bots.ScriptAPI
import core.game.node.entity.npc.NPC
import core.game.node.entity.player.Player
import core.game.node.entity.player.link.request.RequestType
import core.game.node.entity.player.link.request.trade.TradeModule
import core.game.node.item.Item
import core.game.system.task.Pulse
import core.game.world.GameWorld
import core.game.world.map.Location
import core.game.world.repository.Repository
import core.tools.Log

/**
 * A player-like bot that belongs to one player. While the owner is online it follows them,
 * fights what they fight, trades with them, answers their chat requests and can do quests
 * alongside them. While the owner is offline it works a gathering job (woodcutting, fishing)
 * and banks what it gets, which the owner can then buy from it at Grand Exchange prices.
 */
class CompanionBot(val ownerName: String, var owner: Player?, val bot: AIPlayer) {
    enum class Mode { FOLLOW, STAY, QUEST, WORK }

    /** A quote the owner can accept by trading: these items (unnoted id to amount) for [total] coins. */
    data class Sale(val items: List<Pair<Int, Int>>, val total: Int) {
        constructor(itemId: Int, amount: Int, total: Int) : this(listOf(itemId to amount), total)
        fun has(id: Int) = items.any { it.first == id }
    }

    var mode = Mode.FOLLOW
        private set
    var quest: QuestRunner? = null
        private set
    var job: WorkJob? = null
    var work: WorkRunner? = null
        private set
    /** Items (and coins) the owner handed over, which they can take back for free. */
    val deposits = HashMap<Int, Int>()
    /** Everything it has gathered and banked, ever. */
    val lifetimeGathered = HashMap<Int, Int>()
    var sale: Sale? = null
    /** Set while the owner is logged out, so the login report can say what changed. */
    var awaySince: AwayReport? = null

    private val api = ScriptAPI(bot)
    private var pendingReturn: Pair<Int, Int>? = null
    private var tradeCooldown = 0
    private var tradeSnapshot: Map<Int, Int>? = null
    private var tradeComplainedShort = false
    private var tradeOffered = false
    private val requests = ArrayDeque<String>()
    private var dismissed = false
    private var ticks = 0

    val name: String get() = bot.username

    init {
        bot.setAttribute(BotPacketTap.ATTR, true)
        bot.setAttribute("companion:owner", ownerName)
        bot.isHighPriority = true
        GameWorld.Pulser.submit(object : Pulse(1) {
            override fun pulse(): Boolean = tick()
        })
    }

    /** Overhead chat, echoed to the owner's chatbox when they're online. */
    fun say(message: String) {
        api.sendChat(message.take(80))
        owner?.sendMessage("<col=0040ff>[$name] $message</col>")
        if (verbose) log(CompanionBot::class.java, Log.INFO, "[companion $name] says: $message")
    }

    /** Set by ::companion debug: echo every bot decision to the server log and the owner's chatbox. */
    var verbose = false

    fun debug(message: String) {
        if (!verbose) return
        log(CompanionBot::class.java, Log.INFO, "[companion $name] $message")
        owner?.sendMessage("<col=808080>[$name debug] $message</col>")
    }

    fun follow() { stopActivity(); mode = Mode.FOLLOW; say("Right behind you!") }
    fun stay() { stopActivity(); mode = Mode.STAY; bot.walkingQueue.reset(); say("I'll wait here.") }

    fun startQuest(plan: QuestPlan) {
        if (plan.isComplete(bot)) { say(plan.alreadyDoneMessage); return }
        stopActivity()
        quest = QuestRunner(bot, plan, ::say, ::debug)
        mode = Mode.QUEST
        say(plan.startMessage)
    }

    fun startWork(newJob: WorkJob, announce: Boolean = true) {
        val problem = newJob.cannotStart(bot)
        if (problem != null) { say(problem); return }
        stopActivity()
        job = newJob
        work = WorkRunner(this, newJob)
        mode = Mode.WORK
        if (announce) say(newJob.startMessage)
    }

    private fun stopActivity() {
        quest = null
        work = null
        bot.pulseManager.clear()
        if (mode == Mode.QUEST || mode == Mode.WORK) mode = Mode.FOLLOW
    }

    /** Queue a chat line from the owner; it's answered on the companion's next tick. */
    fun hear(message: String) { if (requests.size < 5) requests.addLast(message) }

    // ---- owner online / offline -------------------------------------------------------------

    fun ownerLoggedOut() {
        owner = null
        sale = null
        pendingReturn = null
        delivering = false
        TradeModule.getExtension(bot)?.decline()
        awaySince = AwayReport.start(bot, lifetimeGathered)
        if (mode != Mode.WORK) startWork(job ?: WorkJob.bestFor(bot), announce = false)
        CompanionStore.save(this)
    }

    fun ownerLoggedIn(player: Player) {
        owner = player
        val report = awaySince?.describe(bot, lifetimeGathered)
        awaySince = null
        stopActivity()
        mode = Mode.FOLLOW
        if (BotWorld.dist(bot.location, player.location) > 30 || bot.location.z != player.location.z)
            bot.properties.teleportLocation = player.location.transform(1, 0, 0)
        say("Welcome back, ${player.username}!")
        report?.let { say(it) }
    }

    // ---- selling and trading ----------------------------------------------------------------

    /** Ask the owner to accept a trade so it can hand back something they gave it. */
    fun giveBack(itemId: Int, amount: Int) {
        pendingReturn = itemId to amount
        tradeCooldown = 0
    }

    fun offerTrade() { tradeCooldown = 0; wantsTrade = true }

    /** Bringing [sale] to the owner; afterwards it goes back to [resumeJob] if it was working. */
    var delivering = false
        private set
    private var resumeJob: WorkJob? = null
    private var deliveryTicks = 0

    fun startDelivery() {
        if (!delivering) resumeJob = if (mode == Mode.WORK) job else null
        delivering = true
        deliveryTicks = 0
        bot.pulseManager.clear()
        bot.walkingQueue.reset()
    }

    private fun endDelivery(message: String? = null) {
        delivering = false
        message?.let { say(it) }
        val back = resumeJob
        resumeJob = null
        if (back != null) { startWork(back, announce = false); say("Back to ${back.label}.") }
    }

    /** Go to the owner (teleporting when far, like a home teleport) and open a trade there. */
    private fun deliveryTick() {
        val owner = this.owner ?: run { endDelivery(); return }
        if (sale == null) { endDelivery(); return }
        if (++deliveryTicks > 300) { sale = null; endDelivery("I'll hang on to them for now."); return }
        val distance = BotWorld.dist(bot.location, owner.location)
        if (bot.location.z != owner.location.z || distance > 30) {
            bot.properties.teleportLocation = owner.location.transform(1, 0, 0)
            return
        }
        if (distance > 3) {
            if (!bot.walkingQueue.isMoving) api.walkTo(owner.location.transform(1, 0, 0))
            return
        }
        if (TradeModule.getExtension(bot) == null && tradeCooldown == 0) wantsTrade = true
    }
    private var wantsTrade = false

    fun dismiss(message: String? = "See you later!") {
        if (dismissed) return
        message?.let { say(it) }
        CompanionStore.save(this, working = false)
        retire()
    }

    /** Remove from the world without saving (after a save, or on death). */
    fun retire() {
        dismissed = true
        Companions.forget(ownerName)
        BotPacketTap.forget(bot)
        if (Repository.players.contains(bot)) AIPlayer.deregister(bot.uid)
    }

    private fun tick(): Boolean {
        if (dismissed) return true
        ticks++
        val owner = this.owner
        if (owner != null && (!owner.isActive || !Repository.players.contains(owner))) {
            // Logged out without the listener firing (e.g. a test stand-in): treat it as a logout.
            ownerLoggedOut()
        }
        if (!Repository.players.contains(bot)) {
            this.owner?.sendMessage("<col=ff0000>Your companion $name has fallen. It'll be back in Lumbridge.</col>")
            Companions.revive(this)
            return true
        }
        if (ticks % 500 == 0) CompanionStore.save(this)
        if (tradeCooldown > 0) tradeCooldown--
        if (this.owner != null) {
            requests.removeFirstOrNull()?.let { CompanionRequests.handle(this, it, fromChat = true) }
            handleTrade()
            if (TradeModule.getExtension(bot) != null) return false
            if (delivering) { deliveryTick(); return false }
        }

        when (mode) {
            Mode.QUEST -> {
                val runner = quest ?: run { mode = Mode.FOLLOW; null } ?: return false
                runner.tick()
                if (runner.state != QuestRunner.State.RUNNING) { quest = null; mode = Mode.FOLLOW; runner.plan.onFinished?.invoke(this) }
            }
            Mode.WORK -> work?.tick() ?: run { mode = Mode.FOLLOW }
            Mode.FOLLOW -> { assistInCombat(); followOwner() }
            Mode.STAY -> assistInCombat()
        }
        return false
    }

    private fun assistInCombat() {
        val owner = this.owner ?: return
        val target = owner.properties.combatPulse.getVictim() as? NPC ?: return
        if (!target.isActive || target.skills.lifepoints <= 0) return
        if (bot.properties.combatPulse.getVictim() === target) return
        if (BotWorld.dist(bot.location, target.location) > 15) return
        bot.attack(target)
    }

    private fun followOwner() {
        val owner = this.owner ?: return
        if (bot.properties.combatPulse.isAttacking) return
        val distance = BotWorld.dist(bot.location, owner.location)
        if (bot.location.z != owner.location.z || distance > 30) {
            bot.properties.teleportLocation = owner.location.transform(1, 0, 0)
            return
        }
        if (distance <= 2 || bot.walkingQueue.isMoving || bot.pulseManager.hasPulseRunning()) return
        api.walkTo(owner.location.transform(listOf(-1, 1).random(), listOf(-1, 1).random(), 0))
    }

    private fun inventoryCounts(): Map<Int, Int> {
        val counts = HashMap<Int, Int>()
        for (item in bot.inventory.toArray()) if (item != null) counts.merge(item.id, item.amount, Int::plus)
        return counts
    }

    private fun handleTrade() {
        val owner = this.owner ?: return
        val botTrade = TradeModule.getExtension(bot)
        if (botTrade == null) {
            tradeSnapshot?.let { before -> settleTrade(before); tradeSnapshot = null }
            if (tradeCooldown > 0) return
            val ownerAsked = owner.requestManager.target === bot &&
                owner.getAttribute<RequestType?>("lastRequest", null) === RequestType.TRADE
            if (ownerAsked || pendingReturn != null || wantsTrade) {
                bot.requestManager.request(owner, RequestType.TRADE)
                if (!ownerAsked) say("Accept my trade request.")
                tradeCooldown = if (ownerAsked) 3 else 30
                wantsTrade = false
            }
            return
        }
        if (botTrade.target !== owner) { botTrade.decline(); return }
        val ownerTrade = TradeModule.getExtension(owner) ?: return
        if (tradeSnapshot == null) {
            // Move sold goods out of the bank first, so a declined trade leaves the books balanced.
            sale?.let { CompanionShop.prepare(this, it) }
            pendingReturn?.let { (id, n) -> CompanionShop.prepare(this, Sale(id, n, 0)) }
            tradeSnapshot = inventoryCounts()
            tradeOffered = false
            tradeComplainedShort = false
        }
        if (botTrade.stage == 0 && !tradeOffered) {
            tradeOffered = true
            sale?.items?.forEach { (id, n) -> CompanionShop.offer(this, botTrade, id, n) }
            pendingReturn?.let { (id, amount) ->
                CompanionShop.offer(this, botTrade, id, minOf(amount, deposits[id] ?: 0))
                pendingReturn = null
            }
        }
        val paid = ownerTrade.container?.getAmount(COINS) ?: 0
        val price = sale?.let { amountDue(it) } ?: 0
        if (paid < price) {
            if (ownerTrade.isAccepted && !tradeComplainedShort) {
                say("That's ${CompanionShop.coins(price - paid)} short. ${CompanionShop.coins(price)} in total, please.")
                tradeComplainedShort = true
            }
            if (botTrade.isAccepted) botTrade.setAccepted(false, true)
            return
        }
        if (ownerTrade.isAccepted && !botTrade.isAccepted) botTrade.setAccepted(true, true)
    }

    /** Coins the owner has left with it to spend on their behalf. */
    val balance: Int get() = deposits[COINS] ?: 0

    /** What the owner still has to put in the trade once their balance is used. */
    fun amountDue(s: Sale): Int = (s.total - minOf(balance, s.total)).coerceAtLeast(0)

    /** After a trade window closes: work out what changed hands and keep the ledgers right. */
    private fun settleTrade(before: Map<Int, Int>) {
        val after = inventoryCounts()
        val raw = (before.keys + after.keys).associateWith { (after[it] ?: 0) - (before[it] ?: 0) }
        val changed = HashMap<Int, Int>()
        for ((id, d) in raw) if (d != 0) changed.merge(CompanionShop.unnoted(id), d, Int::plus)
        if (changed.isEmpty()) return
        var coinsIn = changed.remove(COINS) ?: 0
        val s = sale
        val delivered = s != null && s.items.all { (id, n) -> (changed[id] ?: 0) <= -n }
        val finishDelivery = delivered && delivering
        var note: String? = null
        if (s != null && delivered) {
            val fromBalance = minOf(balance, s.total)
            coinsIn -= s.total - fromBalance
            adjustBalance(-fromBalance)
            sale = null
            note = if (fromBalance > 0) "Pleasure doing business! ${CompanionShop.coins(fromBalance)} came out of your balance, " +
                "${CompanionShop.coins(balance)} left." else "Pleasure doing business!"
        }
        if (coinsIn != 0) {
            adjustBalance(coinsIn)
            if (coinsIn > 0 && note == null) note = "Thanks! I'll keep that for you. Your balance is ${CompanionShop.coins(balance)}."
        }
        for ((id, d) in changed) {
            if (d > 0) deposits.merge(id, d, Int::plus)
            else if (d < 0 && (s == null || !s.has(id))) {
                val left = (deposits[id] ?: 0) + d
                if (left > 0) deposits[id] = left else deposits.remove(id)
            }
        }
        note?.let { say(it) }
        if (finishDelivery) endDelivery()
        CompanionStore.save(this)
    }

    private fun adjustBalance(by: Int) {
        val left = balance + by
        if (left > 0) deposits[COINS] = left else deposits.remove(COINS)
    }
}

const val COINS = org.rs09.consts.Items.COINS_995
const val STARTER_COINS = 200

object Companions {
    private val byOwner = HashMap<String, CompanionBot>()

    fun of(owner: Player): CompanionBot? = byOwner[owner.username.lowercase()]
    fun of(ownerName: String): CompanionBot? = byOwner[ownerName.lowercase()]
    val all: Collection<CompanionBot> get() = byOwner.values.toList()

    fun forget(ownerName: String) { byOwner.remove(ownerName.lowercase()) }

    fun register(c: CompanionBot) { byOwner[c.ownerName.lowercase()] = c }

    /** Bring back the saved companion, or make a new one next to the owner. */
    fun summon(owner: Player): CompanionBot {
        of(owner)?.let { return it }
        val spot = owner.location.transform(1, 0, 0)
        CompanionStore.load(owner.username)?.let { saved ->
            return CompanionStore.restore(saved, owner, spot)
        }
        val bot = CombatBotAssembler().produce(CombatBotAssembler.Type.MELEE, CombatBotAssembler.Tier.MED, spot)
            ?: AIPlayer(spot)
        // Pocket money for quest shopping (a bucket, a pot...). It can be spent in shops, but it is
        // never a deposit, so the owner can't take it, or summon a new companion to farm it.
        bot.inventory.add(Item(COINS, STARTER_COINS))
        val companion = CompanionBot(owner.username, owner, bot)
        register(companion)
        CompanionStore.save(companion)
        return companion
    }

    /** It died: start again in Lumbridge from its saved skills and bank, without its inventory. */
    fun revive(dead: CompanionBot) {
        CompanionStore.save(dead, dropInventory = true)
        dead.retire()
        val saved = CompanionStore.load(dead.ownerName) ?: return
        val c = CompanionStore.restore(saved, dead.owner, LUMBRIDGE)
        if (dead.owner == null) {
            c.awaySince = dead.awaySince
            dead.job?.let { c.startWork(it, announce = false) }
        }
    }

    val LUMBRIDGE: Location = Location(3222, 3218, 0)

    @JvmStatic
    fun spawnForTesting(owner: Player, at: Location): CompanionBot {
        val bot = AIPlayer(at)
        bot.inventory.add(Item(COINS, STARTER_COINS))
        return CompanionBot(owner.username, owner, bot).also { register(it) }
    }
}
