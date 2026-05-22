/**
 * PacketHandler530 - Native rev 530 packet handlers.
 *
 * Handles all 46 opcodes the 2009scape server actually emits. For each packet
 * we either (a) update game state or (b) consume the exact payload so the stream
 * stays aligned. The parent parseIncomingPacket has already read `size` bytes
 * into `buf` starting at position 0 — our job is to advance `buf.currentPosition`
 * to `size` before returning true.
 */
import { Buffer } from "./net/Buffer";
import { ObjStack, ProjAnim, SpotAnim } from "./cache/def/ObjStackNode";
import { TextUtils } from "./util/TextUtils";
import { ChatFilterSettings } from "./util/ChatFilterSettings";
import { ClanState, PrivateMessage } from "./util/PrivateMessageQueue";
import { SoundPlayer } from "./sound/SoundPlayer";
import { MusicPlayer } from "./sound/MusicPlayer";
import { InterfaceList } from "./InterfaceList";
import { runClientScript, ClientScript530Data, Cs2Hooks } from "./script/ClientScript530";
import { HuffmanCodec530, decodeQuickChatString } from "./util/HuffmanCodec530";
import { applyAppearanceMask } from "./media/renderable/PlayerAppearance530";
import Long from "long";

export class PacketHandler530 {
    private static equipmentObjIds530: number[] | null = null;
    private static readonly LOC_LAYERS = [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3];

    static handle(opcode530: number, buf: Buffer, size: number, game: any): boolean {
        const startPos = buf.currentPosition;
        const handler = this.handlerName(opcode530);
        try {
            const ok = this.dispatch(opcode530, buf, size, game);
            this.tracePacket(game, {
                opcode: opcode530,
                handler,
                size,
                consumed: buf.currentPosition - startPos,
                ok,
                error: null,
            });
            return ok;
        } catch (e) {
            // Any handler error: realign to the end of this packet and keep going.
            buf.currentPosition = startPos + (size > 0 ? size : 0);
            this.tracePacket(game, {
                opcode: opcode530,
                handler,
                size,
                consumed: buf.currentPosition - startPos,
                ok: true,
                error: (e as Error)?.message || String(e),
            });
            return true;
        }
    }

    private static tracePacket(game: any, entry: any) {
        if (!game) return;
        const enabled = !!game.debugPackets530 || !!(globalThis as any).DEBUG_PACKETS_530;
        if (!enabled) return;
        if (!game.packetTrace530) game.packetTrace530 = [];
        const trace = game.packetTrace530;
        trace.push({ ...entry, cycle: game.pulseCycle ?? game.loopCycle ?? 0 });
        if (trace.length > 200) trace.splice(0, trace.length - 200);
        if (entry.error) {
            console.log("[Packet530] handler error opcode=" + entry.opcode + " handler=" + entry.handler + " size=" + entry.size + " consumed=" + entry.consumed + " error=" + entry.error);
        } else if (entry.consumed !== entry.size && entry.size >= 0) {
            console.log("[Packet530] size mismatch opcode=" + entry.opcode + " handler=" + entry.handler + " size=" + entry.size + " consumed=" + entry.consumed);
        }
    }

    private static traceContainer(game: any, entry: any) {
        if (!game) return;
        if (!game.containerTrace530) game.containerTrace530 = [];
        const trace = game.containerTrace530;
        trace.push({ ...entry, cycle: game.pulseCycle ?? game.loopCycle ?? 0 });
        if (trace.length > 100) trace.splice(0, trace.length - 100);
    }

    private static handlerName(opcode530: number): string {
        switch (opcode530) {
            case 162: return "REBUILD_NORMAL";
            case 110: return "INSTANCED_LOCATION_UPDATE";
            case 112: return "CLEAR_REGION_CHUNK";
            case 214: return "BUILD_DYNAMIC_SCENE";
            case 230: return "UPDATE_AREA_POSITION_A";
            case 26: return "UPDATE_AREA_POSITION_B";
            case 225: return "PLAYER_INFO";
            case 32: return "NPC_INFO";
            case 115: return "RUN_CS2";
            case 116: return "GRAND_EXCHANGE_OFFERS";
            case 86: return "LOGOUT";
            default: return "opcode_" + opcode530;
        }
    }

    static dispatch(opcode530: number, buf: Buffer, size: number, game: any): boolean {
        switch (opcode530) {
            // Critical world/scene packets
            case 162: return this.handleRebuildNormal(buf, size, game);
            case 110: return this.handleInstancedLocationUpdate(buf, size, game);
            case 112: return this.handleClearRegionChunk(buf, size, game);
            case 214: return this.handleBuildDynamicScene(buf, size, game);
            case 230: return this.handleUpdateAreaPositionA(buf, size, game);
            case 26:  return this.handleUpdateAreaPositionB(buf, size, game);

            // Entity synchronization
            case 225: return this.handlePlayerInfo(buf, size, game);
            case 32:  return this.handleNpcInfo(buf, size, game);

            // Zone-update bus (rt4 Protocol.readZonePacket)
            case 14:  return this.handleObjCount(buf, game);          // OBJ_COUNT
            case 16:  return this.handleMapProjAnim2(buf, game);      // MAP_PROJANIM_2
            case 17:  return this.handleSpotAnimSpecific(buf, game);  // SPOTANIM_SPECIFIC
            case 20:  return this.handleLocAnim(buf, game);           // LOC_ANIM
            case 33:  return this.handleObjReveal(buf, game);         // OBJ_REVEAL
            case 56:  return this.handleSpotAnimEntity(buf, game);    // SPOTANIM_ENTITY
            case 102: return this.handleNpcAnimSpecific(buf, game);   // NPC_ANIM_SPECIFIC
            case 104: return this.handleMapProjAnim(buf, game);       // MAP_PROJANIM
            case 121: return this.handleMapProjAnim3(buf, game);      // MAP_PROJANIM_3
            case 135: return this.handleObjAdd(buf, game);            // OBJ_ADD
            case 179: return this.handleLocAdd(buf, game);            // LOC_ADD
            case 195: return this.handleLocDel(buf, game);            // LOC_DEL
            case 202: return this.handleLocAddChange(buf, game);      // LOC_ADD_CHANGE
            case 235: return this.handleLocAnimSpecific(buf, game);   // LOC_ANIM_SPECIFIC
            case 240: return this.handleObjDel(buf, game);            // OBJ_DEL
            case 97:  return this.handleSoundArea(buf, game);         // SOUND_AREA

            // Camera packets
            case 154: return this.handleCamPosition(buf, game);        // CamPosition (8)
            case 125: return this.handleCamRotation(buf, game);        // CamRotation (8)
            case 187: return this.handleCamSet(buf, game);             // CamSet (6)
            case 27:  return this.handleCamShake(buf, size, game);     // CamShake (8)
            case 24:  return this.handleCamReset(buf, game);           // CamReset (2)

            // Interface packets (all fall through as "consumed")
            case 145: return this.handleWindowsPane(buf, size, game);   // WindowsPane (IF_OPENTOP)
            case 149: return this.handleIfCloseSub(buf, game);           // IF_CLOSESUB (6 bytes)
            case 155: return this.handleIfOpenTop(buf, game);            // IF_OPENTOP (9 bytes)
            case 21:  return this.handleIfSetHide(buf, game);            // IF_SETHIDE (7 bytes)
            case 132: return this.handleIfSetAngle(buf, game);           // IF_SETANGLE (12 bytes)
            case 36:  return this.handleIfSetAnim(buf, game);            // IF_SETANIM (8 bytes)
            case 119: return this.handleIfSetPosition(buf, game);        // IF_SETPOSITION (10 bytes)
            case 171: return this.handleIfSetText1(buf, size, game);     // IF_SETTEXT1 (var-byte)
            case 165: return this.handleSetInterfaceSettings(buf, game); // SET_INTERFACE_SETTINGS (14 bytes)
            case 44:  return this.handleSetInteraction(buf, size, game); // SET_INTERACTION (var-byte)
            case 217: return this.handleHintArrow(buf, size, game);      // HINT_ARROW (var-byte)
            case 66:  return this.handleIfSetPlayerHead(buf, game);      // IF_SETPLAYERHEAD (6 bytes)
            case 73:  return this.handleIfSetNpcHead(buf, game);         // IF_SETNPCHEAD (8 bytes)
            case 50:  return this.handleIfSetObject(buf, game);          // IF_SETOBJECT (12 bytes)
            case 130: return this.handleIfSetModel(buf, game);           // IF_SETMODEL (8 bytes)
            case 144: return this.handleUpdateInvClear(buf, game);       // UPDATE_INV_CLEAR (4)
            case 22:  return this.handleUpdateInvPartial(buf, size, game); // UPDATE_INV_PARTIAL (var-short)
            case 105: return this.handleUpdateInvFull(buf, size, game);    // UPDATE_INV_FULL (var-short)
            case 55:  return this.handleJoinClanChat(buf, size, game);   // JOIN_CLAN_CHAT (var-byte)
            case 115: return this.handleRunCs2(buf, size, game);         // RUN_CS2 (var-short)
            case 116: return this.handleGrandExchangeOffers(buf, size, game); // GRAND_EXCHANGE_OFFERS
            case 65:  return this.handleClientSetVarcSmall(buf, game);   // CLIENT_SETVARC_SMALL (5 bytes)
            case 69:  return this.handleClientSetVarcLarge(buf, game);   // CLIENT_SETVARC_LARGE (8 bytes)
            case 2:   return this.handleIfSetColour(buf, game);          // IF_SETCOLOUR
            case 9:   return this.handleWidgetStructSetting(buf, size, game); // WIDGETSTRUCT_SETTING
            case 48:  return this.handleIfSetText2(buf, size, game);     // IF_SETTEXT2
            case 123: return this.handleIfSetText3(buf, size, game);     // IF_SETTEXT3
            case 176: return this.handleSwitchWidget(buf, game);         // SWITCH_WIDGET
            case 207: return this.handleInterfaceAnimateRotate(buf, game); // INTERFACE_ANIMATE_ROTATE
            case 209: return this.handleGameFrameUnk(game);              // GAME_FRAME_UNK
            case 220: return this.handleIfSetScrollPos(buf, game);       // IF_SETSCROLLPOS
            case 42:  return this.handleUrlOpen(buf, size, game);         // URL_OPEN
            case 111: return this.handleGenerateChatHeadFromBody(buf, game); // GENERATE_CHAT_HEAD_FROM_BODY
            case 114: return this.handleReflectionCheatCheck(buf, size, game); // REFLECTION_CHEAT_CHECK

            // State update packets with real handlers
            case 13:  return this.handleTeleportLocalPlayer(buf, game); // TELEPORT_LOCAL_PLAYER
            case 89:  return this.handleResetClientVarCache(game);      // RESET_CLIENT_VARCACHE
            case 128: return this.handleForceVarpRefresh(buf, size, game); // FORCE_VARP_REFRESH
            case 131: return this.handleResetAnims(game);               // RESET_ANIMS
            case 142: return this.handleSettingsString(buf, size, game); // SET_SETTINGS_STRING
            case 159: return this.handleRunWeight530(buf, game);        // UPDATE_RUNWEIGHT
            case 160: return this.handleSetWalkText(buf, size, game);   // SET_WALK_TEXT
            case 164: return this.handleLastLoginInfo(buf, size, game); // LAST_LOGIN_INFO
            case 169: return this.handleUid192(buf, size, game);        // UPDATE_UID192
            case 191: return this.handleDeleteInventory(buf, game);     // DELETE_INVENTORY
            case 232: return this.handleChatFilterSettings(buf, game);  // CHAT_FILTER_SETTINGS
            case 0:   return this.handleMessagePrivate(buf, size, game);
            case 71:  return this.handleMessagePrivateEcho(buf, size, game);
            case 247: return this.handleMessageQuickchatPrivate(buf, size, game);
            case 141: return this.handleMessageQuickchatPrivateEcho(buf, size, game);
            case 54:  return this.handleMessageClanChannel(buf, size, game);
            case 81:  return this.handleClanQuickChat(buf, size, game);
            case 196: return this.handleUpdateClan(buf, game);
            case 60:  return this.handleVarpSmall(buf, game);           // 2 bytes
            case 226: return this.handleVarpLarge(buf, game);           // 6 bytes
            case 38:  return this.handleUpdateStat(buf, game);          // 6 bytes
            case 70:  return this.handleGameMessage(buf, size, game);   // var-byte
            case 172: return this.handleSynthSound(buf, game);          // SYNTH_SOUND
            case 192: return this.handleMinimapState(buf, game);        // 1 byte
            case 234: return this.handleRunEnergy(buf, game);           // 1 byte
            case 174: return this.handleWeightUpdate(buf, game);        // 2 bytes
            case 153: return this.handleClearMinimapFlag(buf, game);    // 0 bytes
            case 86:  return this.handleLogout(buf, game);              // 0 bytes
            case 85:  return this.handleSystemUpdate(buf, game);        // 2 bytes
            case 197: return this.handleContactStatus(buf, game);       // 1 byte
            case 126: return this.handleUpdateIgnoreList(buf, size, game); // UPDATE_IGNORELIST (var-short)
            case 62:  return this.handleUpdateFriendList(buf, size, game); // UPDATE_FRIENDLIST (var-byte)
            case 84:  return this.handleVarbitLarge(buf, game);         // VARBIT_LARGE (6 bytes)
            case 37:  return this.handleVarbitSmall(buf, game);         // VARBIT_SMALL (3 bytes)
            case 4:   return this.handleMidiSong(buf, game);            // MIDI_SONG (2 bytes)
            case 208: return this.handleMidiJingle(buf, game);          // MIDI_JINGLE (5 bytes)
            case 211: return this.handleUpdateRandomFile(buf, size, game); // UPDATE_RANDOM_FILE (never sent in practice)
            case 10:  return this.handleSetWalkOption(buf, size, game);    // SET_WALK_OPTION (TODO on server)

            default:
                // Unknown opcode - consume size bytes defensively to keep stream aligned
                if (size > 0) buf.currentPosition += size;
                return true;
        }
    }

    // ── Buffer helper methods for 530 byte encodings ──

