// Port of rsc-c's packet-handler.c, plus the entity helpers from mudclient.c
// it relies on (mudclient_create_wall_object, mudclient_load_next_region,
// mudclient_add_player/npc, mudclient_play_sound).

import Foundation

/// The bounds-checked readers of utility.c (get_unsigned_byte etc.) over one packet.
/// C asserts on an out-of-range read; here it reads 0.
struct PacketReader {
    let data: [UInt8]
    let size: Int

    func u8(_ o: Int) -> Int { o >= 0 && o < size ? Int(data[o]) : 0 }
    func s8(_ o: Int) -> Int { o >= 0 && o < size ? Int(Int8(bitPattern: data[o])) : 0 }
    func u16(_ o: Int) -> Int { o >= 0 && o + 2 <= size ? (Int(data[o]) << 8) + Int(data[o + 1]) : 0 }
    func s16(_ o: Int) -> Int {
        let i = u8(o) * 256 + u8(o + 1)
        return i > 32767 ? i - 0x10000 : i
    }
    /// get_unsigned_int returns a C int, so the top bit makes it negative.
    func u32(_ o: Int) -> Int { o >= 0 && o + 4 <= size ? ClientUtil.unsignedInt(data, o) : 0 }
    func u64(_ o: Int) -> Int64 {
        (Int64(u32(o)) & 0xffffffff) << 32 + (Int64(u32(o + 4)) & 0xffffffff)
    }
    func stack(_ o: Int) -> Int {
        guard o >= 0 && o < size else { return 0 }
        if data[o] < 128 { return Int(data[o]) }
        return ((u8(o) - 128) << 24) + (u8(o + 1) << 16) + (u8(o + 2) << 8) + u8(o + 3)
    }
    func bits(_ offset: Int, _ n: Int) -> Int {
        guard (offset + n + 7) >> 3 <= size else { return 0 }
        return ClientUtil.bitMask(data, offset, n)
    }
    /// A NUL-terminated C string made from bytes [from, to).
    func string(_ from: Int, _ to: Int) -> String {
        var bytes = [UInt8]()
        var i = from
        while i < to && i < size && data[i] != 0 { bytes.append(data[i]); i += 1 }
        return String(decoding: bytes, as: Latin1.self)
    }
}

extension Mudclient {
    static let regionSize = 48
    static let groundItemFaceTag = 20000
    static let ironMaceId = 0
    static let skillHits = 3

    // MARK: - Entity helpers (mudclient.c)

    /// mudclient_update_ground_item_models
    func updateGroundItemModels() {
        for i in 0..<Mudclient.groundItemsMax {
            guard let m = groundItems[i].model else { continue }
            scene.removeModel(m)
            groundItems[i].model = nil
        }
        guard options.groundItemModels != 0 else { return }
        for i in 0..<groundItemCount {
            let itemId = groundItems[i].id
            let spriteId = gameData.items[itemId].sprite
            guard spriteId < itemModels.count, let original = itemModels[spriteId] else { continue }
            let model = original.copy()
            let mask = gameData.items[itemId].mask
            if mask != 0 {
                GameModel.maskFaces(model.faceFillBack, count: model.faceCount, maskColour: mask)
                GameModel.maskFaces(model.faceFillFront, count: model.faceCount, maskColour: mask)
            }
            model.key = i + Mudclient.groundItemFaceTag
            let ax = groundItems[i].x, ay = groundItems[i].y
            let mx = ((ax + ax + 1) * Mudclient.magicLoc) / 2
            let my = ((ay + ay + 1) * Mudclient.magicLoc) / 2
            model.translate(x: mx, y: -(world.elevation(mx, my) + groundItems[i].z) - 10, z: my)
            model.setLight(gouraud: true, ambience: 48, diffuse: 48, x: -50, y: -10, z: -50)
            scene.addModel(model)
            groundItems[i].model = model
        }
    }

    /// mudclient_create_wall_object
    func createWallObject(x: Int, y: Int, direction: Int, id: Int, count: Int) -> GameModel {
        var x1 = x, y1 = y, x2 = x, y2 = y
        let def = gameData.walls[id]
        let model = GameModel(vertices: 4, faces: 1)
        switch direction {
        case 0: x2 = x + 1
        case 1: y2 = y + 1
        case 2: x1 = x + 1; y2 = y + 1
        case 3: x2 = x + 1; y2 = y + 1
        default: break
        }
        x1 *= Mudclient.magicLoc; y1 *= Mudclient.magicLoc
        x2 *= Mudclient.magicLoc; y2 *= Mudclient.magicLoc
        let v0 = model.vertexAt(x: x1, y: -world.elevation(x1, y1), z: y1)
        let v1 = model.vertexAt(x: x1, y: -world.elevation(x1, y1) - def.height, z: y1)
        let v2 = model.vertexAt(x: x2, y: -world.elevation(x2, y2) - def.height, z: y2)
        let v3 = model.vertexAt(x: x2, y: -world.elevation(x2, y2), z: y2)
        _ = model.createFace([UInt16(truncatingIfNeeded: v0), UInt16(truncatingIfNeeded: v1),
                              UInt16(truncatingIfNeeded: v2), UInt16(truncatingIfNeeded: v3)],
                             fillFront: def.textureFront, fillBack: def.textureBack)
        model.setLight(gouraud: false, ambience: 60, diffuse: 24, x: -50, y: -10, z: -50)
        if x >= 0 && y >= 0 && x < 96 && y < 96 { scene.addModel(model) }
        model.key = count + 10000
        return model
    }

    /// Width and height of an object footprint for its tile direction.
    func objectSize(_ id: Int, direction: Int) -> (Int, Int) {
        let def = gameData.objects[id]
        return direction == World.dirNorth || direction == World.dirSouth ? (def.width, def.height) : (def.height, def.width)
    }

