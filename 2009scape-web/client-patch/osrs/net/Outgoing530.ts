/**
 * Outgoing530 — direct 530-native packet encoders for every interactive
 * action the player can take. Replaces the legacy putOpcode() allow-list
 * (which was 5 entries: keepalive + focus + AFK + chat + walk-remap) for
 * any game action that doesn't have a 1:1 377→530 wire shape match.
 *
 * Every method here writes the exact rt4-client byte layout for its
 * action, including the multi-endian "added" / "subtracted" / "middle"
 * encodings the protocol uses to scramble field ordering inside a packet.
 *
 * Encoder map (rt4-client MiniMenu.java + ClientProt.java):
 *
 *   NPC / Player / Loc / Obj actions are typically:
 *     opcode (ISAAC-encoded) + per-action payload of 2..16 bytes
 *
 *   Component (interface widget) actions add 4 bytes of componentId
 *     (parent << 16 | child) and 2 bytes of slot.
 *
 *   IF_BUTTON 1..10 collapse to ten distinct opcodes that all carry
 *     {p4(componentId), p2(slot)}.
 */

import { Buffer } from "./Buffer";

/**
 * Convenience wrapper. Each action checks its preconditions then calls
 * one of the put* helpers on a Buffer. Buffer's putOpcode530 path emits
 * the opcode through the ISAAC stream (server expects this), the
 * subsequent put* calls write the body in the specified encoding.
 */