    static g1(buf: Buffer): number {
        return buf.buffer[buf.currentPosition++] & 0xFF;
    }
    static g1b(buf: Buffer): number {
        const b = buf.buffer[buf.currentPosition++];
        return (b << 24) >> 24;
    }
    static g1add(buf: Buffer): number {
        return (buf.buffer[buf.currentPosition++] - 128) & 0xFF;
    }
    static g1neg(buf: Buffer): number {
        return (-buf.buffer[buf.currentPosition++]) & 0xFF;
    }
    static g1sub(buf: Buffer): number {
        return (128 - buf.buffer[buf.currentPosition++]) & 0xFF;
    }
    // Reverse of putC (server writes -val as signed byte). Returns signed value.
    static g1c(buf: Buffer): number {
        const b = buf.buffer[buf.currentPosition++];
        return -((b << 24) >> 24);
    }
    // Reverse of putS (server writes (byte)(128 - val)). Value returned is unsigned 0..255.
    static g1s(buf: Buffer): number {
        return (128 - buf.buffer[buf.currentPosition++]) & 0xFF;
    }
    static g2(buf: Buffer): number {
        buf.currentPosition += 2;
        return ((buf.buffer[buf.currentPosition - 2] & 0xFF) << 8) + (buf.buffer[buf.currentPosition - 1] & 0xFF);
    }
    static g2add(buf: Buffer): number {
        buf.currentPosition += 2;
        return ((buf.buffer[buf.currentPosition - 2] & 0xFF) << 8) + ((buf.buffer[buf.currentPosition - 1] - 128) & 0xFF);
    }
    static g2b(buf: Buffer): number {
        const value = this.g2(buf);
        return value > 32767 ? value - 0x10000 : value;
    }
    static g3(buf: Buffer): number {
        buf.currentPosition += 3;
        return ((buf.buffer[buf.currentPosition - 3] & 0xFF) << 16) +
               ((buf.buffer[buf.currentPosition - 2] & 0xFF) << 8) +
                (buf.buffer[buf.currentPosition - 1] & 0xFF);
    }
    static ig3(buf: Buffer): number {
        buf.currentPosition += 3;
        return (buf.buffer[buf.currentPosition - 3] & 0xFF) +
               ((buf.buffer[buf.currentPosition - 2] & 0xFF) << 8) +
               ((buf.buffer[buf.currentPosition - 1] & 0xFF) << 16);
    }
    static ig2(buf: Buffer): number {
        buf.currentPosition += 2;
        return (buf.buffer[buf.currentPosition - 2] & 0xFF) + ((buf.buffer[buf.currentPosition - 1] & 0xFF) << 8);
    }
    static ig2add(buf: Buffer): number {
        buf.currentPosition += 2;
        return ((buf.buffer[buf.currentPosition - 2] - 128) & 0xFF) + ((buf.buffer[buf.currentPosition - 1] & 0xFF) << 8);
    }
    // rt4 Buffer.g1badd: signed byte after subtracting 128.
    static g1badd(buf: Buffer): number {
        const value = (buf.buffer[buf.currentPosition++] - 128) & 0xFF;
        return value > 127 ? value - 256 : value;
    }
    // rt4 Buffer.g1bsub: signed byte after 128 - value.
    static g1bsub(buf: Buffer): number {
        const value = (128 - buf.buffer[buf.currentPosition++]) & 0xFF;
        return value > 127 ? value - 256 : value;
    }
    // rt4 Buffer.ig2badd: little-endian signed short with first byte add-128.
    static ig2badd(buf: Buffer): number {
        const value = (((buf.buffer[buf.currentPosition + 1] & 0xFF) << 8) +
                       ((buf.buffer[buf.currentPosition] - 128) & 0xFF)) & 0xFFFF;
        buf.currentPosition += 2;
        return value > 32767 ? value - 0x10000 : value;
    }
    static g4(buf: Buffer): number {
        buf.currentPosition += 4;
        return (((buf.buffer[buf.currentPosition - 4] & 0xFF) << 24) |
                ((buf.buffer[buf.currentPosition - 3] & 0xFF) << 16) |
                ((buf.buffer[buf.currentPosition - 2] & 0xFF) << 8) |
                 (buf.buffer[buf.currentPosition - 1] & 0xFF)) >>> 0;
    }
    static ig4(buf: Buffer): number {
        buf.currentPosition += 4;
        return ((buf.buffer[buf.currentPosition - 4] & 0xFF) |
                ((buf.buffer[buf.currentPosition - 3] & 0xFF) << 8) |
                ((buf.buffer[buf.currentPosition - 2] & 0xFF) << 16) |
                ((buf.buffer[buf.currentPosition - 1] & 0xFF) << 24)) | 0;
    }
    static mg4(buf: Buffer): number {
        // Middle-endian "BADC": rt4-client Buffer.mg4 reads bytes in read-order
        // B0 B1 B2 B3 and assembles the int as (B1<<24)|(B0<<16)|(B3<<8)|B2.
        // The XTEA key fields and other middle-endian ints use this exact order;
        // any deviation produces unrelated key bytes and downstream decompression
        // of l_X_Z location groups silently fails (returns null).
        buf.currentPosition += 4;
        const b0 = buf.buffer[buf.currentPosition - 4] & 0xFF;
        const b1 = buf.buffer[buf.currentPosition - 3] & 0xFF;
        const b2 = buf.buffer[buf.currentPosition - 2] & 0xFF;
        const b3 = buf.buffer[buf.currentPosition - 1] & 0xFF;
        return ((b1 << 24) | (b0 << 16) | (b3 << 8) | b2) >>> 0;
    }
    static img4(buf: Buffer): number {
        // Inverse-middle-endian: BADC byte order
        buf.currentPosition += 4;
        const b0 = buf.buffer[buf.currentPosition - 4] & 0xFF;
        const b1 = buf.buffer[buf.currentPosition - 3] & 0xFF;
        const b2 = buf.buffer[buf.currentPosition - 2] & 0xFF;
        const b3 = buf.buffer[buf.currentPosition - 1] & 0xFF;
        return ((b1 << 24) | (b0 << 16) | (b3 << 8) | b2) >>> 0;
    }
    static g8(buf: Buffer): Long {
        const high = this.g4(buf) | 0;
        const low = this.g4(buf) | 0;
        return new Long(low, high);
    }
    static gjstr(buf: Buffer): string {
        let s = "";
        const end = buf.buffer ? buf.buffer.length : 0;
        while (buf.currentPosition < end && buf.buffer[buf.currentPosition] !== 0) {
            s += String.fromCharCode(buf.buffer[buf.currentPosition++] & 0xFF);
        }
        if (buf.currentPosition < end) buf.currentPosition++; // skip NUL
        return s;
    }

    static name37ToString(name37: Long): string {
        try {
            return TextUtils.formatName(TextUtils.longToName(name37));
        } catch (e) {
            return name37.toString();
        }
    }

    static messageId(top: number, bot: number): string {
        return `${top >>> 0}:${bot >>> 0}`;
    }

    static consumeMessageBody(buf: Buffer, end: number): string {
        const bytes: number[] = [];
        const limit = Math.min(end, buf.buffer ? buf.buffer.length : end);
        while (buf.currentPosition < limit) {
            const value = buf.buffer[buf.currentPosition++] & 0xFF;
            if (value === 0 || value === 10) break;
            bytes.push(value);
        }
        if (bytes.length === 0) return "";
        const printable = bytes.every(b => b === 9 || b === 13 || (b >= 32 && b <= 126));
        return printable ? String.fromCharCode.apply(null, bytes) : "[message]";
    }

    /** Set by Game.ts once idx10 (or wherever quickchat huffman bits live) loads. */
    public static huffman: HuffmanCodec530 | null = null;

    static consumeQuickChatPayload(buf: Buffer, end: number): string {
        // QuickChat bodies are length-prefixed huffman bytes. With a codec we decode
        // the actual phrase text; without one, we still consume the right number of
        // bytes so the stream stays aligned and return the legacy "[quickchat]" sentinel.
        const limit = Math.min(end, buf.buffer ? buf.buffer.length : end);
        if (buf.currentPosition >= limit) return "[quickchat]";
        const src = buf.buffer instanceof Uint8Array ? buf.buffer : new Uint8Array(buf.buffer);
        try {
            const { text, bytesConsumed } = decodeQuickChatString(src, buf.currentPosition, limit, this.huffman);
            buf.currentPosition = Math.min(limit, buf.currentPosition + bytesConsumed);
            return text || "[quickchat]";
        } catch (_) {
            // Fall back to the conservative skip on any decode error.
            const remaining = limit - buf.currentPosition;
            const declared = buf.buffer[buf.currentPosition] & 0xFF;
            if (declared <= remaining - 1) buf.currentPosition += 1 + declared;
            else buf.currentPosition = limit;
            return "[quickchat]";
        }
    }

    static pushChat(game: any, name: string, message: string, type: number) {
        if (game && game.addChatMessage) {
            game.addChatMessage(name, message, type);
        }
    }

    // Generic consumer for opcodes where we only need to keep the stream aligned
    static consumeKnown(buf: Buffer, size: number): boolean {
        if (size > 0) buf.currentPosition += size;
        return true;
    }

    // ── gsmarts: variable-length smart int (rt4 Buffer.gsmarts) ────
    // If first byte < 128: return that byte (1-byte form).
    // Otherwise: read full g2() and mask off the high bit (2-byte form).
    static gsmarts(buf: Buffer): number {
        const b = buf.buffer[buf.currentPosition] & 0xFF;
        if (b < 128) { buf.currentPosition++; return b; }
        return this.g2(buf) & 0x7FFF;
    }

    // ── Inventory / container packet handlers ────────────────────────

    private static signed32(value: number): number {
        return value | 0;
    }

    private static inventoryContainerId(componentHash: number, containerId: number): number {
        return this.signed32(componentHash) < -70000 ? containerId + 32768 : containerId;
    }

    private static getInventoryComponent(game: any, componentHash: number): any {
        if (this.signed32(componentHash) < 0) return null;
        const fromGame = game?.getComponent ? game.getComponent(componentHash) : null;
        return fromGame || InterfaceList.get(componentHash >>> 16, componentHash & 0xFFFF);
    }

    private static ensureInventoryCapacity(comp: any, length: number): void {
        if (!comp.inventoryItems) comp.inventoryItems = [];
        if (!comp.inventoryItemAmounts) comp.inventoryItemAmounts = [];
        while (comp.inventoryItems.length < length) comp.inventoryItems.push(-1);
        while (comp.inventoryItemAmounts.length < length) comp.inventoryItemAmounts.push(0);
    }

    private static syncLegacyInventoryWidget(game: any, componentHash: number, comp: any): void {
        if (!game?.syncLegacyInventoryWidget || this.signed32(componentHash) < 0) return;
        try {
            game.syncLegacyInventoryWidget(componentHash, comp);
        } catch (_) {
            // The 530 Component state is authoritative; legacy widget mirroring is best-effort.
        }
    }

    private static syncLegacyInterfaceWidgets(game: any, interfaceId: number, rootWidgetId: number = interfaceId): void {
        if (!game?.syncLegacyInterfaceWidgets || interfaceId < 0 || rootWidgetId < 0) return;
        const js5 = game.js5Cache || (globalThis as any).js5Cache || null;
        InterfaceList.loadInterface(js5, interfaceId).then(() => {
            try {
                game.syncLegacyInterfaceWidgets(interfaceId, rootWidgetId);
            } catch (_) {
                // The 530 Component state is authoritative; legacy widget synthesis is best-effort.
            }
        });
    }

    private static syncInventoryComponent(
        game: any,
        componentHash: number,
        clearFirst: boolean,
        updates: { slot: number; itemId: number; count: number }[],
        minLength: number = 0,
    ): void {
        const apply = (): boolean => {
            const comp = this.getInventoryComponent(game, componentHash);
            if (!comp) return false;
            let length = minLength | 0;
            for (const u of updates) if (u.slot + 1 > length) length = u.slot + 1;
            this.ensureInventoryCapacity(comp, length);
            if (clearFirst) {
                for (let i = 0; i < comp.inventoryItems.length; i++) {
                    comp.inventoryItems[i] = -1;
                    comp.inventoryItemAmounts[i] = 0;
                }
            }
            for (const u of updates) {
                if (u.slot < 0) continue;
                this.ensureInventoryCapacity(comp, u.slot + 1);
                comp.inventoryItems[u.slot] = u.itemId;
                comp.inventoryItemAmounts[u.slot] = u.count;
            }
            this.syncLegacyInventoryWidget(game, componentHash, comp);
            return true;
        };
        if (apply()) return;
        const js5 = game ? (game.js5Cache || (globalThis as any).js5Cache || null) : null;
        InterfaceList.loadInterface(js5, componentHash >>> 16).then(() => apply());
    }

    static handleUpdateInvClear(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java UPDATE_INV_CLEAR — reads g4() component hash, zeros all slots.
        const componentHash = this.g4(buf);
        this.syncInventoryComponent(game, componentHash, true, []);
        // Also clear from per-container game map.
        if (game) {
            if (!game.containerItems) game.containerItems = {};
            if (!game.containerAmounts) game.containerAmounts = {};
            let clearedMappedContainer = false;
            if (game.containerComponents) {
                for (const key of Object.keys(game.containerComponents)) {
                    if (game.containerComponents[key] !== componentHash) continue;
                    game.containerItems[key] = [];
                    game.containerAmounts[key] = [];
                    clearedMappedContainer = true;
                }
            }
            if (!clearedMappedContainer) {
                game.containerItems[componentHash] = [];
                game.containerAmounts[componentHash] = [];
            }
        }
        return true;
    }

    static handleUpdateInvPartial(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java UPDATE_INV_PARTIAL — per-slot updates.
        // Format: g4(componentHash) + g2(containerId) + loop: gsmarts(slot) + g2(itemId1based) + if != 0: g1/g4(count)
        const start = buf.currentPosition;
        const componentHash = this.g4(buf);
        const rawContainerId = this.g2(buf);
        const containerId = this.inventoryContainerId(componentHash, rawContainerId);
        const end = start + size;
        const updates: { slot: number; itemId: number; count: number }[] = [];
        if (game) {
            if (!game.containerItems) game.containerItems = {};
            if (!game.containerAmounts) game.containerAmounts = {};
            if (!game.containerComponents) game.containerComponents = {};
            game.containerComponents[containerId] = componentHash;
            if (!game.containerItems[containerId]) game.containerItems[containerId] = [];
            if (!game.containerAmounts[containerId]) game.containerAmounts[containerId] = [];
        }
        while (buf.currentPosition < end && buf.currentPosition < buf.buffer.length) {
            const slot = this.gsmarts(buf);
            const itemId1based = this.g2(buf); // 1-based item id; 0 = empty slot
            let count = 0;
            if (itemId1based !== 0) {
                const raw = this.g1(buf);
                count = raw === 255 ? this.g4(buf) : raw;
            }
            const itemId = itemId1based - 1; // convert to 0-based (-1 when empty)
            updates.push({ slot, itemId: itemId1based === 0 ? -1 : itemId, count });
            if (game) {
                game.containerItems[containerId][slot] = itemId1based === 0 ? -1 : itemId;
                game.containerAmounts[containerId][slot] = count;
            }
        }
        this.syncInventoryComponent(game, componentHash, false, updates);
        this.traceContainer(game, {
            opcode: 22,
            componentHash,
            rawContainerId,
            containerId,
            slots: updates.length,
            sample: updates.slice(0, 8),
        });
        if (buf.currentPosition < end) buf.currentPosition = end;
        return true;
    }

    static handleUpdateInvFull(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java UPDATE_INV_FULL — full container snapshot.
        // Format: g4(componentHash) + g2(containerId) + g2(total) + loop: g1sub(count, 255→g4) + g2(itemId1based)
        const start = buf.currentPosition;
        const componentHash = this.g4(buf);
        const rawContainerId = this.g2(buf);
        const containerId = this.inventoryContainerId(componentHash, rawContainerId);
        const total = this.g2(buf);
        const updates: { slot: number; itemId: number; count: number }[] = [];
        if (game) {
            if (!game.containerItems) game.containerItems = {};
            if (!game.containerAmounts) game.containerAmounts = {};
            if (!game.containerComponents) game.containerComponents = {};
            game.containerComponents[containerId] = componentHash;
            game.containerItems[containerId] = new Array(total).fill(-1);
            game.containerAmounts[containerId] = new Array(total).fill(0);
        }
        for (let slot = 0; slot < total; slot++) {
            const rawCount = this.g1sub(buf);
            const count = rawCount === 255 ? this.g4(buf) : rawCount;
            const itemId1based = this.g2(buf);
            const itemId = itemId1based - 1;
            updates.push({ slot, itemId: itemId1based === 0 ? -1 : itemId, count });
            if (game) {
                game.containerItems[containerId][slot] = itemId1based === 0 ? -1 : itemId;
                game.containerAmounts[containerId][slot] = count;
            }
        }
        this.syncInventoryComponent(game, componentHash, true, updates, total);
        this.traceContainer(game, {
            opcode: 105,
            componentHash,
            rawContainerId,
            containerId,
            total,
            sample: updates.filter((update) => update.itemId >= 0 || update.count > 0).slice(0, 8),
        });
        const end = start + size;
        if (buf.currentPosition < end) buf.currentPosition = end;
        return true;
    }

    // ── Varbit handlers ──────────────────────────────────────────────

    static handleVarbitLarge(buf: Buffer, game: any): boolean {
        // Opcode 84: VARBIT_LARGE — varbitId(g2) + value(g4) = 6 bytes.
        const varbitId = this.g2(buf);
        const value = this.g4(buf);
        if (game) {
            if (!game.varbitValues) game.varbitValues = {};
            game.varbitValues[varbitId] = value;
        }
        return true;
    }

    static handleVarbitSmall(buf: Buffer, game: any): boolean {
        // Opcode 37: VARBIT_SMALL — varbitId(g2) + value(g1) = 3 bytes.
        const varbitId = this.g2(buf);
        const value = this.g1(buf);
        if (game) {
            if (!game.varbitValues) game.varbitValues = {};
            game.varbitValues[varbitId] = value;
        }
        return true;
    }