    /// mudclient_load_next_region: loads the 2x2 sections around (lx, ly) when
    /// the player leaves the loaded area, and moves every entity with it.
    @discardableResult
    public func loadNextRegion(_ lx: Int, _ ly: Int) -> Bool {
        if deathScreenTimeout != 0 {
            world.playerAlive = false
            return false
        }
        loadingArea = false
        let lx = lx + planeWidth, ly = ly + planeHeight
        if lastPlaneIndex == planeIndex && lx > localLowerX && lx < localUpperX && ly > localLowerY && ly < localUpperY {
            world.playerAlive = true
            return false
        }
        surface.drawStringCentre("Loading... Please wait", x: surface.width / 2, y: surface.height / 2 + 19,
                                 font: .bold12, colour: Colour.white)
        drawChatMessageTabs()
        draw()

        let ax = regionX, ay = regionY
        let size = Mudclient.regionSize
        let sectionX = (lx + size / 2) / size
        let sectionY = (ly + size / 2) / size
        lastPlaneIndex = planeIndex
        regionX = sectionX * size - size
        regionY = sectionY * size - size
        localLowerX = sectionX * size - 32
        localLowerY = sectionY * size - 32
        localUpperX = sectionX * size + 32
        localUpperY = sectionY * size + 32
        world.loadSection(x: lx, y: ly, plane: lastPlaneIndex)
        regionX -= planeWidth
        regionY -= planeHeight
        let offsetX = regionX - ax, offsetY = regionY - ay

        for i in 0..<objectCount {
            objects[i].x -= offsetX
            objects[i].y -= offsetY
            let ox = objects[i].x, oy = objects[i].y, id = objects[i].id
            let (w, h) = objectSize(id, direction: objects[i].direction)
            let baseX = ((ox + ox + w) * Mudclient.magicLoc) / 2
            let baseY = ((oy + oy + h) * Mudclient.magicLoc) / 2
            if ox >= 0 && oy >= 0 && ox < 96 && oy < 96, let model = objects[i].model {
                scene.addModel(model)
                model.place(x: baseX, y: -world.elevation(baseX, baseY), z: baseY)
                world.registerObject(x: ox, y: oy, id: id)
                if id == Mudclient.windmillSailsId { model.translate(x: 0, y: -480, z: 0) }
            }
        }

        for i in 0..<wallObjectCount {
            wallObjects[i].x -= offsetX
            wallObjects[i].y -= offsetY
            let w = wallObjects[i]
            world.registerWallObject(x: w.x, y: w.y, dir: w.direction, id: w.id)
            wallObjects[i].model = createWallObject(x: w.x, y: w.y, direction: w.direction, id: w.id, count: i)
        }

        for i in 0..<groundItemCount {
            groundItems[i].x -= offsetX
            groundItems[i].y -= offsetY
        }
        updateGroundItemModels()

        let dx = offsetX * Mudclient.magicLoc, dy = offsetY * Mudclient.magicLoc
        for c in players[0..<playerCount] + npcs[0..<npcCount] {
            guard let c else { continue }
            c.currentX -= dx
            c.currentY -= dy
            for j in 0...c.waypointCurrent {
                c.waypointsX[j] -= dx
                c.waypointsY[j] -= dy
            }
        }
        world.playerAlive = true
        return true
    }

    /// mudclient_add_character
    private func addCharacter(isNpc: Bool, serverIndex: Int, x: Int, y: Int, animation: Int, npcId: Int) -> GameCharacter {
        let existing = isNpc ? npcsServer[serverIndex] : playerServer[serverIndex]
        let character: GameCharacter
        if let existing {
            character = existing
        } else {
            if !isNpc && serverIndex == localPlayerServerIndex {
                if let i = playerServer.firstIndex(where: { $0 === localPlayer }) { playerServer[i] = nil }
                if let i = players.firstIndex(where: { $0 === localPlayer }) { players[i] = nil }
            }
            character = GameCharacter()
            character.serverIndex = serverIndex
            if isNpc { npcsServer[serverIndex] = character } else { playerServer[serverIndex] = character }
        }
        let known = isNpc ? knownNpcs[0..<knownNpcCount] : knownPlayers[0..<knownPlayerCount]
        let exists = known.contains { $0?.serverIndex == serverIndex }
        if npcId > -1 { character.npcId = npcId }
        if exists {
            character.nextAnimation = animation
            var w = character.waypointCurrent
            if x != character.waypointsX[w] || y != character.waypointsY[w] {
                w = (w + 1) % GameCharacter.waypointCount
                character.waypointCurrent = w
                character.waypointsX[w] = x
                character.waypointsY[w] = y
            }
        } else {
            character.serverIndex = serverIndex
            character.movingStep = 0
            character.waypointCurrent = 0
            character.currentX = x
            character.currentY = y
            character.waypointsX[0] = x
            character.waypointsY[0] = y
            character.currentAnimation = animation
            character.nextAnimation = animation
            character.stepCount = 0
        }
        return character
    }

    /// mudclient_add_player
    @discardableResult
    func addPlayer(serverIndex: Int, x: Int, y: Int, animation: Int) -> GameCharacter? {
        guard serverIndex < Mudclient.playersServerMax, playerCount < Mudclient.playersMax else { return nil }
        let p = addCharacter(isNpc: false, serverIndex: serverIndex, x: x, y: y, animation: animation, npcId: -1)
        players[playerCount] = p
        playerCount += 1
        return p
    }

    /// mudclient_add_npc (the diversify_npcs mod is not ported; it is off by default)
    @discardableResult
    func addNpc(serverIndex: Int, x: Int, y: Int, animation: Int, npcId: Int) -> GameCharacter? {
        guard serverIndex < Mudclient.npcsServerMax, npcCount < Mudclient.npcsMax else { return nil }
        let n = addCharacter(isNpc: true, serverIndex: serverIndex, x: x, y: y, animation: animation, npcId: npcId)
        npcs[npcCount] = n
        npcCount += 1
        return n
    }

