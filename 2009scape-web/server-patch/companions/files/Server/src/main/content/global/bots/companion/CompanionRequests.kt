package content.global.bots.companion

import content.global.bots.companion.quest.QuestPlans
import core.game.bots.BotPacketTap
import core.game.node.entity.player.Player

/**
 * Understands what the owner asks for, typed in public chat ("I'd like to buy 200 lobsters",
 * "follow me", "go fishing") or after ::companion. Chat that isn't a request is ignored.
 */
object CompanionRequests {
    init {
        BotPacketTap.onPublicChat { player, message -> Companions.of(player)?.hear(message) }
    }

    /** Called once at startup so the chat listener is registered. */
    fun install() {}

    private val NUMBER = Regex("""^(\d+(?:\.\d+)?)([km]?)$""")

    /** "200" → 200, "2k" → 2000, "1.5m" → 1500000, "a"/"an"/"one" → 1. Null when it isn't an amount. */
    fun parseAmount(token: String): Int? {
        val t = token.lowercase().replace(",", "")
        if (t == "a" || t == "an" || t == "one") return 1
        val m = NUMBER.find(t) ?: return null
        val base = m.groupValues[1].toDouble()
        val mult = when (m.groupValues[2]) { "k" -> 1_000.0; "m" -> 1_000_000.0; else -> 1.0 }
        return (base * mult).toLong().coerceIn(0, Int.MAX_VALUE.toLong()).toInt()
    }

    /** Splits "200 raw lobsters" into (200, "raw lobsters"); "all your logs" into (null, "logs"). */
    private fun amountAndItem(rest: String): Pair<Int?, String> {
        var words = rest.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
        var amount: Int? = null
        if (words.isNotEmpty()) {
            val first = words[0]
            if (first == "all" || first == "every") words = words.drop(1)
            else parseAmount(first)?.let { amount = it; words = words.drop(1) }
        }
        words = words.dropWhile { it in setOf("of", "your", "the", "some", "any", "x") }
        return amount to words.joinToString(" ")
    }

    private fun clean(text: String, c: CompanionBot): String {
        var t = text.lowercase().replace(Regex("[^a-z0-9 ',.]"), " ").replace(Regex("\\s+"), " ").trim().trimEnd('.', ',')
        val n = c.name.lowercase()
        t = t.removePrefix("hey ").removePrefix("hi ").removePrefix("ok ").trim()
        if (t.startsWith(n)) t = t.removePrefix(n).trimStart(',', ':', ' ')
        // Drop trailing bits that don't change the request.
        t = t.replace(Regex("""\s+(please|pls|plz|from you|off you|for me|mate|buddy|$n)$"""), "")
        return t.trim()
    }

    private fun job(q: String) = WorkJob.find(q)

    private fun hint(job: WorkJob) = when (job) {
        WorkJob.WOODCUTTING -> "go chop trees"
        WorkJob.FISHING -> "go fishing"
        WorkJob.LOBSTERS -> "catch lobsters"
    }

