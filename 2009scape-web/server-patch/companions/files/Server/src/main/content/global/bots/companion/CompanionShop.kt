package content.global.bots.companion

import core.cache.def.impl.ItemDefinition
import core.game.ge.GrandExchange
import core.game.node.entity.player.link.request.trade.TradeModule
import core.game.node.item.Item

/**
 * The companion's stall: what it has to sell (inventory plus bank), what it costs
 * (the Grand Exchange guide price), and getting the goods into a trade window.
 */
object CompanionShop {
    private val TOOLS: Set<Int> by lazy { WorkJob.values().flatMap { it.tools }.toSet() }

    fun isTool(id: Int) = unnoted(id) in TOOLS

    fun unnoted(id: Int): Int {
        val def = ItemDefinition.forId(id) ?: return id
        return if (!def.isUnnoted && def.noteId > 0) def.noteId else id
    }

    private fun noted(id: Int): Int? {
        val def = ItemDefinition.forId(id) ?: return null
        return if (def.isUnnoted && def.noteId > 0 && !def.isStackable) def.noteId else null
    }

    /** Everything it could sell, by unnoted id. Coins, tools and worn gear aren't for sale. */
    fun stock(c: CompanionBot): Map<Int, Int> {
        val counts = HashMap<Int, Int>()
        for (item in c.bot.inventory.toArray()) if (item != null) counts.merge(unnoted(item.id), item.amount, Int::plus)
        for (item in c.bot.bank.toArray()) if (item != null) counts.merge(unnoted(item.id), item.amount, Int::plus)
        counts.remove(COINS)
        counts.keys.removeAll { it in TOOLS }
        return counts.filterValues { it > 0 }
    }

    fun price(id: Int): Int {
        val ge = try { GrandExchange.getRecommendedPrice(id) } catch (e: Exception) { 0 }
        return maxOf(1, if (ge > 0) ge else ItemDefinition.forId(id)?.value ?: 1)
    }

    fun name(id: Int): String = ItemDefinition.forId(id)?.name ?: "item $id"

    /** "200 raw lobsters", "1 egg". */
    fun describe(id: Int, n: Int): String {
        val base = name(id).lowercase()
        val plural = if (n == 1 || base.endsWith("s")) base else base + "s"
        return "${"%,d".format(n)} $plural"
    }

    /** 950, 2k, 12.5k, 1.2m, 49,952: short like players write prices, but never rounded. */
    fun coins(n: Int): String = when {
        n >= 1_000_000 && n % 100_000 == 0 -> trim(n / 1_000_000.0) + "m"
        n >= 1000 && n % 100 == 0 -> trim(n / 1000.0) + "k"
        else -> "%,d".format(n)
    }

    private fun trim(v: Double): String = if (v % 1.0 == 0.0) v.toLong().toString() else "%.1f".format(v).removeSuffix(".0")

    /**
     * Best match for what the owner asked for, among the items it has; null when nothing fits.
     * "lobsters" matches Lobster (exact) before Raw lobster (ends with), before anything containing it.
     */
    fun match(query: String, items: Collection<Int>): Int? = matchScored(query, items)?.first

    /** An item named anywhere in a sentence ("I'm out of lobsters, can you bring me 12?"). */
    fun mentionedIn(sentence: String, items: Collection<Int>): Int? =
        sentence.split(" ").filter { it.length >= 4 }
            .mapNotNull { w -> matchScored(w, items)?.takeIf { it.second >= 2 } }
            .maxByOrNull { it.second }?.first

    fun matchScored(query: String, items: Collection<Int>): Pair<Int, Int>? {
        val forms = singulars(query)
        var best: Int? = null
        var bestScore = 0
        for (id in items) {
            val n = name(id).lowercase()
            val score = forms.maxOf { f ->
                when {
                    n == f -> 4
                    n == "raw $f" -> 3
                    n.endsWith(" $f") || n.endsWith(" ${f}s") -> 2
                    n.contains(f) -> 1
                    else -> 0
                }
            }
            if (score > bestScore) { best = id; bestScore = score }
        }
        return best?.let { it to bestScore }
    }

    fun singulars(query: String): List<String> {
        val q = query.trim().lowercase().removePrefix("some ").removePrefix("any ").removePrefix("the ").removePrefix("your ").trim()
        return listOfNotNull(
            q,
            if (q.endsWith("ies")) q.dropLast(3) + "y" else null,
            if (q.endsWith("es")) q.dropLast(2) else null,
            if (q.endsWith("s")) q.dropLast(1) else null,
        ).filter { it.isNotBlank() }.distinct()
    }

    /** Make sure [Sale.amount] of the item is in the inventory, taking it out of the bank as notes. */
    fun prepare(c: CompanionBot, sale: CompanionBot.Sale) {
        for ((itemId, amount) in sale.items) prepare(c, itemId, amount)
    }

    private fun prepare(c: CompanionBot, itemId: Int, amount: Int) {
        val inv = c.bot.inventory
        val notedId = noted(itemId)
        val have = inv.getAmount(itemId) + (notedId?.let { inv.getAmount(it) } ?: 0)
        val need = amount - have
        if (need <= 0) return
        val take = minOf(need, c.bot.bank.getAmount(itemId))
        if (take <= 0) return
        val asItem = if (notedId != null) Item(notedId, take) else Item(itemId, minOf(take, inv.freeSlots()))
        if (asItem.amount <= 0) return
        if (c.bot.bank.remove(Item(itemId, asItem.amount))) inv.add(asItem)
    }

    /** Put [amount] of an item (noted or not) from the companion's inventory into the trade window. */
    fun offer(c: CompanionBot, trade: TradeModule, itemId: Int, amount: Int) {
        var left = amount
        if (left <= 0) return
        val container = trade.container ?: return
        val ids = listOfNotNull(noted(itemId), itemId).distinct()
        for (id in ids) {
            while (left > 0) {
                val slot = c.bot.inventory.getSlot(Item(id))
                if (slot < 0) break
                val n = minOf(left, c.bot.inventory.get(slot).amount)
                val before = container.getAmount(id)
                container.offer(slot, n)
                val moved = container.getAmount(id) - before
                if (moved <= 0) break
                left -= moved
            }
        }
        if (left > 0) c.debug("couldn't put $left x ${name(itemId)} in the trade")
    }
}

object CompanionSale {
    /** Quote several items as one deal, e.g. everything a quest needs. */
    fun offerBundle(c: CompanionBot, items: List<Pair<Int, Int>>) {
        val have = items.filter { (id, n) -> CompanionShop.stock(c)[id] ?: 0 >= n }
        if (have.isEmpty()) return
        val total = have.sumOf { (id, n) -> CompanionShop.price(id).toLong() * n }.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        c.sale = CompanionBot.Sale(have, total)
        c.say("I have " + have.joinToString { (id, n) -> CompanionShop.describe(id, n) } + ". All of it for ${CompanionShop.coins(total)}.")
        c.say(CompanionRequests.payHint(c, c.sale!!))
    }
}
