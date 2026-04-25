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
    static mg4(buf: Buffer): number {
        // Middle-endian: CDAB byte order
        buf.currentPosition += 4;
        const b0 = buf.buffer[buf.currentPosition - 4] & 0xFF;
        const b1 = buf.buffer[buf.currentPosition - 3] & 0xFF;
        const b2 = buf.buffer[buf.currentPosition - 2] & 0xFF;
        const b3 = buf.buffer[buf.currentPosition - 1] & 0xFF;
        return ((b2 << 24) | (b3 << 16) | (b0 << 8) | b1) >>> 0;
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
        // Opcode 162: REBUILD_NORMAL (var-short)
        //   g2add() -> zoneZ
        //   {regionCount x 4 mg4() XTEA keys}
        //   g1sub() -> buildArea
        //   g2()    -> regionX
        //   g2add() -> regionZ
        //   g2add() -> zoneX
        const zoneZ = this.g2add(buf);
        const remainingForXtea = size - 2 - 7; // zoneZ(2) consumed; trailing buildArea(1)+regionX(2)+regionZ(2)+zoneX(2)=7
        const regionCount = (remainingForXtea / 16) | 0;
        for (let i = 0; i < regionCount; i++) {
            for (let j = 0; j < 4; j++) this.mg4(buf);
        }
        const buildArea = this.g1sub(buf);
        const regionX = this.g2(buf);
        const regionZ = this.g2add(buf);
        const zoneX = this.g2add(buf);

        game.chunkX = zoneX;
        game.chunkY = zoneZ;
        game.nextTopLeftTileX = (game.chunkX - 6) * 8;
        game.nextTopRightTileY = (game.chunkY - 6) * 8;
        game.aBoolean1163 = false;
        if (game.plane === undefined || game.plane === null) game.plane = 0;
        game.loadingStage = 2;
        return true;
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
        // We only decode the local player's own position on teleport — that lets the
        // camera anchor correctly. All other blocks are bit-consumed so the stream
        // stays aligned.
        const startPos = buf.currentPosition;
        buf.initBitAccess();
        try {
            this.parseLocalPlayerPosition(buf, game);
            const trackedCount = buf.getBits(8);
            for (let i = 0; i < trackedCount && i < 2047; i++) {
                this.skipRenderBlock(buf);
            }
            // New local players are appended until we see the 2047 sentinel or run out.
            while (true) {
                const remainingBits = (size * 8) - (buf.bitPosition - startPos * 8);
                if (remainingBits < 11) break;
                const index = buf.getBits(11);
                if (index === 2047) break;
                // update(1) + offsetX(5) + direction(3) + teleport(1) + offsetY(5) = 15 bits
                if ((size * 8) - (buf.bitPosition - startPos * 8) < 15) break;
                const update = buf.getBits(1);
                buf.getBits(5); // offsetX
                buf.getBits(3); // direction
                buf.getBits(1); // teleport
                buf.getBits(5); // offsetY
                if (update) {
                    // Mask data follows byte-aligned at end; we just break to let byte section consume.
                    break;
                }
            }
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
        if (subOpcode === 3) {
            // Teleport: 7 bits sceneY, 1 bit teleport, 2 bits z, 1 bit mask flag, 7 bits sceneX
            const sceneY = buf.getBits(7);
            const teleporting = buf.getBits(1);
            const z = buf.getBits(2);
            const maskRequired = buf.getBits(1);
            const sceneX = buf.getBits(7);
            game.plane = z & 3;
            const localPlayer = game.players ? game.players[game.thisPlayerId] : null;
            if (localPlayer) {
                localPlayer.worldX = sceneX * 128 + 64;
                localPlayer.worldY = sceneY * 128 + 64;
                if (game.cameraX === 0 && game.cameraY === 0) {
                    game.cameraX = localPlayer.worldX;
                    game.cameraY = localPlayer.worldY;
                }
            }
        } else if (subOpcode === 2) {
            // Run: walkDir(3) + runDir(3) + mask(1) = 7 bits  (after 1+2 already read)
            buf.getBits(1);
            buf.getBits(3);
            buf.getBits(3);
            buf.getBits(1);
        } else if (subOpcode === 1) {
            // Walk: walkDir(3) + mask(1)
            buf.getBits(3);
            buf.getBits(1);
        } else {
            // subOpcode 0: mask only (no further position bits; 1 bit mask flag)
            buf.getBits(1);
        }
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
            buf.getBits(1);
            buf.getBits(3); // walkDir
            buf.getBits(3); // runDir
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
        // Opcode 32: NPC_INFO (var-short, bit-packed)
        // Skip entirely — we don't render NPCs yet, just consume the payload.
        buf.currentPosition += size;
        return true;
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