    /** Returns true if [text] was a request it understood (and answered). */
    fun handle(c: CompanionBot, text: String, fromChat: Boolean): Boolean {
        val t = clean(text, c)
        if (t.isEmpty()) return false
        c.debug("heard \"$t\"")

        // A yes/no to the last quote.
        if (c.sale != null) {
            if (Regex("""^(yes|yeah|yep|yup|deal|ok|okay|sure|sounds good|go on|i'?ll take (it|them)|done)\b.*""").matches(t)) {
                val due = c.amountDue(c.sale!!)
                c.say(if (due == 0) "Great, accept my trade." else "Great, accept my trade and put in ${CompanionShop.coins(due)}.")
                c.offerTrade()
                return true
            }
            if (Regex("""^(no|nah|nope|never ?mind|cancel|too much|forget it)\b.*""").matches(t)) {
                c.sale = null
                c.say("No problem.")
                return true
            }
        }

        Regex("""\b(?:bring|deliver|fetch|run)(?: me| over| us)?\s+(.+?)(?:\s+(?:to me|here|over))?$""").find(t)?.let { m ->
            val (amount, named) = amountAndItem(m.groupValues[1])
            val item = named.ifBlank { null }
            quote(c, item ?: "", amount, deliver = true, sentence = t)
            return true
        }
        Regex("""^(?:.*\b)?(?:buy|purchase|sell me|sell you)\s+(.+?)(?:\s+(?:for|at)\s+.+)?$""").find(t)?.let { m ->
            val (amount, item) = amountAndItem(m.groupValues[1])
            if (item.isBlank()) return false
            quote(c, item, amount)
            return true
        }
        Regex("""^how (?:many|much) (.+?)(?: do you (?:have|got)| have you got| you got| are there)?$""").find(t)?.let { m ->
            if (m.groupValues[1] in setOf("is it", "for it", "for them", "are they")) return false
            stockQuery(c, amountAndItem(m.groupValues[1]).second)
            return true
        }
        Regex("""^(?:do you have|have you got|got|you got|any) (?:any )?(.+?)$""").find(t)?.let { m ->
            stockQuery(c, amountAndItem(m.groupValues[1]).second)
            return true
        }
        if (Regex("""^(what do you have|what have you got|what you got|what are you selling|what's for sale|stock|bank|what's in your bank|inventory|inv)$""").matches(t)) {
            listStock(c)
            return true
        }
        if (Regex("""^(follow|follow me|come|come here|come with me|come on|let'?s go|heel)$""").matches(t)) { c.follow(); return true }
        if (Regex("""^(stay|stay here|wait|wait here|stop|hold on)$""").matches(t)) { c.stay(); return true }
        if (Regex("""^(dismiss|go away|bye|goodbye|see you|see ya)$""").matches(t)) { c.dismiss(); return true }
        if (Regex("""^(what are you doing|status|what's up|whats up)$""").matches(t)) { c.say(status(c)); return true }
        if (Regex("""^(balance|my balance|what'?s my balance|how much (money |gold |coins )?(do i have|have i got)( left)?( with you)?|how much is left)$""").matches(t)) {
            c.say(if (c.balance > 0) "You have ${CompanionShop.coins(c.balance)} with me." else "You don't have any coins with me. Trade me some and I'll shop for you.")
            return true
        }

        Regex("""^(?:go |can you |could you |start |do some |go do some |go and )*(fish|fishing|chop|chopping|cut|woodcut|woodcutting|catch|net|work)\b\s*(?:some )?(.*)$""").find(t)?.let { m ->
            val what = (m.groupValues[1] + " " + m.groupValues[2]).trim()
            val chosen = job(m.groupValues[2]) ?: job(m.groupValues[1]) ?: if (m.groupValues[1] == "work") (c.job ?: WorkJob.bestFor(c.bot)) else null
            if (chosen == null) { c.say("I don't know how to $what yet."); return true }
            c.startWork(chosen)
            return true
        }
        Regex("""^(?:gather|collect|get) (?:the )?(?:items|stuff|things) for (.+)$""").find(t)?.let { m ->
            val plan = QuestPlans.findGather(m.groupValues[1])
            if (plan == null) c.say("I don't know what ${m.groupValues[1]} needs yet.") else c.startQuest(plan)
            return true
        }
        Regex("""^(?:let'?s do|help me with|help me do|do|start) (?:the )?(.+?)(?: quest)?$""").find(t)?.let { m ->
            val plan = QuestPlans.find(m.groupValues[1]) ?: return@let
            c.startQuest(plan)
            return true
        }
        Regex("""^(?:give me back|give back|return|hand back|give me) (?:my )?(.+)$""").find(t)?.let { m ->
            val (amount, item) = amountAndItem(m.groupValues[1])
            returnDeposit(c, item, amount)
            return true
        }
        if (!fromChat) c.say("Sorry, I didn't understand \"$text\".")
        return false
    }

    fun status(c: CompanionBot): String = when (c.mode) {
        CompanionBot.Mode.QUEST -> c.quest?.status ?: "Questing."
        CompanionBot.Mode.WORK -> c.work?.status ?: "Working."
        CompanionBot.Mode.STAY -> "Waiting here for you."
        CompanionBot.Mode.FOLLOW -> "Following you."
    }