    // ── Interface visibility / VarC handlers ─────────────────────────

    static handleIfSetHide(buf: Buffer, game: any): boolean {
        // rt4 IF_SETHIDE: g1neg(parent) + g2(tracknum) + ig4(componentHash). 7 bytes total.
        const parent = this.g1neg(buf);
        const tracknum = this.g2(buf);
        const componentHash = this.ig4(buf);
        // 'parent' field actually carries the hidden flag (0 = visible, !0 = hidden) per rt4
        // DelayedStateChange.method2905 semantics. We surface both for the renderer to pick from.
        this.recordIfUpdate(game, "IF_SETHIDE", componentHash, { hidden: parent !== 0, parent, tracknum });
        return true;
    }

    static handleClientSetVarcSmall(buf: Buffer, game: any): boolean {
        // rt4 CLIENT_SETVARC_SMALL: ig2(tracknum) + g1neg(value) + ig2add(id). 5 bytes.
        const tracknum = this.ig2(buf);
        const rawValue = this.g1neg(buf);
        const value = rawValue > 127 ? rawValue - 256 : rawValue;
        const id = this.ig2add(buf);
        if (game) {
            if (!game.varcValues) game.varcValues = {};
            game.varcValues[id] = value;
        }
        this.recordIfUpdate(game, "CLIENT_SETVARC", id, { value, tracknum });
        return true;
    }

    static handleClientSetVarcLarge(buf: Buffer, game: any): boolean {
        // rt4 CLIENT_SETVARC_LARGE: ig2add(tracknum) + g4(value) + g2add(id). 8 bytes.
        const tracknum = this.ig2add(buf);
        const value = this.g4(buf) | 0;
        const id = this.g2add(buf);
        if (game) {
            if (!game.varcValues) game.varcValues = {};
            game.varcValues[id] = value;
        }
        this.recordIfUpdate(game, "CLIENT_SETVARC", id, { value, tracknum });
        return true;
    }

    // ── Zone update state (rt4 Protocol.readZonePacket) ──

    static currentPlane(game: any): number {
        const plane = game && typeof game.plane === "number" ? game.plane : 0;
        return Math.max(0, Math.min(3, plane | 0));
    }

    static inBounds(x: number, z: number, limit: number = 104): boolean {
        return x >= 0 && z >= 0 && x < limit && z < limit;
    }

    static ensureZoneState(game: any): void {
        if (!game.groundObjects) game.groundObjects = [];
        for (let p = 0; p < 4; p++) {
            if (!game.groundObjects[p]) game.groundObjects[p] = [];
            for (let x = 0; x < 104; x++) {
                if (!game.groundObjects[p][x]) game.groundObjects[p][x] = [];
            }
        }
        if (!game.locAnims) game.locAnims = [];
        if (!game.projAnims) game.projAnims = [];
        if (!game.spotAnims) game.spotAnims = [];
    }

    static ensureGroundStack(game: any, plane: number, x: number, z: number): ObjStack[] {
        this.ensureZoneState(game);
        if (!game.groundObjects[plane][x][z]) game.groundObjects[plane][x][z] = [];
        return game.groundObjects[plane][x][z];
    }

    static getGroundStack(game: any, plane: number, x: number, z: number): ObjStack[] | null {
        this.ensureZoneState(game);
        return game.groundObjects?.[plane]?.[x]?.[z] || null;
    }

    static tileHeight(game: any, plane: number, x: number, z: number): number {
        if (game && typeof game.getTileHeight === "function") {
            return game.getTileHeight(z, x, 9, plane) || 0;
        }
        return 0;
    }

    static loop(game: any): number {
        return (game && game.constructor && typeof game.constructor.pulseCycle === "number")
            ? game.constructor.pulseCycle
            : 0;
    }

    static originX(game: any): number {
        return typeof game?.nextTopLeftTileX === "number" ? game.nextTopLeftTileX : ((game?.chunkX || 0) - 6) * 8;
    }

    static originZ(game: any): number {
        return typeof game?.nextTopRightTileY === "number" ? game.nextTopRightTileY : ((game?.chunkY || 0) - 6) * 8;
    }

    static pushLocState(game: any, entry: any): void {
        this.ensureZoneState(game);
        game.locAnims.push(entry);
    }

    static handleLocDel(buf: Buffer, game: any): boolean {
        const local15 = this.g1neg(buf);
        const local19 = local15 & 0x3;
        const local23 = local15 >> 2;
        const local27 = this.LOC_LAYERS[local23] || 0;
        const local31 = this.g1(buf);
        const local39 = (local31 >> 4 & 0x7) + game.chunkX;
        const local45 = (local31 & 0x7) + game.chunkY;
        if (this.inBounds(local39, local45)) {
            this.pushLocState(game, { op: "del", plane: this.currentPlane(game), x: local39, z: local45, anim: -1, layer: local27, type: local23, rotation: local19, locId: -1 });
        }
        return true;
    }

    static handleObjReveal(buf: Buffer, game: any): boolean {
        const local15 = this.ig2(buf);
        const local23 = this.g1(buf);
        const local27 = (local23 & 0x7) + game.chunkY;
        const local19 = (local23 >> 4 & 0x7) + game.chunkX;
        const local31 = this.g2add(buf);
        if (this.inBounds(local19, local27)) {
            this.ensureGroundStack(game, this.currentPlane(game), local19, local27).push(new ObjStack(local15, local31));
        }
        return true;
    }

    static handleMapProjAnim3(buf: Buffer, game: any): boolean {
        const local15 = this.g1(buf);
        let local23 = game.chunkX * 2 + (local15 >> 4 & 0xF);
        let local19 = (local15 & 0xF) + game.chunkY * 2;
        let local27 = local23 + this.g1b(buf);
        let local31 = this.g1b(buf) + local19;
        const local39 = this.g2b(buf);
        const local45 = this.g2(buf);
        const local218 = this.g1(buf) * 4;
        const local224 = this.g1(buf) * 4;
        const local228 = this.g2(buf);
        const local232 = this.g2(buf);
        let local236 = this.g1(buf);
        if (local236 === 255) local236 = -1;
        const local247 = this.g1(buf);
        if (this.inBounds(local23, local19, 208) && this.inBounds(local27, local31, 208) && local45 !== 65535) {
            local31 *= 64;
            local27 *= 64;
            local19 *= 64;
            local23 *= 64;
            const loop = this.loop(game);
            const local317 = new ProjAnim(local45, this.currentPlane(game), local23, local19, this.tileHeight(game, this.currentPlane(game), local23, local19) - local218, loop + local228, loop + local232, local236, local247, local39, local224);
            local317.setTarget(local31, loop + local228, -local224 + this.tileHeight(game, this.currentPlane(game), local27, local31), local27);
            this.ensureZoneState(game);
            game.projAnims.push(local317);
        }
        return true;
    }

    static handleSpotAnimSpecific(buf: Buffer, game: any): boolean {
        const local15 = this.g1(buf);
        let local23 = game.chunkX + (local15 >> 4 & 0x7);
        let local19 = game.chunkY + (local15 & 0x7);
        const local27 = this.g2(buf);
        const local31 = this.g1(buf);
        const local39 = this.g2(buf);
        if (this.inBounds(local23, local19)) {
            local23 = local23 * 128 + 64;
            local19 = local19 * 128 + 64;
            this.ensureZoneState(game);
            game.spotAnims.push(new SpotAnim(local27, this.currentPlane(game), local23, local19, this.tileHeight(game, this.currentPlane(game), local23, local19) - local31, local39, this.loop(game)));
        }
        return true;
    }

    static handleLocAdd(buf: Buffer, game: any): boolean {
        const local15 = this.g1add(buf);
        const local23 = local15 >> 2;
        const local19 = local15 & 0x3;
        const local27 = this.LOC_LAYERS[local23] || 0;
        const local31 = this.g1(buf);
        const local39 = game.chunkX + (local31 >> 4 & 0x7);
        const local45 = (local31 & 0x7) + game.chunkY;
        const local218 = this.g2add(buf);
        if (this.inBounds(local39, local45)) {
            this.pushLocState(game, { op: "add", plane: this.currentPlane(game), x: local39, z: local45, anim: -1, layer: local27, type: local23, rotation: local19, locId: local218 });
        }
        return true;
    }

    static handleLocAnim(buf: Buffer, game: any): boolean {
        const local15 = this.g1sub(buf);
        const local23 = (local15 >> 4 & 0x7) + game.chunkX;
        const local19 = game.chunkY + (local15 & 0x7);
        const local27 = this.g1sub(buf);
        const local31 = local27 >> 2;
        const local39 = local27 & 0x3;
        const local45 = this.LOC_LAYERS[local31] || 0;
        let local218 = this.ig2(buf);
        if (local218 === 65535) local218 = -1;
        if (this.inBounds(local23, local19)) {
            this.pushLocState(game, { op: "anim", plane: this.currentPlane(game), x: local23, z: local19, anim: local218, layer: local45, type: local31, rotation: local39 });
        }
        return true;
    }

    static handleLocAddChange(buf: Buffer, game: any): boolean {
        const local15 = this.g1(buf);
        const local23 = local15 >> 2;
        const local19 = local15 & 0x3;
        const local27 = this.g1(buf);
        const local31 = (local27 >> 4 & 0x7) + game.chunkX;
        const local39 = (local27 & 0x7) + game.chunkY;
        const local605 = this.g1badd(buf);
        const local609 = this.g1badd(buf);
        const local613 = this.g1bsub(buf);
        const local228 = this.g2add(buf);
        const local232 = this.ig2(buf);
        const local625 = this.g1b(buf);
        const local247 = this.g2(buf);
        const local633 = this.ig2badd(buf);
        if (this.inBounds(local31, local39)) {
            this.pushLocState(game, { op: "change", plane: this.currentPlane(game), x: local31, z: local39, anim: -1, layer: this.LOC_LAYERS[local23] || 0, type: local23, rotation: local19, locId: local228, raw: { local605, local609, local613, local232, local625, local247, local633 } });
        }
        return true;
    }

    static handleObjCount(buf: Buffer, game: any): boolean {
        const local15 = this.g1(buf);
        const local19 = game.chunkY + (local15 & 0x7);
        const local23 = (local15 >> 4 & 0x7) + game.chunkX;
        const local27 = this.g2(buf);
        const local31 = this.g2(buf);
        const local39 = this.g2(buf);
        if (this.inBounds(local23, local19)) {
            const stack = this.getGroundStack(game, this.currentPlane(game), local23, local19);
            if (stack) {
                const obj = stack.find((o) => (local27 & 0x7FFF) === o.type && local31 === o.amount);
                if (obj) obj.amount = local39;
            }
        }
        return true;
    }

    static handleObjAdd(buf: Buffer, game: any): boolean {
        const local15 = this.ig2add(buf);
        const local23 = this.g1neg(buf);
        const local27 = game.chunkY + (local23 & 0x7);
        const local19 = (local23 >> 4 & 0x7) + game.chunkX;
        const local31 = this.ig2(buf);
        const local39 = this.ig2(buf);
        if (this.inBounds(local19, local27) && game.thisPlayerServerId !== local15) {
            this.ensureGroundStack(game, this.currentPlane(game), local19, local27).push(new ObjStack(local39, local31));
        }
        return true;
    }

    static handleMapProjAnim2(buf: Buffer, game: any): boolean {
        const local15 = this.g1(buf);
        let local23 = game.chunkX + (local15 >> 4 & 0x7);
        let local19 = (local15 & 0x7) + game.chunkY;
        let local27 = local23 + this.g1b(buf);
        let local31 = this.g1b(buf) + local19;
        const local39 = this.g2b(buf);
        const local45 = this.g2(buf);
        const local218 = this.g1(buf) * 4;
        const local224 = this.g1(buf) * 4;
        const local228 = this.g2(buf);
        const local232 = this.g2(buf);
        let local236 = this.g1(buf);
        const local247 = this.g1(buf);
        if (local236 === 255) local236 = -1;
        if (this.inBounds(local23, local19) && this.inBounds(local27, local31) && local45 !== 65535) {
            local31 = local31 * 128 + 64;
            local19 = local19 * 128 + 64;
            local23 = local23 * 128 + 64;
            local27 = local27 * 128 + 64;
            const loop = this.loop(game);
            const local317 = new ProjAnim(local45, this.currentPlane(game), local23, local19, this.tileHeight(game, this.currentPlane(game), local23, local19) - local218, loop + local228, loop + local232, local236, local247, local39, local224);
            local317.setTarget(local31, loop + local228, this.tileHeight(game, this.currentPlane(game), local27, local31) - local224, local27);
            this.ensureZoneState(game);
            game.projAnims.push(local317);
        }
        return true;
    }

    static handleMapProjAnim(buf: Buffer, game: any): boolean {
        const local15 = this.g1(buf);
        let local19 = game.chunkY * 2 + (local15 & 0xF);
        let local23 = game.chunkX * 2 + (local15 >> 4 & 0xF);
        let local27 = this.g1b(buf) + local23;
        let local31 = this.g1b(buf) + local19;
        const local39 = this.g2b(buf);
        const local45 = this.g2b(buf);
        const local218 = this.g2(buf);
        const local224 = this.g1b(buf);
        const local228 = this.g1(buf) * 4;
        const local232 = this.g2(buf);
        const local236 = this.g2(buf);
        let local247 = this.g1(buf);
        const local633 = this.g1(buf);
        if (local247 === 255) local247 = -1;
        if (this.inBounds(local23, local19, 208) && this.inBounds(local27, local31, 208) && local218 !== 65535) {
            local27 *= 64;
            local23 *= 64;
            local31 *= 64;
            local19 *= 64;
            const loop = this.loop(game);
            const local1331 = new ProjAnim(local218, this.currentPlane(game), local23, local19, this.tileHeight(game, this.currentPlane(game), local23, local19) - local224, loop + local232, loop + local236, local247, local633, local45, local228);
            local1331.setTarget(local31, loop + local232, -local228 + this.tileHeight(game, this.currentPlane(game), local27, local31), local27);
            this.ensureZoneState(game);
            game.projAnims.push(local1331);
        }
        return true;
    }

    static handleObjDel(buf: Buffer, game: any): boolean {
        const local15 = this.g1sub(buf);
        const local19 = game.chunkY + (local15 & 0x7);
        const local23 = (local15 >> 4 & 0x7) + game.chunkX;
        const local27 = this.g2(buf);
        if (this.inBounds(local23, local19)) {
            const stack = this.getGroundStack(game, this.currentPlane(game), local23, local19);
            if (stack) {
                const idx = stack.findIndex((obj) => obj.type === (local27 & 0x7FFF));
                if (idx >= 0) stack.splice(idx, 1);
                if (stack.length === 0) game.groundObjects[this.currentPlane(game)][local23][local19] = null;
            }
        }
        return true;
    }

    static handleSoundArea(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:361 — g1 packed local tile, g2 track, g1 range/loops, g1 delay.
        const local15 = this.g1(buf);
        const chunkX = game.chunkX + ((local15 >> 4) & 0x7);
        const chunkZ = game.chunkY + (local15 & 0x7);
        let trackId = this.g2(buf);
        if (trackId === 65535) trackId = -1;
        const local31 = this.g1(buf);
        const range = (local31 >> 4) & 0xF;
        const loops = local31 & 0x7;
        const delay = this.g1(buf);
        if (chunkX >= 0 && chunkZ >= 0 && chunkX < 104 && chunkZ < 104 && trackId >= 0) {
            SoundPlayer.playArea(trackId, chunkX, chunkZ, range, loops, delay);
        }
        return true;
    }

    static handleMidiSong(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:2320 — MIDI_SONG reads ig2add, 65535 means stop.
        let trackId = this.ig2add(buf);
        if (trackId === 65535) trackId = -1;
        game.currentSong = trackId;
        game.nextSong = trackId;
        MusicPlayer.playSong(trackId);
        return true;
    }

