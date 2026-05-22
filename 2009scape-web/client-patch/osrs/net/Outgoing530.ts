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

import { ClientOpcode } from "./PacketConstants";
import type { Buffer } from "./Buffer";
import type { HuffmanCodec530 } from "../util/HuffmanCodec530";
import type Long from "long";

/**
 * Convenience wrapper. Each action checks its preconditions then calls
 * one of the put* helpers on a Buffer. Buffer's putOpcode530 path emits
 * the opcode through the ISAAC stream (server expects this), the
 * subsequent put* calls write the body in the specified encoding.
 */
export class Outgoing530 {
    /** NPC right-click action 1 (default — usually "Attack" / "Talk-to"). */
    static npcAction1(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.NPC_ACTION_1);
        Outgoing530.ip2(buf, npcId);
    }

    /** NPC action 2 (varies — e.g. "Steal-from"). */
    static npcAction2(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.NPC_ACTION_2);
        Outgoing530.ip2add(buf, npcId);
    }

    /** NPC action 3. */
    static npcAction3(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.NPC_ACTION_3);
        Outgoing530.p2add(buf, npcId);
    }

    /** NPC action 4. */
    static npcAction4(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.NPC_ACTION_4);
        Outgoing530.p2(buf, npcId);
    }

    /** NPC action 5. */
    static npcAction5(buf: Buffer, npcId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.NPC_ACTION_5);
        Outgoing530.ip2(buf, npcId);
    }

    /** Examine an NPC (right-click → Examine). */
    static npcExamine(buf: Buffer, npcType: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.EXAMINE_NPC);
        Outgoing530.p2(buf, npcType);
    }

    /** Loc (game-object) right-click action 1 (default). */
    static locAction1(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.SCENERY_ACTION_1);
        Outgoing530.ip2(buf, sceneX);
        Outgoing530.p2add(buf, locId);
        Outgoing530.p2(buf, sceneZ);
    }

    /** Loc action 2. */
    static locAction2(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.SCENERY_ACTION_2);
        Outgoing530.ip2add(buf, sceneZ);
        Outgoing530.ip2(buf, sceneX);
        Outgoing530.p2(buf, locId);
    }

    /** Loc action 3. */
    static locAction3(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.SCENERY_ACTION_3);
        Outgoing530.ip2add(buf, locId);
        Outgoing530.ip2add(buf, sceneZ);
        Outgoing530.ip2(buf, sceneX);
    }

    /** Loc action 4. */
    static locAction4(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.SCENERY_ACTION_4);
        Outgoing530.ip2(buf, sceneZ);
        Outgoing530.ip2add(buf, sceneX);
        Outgoing530.p2(buf, locId);
    }

    /** Loc action 5. */
    static locAction5(buf: Buffer, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.SCENERY_ACTION_5);
        Outgoing530.ip2add(buf, locId);
        Outgoing530.ip2add(buf, sceneX);
        Outgoing530.ip2add(buf, sceneZ);
    }

    /** Loc examine. */
    static locExamine(buf: Buffer, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.EXAMINE_SCENERY);
        Outgoing530.ip2add(buf, locId);
    }

    /** Item-in-component action 1 (default — usually "Wield" / "Use"). */
    static objAction1(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_ACTION_1);
        Outgoing530.ip2add(buf, slot);
        Outgoing530.p2add(buf, objId);
        Outgoing530.ip4(buf, componentId);
    }

    /** Item action 2 (inventory equip/wear in the 530 reference client). */
    static objAction2(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.objEquip(buf, slot, objId, componentId);
    }

    /** Item action 3. */
    static objAction3(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_ACTION_3);
        Outgoing530.ip4(buf, componentId);
        Outgoing530.ip2(buf, slot);
        Outgoing530.ip2(buf, objId);
    }

    /** Item action 4 (e.g. "Drop"). */
    static objAction4(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_ACTION_4);
        Outgoing530.ip4(buf, componentId);
        Outgoing530.ip2add(buf, objId);
        Outgoing530.ip2add(buf, slot);
    }

    /** Item action 5. */
    static objAction5(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_ACTION_5);
        Outgoing530.p2add(buf, objId);
        Outgoing530.p2add(buf, slot);
        Outgoing530.mp4(buf, componentId);
    }

    /** Item operate (right-click "Operate" / context-specific). */
    static objOperate(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_OPERATE);
        Outgoing530.p2add(buf, objId);
        Outgoing530.ip2(buf, slot);
        Outgoing530.ip4(buf, componentId);
    }

    /** Item examine. */
    static objExamine(buf: Buffer, objId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.EXAMINE_ITEM);
        Outgoing530.ip2add(buf, objId);
    }

    /** Equip an item from inventory. */
    static objEquip(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_ACTION_2);
        Outgoing530.ip2(buf, objId);
        Outgoing530.p2add(buf, slot);
        Outgoing530.imp4(buf, componentId);
    }

    /** Component-internal item action 1. */
    static objInComponentAction1(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_IN_COMPONENT_ACTION_1);
        Outgoing530.p2add(buf, slot);
        Outgoing530.p2(buf, objId);
        Outgoing530.imp4(buf, componentId);
    }

    /** Component-internal item action 2. */
    static objInComponentAction2(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_IN_COMPONENT_ACTION_2);
        Outgoing530.ip2(buf, slot);
        Outgoing530.imp4(buf, componentId);
        Outgoing530.ip2add(buf, objId);
    }

    /** Component-internal item action 3. */
    static objInComponentAction3(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_IN_COMPONENT_ACTION_3);
        Outgoing530.imp4(buf, componentId);
        Outgoing530.p2(buf, slot);
        Outgoing530.p2add(buf, objId);
    }

    /** Component-internal item action 5. */
    static objInComponentAction5(buf: Buffer, slot: number, objId: number, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ITEM_IN_COMPONENT_ACTION_5);
        Outgoing530.p4(buf, componentId);
        Outgoing530.p2add(buf, slot);
        Outgoing530.ip2(buf, objId);
    }

    /** Pick up a stacked ground-item. */
    static objstackAction1(buf: Buffer, sceneX: number, sceneZ: number, objId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.GROUND_ITEM_ACTION_1);
        Outgoing530.ip2(buf, sceneX);
        Outgoing530.p2(buf, objId);
        Outgoing530.ip2add(buf, sceneZ);
    }

    /** Ground-item action 2. */
    static objstackAction2(buf: Buffer, sceneX: number, sceneZ: number, objId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.GROUND_ITEM_ACTION_2);
        Outgoing530.p2(buf, objId);
        Outgoing530.p2(buf, sceneX);
        Outgoing530.ip2(buf, sceneZ);
    }

    /** Ground-item action 5. */
    static objstackAction5(buf: Buffer, sceneX: number, sceneZ: number, objId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.GROUND_ITEM_ACTION_5);
        Outgoing530.p2add(buf, sceneX);
        Outgoing530.ip2add(buf, objId);
        Outgoing530.ip2(buf, sceneZ);
    }

    /** Player action 1. */
    static playerAction1(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.PLAYER_ACTION_1);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Player follow action. */
    static playerFollow(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.PLAYER_ACTION_FOLLOW);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Player trade request. */
    static playerTrade(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.PLAYER_ACTION_TRADE);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Player request-assist action. */
    static playerRequestAssist(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.PLAYER_REQ_ASSIST);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Player action 5 from MiniMenu.PLAYER_ACTION_5. */
    static playerAction5(buf: Buffer, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.PLAYER_ACTION_5);
        Outgoing530.p2add(buf, playerIndex);
    }

    /** Player action 6 (block / report). */
    static playerActionBlock(buf: Buffer, sceneX: number, sceneZ: number, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.PLAYER_ACTION_BLOCK);
        Outgoing530.ip2(buf, sceneZ);
        Outgoing530.p2(buf, sceneX);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Use selected inventory item on another item. */
    static useOnItem(
        buf: Buffer,
        selectedSlot: number,
        selectedObjId: number,
        selectedComponentId: number,
        targetSlot: number,
        targetObjId: number,
        targetComponentId: number,
    ): void {
        Outgoing530.putOpcode(buf, ClientOpcode.USE_ON_ITEM);
        Outgoing530.p2(buf, selectedSlot);
        Outgoing530.ip4(buf, targetComponentId);
        Outgoing530.ip2(buf, targetSlot);
        Outgoing530.ip4(buf, selectedComponentId);
        Outgoing530.ip2add(buf, selectedObjId);
        Outgoing530.ip2add(buf, targetObjId);
    }

    /** Use selected inventory item on an NPC. */
    static useOnNpc(buf: Buffer, selectedSlot: number, selectedObjId: number, selectedComponentId: number, npcIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.USE_ON_NPC);
        Outgoing530.mp4(buf, selectedComponentId);
        Outgoing530.ip2(buf, selectedSlot);
        Outgoing530.ip2(buf, npcIndex);
        Outgoing530.ip2add(buf, selectedObjId);
    }

    /** Use selected inventory item on a player. */
    static useOnPlayer(buf: Buffer, selectedSlot: number, selectedObjId: number, selectedComponentId: number, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.USE_ON_PLAYER);
        Outgoing530.ip2add(buf, playerIndex);
        Outgoing530.p2(buf, selectedObjId);
        Outgoing530.p2(buf, selectedSlot);
        Outgoing530.mp4(buf, selectedComponentId);
    }

    /** Use selected inventory item on a loc. */
    static useOnLoc(buf: Buffer, selectedSlot: number, selectedObjId: number, selectedComponentId: number, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.USE_ON_SCENERY);
        Outgoing530.p2add(buf, sceneX);
        Outgoing530.p2(buf, selectedObjId);
        Outgoing530.ip2(buf, sceneZ);
        Outgoing530.p2(buf, selectedSlot);
        Outgoing530.mp4(buf, selectedComponentId);
        Outgoing530.p2add(buf, locId);
    }

    /** Use selected inventory item on a ground item. */
    static useOnGroundItem(buf: Buffer, selectedSlot: number, selectedObjId: number, selectedComponentId: number, sceneX: number, sceneZ: number, objId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.USE_ON_GROUND_ITEM);
        Outgoing530.ip2add(buf, sceneX);
        Outgoing530.ip2(buf, selectedSlot);
        Outgoing530.ip2(buf, selectedObjId);
        Outgoing530.ip2(buf, objId);
        Outgoing530.ip2add(buf, sceneZ);
        Outgoing530.mp4(buf, selectedComponentId);
    }

    /** Use selected component target on an NPC. */
    static componentNpcAction(buf: Buffer, selectedSlot: number, selectedComponentId: number, npcIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.COMPONENT_NPC_ACTION);
        Outgoing530.ip4(buf, selectedComponentId);
        Outgoing530.p2add(buf, selectedSlot);
        Outgoing530.ip2add(buf, npcIndex);
    }

    /** Use selected component target on an item. */
    static componentObjAction(buf: Buffer, selectedSlot: number, selectedComponentId: number, targetSlot: number, targetObjId: number, targetComponentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.COMPONENT_ITEM_ACTION);
        Outgoing530.ip4(buf, selectedComponentId);
        Outgoing530.ip2add(buf, targetSlot);
        Outgoing530.ip4(buf, targetComponentId);
        Outgoing530.p2add(buf, targetObjId);
        Outgoing530.ip2(buf, selectedSlot);
    }

    /** Use selected component target on a loc. */
    static componentLocAction(buf: Buffer, selectedSlot: number, selectedComponentId: number, sceneX: number, sceneZ: number, locId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.COMPONENT_SCENERY_ACTION);
        Outgoing530.ip2add(buf, sceneZ);
        Outgoing530.p2add(buf, sceneX);
        Outgoing530.ip2add(buf, selectedSlot);
        Outgoing530.imp4(buf, selectedComponentId);
        Outgoing530.p2add(buf, locId);
    }

    /** Use selected component target on a player. */
    static componentPlayerAction(buf: Buffer, selectedSlot: number, selectedComponentId: number, playerIndex: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.COMPONENT_PLAYER_ACTION);
        Outgoing530.p2add(buf, selectedSlot);
        Outgoing530.ip4(buf, selectedComponentId);
        Outgoing530.ip2add(buf, playerIndex);
    }

    /** Use selected component target on a ground item. */
    static componentGroundItemAction(buf: Buffer, selectedSlot: number, selectedComponentId: number, sceneX: number, sceneZ: number, objId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.COMPONENT_GROUND_ITEM_ACTION);
        Outgoing530.imp4(buf, selectedComponentId);
        Outgoing530.p2(buf, sceneZ);
        Outgoing530.ip2add(buf, objId);
        Outgoing530.ip2add(buf, sceneX);
        Outgoing530.ip2(buf, selectedSlot);
    }

    /** IF_BUTTON 1..10 — every interface button click. */
    static ifButton(buf: Buffer, action: number, componentId: number, slot: number): void {
        const opcode = Outgoing530.IF_BUTTON_OPCODES[action - 1];
        if (opcode === undefined) return;
        Outgoing530.putOpcode(buf, opcode);
        Outgoing530.p4(buf, componentId);
        Outgoing530.p2(buf, slot);
    }

    /** IF CS2 action (rt4 UNKNOWN_8/LOGOUT_ACTION-style component click). */
    static ifCs2(buf: Buffer, componentId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.IF_CS2);
        Outgoing530.p4(buf, componentId);
    }

    /** Continue dialogue / click-to-continue component action. */
    static continueDialogue(buf: Buffer, componentId: number, slot: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.CONTINUE_DIALOGUE);
        Outgoing530.imp4(buf, componentId);
        Outgoing530.ip2(buf, slot);
    }

    /** CS2 dialogue option action (rt4 script opcode 3110). */
    static dialogAction(buf: Buffer, actionId: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.DIALOG_ACTION);
        Outgoing530.p2(buf, actionId);
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
        Outgoing530.putOpcode(buf, ClientOpcode.CLOSE_IFACE);
    }

    /** Window status (size + render mode + AA). */
    static windowStatus(buf: Buffer, mode: number, w: number, h: number, antialias: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.DISPLAY_UPDATE);
        Outgoing530.p1(buf, mode);
        Outgoing530.p2(buf, w);
        Outgoing530.p2(buf, h);
        Outgoing530.p1(buf, antialias);
    }

    /** Public chat message (rt4 ClientProt.MESSAGE_PUBLIC, opcode 237). */
    static publicChat(buf: Buffer, colour: number, effect: number, message: string, huffman: HuffmanCodec530 | null): void {
        const body: number[] = [];
        body.push(colour & 0xFF, effect & 0xFF);
        const text = message || "";
        const plain = new Uint8Array(Math.min(80, text.length));
        for (let i = 0; i < plain.length; i++) plain[i] = text.charCodeAt(i) & 0xFF;
        Outgoing530.pushSmart(body, plain.length);
        if (huffman) {
            const encoded = new Uint8Array(Math.max(8, plain.length * 2 + 8));
            const n = huffman.encode(plain.length, plain, 0, encoded, 0);
            for (let i = 0; i < n; i++) body.push(encoded[i] & 0xFF);
        } else {
            for (let i = 0; i < plain.length; i++) body.push(plain[i] & 0xFF);
        }
        Outgoing530.putOpcode(buf, ClientOpcode.CHAT_MESSAGE);
        Outgoing530.p1(buf, body.length);
        for (let i = 0; i < body.length; i++) Outgoing530.p1(buf, body[i]);
    }

    /** Add a player to the friends list. */
    static addFriend(buf: Buffer, name37: Long): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ADD_FRIEND);
        Outgoing530.p8(buf, name37);
    }

    /** Remove a player from the friends list. */
    static removeFriend(buf: Buffer, name37: Long): void {
        Outgoing530.putOpcode(buf, ClientOpcode.REMOVE_FRIEND);
        Outgoing530.p8(buf, name37);
    }

    /** Add a player to the ignore list. */
    static addIgnore(buf: Buffer, name37: Long): void {
        Outgoing530.putOpcode(buf, ClientOpcode.ADD_IGNORE);
        Outgoing530.p8(buf, name37);
    }

    /** Remove a player from the ignore list. */
    static removeIgnore(buf: Buffer, name37: Long): void {
        Outgoing530.putOpcode(buf, ClientOpcode.REMOVE_IGNORE);
        Outgoing530.p8(buf, name37);
    }

    /** Private message (rt4 ClientProt.MESSAGE_PRIVATE, opcode 201). */
    static privateMessage(buf: Buffer, recipient37: Long, message: string, huffman: HuffmanCodec530 | null): void {
        const body: number[] = [];
        Outgoing530.pushP8(body, recipient37);
        const text = message || "";
        const plain = new Uint8Array(Math.min(80, text.length));
        for (let i = 0; i < plain.length; i++) plain[i] = text.charCodeAt(i) & 0xFF;
        Outgoing530.pushSmart(body, plain.length);
        if (huffman) {
            const encoded = new Uint8Array(Math.max(8, plain.length * 2 + 8));
            const n = huffman.encode(plain.length, plain, 0, encoded, 0);
            for (let i = 0; i < n; i++) body.push(encoded[i] & 0xFF);
        } else {
            for (let i = 0; i < plain.length; i++) body.push(plain[i] & 0xFF);
        }
        Outgoing530.putOpcode(buf, ClientOpcode.PRIVATE_MESSAGE);
        Outgoing530.p1(buf, body.length);
        for (let i = 0; i < body.length; i++) Outgoing530.p1(buf, body[i]);
    }

    /** Chat filter settings: public, private, trade. */
    static chatSettings(buf: Buffer, publicFilter: number, privateFilter: number, tradeFilter: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.CHAT_SETTINGS);
        Outgoing530.p1(buf, publicFilter);
        Outgoing530.p1(buf, privateFilter);
        Outgoing530.p1(buf, tradeFilter);
    }

    /** Developer/player command line beginning with "::" in the chatbox. */
    static command(buf: Buffer, commandLine: string): void {
        const command = commandLine.startsWith("::") ? commandLine.substring(2) : commandLine;
        Outgoing530.putOpcode(buf, ClientOpcode.COMMAND);
        Outgoing530.p1(buf, command.length + 1);
        Outgoing530.pjstr(buf, command);
    }

    /** Resume integer input prompt. */
    static resumeCountDialog(buf: Buffer, value: number): void {
        Outgoing530.putOpcode(buf, ClientOpcode.RESUME_COUNT_DIALOG);
        Outgoing530.p4(buf, value);
    }

    /** Resume name input prompt. */
    static resumeNameDialog(buf: Buffer, name37: Long): void {
        Outgoing530.putOpcode(buf, ClientOpcode.RESUME_NAME_DIALOG);
        Outgoing530.p8(buf, name37);
    }

    /** Resume string input prompt. */
    static resumeStringDialog(buf: Buffer, value: string): void {
        const text = value || "";
        Outgoing530.putOpcode(buf, ClientOpcode.RESUME_STRING_DIALOG);
        Outgoing530.p1(buf, text.length + 1);
        Outgoing530.pjstr(buf, text);
    }

    /** Report abuse / bug-report packet from rt4 script opcode 5002. */
    static bugReport(buf: Buffer, name37: Long, category: number, mute: boolean): void {
        Outgoing530.putOpcode(buf, ClientOpcode.BUG_REPORT);
        Outgoing530.p8(buf, name37);
        Outgoing530.p1(buf, category - 1);
        Outgoing530.p1(buf, mute ? 1 : 0);
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

    private static pjstr(buf: Buffer, value: string): void {
        buf.putString(value);
    }

    private static pushSmart(out: number[], value: number): void {
        if (value < 128) {
            out.push(value & 0xFF);
        } else {
            out.push(((value >> 8) | 128) & 0xFF, value & 0xFF);
        }
    }

    private static pushP8(out: number[], value: Long): void {
        const high = value.high | 0;
        const low = value.low | 0;
        out.push((high >> 24) & 0xFF, (high >> 16) & 0xFF, (high >> 8) & 0xFF, high & 0xFF);
        out.push((low >> 24) & 0xFF, (low >> 16) & 0xFF, (low >> 8) & 0xFF, low & 0xFF);
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

    private static p8(buf: Buffer, v: Long): void {
        buf.putInt(v.high);
        buf.putInt(v.low);
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