    /// mudclient_play_sound: decodes `<name>.pcm` from the sound archive and hands it to the host.
    public func playSound(_ name: String) {
        if options.members == 0 || settingsSoundDisabled != 0 || options.lowmem != 0 { return }
        guard let data = soundData, data.count >= 2 else { return }
        let entries = (Int(data[0]) << 8) | Int(data[1])
        let wanted = JagArchive.hash("\(name).pcm")
        var offset = 2 + entries * 10
        for e in 0..<entries {
            let p = 2 + e * 10
            guard p + 10 <= data.count else { return }
            let hash = UInt32(data[p]) << 24 | UInt32(data[p + 1]) << 16 | UInt32(data[p + 2]) << 8 | UInt32(data[p + 3])
            let fileSize = Int(data[p + 4]) << 16 | Int(data[p + 5]) << 8 | Int(data[p + 6])
            let archiveSize = Int(data[p + 7]) << 16 | Int(data[p + 8]) << 8 | Int(data[p + 9])
            if hash == wanted {
                guard offset + fileSize <= data.count else { return }
                host?.playSound(ClientUtil.ulawToLinear(data[offset..<(offset + fileSize)]))
                return
            }
            offset += archiveSize
        }
    }

    // MARK: - Packets

    /// mudclient_packet_tick: pings, flushes, and handles one incoming packet.
    public func packetTick() {
        guard let ps = packetStream else { return }
        let timestamp = ClientTime.ticks()
        if ps.hasPacket { packetLastRead = timestamp }
        if timestamp &- packetLastRead > 5000 {
            packetLastRead = timestamp
            ps.newPacket(ClientOpcode.ping)
            ps.sendPacket()
        }
        if ps.writePacket(20) < 0 {
            lostConnection()
            return
        }
        let size = ps.readPacket(into: &incomingPacket)
        if size <= 0 { return }
        var opcode = Int(incomingPacket[0])
        if ps.isaacReady { opcode = (opcode &- Int(ps.nextIncomingIsaac())) & 0xff }
        handlePacket(opcode: opcode, size: size)
    }