    static handleMidiJingle(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:2328 — MIDI_JINGLE reads ig3 volume then ig2 id.
        const volume = this.ig3(buf);
        let trackId = this.ig2(buf);
        if (trackId === 65535) trackId = -1;
        // Do not reuse Game.previousSong here. In the translated 377 client
        // that field is a countdown which eventually re-enters the legacy
        // on-demand MIDI requester; 530 music is handled by MusicPlayer.
        game.lastJingleVolume530 = volume;
        MusicPlayer.playJingle(trackId, volume & 0xFF);
        return true;
    }

    static handleSpotAnimEntity(buf: Buffer, game: any): boolean {
        const delay = this.g2(buf);
        const height = this.ig2(buf);
        const target = this.img4(buf);
        let gfxId = this.ig2add(buf);
        if (gfxId === 65535) gfxId = -1;

        if (target >> 30 === 0) {
            const id = target & 0xFFFF;
            const actor = (target >> 29) !== 0
                ? game.npcs?.[id]
                : ((target >> 28) !== 0 ? (game.thisPlayerId === id ? game.constructor.localPlayer : game.players?.[id]) : null);
            if (actor) {
                actor.spotAnimId = gfxId;
                actor.spotAnimStart = this.loop(game) + delay;
                actor.spotAnimY = height;
                actor.anInt3418 = 1;
                actor.anInt3361 = 0;
                actor.anInt3399 = actor.spotAnimStart > this.loop(game) ? -1 : 0;
            }
        } else {
            const plane = target >> 28 & 0x3;
            let posX = (target >> 14 & 0x3FFF) - this.originX(game);
            let posZ = (target & 0x3FFF) - this.originZ(game);
            if (this.inBounds(posX, posZ)) {
                posZ = posZ * 128 + 64;
                posX = posX * 128 + 64;
                this.ensureZoneState(game);
                game.spotAnims.push(new SpotAnim(gfxId, plane, posX, posZ, this.tileHeight(game, plane, posX, posZ) - height, delay, this.loop(game), target, height));
            }
        }
        return true;
    }

    static handleNpcAnimSpecific(buf: Buffer, game: any): boolean {
        const npcId = this.ig2(buf);
        const value = this.g1sub(buf);
        let seqId = this.g2(buf);
        if (seqId === 65535) seqId = -1;
        const npc = game.npcs?.[npcId];
        if (npc) {
            npc.emoteAnimation = seqId;
            npc.animationDelay = value;
            npc.displayedEmoteFrames = 0;
            npc.anInt1626 = 0;
            npc.anInt1628 = 0;
            npc.animationOverride = seqId;
        }
        return true;
    }

    static handleLocAnimSpecific(buf: Buffer, game: any): boolean {
        const slot = this.g1sub(buf);
        const type = slot >> 2;
        const rotation = slot & 0x3;
        const type2 = this.LOC_LAYERS[type] || 0;
        let seqId = this.g2(buf);
        const pos = this.g4(buf);
        if (seqId === 65535) seqId = -1;
        const z = (pos & 0x3FFF) - this.originZ(game);
        const x = (pos >> 14 & 0x3FFF) - this.originX(game);
        const plane = pos >> 28 & 0x3;
        if (this.inBounds(x, z)) {
            this.pushLocState(game, { op: "animSpecific", plane, x, z, anim: seqId, layer: type2, type, rotation });
        }
        return true;
    }

    // ── World/scene packets ──

    static handleRebuildNormal(buf: Buffer, size: number, game: any): boolean {
        // Opcode 162: REBUILD_NORMAL (var-short).
        // Body order matches rt4-client Protocol.java line ~419:
        //   g2add() -> zoneZ
        //   {regionCount x 4 x mg4()}  XTEA keys (16 bytes per region)
        //   g1sub() -> buildArea
        //   g2()    -> regionX (raw)
        //   g2add() -> regionZ
        //   g2add() -> zoneX
        const zoneZ = this.g2add(buf);
        const remainingForXtea = size - 2 - 7; // zoneZ(2) consumed; trailing buildArea(1)+regionX(2)+regionZ(2)+zoneX(2)=7
        const regionCount = (remainingForXtea / 16) | 0;
        // Capture XTEA keys per-region. game.regionXteaKeys[i] is a length-4
        // Int32Array suitable for direct use by an XTEA block decoder when we
        // wire the idx5 region group fetch in Tier 2e.
        const keys: Int32Array[] = new Array(regionCount);
        for (let i = 0; i < regionCount; i++) {
            const k = new Int32Array(4);
            for (let j = 0; j < 4; j++) k[j] = this.mg4(buf) | 0;
            keys[i] = k;
        }
        const buildArea = this.g1sub(buf);
        const regionX = this.g2(buf);
        const regionZ = this.g2add(buf);
        const zoneX = this.g2add(buf);

        // Compute the region IDs that occupy the 13x13 zone-window centered
        // on (regionX, regionZ) so the renderer / idx5 fetcher can pair each
        // region's map-file groupId with its XTEA key. Mirrors rt4-client
        // Protocol.java loop at line ~448.
        const regionBitPacked: number[] = new Array(regionCount);
        const rxStart = ((regionX - 6) / 8) | 0;
        const rxEnd = ((regionX + 6) / 8) | 0;
        const rzStart = ((regionZ - 6) / 8) | 0;
        const rzEnd = ((regionZ + 6) / 8) | 0;
        let slot = 0;
        for (let rx = rxStart; rx <= rxEnd; rx++) {
            for (let rz = rzStart; rz <= rzEnd; rz++) {
                if (slot < regionCount) regionBitPacked[slot++] = (rx << 8) + rz;
            }
        }

        game.regionXteaKeys = keys;
        game.regionBitPacked = regionBitPacked;
        game.regionX = regionX;
        game.regionZ = regionZ;

        // chunkX / chunkY (377 client term) maps to centralZoneX /
        // centralZoneZ in 530. Per rt4 LoginManager.method2463 (line 698+),
        // SceneGraph.centralZoneX = arg2 = local31 (the g2-raw read 3rd in
        // the packet, which we name regionX here) and centralZoneZ =
        // arg1 = local60 (g2add read 4th, our regionZ). The 4th g2add we
        // currently called zoneX is something else (probably the player's
        // base zone for camera origin) and we were using the wrong values
        // — consequence: nextTopLeftTileX/Y was 2080+ off, every loc fell
        // outside the 0..103 scene grid, world rendered black.
        game.chunkX = regionX;
        game.chunkY = regionZ;
        game.nextTopLeftTileX = (game.chunkX - 6) * 8;
        game.nextTopRightTileY = (game.chunkY - 6) * 8;
        game.aBoolean1163 = false;
        if (game.plane === undefined || game.plane === null) game.plane = 0;
        // Camera fallback: if the local player still has near-origin coords
        // (PLAYER_INFO teleport hasn't arrived or parsed cleanly), seed the
        // camera at scene-local centre tile (52, 52) so the visibility window
        // covers the populated 64×64 region. PLAYER_INFO will overwrite this
        // shortly with the real player position when it arrives.
        const lp = this.ensureLocalPlayer(game);
        if (lp && (lp.worldX === undefined || lp.worldX < 1024)) {
            // Snap the player to scene-local centre so the camera follower
            // (anInt1262/1263 = localPlayer.worldX + anInt853) lands inside
            // the 64×64 populated region. PLAYER_INFO teleport overwrites
            // this when it arrives with the real position.
            const cx = 52, cy = 52;
            if (lp.setPosition) {
                lp.setPosition(cx, cy, true);
            } else {
                if (lp.pathX) lp.pathX[0] = cx;
                if (lp.pathY) lp.pathY[0] = cy;
                lp.worldX = cx * 128 + 64;
                lp.worldY = cy * 128 + 64;
            }
            game.cameraX = lp.worldX;
            game.cameraY = lp.worldY;
            if (!(game as any).__cameraFallbackLogged) {
                (game as any).__cameraFallbackLogged = true;
                console.log("[Camera530] fallback: snapped player+cam to scene centre worldX=" + lp.worldX + " worldY=" + lp.worldY);
            }
        }
        // Mark loading-stage to "loading" so the existing 377 method144
        // pipeline picks up populated byte arrays + parses regions when
        // the async fetch below completes.
        game.loadingStage = 1;
        game.__rendererProbePending = true;
        console.log("REBUILD_NORMAL: regions=" + regionCount + " centre=(" + regionX + "," + regionZ + ") zone=(" + zoneX + "," + zoneZ + ")");

        // Tier 2f: populate game's region byte-array slots from idx5 so
        // method144 can flip to loadingStage=2 and Region.method181 can
        // parse terrain + locations into the scene. Mirrors the 377
        // OnDemand path at Game.ts:8627+ but pulls bytes from Js5Cache
        // synchronously into memory instead of going through Jaggrab.
        const js5 = (globalThis as any).js5Cache;
        if (js5 && typeof js5.getRegionBytes === "function") {
            this.populateRegionsFromJs5(game, regionBitPacked, keys, js5);
        }
        return true;
    }

    /**
     * Allocates the same byte-array slots the 377 OnDemand path populates
     * and fills them with idx5 m_X_Z (terrain, no XTEA) + l_X_Z (locations,
     * XTEA-decrypted with the per-region key from REBUILD_NORMAL). Each
     * region runs in parallel; once all complete, anIntArray857/858 are
     * cleared so method144's "still loading" check passes.
     */
    static populateRegionsFromJs5(game: any, regionBitPacked: number[], keys: Int32Array[], js5: any): void {
        const count = regionBitPacked.length;
        // 377 client uses plain number-arrays here, not Uint8Array (the
        // existing decoders in Region.method181 read with Buffer.getByte).
        // We still use the rt4 cache sourced via Js5Cache.
        const newNumberArr = (n: number, fill: number = 0) => { const a: number[] = []; for (let i = 0; i < n; i++) a.push(fill); return a; };
        game.aByteArrayArray838 = new Array<number[] | null>(count).fill(null);
        game.aByteArrayArray1232 = new Array<number[] | null>(count).fill(null);
        game.coordinates = newNumberArr(count);
        game.anIntArray857 = newNumberArr(count, -1);
        game.anIntArray858 = newNumberArr(count, -1);
        for (let i = 0; i < count; i++) {
            game.coordinates[i] = regionBitPacked[i];
            // Use 0 as the "pending" file id; -1 means "no file expected".
            // method144 returns -1 if anIntArray857[i] !== -1 && byte slot still null.
            game.anIntArray857[i] = 0;
            game.anIntArray858[i] = 0;
        }
        let pending = count * 2;
        game.regionPopulatePending530 = pending;
        const fillSlot = (which: 0 | 1, slotIdx: number, bytes: Uint8Array | null) => {
            const slotArr = which === 0 ? game.aByteArrayArray838 : game.aByteArrayArray1232;
            const idArr = which === 0 ? game.anIntArray857 : game.anIntArray858;
            if (bytes && bytes.byteLength > 0) {
                // Convert Uint8Array → number[] for the legacy Buffer parser
                const arr: number[] = new Array(bytes.byteLength);
                for (let i = 0; i < bytes.byteLength; i++) arr[i] = bytes[i];
                slotArr[slotIdx] = arr;
            } else {
                // Mark "no file" so method144 doesn't keep waiting forever.
                idArr[slotIdx] = -1;
                slotArr[slotIdx] = null;
            }
            pending--;
            game.regionPopulatePending530 = pending;
            if (pending === 0) {
                console.log("region populate complete: " + count + " regions filled");
            }
        };
        for (let i = 0; i < count; i++) {
            const regionId = regionBitPacked[i];
            const key = keys[i];
            ((idx: number, rid: number, k: Int32Array) => {
                js5.getRegionBytes("m", rid, null).then((b: Uint8Array | null) => fillSlot(0, idx, b)).catch(() => fillSlot(0, idx, null));
                js5.getRegionBytes("l", rid, k).then((b: Uint8Array | null) => fillSlot(1, idx, b)).catch(() => fillSlot(1, idx, null));
            })(i, regionId, key);
        }
    }

    static handleInstancedLocationUpdate(buf: Buffer, size: number, game: any): boolean {
        // Opcode 110: InstancedLocationUpdate (3 bytes)
        //   putS(flag)      -- signed subtract (128 - b)
        //   put(sceneX)     -- plain byte
        //   putA(sceneY)    -- additive (b + 128)
        const flag = this.g1sub(buf);
        const sceneX = this.g1(buf);
        const sceneY = this.g1add(buf);
        const plane = flag >> 1;
        const teleport = (flag & 1) !== 0;
        if (plane >= 0 && plane < 4) game.plane = plane;
        if (game) game.instancedLocationUpdate530 = { plane, teleport, sceneX, sceneY };
        return true;
    }

    static handleClearRegionChunk(buf: Buffer, size: number, game: any): boolean {
        // Opcode 112: ClearRegionChunk (2 bytes) - put(x) + putC(y)
        const x = this.g1(buf);
        const y = this.g1neg(buf);
        if (game) game.clearRegionChunk530 = { x, y };
        return true;
    }