export class Outgoing530 {
    /** NPC right-click action 1 (default — usually "Attack" / "Talk-to"). */
    static npcAction1(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, 78);
        Outgoing530.p2(buf, npcId);
    }

    /** NPC action 2 (varies — e.g. "Steal-from"). */
    static npcAction2(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, 27);
        Outgoing530.p2add(buf, npcId);
    }

    /** NPC action 3. */
    static npcAction3(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, 148);
        Outgoing530.p2add(buf, npcId);
    }

    /** NPC action 4. */
    static npcAction4(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, 30);
        Outgoing530.p2(buf, npcId);
    }

    /** NPC action 5. */
    static npcAction5(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, 218);
        Outgoing530.ip2(buf, npcId);
    }

    /** Examine an NPC (right-click → Examine). */
    static npcExamine(buf: Buffer, npcType: number): void {
        Outgoing530.putOpcode(buf, 72);
        Outgoing530.p2(buf, npcType);
    }

    /** Loc (game-object) right-click action 1 (default). */
    static locAction1(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, 254);
        Outgoing530.ip2(buf, sceneX);
        Outgoing530.p2add(buf, locId);
        Outgoing530.p2(buf, sceneZ);
    }

    /** Loc action 3. */
    static locAction3(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, 84);
        Outgoing530.ip2add(buf, locId);
        Outgoing530.ip2add(buf, sceneZ);
        Outgoing530.ip2(buf, sceneX);
    }

    /** Loc action 4. */
    static locAction4(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, 247);
        Outgoing530.ip2(buf, sceneZ);
        Outgoing530.ip2add(buf, sceneX);
        Outgoing530.p2(buf, locId);
    }

    /** Loc action 5. */
    static locAction5(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, 170);
        Outgoing530.ip2add(buf, locId);
        Outgoing530.ip2add(buf, sceneX);
        Outgoing530.ip2add(buf, sceneZ);
    }

    /** Item-in-component action 1 (default — usually "Wield" / "Use"). */
    static objAction1(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, 156);
        Outgoing530.ip2add(buf, slot);
        Outgoing530.p2add(buf, objId);
        Outgoing530.ip4(buf, componentId);
    }

    /** Item action 4 (e.g. "Drop"). */
    static objAction4(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, 161);
        Outgoing530.ip4(buf, componentId);
        Outgoing530.ip2add(buf, objId);
        Outgoing530.ip2add(buf, slot);
    }

    /** Item action 5. */
    static objAction5(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, 135);
        Outgoing530.p2add(buf, objId);
        Outgoing530.p2add(buf, slot);
        Outgoing530.mp4(buf, componentId);
    }

    /** Item operate (right-click "Operate" / context-specific). */
    static objOperate(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, 206);
        Outgoing530.p2add(buf, objId);
        Outgoing530.ip2(buf, slot);
        Outgoing530.ip4(buf, componentId);
    }

    /** Item examine. */
    static objExamine(buf: Buffer, objId: number): void {
        Outgoing530.putOpcode(buf, 92);
        Outgoing530.ip2add(buf, objId);
    }

    /** Equip an item from inventory. */
    static objEquip(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, 55);
        Outgoing530.ip2(buf, objId);
        Outgoing530.p2add(buf, slot);
        Outgoing530.imp4(buf, componentId);
    }

    /** Component-internal item action 1. */
    static objInComponentAction1(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, 81);
        Outgoing530.p2add(buf, slot);
        Outgoing530.p2(buf, objId);
        Outgoing530.imp4(buf, componentId);
    }

    /** Pick up a stacked ground-item. */
    static objstackAction1(buf: Buffer, sceneX: number, sceneZ: number, objId: number): void {
        Outgoing530.putOpcode(buf, 66);
        Outgoing530.ip2(buf, sceneX);
        Outgoing530.p2(buf, objId);
        Outgoing530.ip2add(buf, sceneZ);
    }

    /** Player trade request. */
    static playerTrade(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, 180);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Player action 5 (request assist). */
    static playerRequestAssist(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, 114);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Player action 6 (block / report). */
    static playerActionBlock(buf: Buffer, sceneX: number, sceneZ: number, playerIndex: number): void {
        Outgoing530.putOpcode(buf, 109);
        Outgoing530.ip2(buf, sceneZ);
        Outgoing530.p2(buf, sceneX);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** IF_BUTTON 1..10 — every interface button click. */
    static ifButton(buf: Buffer, action: number, componentId: number, slot: number): void {
        const opcode = Outgoing530.IF_BUTTON_OPCODES[action - 1];
        if (opcode === undefined) return;
        Outgoing530.putOpcode(buf, opcode);
        Outgoing530.p4(buf, componentId);
        Outgoing530.p2(buf, slot);
    }

    private static readonly IF_BUTTON_OPCODES: number[] = [
        155, // 1
        196, // 2
        124, // 3
        199, // 4
        234, // 5
        168, // 6
        166, // 7
        64,  // 8
        53,  // 9
        9,   // 10
    ];

    /** Close any modal interface (rt4 ClientProt.closeWidget). */
    static closeModal(buf: Buffer): void {
        Outgoing530.putOpcode(buf, 184);
    }

    /** Window status (size + render mode + AA). */
    static windowStatus(buf: Buffer, mode: number, w: number, h: number, antialias: number): void {
        Outgoing530.putOpcode(buf, 243);
        Outgoing530.p1(buf, mode);
        Outgoing530.p2(buf, w);
        Outgoing530.p2(buf, h);
        Outgoing530.p1(buf, antialias);
    }

    // ── Wire-encoding primitives (Buffer accessors) ─────────────────

    /**
     * Write the opcode through the ISAAC stream. Uses Buffer.putOpcode530
     * when present (direct write, no 377→530 remap). Falls back to the
     * generic putOpcode for buffer implementations that don't have the
     * companion yet.
     */
    private static putOpcode(buf: Buffer, opcode: number): void {
        const anyBuf = buf as any;
        if (typeof anyBuf.putOpcode530 === "function") {
            anyBuf.putOpcode530(opcode);
        } else {
            buf.putOpcode(opcode);
        }
    }

    private static p1(buf: Buffer, v: number): void {
        buf.putByte(v);
    }

    private static p2(buf: Buffer, v: number): void {
        buf.putShort(v);
    }

    private static p2add(buf: Buffer, v: number): void {
        buf.putShortAdded(v);
    }

    private static ip2(buf: Buffer, v: number): void {
        buf.putLEShort(v);
    }

    private static ip2add(buf: Buffer, v: number): void {
        buf.putLEShortAdded(v);
    }

    private static p4(buf: Buffer, v: number): void {
        buf.putInt(v);
    }

    private static ip4(buf: Buffer, v: number): void {
        buf.putLEInt(v);
    }

    /**
     * Middle-endian 32-bit (CDAB byte order). rt4 Buffer.mp4 emits bytes
     * as `b2 b3 b0 b1` — used by component-id fields in some opcodes.
     * Falls back to manual byte writes since the in-tree Buffer doesn't
     * expose a mp4 method.
     */
    private static mp4(buf: Buffer, v: number): void {
        buf.putByte((v >> 8)  & 0xFF);
        buf.putByte( v        & 0xFF);
        buf.putByte((v >> 24) & 0xFF);
        buf.putByte((v >> 16) & 0xFF);
    }

    /**
     * Inverse-middle-endian 32-bit (BADC byte order — `b1 b0 b3 b2`).
     */
    private static imp4(buf: Buffer, v: number): void {
        buf.putByte((v >> 16) & 0xFF);
        buf.putByte((v >> 24) & 0xFF);
        buf.putByte( v        & 0xFF);
        buf.putByte((v >> 8)  & 0xFF);
    }
}