    /// The opcode switch of mudclient_packet_tick, over `incomingPacket[0..<size]`.
    public func handlePacket(opcode: Int, size: Int) {
        let r = PacketReader(data: incomingPacket, size: size)
        let loc = Mudclient.magicLoc
        switch opcode {
        case ServerOpcode.worldInfo:
            if localPlayerServerIndex >= Mudclient.playersServerMax { return }
            loadingArea = true
            localPlayerServerIndex = r.u16(1)
            planeWidth = r.u16(3)
            planeHeight = r.u16(5)
            planeIndex = r.u16(7)
            planeMultiplier = r.u16(9)
            planeHeight -= planeIndex * planeMultiplier

        case ServerOpcode.regionPlayers:
            knownPlayerCount = playerCount
            for i in 0..<knownPlayerCount { knownPlayers[i] = players[i] }
            var offset = 8
            localRegionX = r.bits(offset, 11); offset += 11
            localRegionY = r.bits(offset, 13); offset += 13
            let sprite = r.bits(offset, 4); offset += 4
            let loaded = loadNextRegion(localRegionX, localRegionY)
            localRegionX -= regionX
            localRegionY -= regionY
            let px = localRegionX * loc + 64, py = localRegionY * loc + 64
            if loaded {
                localPlayer.waypointCurrent = 0
                localPlayer.movingStep = 0
                localPlayer.currentX = px; localPlayer.waypointsX[0] = px
                localPlayer.currentY = py; localPlayer.waypointsY[0] = py
            }
            playerCount = 0
            if let p = addPlayer(serverIndex: localPlayerServerIndex, x: px, y: py, animation: sprite) { localPlayer = p }
            let length = r.bits(offset, 8); offset += 8
            for i in 0..<length {
                let player = knownPlayers[i + 1]
                let updated = r.bits(offset, 1); offset += 1
                if updated != 0 {
                    let type = r.bits(offset, 1); offset += 1
                    if type == 0 {
                        let s = r.bits(offset, 3); offset += 3
                        if let player { stepWaypoint(player, sprite: s) }
                    } else {
                        let s = r.bits(offset, 4)
                        if (s & 12) == 12 {
                            offset += 2
                            continue
                        }
                        player?.nextAnimation = r.bits(offset, 4)
                        offset += 4
                    }
                }
                players[playerCount] = player
                playerCount += 1
            }
            var newCount = 0
            while offset + 24 < size * 8 {
                let serverIndex = r.bits(offset, 11); offset += 11
                if serverIndex >= Mudclient.playersServerMax { return }
                var ax = r.bits(offset, 5); offset += 5
                if ax > 15 { ax -= 32 }
                var ay = r.bits(offset, 5); offset += 5
                if ay > 15 { ay -= 32 }
                let s = r.bits(offset, 4); offset += 4
                let known = r.bits(offset, 1); offset += 1
                addPlayer(serverIndex: serverIndex, x: (localRegionX + ax) * loc + 64, y: (localRegionY + ay) * loc + 64,
                          animation: s)
                if known == 0 {
                    playerServerIndexes[newCount] = serverIndex
                    newCount += 1
                }
            }
            if newCount > 0, let ps = packetStream {
                ps.newPacket(ClientOpcode.knownPlayers)
                ps.putShort(newCount)
                for i in 0..<newCount {
                    let p = playerServer[playerServerIndexes[i]]
                    ps.putShort(p?.serverIndex ?? 0)
                    ps.putShort(p?.serverId ?? 0)
                }
                ps.sendPacket()
            }

        case ServerOpcode.regionPlayerUpdate:
            let length = r.u16(1)
            var offset = 3
            for _ in 0..<length {
                let index = r.u16(offset); offset += 2
                let player = index < Mudclient.playersServerMax ? playerServer[index] : nil
                let type = r.u8(offset); offset += 1
                switch type {
                case 0:
                    var itemId = r.u16(offset)
                    if itemId >= gameData.items.count { itemId = Mudclient.ironMaceId }
                    offset += 2
                    if let player {
                        player.bubbleTimeout = 150
                        player.bubbleItem = itemId
                    }
                case 1:
                    let len = r.u8(offset); offset += 1
                    if let player, len <= size - offset {
                        let message = ChatMessage.decode(r.data, offset: offset, length: len)
                        if !ignoreList[0..<ignoreListCount].contains(player.encodedUsername) {
                            player.messageTimeout = 150
                            player.message = message
                            showMessage("\(player.name): \(player.message)", .chat)
                        }
                    }
                    offset += len
                case 2:
                    let damage = r.u8(offset), current = r.u8(offset + 1), max = r.u8(offset + 2)
                    offset += 3
                    if let player {
                        player.damageTaken = damage
                        player.currentHits = current
                        player.maxHits = max
                        player.combatTimer = 200
                        if player === localPlayer {
                            playerSkillCurrent[Mudclient.skillHits] = current
                            playerSkillBase[Mudclient.skillHits] = max
                            showDialogWelcome = false
                            showDialogServerMessage = false
                        }
                    }
                case 3, 4:
                    let projectile = r.u16(offset); offset += 2
                    let target = r.u16(offset); offset += 2
                    if target >= (type == 3 ? Mudclient.npcsServerMax : Mudclient.playersServerMax) { return }
                    if let player {
                        player.incomingProjectileSprite = projectile
                        player.attackingNpcServerIndex = type == 3 ? target : -1
                        player.attackingPlayerServerIndex = type == 3 ? -1 : target
                        player.projectileRange = Mudclient.projectileRangeMax
                    }
                case 5:
                    if let player {
                        player.serverId = r.u16(offset); offset += 2
                        player.encodedUsername = r.u64(offset); offset += 8
                        player.name = ClientUtil.decodeUsername(player.encodedUsername)
                        let equipped = r.u8(offset); offset += 1
                        for j in 0..<AnimationIndex.count {
                            if j < equipped {
                                player.animations[j] = r.u8(offset); offset += 1
                            } else {
                                player.animations[j] = 0
                            }
                        }
                        // equipped counts above 12 overflow the C array; skip the extra bytes like a reader would
                        if equipped > AnimationIndex.count { offset += equipped - AnimationIndex.count }
                        player.hairColour = r.u8(offset); offset += 1
                        player.topColour = r.u8(offset); offset += 1
                        player.bottomColour = r.u8(offset); offset += 1
                        player.skinColour = r.u8(offset); offset += 1
                        player.level = r.u8(offset); offset += 1
                        player.skullVisible = r.u8(offset); offset += 1
                    } else {
                        offset += 14
                        let unused = r.u8(offset)
                        offset += unused + 1
                    }
                case 6:
                    let len = r.u8(offset); offset += 1
                    if let player, len <= size - offset {
                        player.messageTimeout = 150
                        player.message = ChatMessage.decode(r.data, offset: offset, length: len)
                        if player === localPlayer { showMessage("\(player.name): \(player.message)", .quest) }
                    }
                    offset += len
                default:
                    break
                }
            }

        case ServerOpcode.regionObjects:
            var offset = 1
            while offset < size {
                if r.u8(offset) == 255 {
                    let lx = (localRegionX + r.s8(offset + 1)) / 8
                    let ly = (localRegionY + r.s8(offset + 2)) / 8
                    offset += 3
                    var index = 0
                    for i in 0..<objectCount {
                        if objects[i].x / 8 - lx != 0 || objects[i].y / 8 - ly != 0 {
                            if i != index {
                                objects[index] = objects[i]
                                objects[index].model?.key = index
                            }
                            index += 1
                        } else {
                            if let m = objects[i].model { scene.removeModel(m) }
                            // C passes (id, x, y) here; kept as-is
                            world.removeObject(x: objects[i].id, y: objects[i].x, id: objects[i].y)
                            objects[i].model = nil
                        }
                    }
                    objectCount = index
                } else {
                    var objectId = r.u16(offset); offset += 2
                    let ax = localRegionX + r.s8(offset); offset += 1
                    let ay = localRegionY + r.s8(offset); offset += 1
                    var index = 0
                    for i in 0..<objectCount {
                        if objects[i].x != ax || objects[i].y != ay {
                            if i != index {
                                objects[index].model = objects[i].model
                                objects[index].model?.key = index
                                objects[index].x = objects[i].x
                                objects[index].y = objects[i].y
                                objects[index].id = objects[i].id
                                objects[index].direction = objects[i].direction
                            }
                            index += 1
                        } else {
                            if let m = objects[i].model { scene.removeModel(m) }
                            world.removeObject(x: objects[i].x, y: objects[i].y, id: objects[i].id)
                            objects[i].model = nil
                        }
                    }
                    objectCount = index
                    if objectId != 60000 {
                        if objectId >= gameData.objects.count { objectId = Mudclient.oddWellId }
                        if objectCount >= Mudclient.objectsMax { return }
                        let dir = world.tileDirection(ax, ay)
                        let (w, h) = objectSize(objectId, direction: dir)
                        let mx = ((ax + ax + w) * loc) / 2, my = ((ay + ay + h) * loc) / 2
                        let modelIndex = gameData.objects[objectId].modelIndex
                        guard let source = gameModels[modelIndex] else { continue }
                        let model = source.copy()
                        scene.addModel(model)
                        model.key = objectCount
                        model.rotate(yaw: 0, pitch: dir * 32, roll: 0)
                        model.translate(x: mx, y: -world.elevation(mx, my), z: my)
                        model.setLight(gouraud: true, ambience: 48, diffuse: 48, x: -50, y: -10, z: -50)
                        world.registerObject(x: ax, y: ay, id: objectId)
                        if objectId == Mudclient.windmillSailsId { model.translate(x: 0, y: -480, z: 0) }
                        objects[objectCount] = Scenery(x: ax, y: ay, id: objectId, direction: dir, model: model)
                        objectCount += 1
                    }
                }
            }

        case ServerOpcode.regionNpcs:
            knownNpcCount = npcCount
            npcCount = 0
            for i in 0..<knownNpcCount { knownNpcs[i] = npcs[i] }
            var offset = 8
            let length = r.bits(offset, 8); offset += 8
            for i in 0..<length {
                let npc = knownNpcs[i]
                let updated = r.bits(offset, 1); offset += 1
                if updated != 0 {
                    let moved = r.bits(offset, 1); offset += 1
                    if moved == 0 {
                        let s = r.bits(offset, 3); offset += 3
                        if let npc { stepWaypoint(npc, sprite: s) }
                    } else {
                        let s = r.bits(offset, 4)
                        if (s & 12) == 12 {
                            offset += 2
                            continue
                        }
                        npc?.nextAnimation = r.bits(offset, 4)
                        offset += 4
                    }
                }
                npcs[npcCount] = npc
                npcCount += 1
            }
            while offset + 34 < size * 8 {
                let serverIndex = r.bits(offset, 12); offset += 12
                if serverIndex >= Mudclient.npcsServerMax { return }
                var ax = r.bits(offset, 5); offset += 5
                if ax > 15 { ax -= 32 }
                var ay = r.bits(offset, 5); offset += 5
                if ay > 15 { ay -= 32 }
                let s = r.bits(offset, 4); offset += 4
                var npcId = r.bits(offset, 10); offset += 10
                if npcId >= gameData.npcs.count { npcId = Mudclient.shiftyManId }
                addNpc(serverIndex: serverIndex, x: (localRegionX + ax) * loc + 64, y: (localRegionY + ay) * loc + 64,
                       animation: s, npcId: npcId)
            }

        case ServerOpcode.regionNpcUpdate:
            let length = r.u16(1)
            var offset = 3
            for _ in 0..<length {
                let serverIndex = r.u16(offset); offset += 2
                if serverIndex >= Mudclient.npcsServerMax { return }
                guard let npc = npcsServer[serverIndex] else { return }
                let type = r.u8(offset); offset += 1
                if type == 1 {
                    let target = r.u16(offset); offset += 2
                    let len = r.u8(offset); offset += 1
                    if len <= size - offset {
                        let message = ChatMessage.decode(r.data, offset: offset, length: len)
                        npc.messageTimeout = 150
                        npc.message = message
                        if target == localPlayer.serverIndex {
                            showMessage("@yel@\(gameData.npcs[npc.npcId].name): \(message)", .quest)
                        }
                    }
                    offset += len
                } else if type == 2 {
                    npc.damageTaken = r.u8(offset)
                    npc.currentHits = r.u8(offset + 1)
                    npc.maxHits = r.u8(offset + 2)
                    npc.combatTimer = 200
                    offset += 3
                }
            }

        case ServerOpcode.regionEntityUpdate:
            let length = (size - 1) / 4
            for i in 0..<length {
                let dx = (localRegionX + r.s16(1 + i * 4)) / 8
                let dy = (localRegionY + r.s16(3 + i * 4)) / 8
                var count = 0
                for j in 0..<groundItemCount where groundItems[j].x / 8 - dx != 0 || groundItems[j].y / 8 - dy != 0 {
                    if j != count { moveGroundItem(from: j, to: count) }
                    count += 1
                }
                groundItemCount = count
                count = 0
                for j in 0..<objectCount {
                    if objects[j].x / 8 - dx != 0 || objects[j].y / 8 - dy != 0 {
                        if j != count {
                            objects[count] = objects[j]
                            objects[count].model?.key = count
                        }
                        count += 1
                    } else {
                        if let m = objects[j].model { scene.removeModel(m) }
                        world.removeObject(x: objects[j].x, y: objects[j].y, id: objects[j].id)
                        objects[j].model = nil
                    }
                }
                objectCount = count
                count = 0
                for j in 0..<wallObjectCount {
                    if wallObjects[j].x / 8 - dx != 0 || wallObjects[j].y / 8 - dy != 0 {
                        if j != count {
                            wallObjects[count] = wallObjects[j]
                            wallObjects[count].model?.key = count + 10000
                        }
                        count += 1
                    } else {
                        removeWallObjectEntry(j)
                    }
                }
                wallObjectCount = count
            }
            updateGroundItemModels()

        case ServerOpcode.regionWallObjects:
            var offset = 1
            while offset < size {
                if r.u8(offset) == 255 {
                    let lx = (localRegionX + r.s8(offset + 1)) / 8
                    let ly = (localRegionY + r.s8(offset + 2)) / 8
                    offset += 3
                    var index = 0
                    for i in 0..<wallObjectCount {
                        if wallObjects[i].x / 8 - lx != 0 || wallObjects[i].y / 8 - ly != 0 {
                            if i != index {
                                wallObjects[index] = wallObjects[i]
                                wallObjects[index].model?.key = index + 10000
                            }
                            index += 1
                        } else {
                            removeWallObjectEntry(i)
                        }
                    }
                    wallObjectCount = index
                } else {
                    var id = r.u16(offset); offset += 2
                    let lx = localRegionX + r.s8(offset); offset += 1
                    let ly = localRegionY + r.s8(offset); offset += 1
                    let direction = r.s8(offset); offset += 1
                    var count = 0
                    for i in 0..<wallObjectCount {
                        if wallObjects[i].x != lx || wallObjects[i].y != ly || wallObjects[i].direction != direction {
                            if i != count {
                                wallObjects[count] = wallObjects[i]
                                wallObjects[count].model?.key = count + 10000
                            }
                            count += 1
                        } else {
                            removeWallObjectEntry(i)
                        }
                    }
                    wallObjectCount = count
                    if id != 65535 {
                        if id >= gameData.walls.count { id = Mudclient.oddLookingWallId }
                        if wallObjectCount >= Mudclient.wallObjectsMax { return }
                        world.registerWallObject(x: lx, y: ly, dir: direction, id: id)
                        let model = createWallObject(x: lx, y: ly, direction: direction, id: id, count: wallObjectCount)
                        wallObjects[wallObjectCount] = ServerBoundary(model: model, x: lx, y: ly, id: id, direction: direction)
                        wallObjectCount += 1
                    }
                }
            }

        case ServerOpcode.regionGroundItems:
            var offset = 1
            while offset < size {
                if r.u8(offset) == 255 {
                    let lx = (localRegionX + r.s8(offset + 1)) / 8
                    let ly = (localRegionY + r.s8(offset + 2)) / 8
                    offset += 3
                    var index = 0
                    for i in 0..<groundItemCount where groundItems[i].x / 8 - lx != 0 || groundItems[i].y / 8 - ly != 0 {
                        if i != index { moveGroundItem(from: i, to: index) }
                        index += 1
                    }
                    groundItemCount = index
                } else {
                    var itemId = r.u16(offset); offset += 2
                    let ax = localRegionX + r.s8(offset); offset += 1
                    let ay = localRegionY + r.s8(offset); offset += 1
                    if itemId & 32768 == 0 {
                        if itemId >= gameData.items.count { itemId = Mudclient.ironMaceId }
                        if groundItemCount >= Mudclient.groundItemsMax { return }
                        groundItems[groundItemCount].x = ax
                        groundItems[groundItemCount].y = ay
                        groundItems[groundItemCount].id = itemId
                        groundItems[groundItemCount].z = 0
                        if let o = objects[0..<objectCount].first(where: { $0.x == ax && $0.y == ay }) {
                            groundItems[groundItemCount].z = gameData.objects[o.id].elevation
                        }
                        groundItemCount += 1
                    } else {
                        itemId &= 32767
                        var index = 0
                        for i in 0..<groundItemCount {
                            if groundItems[i].x != ax || groundItems[i].y != ay || groundItems[i].id != itemId {
                                if i != index { moveGroundItem(from: i, to: index) }
                                index += 1
                            } else {
                                itemId = -123
                            }
                        }
                        groundItemCount = index
                    }
                }
            }
            updateGroundItemModels()

        case ServerOpcode.message:
            showServerMessage(r.string(1, size))

        case ServerOpcode.inventoryItems:
            var offset = 1
            inventoryItemsCount = min(r.u8(offset), Mudclient.inventoryItemsMax); offset += 1
            for i in 0..<inventoryItemsCount {
                let idEquip = r.u16(offset); offset += 2
                var id = idEquip & 32767
                if id >= gameData.items.count { id = Mudclient.ironMaceId }
                inventoryItemId[i] = id
                inventoryEquipped[i] = idEquip / 32768
                if gameData.items[id].stackable == 0 {
                    inventoryItemStackCount[i] = r.stack(offset)
                    offset += inventoryItemStackCount[i] >= 128 ? 4 : 1
                } else {
                    inventoryItemStackCount[i] = 1
                }
            }

        case ServerOpcode.inventoryItemUpdate:
            var offset = 1
            var stack = 1
            let index = r.u8(offset); offset += 1
            if index >= Mudclient.inventoryItemsMax { return }
            let idEquip = r.u16(offset); offset += 2
            var id = idEquip & 32767
            if id >= gameData.items.count { id = Mudclient.ironMaceId }
            if gameData.items[id].stackable == 0 {
                stack = r.stack(offset)
                offset += stack >= 128 ? 4 : 1
            }
            inventoryItemId[index] = id
            inventoryEquipped[index] = idEquip / 32768
            inventoryItemStackCount[index] = stack
            if index >= inventoryItemsCount { inventoryItemsCount = index + 1 }

        case ServerOpcode.inventoryItemRemove:
            let index = r.u8(1)
            if index >= Mudclient.inventoryItemsMax { return }
            inventoryItemsCount -= 1
            var i = index
            while i < inventoryItemsCount {
                inventoryItemId[i] = inventoryItemId[i + 1]
                inventoryItemStackCount[i] = inventoryItemStackCount[i + 1]
                inventoryEquipped[i] = inventoryEquipped[i + 1]
                i += 1
            }

        case ServerOpcode.playerStatList:
            var offset = 1
            let n = StatsTab.skillNames.count
            for i in 0..<n { playerSkillCurrent[i] = r.u8(offset); offset += 1 }
            for i in 0..<n { playerSkillBase[i] = r.u8(offset); offset += 1 }
            for i in 0..<n { playerExperience[i] = r.u32(offset); offset += 4 }
            playerQuestPoints = r.u8(offset)

        case ServerOpcode.playerStatEquipmentBonus:
            for i in 0..<Mudclient.playerStatEquipmentCount { playerStatEquipment[i] = r.u8(1 + i) }

        case ServerOpcode.playerStatExperienceUpdate:
            let skill = r.u8(1)
            if skill >= Mudclient.playerSkillCount { return }
            let old = playerExperience[skill]
            playerExperience[skill] = r.u32(2)
            dropExperience(skill: skill, experience: Int(Int32(truncatingIfNeeded: playerExperience[skill] &- old)))

        case ServerOpcode.playerStatUpdate:
            let skill = r.u8(1)
            if skill >= Mudclient.playerSkillCount { return }
            playerSkillCurrent[skill] = r.u8(2)
            playerSkillBase[skill] = r.u8(3)
            playerExperience[skill] = r.u32(4)

        case ServerOpcode.playerStatFatigue:
            statFatigue = r.u16(1)

        case ServerOpcode.playerQuestList:
            for i in 0..<questComplete.count { questComplete[i] = r.u8(i + 1) }

        case ServerOpcode.friendList:
            friendListCount = min(r.u8(1), Mudclient.socialListMax * 2)
            for i in 0..<friendListCount {
                friendList[i] = r.u64(2 + i * 9)
                friendListOnline[i] = r.u8(10 + i * 9)
            }
            sortFriends()

        case ServerOpcode.friendStatusChange:
            let encoded = r.u64(1)
            let world = r.u8(9)
            for i in 0..<friendListCount where friendList[i] == encoded {
                if friendListOnline[i] == 0 && world != 0 {
                    showServerMessage("@pri@\(ClientUtil.decodeUsername(friendList[i])) has logged in")
                }
                if friendListOnline[i] != 0 && world == 0 {
                    showServerMessage("@pri@\(ClientUtil.decodeUsername(friendList[i])) has logged out")
                }
                friendListOnline[i] = world
                sortFriends()
                return
            }
            if friendListCount >= Mudclient.socialListMax * 2 { return }
            friendList[friendListCount] = encoded
            friendListOnline[friendListCount] = world
            friendListCount += 1
            sortFriends()

        case ServerOpcode.friendMessage:
            let from = r.u64(1)
            let offset = 1 + 8 + 4 // the message number after the name is ignored
            let message = ChatMessage.decode(r.data, offset: offset, length: max(0, size - offset))
            showServerMessage("@pri@\(ClientUtil.decodeUsername(from)): tells you \(message)")

        case ServerOpcode.ignoreList:
            ignoreListCount = min(r.u8(1), Mudclient.socialListMax)
            for i in 0..<ignoreListCount { ignoreList[i] = r.u64(2 + i * 8) }

        case ServerOpcode.closeConnection:
            closeConnection()

        case ServerOpcode.sound:
            playSound(r.string(1, size))

        case ServerOpcode.appearance:
            showAppearanceChange = true

        case ServerOpcode.sleepOpen:
            if !isSleeping { fatigueSleeping = statFatigue }
            isSleeping = true
            inputTextCurrent = ""
            inputTextFinal = ""
            surface.readSleepWord(id: spriteTexture + 1, data: Array(incomingPacket[0..<size]))
            sleepingStatusText = nil

        case ServerOpcode.sleepClose:
            isSleeping = false

        case ServerOpcode.sleepIncorrect:
            sleepingStatusText = "Incorrect - Please wait..."

        case ServerOpcode.playerStatFatigueAsleep:
            fatigueSleeping = r.u16(1)

        case ServerOpcode.optionList:
            let count = r.u8(1)
            showOptionMenu = true
            optionMenuCount = count
            var offset = 2
            for i in 0..<count {
                let len = r.u8(offset); offset += 1
                if len > size - offset { break }
                if i < optionMenuEntry.count { optionMenuEntry[i] = r.string(offset, offset + len) }
                offset += len
            }

        case ServerOpcode.optionListClose:
            showOptionMenu = false

        case ServerOpcode.welcome:
            welcomeLastIp = r.u32(1)
            welcomeDaysAgo = r.u16(5)
            welcomeRecoverySetDays = r.u8(7)
            welcomeUnreadMessages = r.u16(8)
            showDialogWelcome = true
            welcomeScreenAlreadyShown = true
            welcomeLastIpString = ""

        case ServerOpcode.serverMessage, ServerOpcode.serverMessageOntop:
            if size >= 1 {
                serverMessage = r.string(1, size)
                showDialogServerMessage = true
                serverMessageBoxTop = opcode == ServerOpcode.serverMessageOntop
                serverMessageNext = ""
                serverMessagePage = 0
            }

        case ServerOpcode.bankOpen:
            showDialogBank = true
            if options.bankMenus != 0 { showRightClickMenu = false }
            var offset = 1
            newBankItemCount = min(r.u8(offset), Mudclient.bankItemsMax); offset += 1
            bankItemsMax = min(r.u8(offset), Mudclient.bankItemsMax); offset += 1
            for i in 0..<newBankItemCount {
                newBankItems[i] = r.u16(offset); offset += 2
                newBankItemsCount[i] = r.stack(offset)
                offset += newBankItemsCount[i] >= 128 ? 4 : 1
            }
            updateBankItems()
            if options.bankSearch != 0 {
                inputPmCurrent = ""
                inputPmFinal = ""
            }
            inputDigitsCurrent = ""
            inputDigitsFinal = 0

        case ServerOpcode.bankClose:
            showDialogBank = false

        case ServerOpcode.bankUpdate:
            var offset = 1
            let itemIndex = r.u8(offset); offset += 1
            let item = r.u16(offset); offset += 2
            let itemCount = r.stack(offset)
            if itemCount == 0 {
                newBankItemCount -= 1
                var i = itemIndex
                while i < newBankItemCount {
                    newBankItems[i] = newBankItems[i + 1]
                    newBankItemsCount[i] = newBankItemsCount[i + 1]
                    i += 1
                }
            } else {
                newBankItems[itemIndex] = item
                newBankItemsCount[itemIndex] = itemCount
                if itemIndex >= newBankItemCount { newBankItemCount = itemIndex + 1 }
            }
            updateBankItems()

        case ServerOpcode.shopOpen:
            showDialogShop = true
            var offset = 1
            let newCount = r.u8(offset); offset += 1
            if newCount > 40 { return }
            let isGeneral = r.u8(offset); offset += 1
            shopSellPriceMod = r.u8(offset); offset += 1
            shopBuyPriceMod = r.u8(offset); offset += 1
            for i in 0..<40 { shopItems[i] = -1 }
            for i in 0..<newCount {
                shopItems[i] = r.u16(offset); offset += 2
                shopItemsCount[i] = r.u16(offset); offset += 2
                shopItemsPrice[i] = r.s8(offset); offset += 1
            }
            if isGeneral == 1 {
                var shopIndex = 39
                for i in 0..<inventoryItemsCount {
                    if shopIndex < newCount { break }
                    var unsellable = shopItems[0..<40].contains(inventoryItemId[i])
                    if inventoryItemId[i] == Mudclient.coinsId { unsellable = true }
                    if !unsellable {
                        shopItems[shopIndex] = inventoryItemId[i] & 32767
                        shopItemsCount[shopIndex] = 0
                        shopItemsPrice[shopIndex] = 0
                        shopIndex -= 1
                    }
                }
            }
            if shopSelectedItemIndex >= 0 && shopSelectedItemIndex < 40 &&
                shopItems[shopSelectedItemIndex] != shopSelectedItemType {
                shopSelectedItemIndex = -1
                shopSelectedItemType = -2
            }

        case ServerOpcode.shopClose:
            showDialogShop = false

        case ServerOpcode.tradeOpen, ServerOpcode.duelOpen:
            let playerIndex = r.u16(1)
            if playerIndex >= Mudclient.playersServerMax { return }
            if let p = playerServer[playerIndex] { transactionRecipientName = p.name }
            let isTrade = opcode == ServerOpcode.tradeOpen
            showDialogTrade = isTrade
            transactionRecipientAccepted = 0
            transactionAccepted = 0
            transactionItemCount = 0
            transactionRecipientItemCount = 0
            if !isTrade {
                showDialogDuel = true
                duelOptionRetreat = 0
                duelOptionMagic = 0
                duelOptionPrayer = 0
                duelOptionWeapons = 0
            }

        case ServerOpcode.tradeClose, ServerOpcode.duelClose:
            showDialogTrade = false
            showDialogTradeConfirm = false
            showDialogDuel = false
            showDialogDuelConfirm = false
            showDialogOfferX = false

        case ServerOpcode.tradeItems, ServerOpcode.duelItems:
            transactionRecipientItemCount = min(r.u8(1), Mudclient.tradeItemsMax)
            var offset = 2
            for i in 0..<transactionRecipientItemCount {
                transactionRecipientItems[i] = r.u16(offset); offset += 2
                transactionRecipientItemsCount[i] = r.u32(offset); offset += 4
            }
            transactionRecipientAccepted = 0
            transactionAccepted = 0

        case ServerOpcode.tradeRecipientAccepted, ServerOpcode.duelRecipientAccepted:
            transactionRecipientAccepted = r.u8(1)

        case ServerOpcode.tradeAccepted, ServerOpcode.duelAccepted:
            transactionAccepted = r.u8(1)

        case ServerOpcode.tradeConfirmOpen, ServerOpcode.duelConfirmOpen:
            showDialogOfferX = false
            if opcode == ServerOpcode.tradeConfirmOpen { showDialogTradeConfirm = true } else { showDialogDuelConfirm = true }
            transactionConfirmAccepted = 0
            showDialogTrade = false
            showDialogDuel = false
            var offset = 1
            transactionRecipientConfirmName = r.u64(offset); offset += 8
            // not clamped in C either; clamp to the array so a bad count can't crash
            transactionRecipientConfirmItemCount = r.u8(offset); offset += 1
            for i in 0..<transactionRecipientConfirmItemCount {
                let item = r.u16(offset); offset += 2
                let count = r.u32(offset); offset += 4
                if i < Mudclient.tradeItemsMax {
                    transactionRecipientConfirmItems[i] = item
                    transactionRecipientConfirmItemsCount[i] = count
                }
            }
            transactionRecipientConfirmItemCount = min(transactionRecipientConfirmItemCount, Mudclient.tradeItemsMax)
            transactionConfirmItemCount = min(r.u8(offset), Mudclient.tradeItemsMax); offset += 1
            for i in 0..<transactionConfirmItemCount {
                transactionConfirmItems[i] = r.u16(offset); offset += 2
                transactionConfirmItemsCount[i] = r.u32(offset); offset += 4
            }

        case ServerOpcode.duelSettings:
            duelOptionRetreat = r.u8(1)
            duelOptionMagic = r.u8(2)
            duelOptionPrayer = r.u8(3)
            duelOptionWeapons = r.u8(4)
            transactionRecipientAccepted = 0
            transactionAccepted = 0

        case ServerOpcode.prayerStatus:
            let n = min(size - 1, Mudclient.prayerCount)
            for i in 0..<max(0, n) {
                let on = incomingPacket[i + 1] == 1
                if !prayerOn[i] && on { playSound("prayeron") }
                if prayerOn[i] && !on { playSound("prayeroff") }
                prayerOn[i] = on
            }

        case ServerOpcode.magicBubble:
            if magicBubbleCount < Mudclient.magicBubbleMax {
                magicBubbles[magicBubbleCount] = MagicBubble(x: r.s8(2) + localRegionX, y: r.s8(3) + localRegionY,
                                                             type: r.u8(1), time: 0)
                magicBubbleCount += 1
            }

        case ServerOpcode.playerDied:
            deathScreenTimeout = 250

        case ServerOpcode.logoutDeny:
            logoutTimeout = 0
            showMessage("@cya@Sorry, you can't logout at the moment", .game)

        case ServerOpcode.gameSettings:
            settingsCameraAuto = r.u8(1)
            settingsMouseButtonOne = r.u8(2)
            settingsSoundDisabled = r.u8(3)

        case ServerOpcode.privacySettings:
            settingsBlockChat = r.u8(1)
            settingsBlockPrivate = r.u8(2)
            settingsBlockTrade = r.u8(3)
            settingsBlockDuel = r.u8(4)

        case ServerOpcode.systemUpdate:
            systemUpdate = r.u16(1) * 32

        default:
            break
        }
    }

