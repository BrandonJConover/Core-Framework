#!/usr/bin/env bash
# Adds AI companions (player-like bots that follow, fight, trade and quest with you)
# to a 2009scape server checkout. Safe to run more than once.
#
#   ./apply.sh /path/to/2009scape        (the folder that contains Server/)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
if [[ -z "$TARGET" || ! -d "$TARGET/Server/src/main" ]]; then
    echo "Usage: $0 /path/to/2009scape   (folder containing Server/src/main)" >&2
    exit 1
fi

echo "Copying companion sources into $TARGET/Server/src/main ..."
cp -R "$HERE/files/Server/." "$TARGET/Server/"

REPO_FILE="$TARGET/Server/src/main/core/net/packet/PacketRepository.java"
if grep -q "BotPacketTap" "$REPO_FILE"; then
    echo "PacketRepository hook already present."
else
    echo "Hooking PacketRepository so bots can read dialogue text ..."
    (cd "$TARGET" && git apply --whitespace=nowarn "$HERE/bot-packet-tap.patch") || {
        echo "git apply failed; patching the one line with sed instead." >&2
        sed -i.bak 's#if(context.getPlayer() instanceof AIPlayer) return;#if(context.getPlayer() instanceof AIPlayer) { core.game.bots.BotPacketTap.tap(context); return; }#' "$REPO_FILE"
        grep -q "BotPacketTap" "$REPO_FILE" || { echo "Could not hook PacketRepository.java" >&2; exit 1; }
        rm -f "$REPO_FILE.bak"
    }
fi
PROC_FILE="$TARGET/Server/src/main/core/net/packet/PacketProcessor.kt"
if grep -q "BotPacketTap.heard" "$PROC_FILE"; then
    echo "PacketProcessor chat hook already present."
else
    echo "Hooking public chat so companions can hear their owner's requests ..."
    (cd "$TARGET" && git apply --whitespace=nowarn "$HERE/bot-chat-hook.patch") || {
        echo "git apply failed; adding the line with sed instead." >&2
        sed -i.bak 's#^\( *\)pkt.player.updateMasks.register(EntityFlag.Chat, ctx)$#&\n\1core.game.bots.BotPacketTap.heard(pkt.player, pkt.message)#' "$PROC_FILE"
        grep -q "BotPacketTap.heard" "$PROC_FILE" || { echo "Could not hook PacketProcessor.kt" >&2; exit 1; }
        rm -f "$PROC_FILE.bak"
    }
fi
echo "Done. Rebuild the server, make sure enable_bots = true in worldprops, then type ::companion in game."