    static handleUpdateAreaPositionA(buf: Buffer, size: number, game: any): boolean {
        // Opcode 230: UpdateAreaPosition (var-short) - putA(y) + putS(x) + chunk data
        const start = buf.currentPosition;
        let x = 0;
        let y = 0;
        if (size >= 2) {
            y = this.g1add(buf);
            x = this.g1sub(buf);
        }
        if (game) game.updateAreaPosition530 = { variant: "A", x, y, size };
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleUpdateAreaPositionB(buf: Buffer, size: number, game: any): boolean {
        // Opcode 26: UpdateAreaPosition fixed variant (2 bytes) - putC(x) + put(y)
        const x = this.g1neg(buf);
        const y = this.g1(buf);
        if (game) game.updateAreaPosition530 = { variant: "B", x, y, size };
        return true;
    }

    static handleBuildDynamicScene(buf: Buffer, size: number, game: any): boolean {
        // Opcode 214: BuildDynamicScene (var-short) - complex payload, consume
        const start = buf.currentPosition;
        const preview: number[] = [];
        const previewLen = Math.min(size, 32);
        for (let i = 0; i < previewLen; i++) preview.push(buf.buffer[start + i] & 0xFF);
        if (game) {
            game.dynamicScene530 = {
                size,
                rawPreview: preview,
                receivedAtCycle: game.pulseCycle ?? game.loopCycle ?? 0,
            };
        }
        if (size > 0) buf.currentPosition += size;
        return true;
    }

    // ── Interface drain-only packets (Tier 5c flight recorder) ──

    static recordIfUpdate(game: any, kind: string, compId: number, payload: any) {
        if (game && game.recordIfUpdate) {
            game.recordIfUpdate(kind, compId, payload);
        }
        if (compId !== 0) {
            InterfaceList.applyUpdate(game, kind, compId, payload);
        }
    }

    static handleIfSetColour(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1737 — img4(id), g2add(tracknum), ig2add(color).
        const id = this.img4(buf);
        const tracknum = this.g2add(buf);
        const color = this.ig2add(buf);
        this.recordIfUpdate(game, "IF_SETCOLOUR", id, { tracknum, color });
        return true;
    }

    static handleIfSetScrollPos(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1099 — mg4(id), ig2(pos), g2(tracknum).
        const id = this.mg4(buf);
        const pos = this.ig2(buf);
        const tracknum = this.g2(buf);
        this.recordIfUpdate(game, "IF_SETSCROLLPOS", id, { pos, tracknum });
        return true;
    }

    static handleInterfaceAnimateRotate(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1432 — mg4(ptr), g2add(tracknum), g2(pitchStep), g2add(yawStep).
        const ptr = this.mg4(buf);
        const tracknum = this.g2add(buf);
        const pitchStep = this.g2(buf);
        const yawStep = this.g2add(buf);
        this.recordIfUpdate(game, "INTERFACE_ANIMATE_ROTATE", ptr, { tracknum, pitchStep, yawStep });
        return true;
    }

    static handleGameFrameUnk(game: any): boolean {
        // rt4 Protocol.java:1768 — current reference reads no payload.
        this.recordIfUpdate(game, "GAME_FRAME_UNK", 0, {});
        return true;
    }

    static handleIfSetText2(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1212 — g2(tracknum), gjstr(text), ig2add(id).
        const start = buf.currentPosition;
        const tracknum = this.g2(buf);
        const text = this.gjstr(buf);
        const id = this.ig2add(buf);
        this.recordIfUpdate(game, "IF_SETTEXT2", id, { text, tracknum });
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleIfSetText3(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1078 — ig2(id), g2add(tracknum), gjstr(value).
        const start = buf.currentPosition;
        const id = this.ig2(buf);
        const tracknum = this.g2add(buf);
        const text = this.gjstr(buf);
        this.recordIfUpdate(game, "IF_SETTEXT3", id, { text, tracknum });
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleWidgetStructSetting(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1319 — ig2add(value), ig4(parent), g2add(tracknum), ig2(end), g2add(start).
        const startOffset = buf.currentPosition;
        const value = this.ig2add(buf);
        const parent = this.ig4(buf);
        const tracknum = this.g2add(buf);
        let end = this.ig2(buf);
        if (end === 65535) end = -1;
        let start = this.g2add(buf);
        if (start === 65535) start = -1;
        this.recordIfUpdate(game, "WIDGETSTRUCT_SETTING", parent, { value, tracknum, start, end });
        if (buf.currentPosition - startOffset < size) buf.currentPosition = startOffset + size;
        return true;
    }

    static handleSwitchWidget(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1694 — img4(source), g2add(tracknum), img4(target).
        const source = this.img4(buf);
        const tracknum = this.g2add(buf);
        const target = this.img4(buf);
        this.recordIfUpdate(game, "SWITCH_WIDGET", target, { source, target, tracknum });
        return true;
    }

    static handleUrlOpen(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1802 — gBytesIsaac(length) then browser URL open.
        let url = "";
        const end = buf.currentPosition + size;
        while (buf.currentPosition < end && buf.currentPosition < buf.buffer.length) {
            const ch = buf.buffer[buf.currentPosition++] & 0xFF;
            if (ch !== 0) url += String.fromCharCode(ch);
        }
        game.lastUrlOpen = url;
        this.recordIfUpdate(game, "URL_OPEN", 0, { url });
        try {
            if (url && typeof window !== "undefined" && /^https?:\/\//i.test(url)) {
                window.open(url, "_blank", "noopener");
            }
        } catch (e) {}
        return true;
    }

    static handleGenerateChatHeadFromBody(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1818 — g2add(tracknum), mg4(id), ig2add(value1), ig2(value2), ig2add(value3).
        const tracknum = this.g2add(buf);
        const id = this.mg4(buf);
        const value1 = this.ig2add(buf);
        const value2 = this.ig2(buf);
        const value3 = this.ig2add(buf);
        this.recordIfUpdate(game, "GENERATE_CHAT_HEAD_FROM_BODY", id, { tracknum, value1, value2, value3, modelKey: (value2 << 16) | value3 });
        return true;
    }

    static handleReflectionCheatCheck(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1750 pushes reflection tasks. Browser client has no JVM reflection surface.
        game.lastReflectionCheatCheckSize = size;
        if (size > 0) buf.currentPosition += size;
        return true;
    }

    // ── State update packets ──

    static handleTeleportLocalPlayer(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1543 — g1sub(pos1), g1add(flags), g1(pos2).
        const pos1 = this.g1sub(buf);
        const flags = this.g1add(buf);
        const pos2 = this.g1(buf);
        game.plane = flags >> 1;
        if (game.players && game.thisPlayerId != null && game.players[game.thisPlayerId]) {
            game.players[game.thisPlayerId].setPosition(pos1, pos2, (flags & 1) === 1);
        } else if ((game.constructor as any).localPlayer) {
            (game.constructor as any).localPlayer.setPosition(pos1, pos2, (flags & 1) === 1);
        }
        return true;
    }

    static handleResetClientVarCache(game: any): boolean {
        // rt4 Protocol.java:1294 — no payload, reset client-side varp cache.
        game.clientVarCacheResetAt = (game.loopCycle || game.pulseCycle || Date.now()) | 0;
        game.redrawTabArea = true;
        return true;
    }

    static handleForceVarpRefresh(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1634 — current reference reads no bytes and refreshes active varps.
        // Some handoff notes describe an older g2 varpId variant, so preserve it if present.
        if (size >= 2) {
            game.forceVarpRefreshId = this.g2(buf);
        }
        if (buf.currentPosition < size) buf.currentPosition = size;
        game.forceVarpRefreshCount = (game.forceVarpRefreshCount || 0) + 1;
        return true;
    }

    static handleResetAnims(game: any): boolean {
        // rt4 Protocol.java:1847 — clear in-flight seqId on all players and NPCs.
        const clear = (actor: any) => {
            if (!actor) return;
            actor.seqId = -1;
            actor.emoteAnimation = -1;
            actor.currentAnimation = -1;
            actor.animationDelay = 0;
        };
        if (game.players) for (const player of game.players) clear(player);
        if (game.npcs) for (const npc of game.npcs) clear(npc);
        return true;
    }

    static handleSettingsString(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:2309 currently calls method3954(gjstr()). Some 530 notes
        // describe a slot-prefixed shape; parse that adaptively without risking drift.
        if (size <= 0) return true;
        const start = buf.currentPosition;
        if (size >= 2) {
            const slot = this.g1(buf);
            const text = this.gjstr(buf);
            if (buf.currentPosition === start + size && slot >= 0 && slot < 256) {
                game.settingsStrings[slot] = text;
                return true;
            }
            buf.currentPosition = start;
        }
        const text = this.gjstr(buf);
        game.settingsStrings[0] = text;
        return true;
    }

    static handleRunWeight530(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1790 — UPDATE_RUNWEIGHT reads g2b.
        game.runWeight = this.g2b(buf);
        game.anInt1319 = game.runWeight;
        return true;
    }

    static handleSetWalkText(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1626 — empty payload restores default "Walk here".
        game.walkText = size === 0 ? "Walk here" : this.gjstr(buf);
        return true;
    }

    static handleLastLoginInfo(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1203 reads img4; keep optional legacy fields if present.
        const ip = size >= 4 ? this.img4(buf) : 0;
        const remaining = size - 4;
        const daysAgo = remaining >= 2 ? this.g2(buf) : 0;
        const recoveryDays = remaining >= 4 ? this.g2(buf) : 0;
        game.lastLogin = { ip, daysAgo, recoveryDays };
        return true;
    }

    static handleUid192(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1290 writeRandom(inboundBuffer). Store the 32-bit seed chunk.
        game.uid192 = size >= 4 ? this.g4(buf) : 0;
        if (buf.currentPosition < size) buf.currentPosition = size;
        return true;
    }

    static handleDeleteInventory(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1774 — DELETE_INVENTORY reads only ig2 container id.
        const id = this.ig2(buf);
        if (!game.deletedInventories) game.deletedInventories = [];
        game.deletedInventories.push(id & 0x7FFF);
        return true;
    }

    static handleChatFilterSettings(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:1220 — public/private/trade, one byte each.
        game.chatFilter = ChatFilterSettings.fromServer(buf);
        game.publicChatMode = game.chatFilter.publicFilter;
        game.privateChatMode = game.chatFilter.privateFilter;
        game.tradeMode = game.chatFilter.tradeFilter;
        return true;
    }

    static handleMessagePrivate(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1944 — g8 sender, g2 top, g3 bot, g1 rights, encoded body.
        const sender37 = this.g8(buf);
        const top = this.g2(buf);
        const bot = this.g3(buf);
        const rights = this.g1(buf);
        const body = this.consumeMessageBody(buf, size);
        const senderName = this.name37ToString(sender37);
        const msg: PrivateMessage = {
            senderName,
            senderName37: sender37.toString(),
            rights,
            body,
            receivedAt: Date.now(),
            direction: "in",
            messageId: this.messageId(top, bot)
        };
        game.privateMessages.push(msg);
        this.pushChat(game, rights !== 0 ? `@cr${Math.min(rights, 2)}@${senderName}` : senderName, body, rights !== 0 ? 7 : 3);
        return true;
    }

    static handleMessagePrivateEcho(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1796 — g8 recipient, encoded outgoing body.
        const target37 = this.g8(buf);
        const body = this.consumeMessageBody(buf, size);
        const targetName = this.name37ToString(target37);
        game.privateMessages.push({
            senderName: targetName,
            senderName37: target37.toString(),
            rights: 0,
            body,
            receivedAt: Date.now(),
            direction: "out"
        });
        this.pushChat(game, targetName, body, 6);
        return true;
    }

    static handleMessageQuickchatPrivate(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1655 — g8 sender, g2/g3 id pair, g1 rights, g2 quickchat id.
        const sender37 = this.g8(buf);
        const top = this.g2(buf);
        const bot = this.g3(buf);
        const rights = this.g1(buf);
        const quickchatId = this.g2(buf);
        const body = this.consumeQuickChatPayload(buf, size);
        const senderName = this.name37ToString(sender37);
        game.privateMessages.push({
            senderName,
            senderName37: sender37.toString(),
            rights,
            body,
            receivedAt: Date.now(),
            direction: "in",
            messageId: this.messageId(top, bot),
            quickchatId
        });
        this.pushChat(game, rights !== 0 ? `@cr${Math.min(rights, 2)}@${senderName}` : senderName, body, 7);
        return true;
    }

    static handleMessageQuickchatPrivateEcho(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1283 — g8 recipient, g2 quickchat id, variable quickchat params.
        const target37 = this.g8(buf);
        const quickchatId = this.g2(buf);
        const body = this.consumeQuickChatPayload(buf, size);
        const targetName = this.name37ToString(target37);
        game.privateMessages.push({
            senderName: targetName,
            senderName37: target37.toString(),
            rights: 0,
            body,
            receivedAt: Date.now(),
            direction: "out",
            quickchatId
        });
        this.pushChat(game, targetName, body, 6);
        return true;
    }

    static ensureClanState(game: any): ClanState {
        if (!game.clanState) {
            game.clanState = { name: "", owner: "", world: 0, rank: 0, minKick: 0, members: [], messages: [] };
        }
        if (!game.clanState.messages) game.clanState.messages = [];
        if (!game.clanState.members) game.clanState.members = [];
        return game.clanState;
    }

    static handleMessageClanChannel(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1987 — g8 sender, g1b world/rank byte, g8 clan, g2/g3 id, g1 rights, body.
        const sender37 = this.g8(buf);
        this.g1b(buf);
        const clan37 = this.g8(buf);
        const top = this.g2(buf);
        const bot = this.g3(buf);
        const rights = this.g1(buf);
        const body = this.consumeMessageBody(buf, size);
        const senderName = this.name37ToString(sender37);
        const clanName = this.name37ToString(clan37);
        const msg: PrivateMessage = {
            senderName,
            senderName37: sender37.toString(),
            rights,
            body,
            receivedAt: Date.now(),
            direction: "clan",
            messageId: this.messageId(top, bot),
            clanName
        };
        const clan = this.ensureClanState(game);
        clan.name = clan.name || clanName;
        clan.messages.push(msg);
        this.pushChat(game, `[${clanName}] ${rights !== 0 ? `@cr${Math.min(rights, 2)}@` : ""}${senderName}`, body, 16);
        return true;
    }

    static handleClanQuickChat(buf: Buffer, size: number, game: any): boolean {
        // rt4 Protocol.java:1107 — clan-channel quickchat; payload after quickchatId is Huffman-backed params.
        const sender37 = this.g8(buf);
        this.g1b(buf);
        const clan37 = this.g8(buf);
        const top = this.g2(buf);
        const bot = this.g3(buf);
        const rights = this.g1(buf);
        const quickchatId = this.g2(buf);
        const body = this.consumeQuickChatPayload(buf, size);
        const senderName = this.name37ToString(sender37);
        const clanName = this.name37ToString(clan37);
        const msg: PrivateMessage = {
            senderName,
            senderName37: sender37.toString(),
            rights,
            body,
            receivedAt: Date.now(),
            direction: "clan",
            messageId: this.messageId(top, bot),
            quickchatId,
            clanName
        };
        const clan = this.ensureClanState(game);
        clan.name = clan.name || clanName;
        clan.messages.push(msg);
        this.pushChat(game, `[${clanName}] ${senderName}`, body, 20);
        return true;
    }

    static handleUpdateClan(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:2172 — member add/update or high-bit remove.
        let name37 = this.g8(buf);
        const world = this.g2(buf);
        const rank = this.g1b(buf);
        const clan = this.ensureClanState(game);
        const removed = name37.isNegative();
        if (removed) {
            name37 = new Long(name37.low, name37.high & 0x7FFFFFFF);
            const key = name37.toString();
            clan.members = clan.members.filter(member => !(member.name37 === key && member.world === world));
            return true;
        }
        const worldName = this.gjstr(buf);
        const name = this.name37ToString(name37);
        const key = name37.toString();
        const existing = clan.members.find(member => member.name37 === key);
        if (existing) {
            existing.world = world;
            existing.rank = rank;
            existing.worldName = worldName;
        } else {
            clan.members.push({ name, name37: key, world, worldName, rank });
            clan.members.sort((a, b) => a.name.localeCompare(b.name));
        }
        return true;
    }

    static handleVarpSmall(buf: Buffer, game: any): boolean {
        // Opcode 60: VARP_SMALL (3 bytes)
        // Server: putShortA(id) + putC(value)
        const id = this.g2add(buf);
        const value = this.g1c(buf);
        if (game.widgetSettings && id < game.widgetSettings.length) {
            game.widgetSettings[id] = value;
        }
        return true;
    }

    static handleVarpLarge(buf: Buffer, game: any): boolean {
        // Opcode 226: VARP_LARGE (6 bytes)
        const value = this.g4(buf);
        const id = this.g2add(buf);
        if (game.widgetSettings && id < game.widgetSettings.length) {
            game.widgetSettings[id] = value;
        }
        return true;
    }

    static handleUpdateStat(buf: Buffer, game: any): boolean {
        // Opcode 38: UPDATE_STAT (6 bytes)
        // Server writes: putA(level), putIntA(xp), put(skillId)
        // putIntA order: B1 B0 B3 B2 — matches mg4() reader.
        const boostedLevel = this.g1add(buf);
        const xp = this.mg4(buf);
        const skillId = this.g1(buf);
        if (game.currentStats && skillId < game.currentStats.length) {
            game.currentStats[skillId] = boostedLevel;
            if (game.statXp) game.statXp[skillId] = xp;
        }
        return true;
    }

    static handleGameMessage(buf: Buffer, size: number, game: any): boolean {
        // Opcode 70: MESSAGE_GAME (var-byte) — just a NUL-terminated string, no type prefix.
        // addChatMessage signature is (name, message, type); 0 is the plain game-message type.
        const message = this.gjstr(buf);
        if (game.addChatMessage) {
            game.addChatMessage("", message, 0);
        }
        return true;
    }

    static handleSynthSound(buf: Buffer, game: any): boolean {
        // rt4 Protocol.java:2032 — g2 trackId, g1 volume, g2 delay.
        let trackId = this.g2(buf);
        const volume = this.g1(buf);
        if (trackId === 65535) trackId = -1;
        const delay = this.g2(buf);
        if (trackId >= 0) SoundPlayer.play(volume, trackId, delay);
        return true;
    }

    static handleMinimapState(buf: Buffer, game: any): boolean {
        // Opcode 192: MinimapState (1 byte)
        game.minimapState = this.g1(buf);
        return true;
    }

    static handleRunEnergy(buf: Buffer, game: any): boolean {
        // Opcode 234: RunEnergy (1 byte)
        game.anInt1324 = this.g1(buf);
        return true;
    }

    static handleWeightUpdate(buf: Buffer, game: any): boolean {
        // Opcode 174: WeightUpdate (2 bytes)
        game.anInt1319 = this.g2(buf);
        return true;
    }

    static handleClearMinimapFlag(buf: Buffer, game: any): boolean {
        // Opcode 153: ClearMinimapFlag (0 bytes)
        game.destinationX = 0;
        game.destinationY = 0;
        return true;
    }

    static handleLogout(buf: Buffer, game: any): boolean {
        // Opcode 86: Logout (0 bytes)
        if (game.logout) game.logout();
        return true;
    }

    static handleSystemUpdate(buf: Buffer, game: any): boolean {
        // Opcode 85: SystemUpdate (2 bytes). Server sends remaining ticks/seconds.
        // Client renders seconds as `systemUpdateTime / 50`, so multiply by 50 to present in seconds.
        game.systemUpdateTime = this.g2(buf) * 50;
        return true;
    }

    static handleContactStatus(buf: Buffer, game: any): boolean {
        // Opcode 197: Contact status (1 byte)
        game.friendListStatus = this.g1(buf);
        return true;
    }

    // ── Entity synchronization ──

    static handlePlayerInfo(buf: Buffer, size: number, game: any): boolean {
        // Opcode 225: PLAYER_INFO (var-short, bit-packed)
        //
        // Layout (from 2009scape server PlayerRenderer.kt):
        //   updateLocalPosition: either teleport block (1+2+7+1+2+1+7 = 21 bits) or
        //                        renderLocalPlayer block (walking/running/mask/idle).
        //   8 bits: count of currently-tracked remote players
        //   For each tracked: renderLocalPlayer block
        //   For each new (up to 10): 11+1+5+3+1+5 = 26 bits
        //   11 bits sentinel (2047) if any mask updates, then byte-aligned mask data.
        //
        // Keep the 377 actor-list state in sync with the native 530 bitstream:
        // local movement, tracked remote movement/removal, and newly visible
        // remote players are applied here. Appearance/chat/animation masks are
        // still byte-skipped below until those 530 mask bodies are ported.
        const startPos = buf.currentPosition;
        buf.initBitAccess();
        try {
            game.removePlayerCount = 0;
            game.updatedPlayerCount = 0;
            this.parseLocalPlayerPosition(buf, game);
            this.parseTrackedPlayers(buf, game);
            this.parseNewPlayers(buf, size, startPos, game);
            buf.finishBitAccess();
            this.parsePlayerMasks(buf, startPos + size, game);
            this.removeStalePlayers(game);
        } catch (e) {
            // Malformed bit stream — swallow and realign to packet end
        }
        buf.currentPosition = startPos + size;
        return true;
    }

    static parseLocalPlayerPosition(buf: Buffer, game: any): void {
        const updating = buf.getBits(1);
        if (!updating) return;
        const subOpcode = buf.getBits(2);
        const localPlayer = this.ensureLocalPlayer(game);
        if (subOpcode === 3) {
            // Teleport: sceneY(7) + teleport(1) + z(2) + maskRequired(1) + sceneX(7)
            const sceneY = buf.getBits(7);
            const teleporting = buf.getBits(1);
            const z = buf.getBits(2);
            const maskRequired = buf.getBits(1);
            const sceneX = buf.getBits(7);
            if (maskRequired === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = game.thisPlayerId;
            }
            game.plane = z & 3;
            if (localPlayer) {
                if (localPlayer.setPosition) {
                    localPlayer.setPosition(sceneX, sceneY, teleporting === 1);
                } else {
                    localPlayer.pathX[0] = sceneX;
                    localPlayer.pathY[0] = sceneY;
                    localPlayer.worldX = sceneX * 128 + 64;
                    localPlayer.worldY = sceneY * 128 + 64;
                }
                if (!(game as any).__teleportLogged) {
                    (game as any).__teleportLogged = true;
                    console.log("[PlayerPos530] teleport sceneX=" + sceneX + " sceneY=" + sceneY + " z=" + z + " teleporting=" + teleporting + " worldX=" + localPlayer.worldX + " worldY=" + localPlayer.worldY);
                }
                // Always snap the camera to the new player position on teleport
                // (377 only seeded the camera once on first arrival; for the 530
                // path we want every teleport / region rebuild to recentre).
                game.cameraX = localPlayer.worldX;
                game.cameraY = localPlayer.worldY;
            }
        } else if (subOpcode === 2) {
            // rt4 readSelfPlayerInfo type 2:
            //   if double-step bit is 1: dir(3) + dir(3), both speed 2
            //   else: dir(3), speed 0
            const doubleStep = buf.getBits(1);
            const walkDir = buf.getBits(3);
            if (localPlayer && localPlayer.move) {
                localPlayer.move(walkDir, doubleStep === 1);
            }
            if (doubleStep === 1) {
                const runDir = buf.getBits(3);
                if (localPlayer && localPlayer.move) {
                    localPlayer.move(runDir, true);
                }
            }
            const maskRequired = buf.getBits(1);
            if (maskRequired === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = game.thisPlayerId;
            }
        } else if (subOpcode === 1) {
            // Walk: walkDir(3) + maskRequired(1)
            const walkDir = buf.getBits(3);
            const maskRequired = buf.getBits(1);
            if (localPlayer && localPlayer.move) {
                localPlayer.move(walkDir, false);
            }
            if (maskRequired === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = game.thisPlayerId;
            }
        } else {
            // subOpcode 0: maskRequired only — position unchanged.
            const maskRequired = buf.getBits(1);
            if (maskRequired === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = game.thisPlayerId;
            }
        }
    }

    static parseTrackedPlayers(buf: Buffer, game: any): void {
        const trackedCount = buf.getBits(8);
        const oldCount = game.localPlayerCount || 0;
        if (trackedCount < oldCount) {
            for (let i = trackedCount; i < oldCount; i++) {
                game.removePlayers[game.removePlayerCount++] = game.playerList[i];
            }
        }

        game.localPlayerCount = 0;
        const safeTrackedCount = Math.min(trackedCount, oldCount, 2047);
        for (let i = 0; i < safeTrackedCount; i++) {
            const id = game.playerList[i];
            const player = game.players[id];
            if (!player) {
                this.skipRenderBlock(buf);
                continue;
            }
            this.parseTrackedPlayerBlock(buf, game, id, player);
        }

        // If the server reports more tracked players than this bridge knows
        // about, consume their movement blocks to preserve stream alignment.
        for (let i = safeTrackedCount; i < trackedCount && i < 2047; i++) {
            this.skipRenderBlock(buf);
        }
    }

    static parseTrackedPlayerBlock(buf: Buffer, game: any, id: number, player: any): void {
        const updating = buf.getBits(1);
        if (!updating) {
            game.playerList[game.localPlayerCount++] = id;
            player.pulseCycle = game.constructor.pulseCycle;
            return;
        }
        const subOpcode = buf.getBits(2);
        if (subOpcode === 0) {
            game.playerList[game.localPlayerCount++] = id;
            player.pulseCycle = game.constructor.pulseCycle;
            game.updatedPlayers[game.updatedPlayerCount++] = id;
        } else if (subOpcode === 1) {
            game.playerList[game.localPlayerCount++] = id;
            player.pulseCycle = game.constructor.pulseCycle;
            player.move(buf.getBits(3), false);
            if (buf.getBits(1) === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = id;
            }
        } else if (subOpcode === 2) {
            game.playerList[game.localPlayerCount++] = id;
            player.pulseCycle = game.constructor.pulseCycle;
            const doubleStep = buf.getBits(1);
            player.move(buf.getBits(3), doubleStep === 1);
            if (doubleStep === 1) {
                player.move(buf.getBits(3), true);
            }
            if (buf.getBits(1) === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = id;
            }
        } else {
            game.removePlayers[game.removePlayerCount++] = id;
        }
    }

    static parseNewPlayers(buf: Buffer, size: number, startPos: number, game: any): void {
        while (true) {
            const remainingBits = (size * 8) - (buf.bitPosition - startPos * 8);
            if (remainingBits < 11) break;
            const id = buf.getBits(11);
            if (id === 2047) break;
            if ((size * 8) - (buf.bitPosition - startPos * 8) < 15) break;

            const player = this.ensurePlayer(game, id);
            game.playerList[game.localPlayerCount++] = id;
            player.pulseCycle = game.constructor.pulseCycle;

            const update = buf.getBits(1);
            let offsetX = buf.getBits(5);
            const direction = buf.getBits(3);
            const teleport = buf.getBits(1);
            let offsetY = buf.getBits(5);
            if (offsetX > 15) offsetX -= 32;
            if (offsetY > 15) offsetY -= 32;
            player.nextStepOrientation = PacketHandler530.ANGLES[direction & 7];
            const localPlayer = this.ensureLocalPlayer(game);
            player.setPosition(localPlayer.pathX[0] + offsetX, localPlayer.pathY[0] + offsetY, teleport === 1);
            if (update === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = id;
            }
        }
    }

    static parsePlayerMasks(buf: Buffer, endPos: number, game: any): void {
        for (let i = 0; i < game.updatedPlayerCount && buf.currentPosition < endPos; i++) {
            const id = game.updatedPlayers[i];
            const player = id === 2047 ? this.ensureLocalPlayer(game) : this.ensurePlayer(game, id);
            let flags = buf.getUnsignedByte();
            if ((flags & 0x10) !== 0 && buf.currentPosition < endPos) {
                flags += buf.getUnsignedByte() << 8;
            }
            this.parsePlayerMask(flags, id, player, buf, game);
        }
    }

    static parsePlayerMask(flags: number, id: number, player: any, buf: Buffer, game: any): void {
        // Order follows server PlayerFlags530 ordinal order / rt4 Protocol.readExtendedPlayerInfo.
        if ((flags & 0x80) !== 0) {
            buf.currentPosition += 2; // chat effects (ip2)
            buf.currentPosition += 1; // chat icon
            const length = buf.getUnsignedByte();
            buf.currentPosition += length;
        }
        if ((flags & 0x1) !== 0) {
            this.skipSmart(buf);
            buf.currentPosition += 2; // hit type + hp ratio
        }
        if ((flags & 0x8) !== 0) {
            const animation = this.g2(buf);
            const delay = this.g1(buf);
            if (player) {
                player.emoteAnimation = animation === 65535 ? -1 : animation;
                player.animationDelay = delay;
                player.displayedEmoteFrames = 0;
                player.anInt1626 = 0;
                player.anInt1628 = 0;
            }
        }
        if ((flags & 0x4) !== 0) {
            this.parseAppearanceMask(buf, id, player, game);
        }
        if ((flags & 0x2) !== 0) {
            if (player) {
                player.anInt1609 = this.g2add(buf);
                if (player.anInt1609 === 65535) player.anInt1609 = -1;
            } else {
                buf.currentPosition += 2;
            }
        }
        if ((flags & 0x400) !== 0) {
            buf.currentPosition += 9;
            if (player && player.resetPath) player.resetPath();
        }
        if ((flags & 0x20) !== 0) {
            const text = this.gjstr(buf);
            if (player) {
                player.forcedChat = text.charAt(0) === "~" ? text.substring(1) : text;
                player.textColour = 0;
                player.textEffect = 0;
                player.textCycle = 150;
            }
        }
        if ((flags & 0x200) !== 0) {
            this.skipSmart(buf);
            buf.currentPosition += 1; // secondary hit type
        }
        if ((flags & 0x800) !== 0) {
            // 2009scape's 530 AnimationSequence mask is still TODO server-side.
        }
        if ((flags & 0x100) !== 0) {
            if (player) {
                player.graphic = this.ig2(buf);
                const heightAndDelay = this.mg4(buf);
                player.spotAnimationDelay = heightAndDelay >> 16;
                player.anInt1617 = game.constructor.pulseCycle + (heightAndDelay & 65535);
                player.currentAnimation = player.anInt1617 > game.constructor.pulseCycle ? -1 : 0;
                player.anInt1616 = 0;
                if (player.graphic === 65535) player.graphic = -1;
            } else {
                buf.currentPosition += 6;
            }
        }
        if ((flags & 0x40) !== 0) {
            if (player) {
                player.anInt1598 = this.g2(buf);
                player.anInt1599 = this.ig2add(buf);
            } else {
                buf.currentPosition += 4;
            }
        }
    }

    static parseAppearanceMask(buf: Buffer, id: number, player: any, game: any): void {
        const length = buf.getByteAdded();
        const start = buf.currentPosition;
        // Snapshot the raw 530 wire slice before we consume it. The 377-shape
        // bytes assembled below feed the legacy avatar; the snapshot feeds
        // applyAppearanceMask() so PlayerAppearance530.composeAppearanceModel
        // can rebuild the rev-530 mesh on the next compose tick.
        const raw530Bytes = new Uint8Array(length);
        if (length > 0 && buf.buffer && start + length <= buf.buffer.length) {
            for (let i = 0; i < length; i++) raw530Bytes[i] = buf.buffer[start + i] & 0xFF;
        }
        const bytes: number[] = [];
        const pushByte = (value: number) => bytes.push(value & 0xFF);
        const pushShort = (value: number) => {
            pushByte(value >> 8);
            pushByte(value);
        };

        const settings = this.g1(buf);
        pushByte(settings & 1); // 377 only understands the gender bit.
        pushByte(this.g1b(buf)); // skull
        pushByte(this.g1b(buf)); // prayer/head icon

        let npcTransform = false;
        for (let part = 0; part < 12; part++) {
            const upper = this.g1(buf);
            if (upper === 0) {
                pushByte(0);
                continue;
            }
            const lower = this.g1(buf);
            const raw = (upper << 8) | lower;
            if (part === 0 && raw === 65535) {
                npcTransform = true;
                pushShort(65535);
                pushShort(this.g2(buf));
                buf.currentPosition += 1; // 530 team byte; 377 derives team from items.
                break;
            }
            const converted = this.convertAppearancePart530(raw);
            pushShort(converted);
        }

        for (let color = 0; color < 5; color++) {
            pushByte(this.g1(buf));
        }

        const basId = this.g2(buf);
        const bas = this.getBas(game, basId);
        const idle = bas ? bas.idleAnimationId : -1;
        const walk = bas ? bas.walkAnimation : -1;
        const turnAround = bas && bas.walkFullTurnAnimationId !== -1 ? bas.walkFullTurnAnimationId : walk;
        const turnRight = bas && bas.walkCWTurnAnimationId !== -1 ? bas.walkCWTurnAnimationId : walk;
        const turnLeft = bas && bas.walkCCWTurnAnimationId !== -1 ? bas.walkCCWTurnAnimationId : walk;
        const run = bas ? bas.runAnimationId : -1;
        pushShort(idle === -1 ? 65535 : idle);
        pushShort(bas && bas.standingCWTurn !== -1 ? bas.standingCWTurn : (idle === -1 ? 65535 : idle));
        pushShort(walk === -1 ? 65535 : walk);
        pushShort(turnAround === -1 ? 65535 : turnAround);
        pushShort(turnRight === -1 ? 65535 : turnRight);
        pushShort(turnLeft === -1 ? 65535 : turnLeft);
        pushShort(run === -1 ? 65535 : run);

        for (let i = 0; i < 8; i++) pushByte(this.g1(buf)); // base37 username
        pushByte(this.g1(buf)); // combat level
        const showSkillLevel = (settings & 0x4) !== 0;
        if (showSkillLevel) {
            pushShort(this.g2(buf));
        } else {
            buf.currentPosition += 2; // combat with summoning + combat range
            pushShort(0);
        }
        const soundRadius = this.g1(buf);
        if (soundRadius !== 0) {
            buf.currentPosition += 8;
        }

        if (player && !npcTransform) {
            const appearance = new Buffer(bytes);
            game.cachedAppearances[id] = appearance;
            player.updateAppearance(appearance);
        } else if (player) {
            const appearance = new Buffer(bytes);
            game.cachedAppearances[id] = appearance;
            player.updateAppearance(appearance);
        }
        // 530 path: parse the raw wire bytes into PlayerAppearance530Data and
        // mark the player dirty. The compose poller in Game.ts picks this up
        // and runs composeAppearanceModel asynchronously.
        if (player && !npcTransform && raw530Bytes.length > 0) {
            try {
                applyAppearanceMask(player, raw530Bytes);
            } catch (e) {
                // Decode failures are silent — the legacy 377 avatar still renders.
            }
        }
        buf.currentPosition = start + length;
    }

    static convertAppearancePart530(raw: number): number {
        if (raw < 32768) return raw;
        const equipId = raw - 32768;
        const equipment = this.getEquipmentObjIds530();
        const itemId = equipment && equipId >= 0 && equipId < equipment.length ? equipment[equipId] : equipId;
        return itemId + 512;
    }

    static getEquipmentObjIds530(): number[] | null {
        if (this.equipmentObjIds530) return this.equipmentObjIds530;
        const ItemDefinition = require("./cache/def/ItemDefinition").ItemDefinition;
        const cache530: Map<number, any> | null = ItemDefinition.cache530;
        if (!cache530) return null;
        this.equipmentObjIds530 = Array.from(cache530.entries())
            .filter((entry) => entry[1] && (entry[1].manwear >= 0 || entry[1].womanwear >= 0))
            .sort((a, b) => a[0] - b[0])
            .map((entry) => entry[0]);
        return this.equipmentObjIds530;
    }

    static getBas(game: any, id: number): any {
        if (id === 65535 || id < 0) return null;
        const ActorDefinition = require("./cache/def/ActorDefinition").ActorDefinition;
        return ActorDefinition.basCache530 ? ActorDefinition.basCache530.get(id) : null;
    }

    static removeStalePlayers(game: any): void {
        for (let i = 0; i < game.removePlayerCount; i++) {
            const id = game.removePlayers[i];
            const player = game.players[id];
            if (player && player.pulseCycle !== game.constructor.pulseCycle) {
                game.players[id] = null;
            }
        }
    }

    static ensureLocalPlayer(game: any): any {
        const player = this.ensurePlayer(game, game.thisPlayerId);
        const GameClass = require("./Game").Game;
        if (!GameClass.localPlayer) {
            GameClass.localPlayer = player;
        }
        return player;
    }

    static ensurePlayer(game: any, id: number): any {
        if (!game.players || id < 0 || id >= game.players.length) return null;
        let player = game.players[id];
        if (!player) {
            const PlayerClass = require("./media/renderable/actor/Player").Player;
            player = new PlayerClass();
            game.players[id] = player;
            if (game.cachedAppearances && game.cachedAppearances[id]) {
                player.updateAppearance(game.cachedAppearances[id]);
            }
        }
        return player;
    }

    static readonly ANGLES: number[] = [768, 1024, 1280, 512, 1536, 256, 0, 1792];

    static skipSmart(buf: Buffer): void {
        const peek = buf.buffer[buf.currentPosition] & 0xFF;
        buf.currentPosition += peek < 128 ? 1 : 2;
    }

    static skipRenderBlock(buf: Buffer): void {
        const updating = buf.getBits(1);
        if (!updating) return;
        const subOpcode = buf.getBits(2);
        if (subOpcode === 0) {
            buf.getBits(1); // mask required
        } else if (subOpcode === 1) {
            buf.getBits(3); // walkDir
            buf.getBits(1); // mask required
        } else if (subOpcode === 2) {
            const doubleStep = buf.getBits(1);
            buf.getBits(3); // walkDir
            if (doubleStep === 1) {
                buf.getBits(3); // runDir
            }
            buf.getBits(1); // mask required
        } else {
            buf.getBits(7); // sceneY
            buf.getBits(1); // teleport
            buf.getBits(2); // z
            buf.getBits(1); // mask required
            buf.getBits(7); // sceneX
        }
    }

    static handleNpcInfo(buf: Buffer, size: number, game: any): boolean {
        // Opcode 32: NPC_INFO (var-short, bit-packed). Server source:
        // 2009scape NPCRenderer.kt. This mirrors the 377 actor-list fields
        // (`anInt1133`, `anIntArray1134`, `npcs`) so the existing scene code
        // can draw 530 NPC definitions.
        const startPos = buf.currentPosition;
        buf.initBitAccess();
        try {
            game.removePlayerCount = 0;
            game.updatedPlayerCount = 0;
            this.parseTrackedNpcs(buf, game);
            this.parseNewNpcs(buf, size, startPos, game);
            buf.finishBitAccess();
            this.parseNpcMasks(buf, startPos + size, game);
            this.removeStaleNpcs(game);
        } catch (e) {
            // Keep the packet stream aligned if a definition/mask is malformed.
        }
        buf.currentPosition = startPos + size;
        return true;
    }

    static parseTrackedNpcs(buf: Buffer, game: any): void {
        const npcCount = buf.getBits(8);
        const oldCount = game.anInt1133 || 0;
        if (npcCount < oldCount) {
            for (let i = npcCount; i < oldCount; i++) {
                game.removePlayers[game.removePlayerCount++] = game.anIntArray1134[i];
            }
        }
        game.anInt1133 = 0;
        const safeCount = Math.min(npcCount, oldCount, 255);
        for (let i = 0; i < safeCount; i++) {
            const id = game.anIntArray1134[i];
            const npc = game.npcs[id];
            if (!npc) {
                this.skipNpcMovementBlock(buf);
                continue;
            }
            const updating = buf.getBits(1);
            if (updating === 0) {
                game.anIntArray1134[game.anInt1133++] = id;
                npc.pulseCycle = game.constructor.pulseCycle;
                continue;
            }
            const type = buf.getBits(2);
            if (type === 0) {
                game.anIntArray1134[game.anInt1133++] = id;
                npc.pulseCycle = game.constructor.pulseCycle;
                game.updatedPlayers[game.updatedPlayerCount++] = id;
            } else if (type === 1) {
                game.anIntArray1134[game.anInt1133++] = id;
                npc.pulseCycle = game.constructor.pulseCycle;
                npc.move(buf.getBits(3), false);
                if (buf.getBits(1) === 1) game.updatedPlayers[game.updatedPlayerCount++] = id;
            } else if (type === 2) {
                game.anIntArray1134[game.anInt1133++] = id;
                npc.pulseCycle = game.constructor.pulseCycle;
                const doubleStep = buf.getBits(1);
                if (doubleStep === 1) {
                    npc.move(buf.getBits(3), true);
                    npc.move(buf.getBits(3), true);
                } else {
                    npc.move(buf.getBits(3), false);
                }
                if (buf.getBits(1) === 1) game.updatedPlayers[game.updatedPlayerCount++] = id;
            } else {
                game.removePlayers[game.removePlayerCount++] = id;
            }
        }
        for (let i = safeCount; i < npcCount && i < 255; i++) {
            this.skipNpcMovementBlock(buf);
        }
    }

    static parseNewNpcs(buf: Buffer, size: number, startPos: number, game: any): void {
        while (true) {
            const remainingBits = (size * 8) - (buf.bitPosition - startPos * 8);
            if (remainingBits < 15) break;
            const index = buf.getBits(15);
            if (index === 32767) break;
            if ((size * 8) - (buf.bitPosition - startPos * 8) < 29) break;

            const npc = this.ensureNpc(game, index);
            const teleport = buf.getBits(1);
            npc.nextStepOrientation = PacketHandler530.ANGLES[buf.getBits(3) & 7];
            if (buf.getBits(1) === 1) {
                game.updatedPlayers[game.updatedPlayerCount++] = index;
            }
            let offsetY = buf.getBits(5);
            const typeId = buf.getBits(14);
            let offsetX = buf.getBits(5);
            if (offsetX > 15) offsetX -= 32;
            if (offsetY > 15) offsetY -= 32;
            this.applyNpcDefinition(npc, typeId);
            game.anIntArray1134[game.anInt1133++] = index;
            npc.pulseCycle = game.constructor.pulseCycle;
            const localPlayer = this.ensureLocalPlayer(game);
            npc.setPosition(localPlayer.pathX[0] + offsetX, localPlayer.pathY[0] + offsetY, teleport === 1);
        }
    }

    static parseNpcMasks(buf: Buffer, endPos: number, game: any): void {
        for (let i = 0; i < game.updatedPlayerCount && buf.currentPosition < endPos; i++) {
            const id = game.updatedPlayers[i];
            const npc = this.ensureNpc(game, id);
            let flags = buf.getUnsignedByte();
            if ((flags & 0x8) !== 0 && buf.currentPosition < endPos) {
                flags += buf.getUnsignedByte() << 8;
            }
            if ((flags & 0x40) !== 0) {
                const damage = this.g1(buf);
                const type = this.g1neg(buf);
                if (npc) npc.updateHits(type, damage, game.constructor.pulseCycle);
                buf.currentPosition += 1; // hp ratio
            }
            if ((flags & 0x2) !== 0) {
                const damage = this.g1neg(buf);
                const type = this.g1sub(buf);
                if (npc) npc.updateHits(type, damage, game.constructor.pulseCycle);
            }
            if ((flags & 0x10) !== 0) {
                const animation = this.g2(buf);
                const delay = this.g1(buf);
                if (npc) {
                    npc.emoteAnimation = animation === 65535 ? -1 : animation;
                    npc.animationDelay = delay;
                    npc.displayedEmoteFrames = 0;
                    npc.anInt1626 = 0;
                    npc.anInt1628 = 0;
                }
            }
            if ((flags & 0x4) !== 0) {
                if (npc) {
                    npc.anInt1609 = this.g2add(buf);
                    if (npc.anInt1609 === 65535) npc.anInt1609 = -1;
                } else {
                    buf.currentPosition += 2;
                }
            }
            if ((flags & 0x80) !== 0) {
                if (npc) {
                    npc.graphic = this.g2add(buf);
                    const heightAndDelay = this.ig4(buf);
                    npc.spotAnimationDelay = heightAndDelay >> 16;
                    npc.anInt1617 = game.constructor.pulseCycle + (heightAndDelay & 65535);
                    npc.currentAnimation = npc.anInt1617 > game.constructor.pulseCycle ? -1 : 0;
                    npc.anInt1616 = 0;
                    if (npc.graphic === 65535) npc.graphic = -1;
                } else {
                    buf.currentPosition += 6;
                }
            }
            if ((flags & 0x1) !== 0) {
                this.applyNpcDefinition(npc, this.ig2(buf));
            }
            if ((flags & 0x20) !== 0) {
                if (npc) {
                    npc.forcedChat = this.gjstr(buf);
                    npc.textColour = 0;
                    npc.textEffect = 0;
                    npc.textCycle = 150;
                } else {
                    this.gjstr(buf);
                }
            }
            if ((flags & 0x100) !== 0) {
                // 2009scape's 530 NPC animation-sequence mask is currently TODO.
            }
            if ((flags & 0x200) !== 0) {
                if (npc) {
                    npc.anInt1598 = this.g2add(buf);
                    npc.anInt1599 = this.g2(buf);
                } else {
                    buf.currentPosition += 4;
                }
            }
        }
    }

    static removeStaleNpcs(game: any): void {
        for (let i = 0; i < game.removePlayerCount; i++) {
            const id = game.removePlayers[i];
            const npc = game.npcs[id];
            if (npc && npc.pulseCycle !== game.constructor.pulseCycle) {
                npc.npcDefinition = null;
                game.npcs[id] = null;
            }
        }
    }

    static skipNpcMovementBlock(buf: Buffer): void {
        const updating = buf.getBits(1);
        if (!updating) return;
        const type = buf.getBits(2);
        if (type === 0) {
            return;
        } else if (type === 1) {
            buf.getBits(3);
            buf.getBits(1);
        } else if (type === 2) {
            const doubleStep = buf.getBits(1);
            buf.getBits(3);
            if (doubleStep === 1) {
                buf.getBits(3);
            }
            buf.getBits(1);
        }
    }

    static ensureNpc(game: any, id: number): any {
        if (!game.npcs) return null;
        let npc = game.npcs[id];
        if (!npc) {
            const NpcClass = require("./media/renderable/actor/Npc").Npc;
            npc = new NpcClass();
            game.npcs[id] = npc;
        }
        return npc;
    }

    static applyNpcDefinition(npc: any, typeId: number): void {
        if (!npc) return;
        const ActorDefinition = require("./cache/def/ActorDefinition").ActorDefinition;
        npc.npcDefinition = ActorDefinition.getDefinition(typeId);
        if (!npc.npcDefinition) return;
        npc.boundaryDimension = npc.npcDefinition.boundaryDimension;
        npc.anInt1600 = npc.npcDefinition.degreesToTurn;
        npc.walkAnimationId = npc.npcDefinition.walkAnimationId;
        npc.turnAroundAnimationId = npc.npcDefinition.turnAroundAnimationId;
        npc.turnRightAnimationId = npc.npcDefinition.turnRightAnimationId;
        npc.turnLeftAnimationId = npc.npcDefinition.turnLeftAnimationId;
        npc.idleAnimation = npc.npcDefinition.standAnimationId;
    }

    // ── Camera packets ──
    // All camera packets prefix with a 2-byte packetCount (interface-sequence
    // tracking). The useful data follows.

    static handleCamPosition(buf: Buffer, game: any): boolean {
        // Opcode 154: POSITION — cameraMoveTo
        // putShort(packetCount) put(x) put(y) putShort(height) put(speed) put(zoomSpeed)
        this.g2(buf); // packetCount
        const sceneX = this.g1(buf);
        const sceneY = this.g1(buf);
        const height = this.g2(buf);
        const speed = this.g1(buf);
        const zoomSpeed = this.g1(buf);
        game.oriented = true;
        game.anInt874 = sceneX;
        game.anInt875 = sceneY;
        game.anInt876 = height;
        game.anInt877 = speed;
        game.anInt878 = zoomSpeed;
        if (zoomSpeed >= 100 && game.getTileHeight) {
            game.cameraX = sceneX * 128 + 64;
            game.cameraY = sceneY * 128 + 64;
            game.cameraZ = game.getTileHeight(game.cameraY, game.cameraX, 9 | 0, game.plane) - height;
        }
        return true;
    }

    static handleCamRotation(buf: Buffer, game: any): boolean {
        // Opcode 125: ROTATION — cameraLookAt
        this.g2(buf); // packetCount
        const sceneX = this.g1(buf);
        const sceneY = this.g1(buf);
        const height = this.g2(buf);
        const speed = this.g1(buf);
        const zoomSpeed = this.g1(buf);
        game.oriented = true;
        game.anInt993 = sceneX;
        game.anInt994 = sceneY;
        game.anInt995 = height;
        game.anInt996 = speed;
        game.anInt997 = zoomSpeed;
        if (zoomSpeed >= 100 && game.getTileHeight) {
            const targetX = sceneX * 128 + 64;
            const targetY = sceneY * 128 + 64;
            const targetZ = game.getTileHeight(targetY, targetX, 9 | 0, game.plane) - height;
            const dx = targetX - game.cameraX;
            const dz = targetZ - game.cameraZ;
            const dy = targetY - game.cameraY;
            const horiz = Math.sqrt(dx * dx + dy * dy) | 0;
            let pitch = ((Math.atan2(dz, horiz) * 325.949) | 0) & 2047;
            if (pitch < 128) pitch = 128;
            if (pitch > 383) pitch = 383;
            game.cameraPitch = pitch;
            game.cameraYaw = ((Math.atan2(dx, dy) * -325.949) | 0) & 2047;
        }
        return true;
    }

    static handleCamSet(buf: Buffer, game: any): boolean {
        // Opcode 187: SET — putLEShort(x) putShort(packetCount) putShort(y)
        const x = buf.buffer[buf.currentPosition] & 0xFF | ((buf.buffer[buf.currentPosition + 1] & 0xFF) << 8);
        buf.currentPosition += 2;
        this.g2(buf); // packetCount
        const y = this.g2(buf);
        // No documented 377 analog; just consume. Some builds treat this as a camera target.
        return true;
    }

    static handleCamShake(buf: Buffer, size: number, game: any): boolean {
        // Opcode 27: SHAKE — skip; purely visual, scene graph must exist to apply.
        buf.currentPosition += size;
        return true;
    }

    static handleCamReset(buf: Buffer, game: any): boolean {
        // Opcode 24: RESET — 2 bytes packetCount.
        this.g2(buf);
        game.oriented = false;
        return true;
    }

    static handleWindowsPane(buf: Buffer, size: number, game: any): boolean {
        // Opcode 145: IF_OPENTOP. Server sends putLEShortA(windowId), putS(type), putLEShortA(packetCount).
        // The 530 windowId (548 fixed / 746 resizable) isn't in the 377 cache, so setting
        // openInterfaceId to it causes the render path to iterate a stub widget and various
        // render helpers to hit null fields. Safer to just consume the packet — the static
        // 377 chrome + chat still render regardless.
        const windowId = this.ig2add(buf);
        const type = this.g1s(buf);
        const packetCount = this.ig2add(buf);
        if (game) {
            game.windowPaneId = windowId;
            game.windowPaneType = type;
            game.windowPanePacketCount = packetCount;
        }
        InterfaceList.openModal(windowId, windowId << 16);
        this.syncLegacyInterfaceWidgets(game, windowId, windowId);
        return true;
    }

    // ── Helpers for signed-short variants used below ─────────────────

    /** LE signed 16-bit (rt4 Buffer.ig2b). */
    static ig2b(buf: Buffer): number {
        const v = this.ig2(buf);
        return v > 32767 ? v - 0x10000 : v;
    }

    /** BE signed 16-bit with second byte add-128 (rt4 Buffer.g2badd). */
    static g2badd(buf: Buffer): number {
        const v = this.g2add(buf);
        return v > 32767 ? v - 0x10000 : v;
    }

    // ── Misc UI / display-model handlers ─────────────────────────────

    static handleIfSetAnim(buf: Buffer, game: any): boolean {
        // rt4 IF_SETANIM: mg4(componentHash) + ig2b(seqId) + g2add(tracknum). 8 bytes.
        const id = this.mg4(buf);
        const seqId = this.ig2b(buf);
        const tracknum = this.g2add(buf);
        this.recordIfUpdate(game, "IF_SETANIM", id, { seqId, tracknum });
        return true;
    }

    static handleIfSetPosition(buf: Buffer, game: any): boolean {
        // rt4 IF_SETPOSITION: g2add(tracknum) + ig4(componentHash) + g2b(x) + g2badd(y). 10 bytes.
        const tracknum = this.g2add(buf);
        const id = this.ig4(buf);
        const x = this.g2b(buf);
        const y = this.g2badd(buf);
        this.recordIfUpdate(game, "IF_SETPOSITION", id, { x, y, tracknum });
        return true;
    }

    static handleIfSetText1(buf: Buffer, size: number, game: any): boolean {
        // rt4 IF_SETTEXT1: mg4(componentHash) + gjstr(text) + g2add(tracknum). var-byte.
        const start = buf.currentPosition;
        const id = this.mg4(buf);
        const text = this.gjstr(buf);
        const tracknum = this.g2add(buf);
        this.recordIfUpdate(game, "IF_SETTEXT2", id, { text, tracknum });
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleSetInterfaceSettings(buf: Buffer, game: any): boolean {
        // rt4 SET_INTERFACE_SETTINGS: ig2(tracknum) + ig2(end) + g4(componentHash) + g2add(start) + img4(accessMask). 14 bytes.
        const tracknum = this.ig2(buf);
        const endRaw = this.ig2(buf);
        const end = endRaw === 65535 ? -1 : endRaw;
        const id = this.g4(buf);
        const startRaw = this.g2add(buf);
        const startSlot = startRaw === 65535 ? -1 : startRaw;
        const accessMask = this.img4(buf);
        this.recordIfUpdate(game, "SET_INTERFACE_SETTINGS", id, { tracknum, accessMask, startSlot, end });
        return true;
    }

    static handleSetInteraction(buf: Buffer, size: number, game: any): boolean {
        // rt4 SET_INTERACTION: ig2add(cursor) + g1(top) + g1(optId) + gjstr(option). var-byte.
        const start = buf.currentPosition;
        const cursor = this.ig2add(buf);
        const top = this.g1(buf);
        const optId = this.g1(buf);
        const option = this.gjstr(buf);
        if (game) {
            if (!game.interactions) game.interactions = {};
            game.interactions[optId] = { cursor, top, option };
        }
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleHintArrow(buf: Buffer, size: number, game: any): boolean {
        // rt4 HINT_ARROW: variable shape — first byte is the type/flags, payload depends on it.
        // We capture the type and consume the rest verbatim; any future renderer pass can decode
        // from the raw bytes. The wire format is documented in rt4 Protocol.java around opcode 217.
        const start = buf.currentPosition;
        if (size <= 0) return true;
        const type = this.g1(buf);
        const remaining = (start + size) - buf.currentPosition;
        const raw: number[] = [];
        for (let i = 0; i < remaining; i++) raw.push(this.g1(buf));
        if (game) {
            if (!game.hintArrows) game.hintArrows = [];
            game.hintArrows.push({ type, payload: raw });
        }
        return true;
    }

    static handleIfSetPlayerHead(buf: Buffer, game: any): boolean {
        // rt4 IF_SETPLAYERHEAD: ig2add(tracknum) + img4(componentHash). 6 bytes.
        const tracknum = this.ig2add(buf);
        const id = this.img4(buf);
        this.recordIfUpdate(game, "IF_SETPLAYERHEAD", id, { tracknum });
        return true;
    }

    static handleIfSetNpcHead(buf: Buffer, game: any): boolean {
        // rt4 IF_SETNPCHEAD: g2add(npcId) + ig4(componentHash) + ig2(tracknum). 8 bytes.
        const npcId = this.g2add(buf);
        const id = this.ig4(buf);
        const tracknum = this.ig2(buf);
        this.recordIfUpdate(game, "IF_SETNPCHEAD", id, { npcId, tracknum });
        return true;
    }

    static handleIfSetObject(buf: Buffer, game: any): boolean {
        // rt4 IF_SETOBJECT: g4(slotIndex) + mg4(componentHash) + ig2add(itemId) + ig2(tracknum). 12 bytes.
        const slotIndex = this.g4(buf);
        const id = this.mg4(buf);
        const itemId = this.ig2add(buf);
        const tracknum = this.ig2(buf);
        this.recordIfUpdate(game, "IF_SETOBJECT", id, { slotIndex, itemId, tracknum });
        return true;
    }

    static handleIfSetModel(buf: Buffer, game: any): boolean {
        // rt4 IF_SETMODEL: ig4(componentHash) + ig2add(tracknum) + g2add(modelId). 8 bytes.
        const id = this.ig4(buf);
        const tracknum = this.ig2add(buf);
        const modelId = this.g2add(buf);
        this.recordIfUpdate(game, "IF_SETMODEL", id, { modelId, tracknum });
        return true;
    }

    // ── Friend/ignore lists ──────────────────────────────────────────

    static handleUpdateFriendList(buf: Buffer, size: number, game: any): boolean {
        // rt4 UPDATE_FRIENDLIST: g8(name37) + g2(worldId) + g1(rank) + (gjstr(worldName) if worldId > 0). var-byte.
        const start = buf.currentPosition;
        const name37 = this.g8(buf);
        const worldId = this.g2(buf);
        const rank = this.g1(buf);
        let worldName = "";
        if (worldId > 0 && (start + size) > buf.currentPosition) {
            worldName = this.gjstr(buf);
        }
        if (game) {
            if (!game.friendList) game.friendList = [];
            game.friendList.push({
                name: this.name37ToString(name37),
                name37: name37.toString(),
                worldId, rank, worldName,
            });
        }
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleUpdateIgnoreList(buf: Buffer, size: number, game: any): boolean {
        // rt4 UPDATE_IGNORELIST: repeating g8(name37). var-short.
        const start = buf.currentPosition;
        const entries: string[] = [];
        const limit = start + size;
        while (buf.currentPosition + 8 <= limit) {
            const n37 = this.g8(buf);
            entries.push(this.name37ToString(n37));
        }
        if (game) {
            if (!game.ignoreList) game.ignoreList = [];
            for (const e of entries) game.ignoreList.push(e);
        }
        if (buf.currentPosition < limit) buf.currentPosition = limit;
        return true;
    }

    // ── CS2 / GE handlers ────────────────────────────────────────────

    static handleRunCs2(buf: Buffer, size: number, game: any): boolean {
        // rt4 RUN_CS2: g2(tracknum) + gjstr(argTypes) + per-arg [g4 or gjstr by 's'] + g4(scriptId).
        // Decoded args are queued onto game.cs2Pending. If game.cs2Hooks (Cs2Hooks) and
        // game.cs2LoadScript (script-id → ClientScript530Data) are present, the VM runs
        // the script immediately and the result is pushed to game.cs2Results.
        const start = buf.currentPosition;
        const tracknum = this.g2(buf);
        const argTypes = this.gjstr(buf);
        const args: any[] = new Array(argTypes.length + 1);
        for (let i = argTypes.length - 1; i >= 0; i--) {
            if (argTypes.charCodeAt(i) === 115) { // 's' = string
                args[i + 1] = this.gjstr(buf);
            } else {
                args[i + 1] = this.g4(buf);
            }
        }
        args[0] = this.g4(buf);
        const scriptId = args[0];
        const scriptArgs = args.slice(1);
        if (game) {
            if (!game.cs2Pending) game.cs2Pending = [];
            game.cs2Pending.push({ scriptId, argTypes, args: scriptArgs, tracknum });
            const loadScript: ((id: number) => ClientScript530Data | null) | undefined = game.cs2LoadScript;
            if (loadScript) {
                try {
                    const script = loadScript(scriptId);
                    if (script) {
                        const gameHooks = (game.cs2Hooks || {}) as Cs2Hooks;
                        const hooks: Cs2Hooks = {
                            ...gameHooks,
                            getVarp: gameHooks.getVarp ?? ((id) => game.widgetSettings?.[id] ?? 0),
                            setVarp: gameHooks.setVarp ?? ((id, v) => { if (game.widgetSettings) game.widgetSettings[id] = v; }),
                            getVarbit: gameHooks.getVarbit ?? ((id) => game.varbitValues?.[id] ?? 0),
                            setVarbit: gameHooks.setVarbit ?? ((id, v) => { if (!game.varbitValues) game.varbitValues = {}; game.varbitValues[id] = v; }),
                            getVarc: gameHooks.getVarc ?? ((id) => game.varcValues?.[id] ?? 0),
                            setVarc: gameHooks.setVarc ?? ((id, v) => { if (!game.varcValues) game.varcValues = {}; game.varcValues[id] = v; }),
                            loadScript: gameHooks.loadScript ?? loadScript,
                        };
                        const result = runClientScript(script, scriptArgs, hooks);
                        if (!game.cs2Results) game.cs2Results = [];
                        game.cs2Results.push({ scriptId, result, tracknum });
                    }
                } catch (_) {
                    // Swallow VM errors so a single bad script doesn't tear down the packet stream.
                }
            }
        }
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleIfCloseSub(buf: Buffer, game: any): boolean {
        // rt4 IF_CLOSESUB: g2(tracknum) + g4(componentHash). 6 bytes.
        const tracknum = this.g2(buf);
        const id = this.g4(buf);
        InterfaceList.closeSub(id);
        this.recordIfUpdate(game, "IF_CLOSESUB", id, { tracknum });
        return true;
    }

    static handleIfOpenTop(buf: Buffer, game: any): boolean {
        // rt4 IF_OPENTOP: g1(type) + mg4(pointer) + g2add(tracknum) + g2(component). 9 bytes.
        const type = this.g1(buf);
        const pointer = this.mg4(buf);
        const tracknum = this.g2add(buf);
        const component = this.g2(buf);
        if (game) {
            game.topInterface = { type, pointer, component, tracknum };
        }
        InterfaceList.openModal(component, pointer);
        this.syncLegacyInterfaceWidgets(game, component, component);
        return true;
    }

    static handleIfSetAngle(buf: Buffer, game: any): boolean {
        // rt4 IF_SETANGLE: g2(pitch) + g2add(tracknum) + ig2add(scale) + ig2add(yaw) + g4(componentHash). 12 bytes.
        const pitch = this.g2(buf);
        const tracknum = this.g2add(buf);
        const scale = this.ig2add(buf);
        const yaw = this.ig2add(buf);
        const id = this.g4(buf);
        this.recordIfUpdate(game, "IF_SETANGLE", id, { pitch, yaw, scale, tracknum });
        return true;
    }

    static handleUpdateRandomFile(buf: Buffer, size: number, game: any): boolean {
        // rt4 UPDATE_RANDOM_FILE: gjstr(filename) + g4(checksum). Triggers a forced
        // download of an arbitrary file. The 2009scape server does not emit this in
        // practice, but we decode it cleanly so the stream stays aligned if it ever does.
        const start = buf.currentPosition;
        const filename = this.gjstr(buf);
        const checksum = (buf.currentPosition + 4 <= start + size) ? this.g4(buf) : 0;
        if (game) {
            if (!game.randomFileRequests) game.randomFileRequests = [];
            game.randomFileRequests.push({ filename, checksum });
        }
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleSetWalkOption(buf: Buffer, size: number, game: any): boolean {
        // rt4 SET_WALK_OPTION: g1(walkOption). Single byte controlling default walk
        // behavior (toggle run/walk). 2009scape doesn't currently emit this, but
        // decoding it costs us nothing and unblocks future server work.
        if (size > 0) {
            const walkOption = this.g1(buf);
            if (game) game.walkOption = walkOption;
        }
        return true;
    }

    static handleJoinClanChat(buf: Buffer, size: number, game: any): boolean {
        // rt4 JOIN_CLAN_CHAT: g8(owner37). If 0L: leave. Else g8(name37) + g1b(minKick) + g1(clanSize)
        // + clanSize x { g8(memberKey) + g2(world) + g1b(rank) + gjstr(worldName) }.
        const start = buf.currentPosition;
        const owner37 = this.g8(buf);
        if (owner37.toString() === "0") {
            // Leave clan chat.
            if (game) game.clanState = null;
            if (buf.currentPosition - start < size) buf.currentPosition = start + size;
            return true;
        }
        const name37 = this.g8(buf);
        const minKick = this.g1b(buf);
        const clanSize = this.g1(buf);
        const members: any[] = [];
        for (let i = 0; i < clanSize && buf.currentPosition < start + size; i++) {
            const memberKey = this.g8(buf);
            const world = this.g2(buf);
            const rank = this.g1b(buf);
            const worldName = this.gjstr(buf);
            members.push({
                name: this.name37ToString(memberKey),
                name37: memberKey.toString(),
                world,
                rank,
                worldName,
            });
        }
        if (game) {
            game.clanState = {
                owner: this.name37ToString(owner37),
                name: this.name37ToString(name37),
                minKick,
                members,
            };
        }
        if (buf.currentPosition - start < size) buf.currentPosition = start + size;
        return true;
    }

    static handleGrandExchangeOffers(buf: Buffer, size: number, game: any): boolean {
        // rt4 GRAND_EXCHANGE_OFFERS: g1(slot), then either g1(0) for an empty
        // offer or StockMarketOffer(statusAndType, item, price, count,
        // completedCount, completedGold). Keep a raw copy as a fallback for
        // future UI work, but expose parsed fields to CS2 immediately.
        const start = buf.currentPosition;
        const limit = start + size;
        if (game && !game.geOffers) game.geOffers = [];
        while (buf.currentPosition < limit) {
            const rawStart = buf.currentPosition;
            const slot = this.g1(buf);
            const marker = buf.currentPosition < limit ? this.g1(buf) : 0;
            let offer: any;
            if (marker === 0 || buf.currentPosition + 17 > limit) {
                offer = { type: 0, status: 0, item: -1, price: 0, count: 0, completedCount: 0, completedGold: 0 };
            } else {
                buf.currentPosition--;
                const statusAndType = this.g1(buf);
                offer = {
                    type: (statusAndType & 0x8) === 0x8 ? 1 : 0,
                    status: statusAndType & 0x7,
                    item: this.g2(buf),
                    price: this.g4(buf) | 0,
                    count: this.g4(buf) | 0,
                    completedCount: this.g4(buf) | 0,
                    completedGold: this.g4(buf) | 0,
                };
            }
            const raw: number[] = [];
            for (let i = rawStart; i < Math.min(buf.currentPosition, limit); i++) raw.push(buf.buffer[i] & 0xFF);
            offer.raw = raw;
            if (game && slot >= 0) {
                game.geOffers[slot] = offer;
            }
        }
        if (buf.currentPosition < limit) buf.currentPosition = limit;
        return true;
    }
}