    /// One walking step of a known character: the 3-bit direction sprite moves the last waypoint by a tile.
    private func stepWaypoint(_ c: GameCharacter, sprite: Int) {
        let loc = Mudclient.magicLoc
        var w = c.waypointCurrent
        var x = c.waypointsX[w], y = c.waypointsY[w]
        if sprite == 2 || sprite == 1 || sprite == 3 { x += loc }
        if sprite == 6 || sprite == 5 || sprite == 7 { x -= loc }
        if sprite == 4 || sprite == 3 || sprite == 5 { y += loc }
        if sprite == 0 || sprite == 1 || sprite == 7 { y -= loc }
        c.nextAnimation = sprite
        w = (w + 1) % GameCharacter.waypointCount
        c.waypointCurrent = w
        c.waypointsX[w] = x
        c.waypointsY[w] = y
    }

    /// The ground item copy in C moves x, y, id and z but leaves the model in its slot.
    private func moveGroundItem(from: Int, to: Int) {
        groundItems[to].x = groundItems[from].x
        groundItems[to].y = groundItems[from].y
        groundItems[to].id = groundItems[from].id
        groundItems[to].z = groundItems[from].z
    }

    private func removeWallObjectEntry(_ i: Int) {
        if let m = wallObjects[i].model { scene.removeModel(m) }
        world.removeWallObject(x: wallObjects[i].x, y: wallObjects[i].y, dir: wallObjects[i].direction,
                               id: wallObjects[i].id)
        wallObjects[i].model = nil
    }

    // MARK: - Small UI helpers used by packets

    /// mudclient_sort_friends (ui/social-tab.c): online friends first.
    public func sortFriends() {
        var flag = true
        while flag {
            flag = false
            var i = 0
            while i < friendListCount - 1 {
                if (friendListOnline[i] != SocialTab.friendOnline && friendListOnline[i + 1] == SocialTab.friendOnline) ||
                    (friendListOnline[i] == 0 && friendListOnline[i + 1] != 0) {
                    friendListOnline.swapAt(i, i + 1)
                    friendList.swapAt(i, i + 1)
                    flag = true
                }
                i += 1
            }
        }
    }

    /// mudclient_drop_experience (ui/experience-drops.c)
    public func dropExperience(skill: Int, experience: Int) {
        if options.experienceDrops == 0 || experienceDropCount >= Mudclient.experienceDropsMax { return }
        let maxY = Mudclient.height / 4
        experienceDropY[experienceDropCount] = Float(maxY + experienceDropCount * 16)
        experienceDropSkill[experienceDropCount] = skill
        experienceDropAmount[experienceDropCount] = experience
        experienceDropSpeed[experienceDropCount] = -30
        experienceDropCount += 1
    }
}
