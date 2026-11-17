package core.game.bots

import core.game.node.entity.player.Player
import core.net.packet.Context
import core.net.packet.context.StringContext
import java.util.WeakHashMap

/**
 * Bots have no client, so outgoing packets for them are dropped in PacketRepository.
 * This tap keeps the interface strings sent to opted-in bots (attribute "bot:tap_strings")
 * so a bot script can read what a dialogue says and which options it offers.
 */
object BotPacketTap {
    const val ATTR = "bot:tap_strings"
    private val strings = WeakHashMap<Player, HashMap<Int, HashMap<Int, String>>>()

    @JvmStatic
    fun tap(context: Context) {
        val player = context.player ?: return
        if (context !is StringContext) return
        if (!player.getAttribute(ATTR, false)) return
        strings.getOrPut(player) { HashMap() }
            .getOrPut(context.interfaceId) { HashMap() }[context.lineId] = context.string ?: ""
    }

    @JvmStatic
    fun get(player: Player, interfaceId: Int, lineId: Int): String? = strings[player]?.get(interfaceId)?.get(lineId)

    @JvmStatic
    fun lines(player: Player, interfaceId: Int): Map<Int, String> = strings[player]?.get(interfaceId) ?: emptyMap()

    @JvmStatic
    fun forget(player: Player) {
        strings.remove(player)
    }
}