    /** Quote a price for [query]. The owner accepts by trading (or saying deal). */
    fun quote(c: CompanionBot, query: String, wanted: Int?, deliver: Boolean = false, sentence: String = query) {
        val stock = CompanionShop.stock(c)
        val id = (if (query.isNotBlank()) CompanionShop.match(query, stock.keys) else null)
            ?: CompanionShop.mentionedIn(sentence, stock.keys)
        if (id == null) {
            val what = query.ifBlank {
                Regex("""\b(?:out of|need|want) (?:some |more )?([a-z ]+?)(?: can| could| would| so| and|$)""").find(sentence)?.groupValues?.get(1) ?: "of that"
            }
            val j = job(query.ifBlank { sentence })
            c.say("I don't have any $what." + (j?.let { " I can get some: say \"${hint(it)}\"." } ?: ""))
            c.sale = null
            return
        }
        val have = stock.getValue(id)
        val want = wanted ?: have
        if (want <= 0) return
        val n = minOf(want, have)
        val unit = CompanionShop.price(id)
        val total = (unit.toLong() * n).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        c.sale = CompanionBot.Sale(id, n, total)
        val each = "${CompanionShop.coins(unit)} each"
        if (deliver) {
            val due = c.amountDue(c.sale!!)
            val short = if (n < want) "I only have ${CompanionShop.describe(id, n)}. " else ""
            val pay = when {
                due == 0 -> "${CompanionShop.coins(total)} from your balance."
                c.balance > 0 -> "${CompanionShop.coins(total)}: your balance covers ${CompanionShop.coins(c.balance)}, have ${CompanionShop.coins(due)} ready."
                else -> "${CompanionShop.coins(total)} ($each), have the coins ready."
            }
            c.say("${short}On my way with ${CompanionShop.describe(id, n)}. $pay")
            c.startDelivery()
            return
        }
        if (n < want) c.say("I only have ${CompanionShop.describe(id, n)}. You can have them for ${CompanionShop.coins(total)} ($each).")
        else c.say("I can sell you ${CompanionShop.describe(id, n)} for ${CompanionShop.coins(total)} ($each).")
        c.say(payHint(c, c.sale!!))
    }

    /** How the owner pays: from their balance, partly, or with coins in the trade. */
    fun payHint(c: CompanionBot, sale: CompanionBot.Sale): String {
        val due = c.amountDue(sale)
        return when {
            c.balance <= 0 -> "Say deal, or trade me with the coins."
            due == 0 -> "Say deal and it comes out of your balance (${CompanionShop.coins(c.balance)})."
            else -> "Your balance covers ${CompanionShop.coins(c.balance)}. Say deal and put in the other ${CompanionShop.coins(due)}."
        }
    }

    private fun stockQuery(c: CompanionBot, query: String) {
        val stock = CompanionShop.stock(c)
        val id = CompanionShop.match(query, stock.keys)
        if (id == null) { c.say("I don't have any $query."); return }
        c.say("I have ${CompanionShop.describe(id, stock.getValue(id))}, ${CompanionShop.coins(CompanionShop.price(id))} each.")
    }

    fun listStock(c: CompanionBot) {
        val stock = CompanionShop.stock(c)
        if (stock.isEmpty()) { c.say("I don't have anything to sell yet."); return }
        val top = stock.entries.sortedByDescending { it.value * CompanionShop.price(it.key).toLong() }.take(6)
        c.say("I have " + top.joinToString { CompanionShop.describe(it.key, it.value) } + if (stock.size > 6) " and more." else ".")
    }

    private fun returnDeposit(c: CompanionBot, query: String, wanted: Int?) {
        val id = CompanionShop.match(query, c.deposits.keys)
        if (id == null) {
            val forSale = CompanionShop.match(query, CompanionShop.stock(c).keys)
            if (forSale != null) c.say("That's mine, but I'll sell it to you: say \"buy $query\".")
            else c.say("You didn't give me any $query.")
            return
        }
        val n = minOf(wanted ?: c.deposits.getValue(id), c.deposits.getValue(id))
        c.say("Here's your ${CompanionShop.describe(id, n)} back. Accept my trade.")
        c.giveBack(id, n)
    }

    /** Lets a test pretend the owner typed something. */
    fun simulateChat(owner: Player, message: String) = BotPacketTap.heard(owner, message)
}
