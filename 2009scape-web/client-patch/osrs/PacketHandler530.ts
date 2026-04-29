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

export class PacketHandler530 {
    private static equipmentObjIds530: number[] | null = null;

    static handle(opcode530: number, buf: Buffer, size: number, game: any): boolean {
        const startPos = buf.currentPosition;
        try {
            return this.dispatch(opcode530, buf, size, game);
        } catch (e) {
            // Any handler error: realign to the end of this packet and keep going.
            buf.currentPosition = startPos + (size > 0 ? size : 0);
            return true;
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

            // Camera packets
            case 154: return this.handleCamPosition(buf, game);        // CamPosition (8)
            case 125: return this.handleCamRotation(buf, game);        // CamRotation (8)
            case 187: return this.handleCamSet(buf, game);             // CamSet (6)
            case 27:  return this.handleCamShake(buf, size, game);     // CamShake (8)
            case 24:  return this.handleCamReset(buf, game);           // CamReset (2)

            // Interface packets (all fall through as "consumed")
            case 145: return this.handleWindowsPane(buf, size, game);   // WindowsPane (IF_OPENTOP)
            case 149: return this.consumeKnown(buf, size);              // ResetInterface
            case 155: return this.consumeKnown(buf, size);              // Interface (OpenTop)
            case 21:  return this.consumeKnown(buf, size);              // InterfaceConfig
            case 132: return this.consumeKnown(buf, size);              // InterfaceSetAngle
            case 36:  return this.consumeKnown(buf, size);              // AnimateInterface
            case 119: return this.consumeKnown(buf, size);              // RepositionChild
            case 171: return this.consumeKnown(buf, size);              // IF_SETTEXT
            case 165: return this.consumeKnown(buf, size);              // AccessMask
            case 44:  return this.consumeKnown(buf, size);              // InteractionOption
            case 217: return this.consumeKnown(buf, size);              // HintIcon
            case 66:  return this.consumeKnown(buf, size);              // DisplayModel
            case 73:  return this.consumeKnown(buf, size);              // DisplayModel
            case 50:  return this.consumeKnown(buf, size);              // DisplayModel
            case 130: return this.consumeKnown(buf, size);              // DisplayModel
            case 144: return this.consumeKnown(buf, size);              // ContainerPacket clear (4)
            case 22:  return this.consumeKnown(buf, size);              // ContainerPacket slot-based update (var-short)
            case 105: return this.consumeKnown(buf, size);              // ContainerPacket full update (var-short)
            case 55:  return this.consumeKnown(buf, size);              // UpdateClanChat
            case 115: return this.consumeKnown(buf, size);              // CSConfigPacket
            case 116: return this.consumeKnown(buf, size);              // CSConfigPacket (alt)
            case 65:  return this.consumeKnown(buf, size);              // VarcUpdate / CSConfig
            case 69:  return this.consumeKnown(buf, size);              // VarcUpdate

            // State update packets with real handlers
            case 60:  return this.handleVarpSmall(buf, game);           // 2 bytes
            case 226: return this.handleVarpLarge(buf, game);           // 6 bytes
            case 38:  return this.handleUpdateStat(buf, game);          // 6 bytes
            case 70:  return this.handleGameMessage(buf, size, game);   // var-byte
            case 192: return this.handleMinimapState(buf, game);        // 1 byte
            case 234: return this.handleRunEnergy(buf, game);           // 1 byte
            case 174: return this.handleWeightUpdate(buf, game);        // 2 bytes
            case 153: return this.handleClearMinimapFlag(buf, game);    // 0 bytes
            case 86:  return this.handleLogout(buf, game);              // 0 bytes
            case 85:  return this.handleSystemUpdate(buf, game);        // 2 bytes
            case 197: return this.handleContactStatus(buf, game);       // 1 byte
            case 126: return this.consumeKnown(buf, size);              // Contact list update (var-short)
            case 62:  return this.consumeKnown(buf, size);              // Contact ignore (var-byte)
            case 84:  return this.handleVarbit(buf, game);              // 6 bytes
            case 37:  return this.consumeKnown(buf, size);              // Varbit (3 bytes)
            case 208: return this.consumeKnown(buf, size);              // Varbit (5 bytes)
            case 4:   return this.consumeKnown(buf, size);              // Music (2 bytes)
            case 211: return this.consumeKnown(buf, size);              // UpdateRandomFile (never sent)
            case 10:  return this.consumeKnown(buf, size);              // SetWalkOption (TODO on server)

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
    static ig2(buf: Buffer): number {
        buf.currentPosition += 2;
        return (buf.buffer[buf.currentPosition - 2] & 0xFF) + ((buf.buffer[buf.currentPosition - 1] & 0xFF) << 8);
    }
    static ig2add(buf: Buffer): number {
        buf.currentPosition += 2;
        return ((buf.buffer[buf.currentPosition - 2] - 128) & 0xFF) + ((buf.buffer[buf.currentPosition - 1] & 0xFF) << 8);
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
    static gjstr(buf: Buffer): string {
        let s = "";
        const end = buf.buffer ? buf.buffer.length : 0;
        while (buf.currentPosition < end && buf.buffer[buf.currentPosition] !== 0) {
            s += String.fromCharCode(buf.buffer[buf.currentPosition++] & 0xFF);
        }
        if (buf.currentPosition < end) buf.currentPosition++; // skip NUL
        return s;
    }

    // Generic consumer for opcodes where we only need to keep the stream aligned
    static consumeKnown(buf: Buffer, size: number): boolean {
        if (size > 0) buf.currentPosition += size;
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
        let slot = 0;
        for (let rx = ((regionX - 6) / 8) | 0; rx <= ((regionX + 6) / 8) | 0; rx++) {
            for (let rz = ((regionZ - 6) / 8) | 0; rz <= ((regionZ + 6) / 8) | 0; rz++) {
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
        // Mark loading-stage to "loading" so the existing 377 method144
        // pipeline picks up populated byte arrays + parses regions when
        // the async fetch below completes.
        game.loadingStage = 1;
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
        return true;
    }

    static handleClearRegionChunk(buf: Buffer, size: number, game: any): boolean {
        // Opcode 112: ClearRegionChunk (2 bytes) - put(x) + putC(y)
        const x = this.g1(buf);
        const y = this.g1neg(buf);
        return true;
    }

    static handleUpdateAreaPositionA(buf: Buffer, size: number, game: any): boolean {
        // Opcode 230: UpdateAreaPosition (var-short) - putA(y) + putS(x) + chunk data
        if (size > 0) buf.currentPosition += size;
        return true;
    }

    static handleUpdateAreaPositionB(buf: Buffer, size: number, game: any): boolean {
        // Opcode 26: UpdateAreaPosition fixed variant (2 bytes) - putC(x) + put(y)
        const x = this.g1neg(buf);
        const y = this.g1(buf);
        return true;
    }

    static handleBuildDynamicScene(buf: Buffer, size: number, game: any): boolean {
        // Opcode 214: BuildDynamicScene (var-short) - complex payload, consume
        if (size > 0) buf.currentPosition += size;
        return true;
    }

    // ── State update packets ──

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

    static handleVarbit(buf: Buffer, game: any): boolean {
        // Opcode 84: Varbit (6 bytes) - varbit id + value
        if (buf.currentPosition + 6 > buf.buffer.length) {
            return true;
        }
        buf.currentPosition += 6;
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
                if (game.cameraX === 0 && game.cameraY === 0) {
                    game.cameraX = localPlayer.worldX;
                    game.cameraY = localPlayer.worldY;
                }
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
        } else if (subOpcode === 1) {
            // Walk: walkDir(3) + maskRequired(1)
            const walkDir = buf.getBits(3);
            const maskRequired = buf.getBits(1);
            if (localPlayer && localPlayer.move) {
                localPlayer.move(walkDir, false);
            }
        } else {
            // subOpcode 0: maskRequired only — position unchanged.
            buf.getBits(1);
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
                npc.move(buf.getBits(3), true);
                npc.move(buf.getBits(3), true);
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
            buf.getBits(3);
            buf.getBits(3);
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
        return true;
    }
}
