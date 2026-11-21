// Port of world.c's section loading and model assembly.

extension World {
    private struct ByteReader {
        let data: [UInt8]
        var offset = 0
        init(_ data: [UInt8]) { self.data = data }
        mutating func u8() -> Int {
            defer { offset += 1 }
            return offset < data.count ? Int(data[offset]) : 0
        }
        mutating func s8() -> Int { Int(Int8(bitPattern: UInt8(u8()))) }
        mutating func u16() -> Int {
            let hi = u8(), lo = u8()
            return hi << 8 | lo
        }
    }

    private func file(_ name: String, _ pack: JagArchive?) -> [UInt8]? {
        guard let pack else { return nil }
        return (try? pack.file(name)) ?? nil
    }

    func clearRegion(plane: Int, chunk: Int) {
        let base = chunk * World.tileCount
        let decoration: Int8 = plane == 0 ? -6 : plane == 3 ? 8 : 0
        for t in base..<(base + World.tileCount) {
            terrainHeight[t] = 0
            terrainColour[t] = 0
            wallsNorthSouth[t] = 0
            wallsEastWest[t] = 0
            wallsDiagonal[t] = 0
            wallsRoof[t] = 0
            tileDecoration[t] = decoration
            tileDirection[t] = 0
        }
    }

    func loadSectionJm(_ data: [UInt8], chunk: Int) {
        var r = ByteReader(data)
        let base = chunk * World.tileCount
        var prev = 0
        for t in 0..<World.tileCount {
            prev += r.s8()
            terrainHeight[base + t] = Int8(truncatingIfNeeded: prev & 0xff)
        }
        prev = 0
        for t in 0..<World.tileCount {
            prev += r.s8()
            terrainColour[base + t] = Int8(truncatingIfNeeded: prev & 0xff)
        }
        for t in 0..<World.tileCount { wallsNorthSouth[base + t] = Int8(truncatingIfNeeded: r.s8()) }
        for t in 0..<World.tileCount { wallsEastWest[base + t] = Int8(truncatingIfNeeded: r.s8()) }
        for t in 0..<World.tileCount { wallsDiagonal[base + t] = UInt16(truncatingIfNeeded: r.u16()) }
        for t in 0..<World.tileCount { wallsRoof[base + t] = Int8(truncatingIfNeeded: r.s8()) }
        for t in 0..<World.tileCount { tileDecoration[base + t] = Int8(truncatingIfNeeded: r.s8()) }
        for t in 0..<World.tileCount { tileDirection[base + t] = Int8(truncatingIfNeeded: r.s8()) }
    }

    func loadSectionFiles(x: Int, y: Int, plane: Int, chunk: Int) {
        let name = "m\(plane)\(x / 10)\(x % 10)\(y / 10)\(y % 10)"
        let base = chunk * World.tileCount
        let count = World.tileCount

        if landscapePack == nil {
            if let data = file(name + ".jm", mapPack) {
                loadSectionJm(data, chunk: chunk)
            } else {
                clearRegion(plane: plane, chunk: chunk)
            }
            return
        }

        // Run-length data can overrun a section in malformed files; rsc-c would write into the next array.
        func put<T>(_ a: inout [T], _ tile: Int, _ v: T) { if tile < count { a[base + tile] = v } }

        var hei = file(name + ".hei", landscapePack)
        if hei == nil && memberLandscapePack != nil { hei = file(name + ".hei", memberLandscapePack) }
        if let hei {
            var r = ByteReader(hei)
            var last = 0
            var tile = 0
            while tile < count {
                let v = r.u8()
                if v < 128 {
                    put(&terrainHeight, tile, Int8(truncatingIfNeeded: v)); tile += 1
                    last = v
                }
                if v >= 128 {
                    for _ in 0..<(v - 128) { put(&terrainHeight, tile, Int8(truncatingIfNeeded: last)); tile += 1 }
                }
            }
            last = 64
            for ty in 0..<48 {
                for tx in 0..<48 {
                    last = (Int(terrainHeight[base + tx * 48 + ty]) + last) & 127
                    terrainHeight[base + tx * 48 + ty] = Int8(truncatingIfNeeded: last * 2)
                }
            }
            last = 0
            tile = 0
            while tile < count {
                let v = r.u8()
                if v < 128 {
                    put(&terrainColour, tile, Int8(truncatingIfNeeded: v)); tile += 1
                    last = v
                }
                if v >= 128 {
                    for _ in 0..<(v - 128) { put(&terrainColour, tile, Int8(truncatingIfNeeded: last)); tile += 1 }
                }
            }
            last = 35
            for ty in 0..<48 {
                for tx in 0..<48 {
                    last = (Int(terrainColour[base + tx * 48 + ty]) + last) & 127
                    terrainColour[base + tx * 48 + ty] = Int8(truncatingIfNeeded: last * 2)
                }
            }
        } else {
            for t in 0..<count {
                terrainHeight[base + t] = 0
                terrainColour[base + t] = 0
            }
        }

        var dat = file(name + ".dat", mapPack)
        if dat == nil && memberMapPack != nil { dat = file(name + ".dat", memberMapPack) }
        guard let dat else {
            clearRegion(plane: plane, chunk: chunk)
            return
        }
        var r = ByteReader(dat)

        func wallLayer(_ store: (Int, Int) -> Void) {
            var tile = 0
            while tile < count {
                let v = r.u8()
                if version > 54 {
                    store(tile, v); tile += 1
                } else if version > 45 {
                    if v < 192 { store(tile, v); tile += 1 } else { for _ in 0..<(v - 192) { store(tile, 0); tile += 1 } }
                } else {
                    if v < 128 { store(tile, v); tile += 1 } else { for _ in 0..<(v - 128) { store(tile, 0); tile += 1 } }
                }
            }
        }
        wallLayer { t, v in put(&self.wallsNorthSouth, t, Int8(truncatingIfNeeded: v)) }
        wallLayer { t, v in put(&self.wallsEastWest, t, Int8(truncatingIfNeeded: v)) }
        wallLayer { t, v in put(&self.wallsDiagonal, t, UInt16(truncatingIfNeeded: v)) }

        var tile = 0
        while tile < count {
            let v = r.u8()
            if version > 54 {
                if v > 0 { put(&wallsDiagonal, tile, UInt16(truncatingIfNeeded: v + 12000)) }
                tile += 1
            } else if version > 45 {
                if v < 192 { put(&wallsDiagonal, tile, UInt16(truncatingIfNeeded: v + 12000)); tile += 1 } else { tile += v - 192 }
            } else {
                if v < 128 { put(&wallsDiagonal, tile, UInt16(truncatingIfNeeded: v + 12000)); tile += 1 } else { tile += v - 128 }
            }
        }

        tile = 0
        while tile < count {
            let v = r.u8()
            if v < 128 {
                put(&wallsRoof, tile, Int8(truncatingIfNeeded: v)); tile += 1
            } else {
                for _ in 0..<(v - 128) { put(&wallsRoof, tile, 0); tile += 1 }
            }
        }

        var last = 0
        tile = 0
        while tile < count {
            let v = r.u8()
            if v < 128 {
                put(&tileDecoration, tile, Int8(truncatingIfNeeded: v)); tile += 1
                last = v
            } else {
                for _ in 0..<(v - 128) { put(&tileDecoration, tile, Int8(truncatingIfNeeded: last)); tile += 1 }
            }
        }

        tile = 0
        while tile < count {
            let v = r.u8()
            if v < 128 {
                put(&tileDirection, tile, Int8(truncatingIfNeeded: v)); tile += 1
            } else {
                for _ in 0..<(v - 128) { put(&tileDirection, tile, 0); tile += 1 }
            }
        }

        // .loc only comes from the free map pack in rsc-c.
        if let loc = file(name + ".loc", mapPack) {
            var lr = ByteReader(loc)
            tile = 0
            while tile < count {
                let v = lr.u8()
                if v < 128 {
                    put(&wallsDiagonal, tile, UInt16(truncatingIfNeeded: v + 48000)); tile += 1
                } else {
                    tile += v - 128
                }
            }
        }
    }

    // MARK: - Assembly

    private func newParent() -> GameModel {
        GameModel(vertices: World.terrainMaxVertices, faces: World.terrainMaxFaces, autocommit: true, isolated: true,
                  unlit: false, unpickable: false, projected: true)
    }

    private func isBridge(_ decoration: Int) -> Bool {
        decoration > 0 && gameData.tiles[decoration - 1].type == World.bridgeTile
    }

    private func tagTile(_ m: GameModel, _ face: Int, _ x: Int, _ y: Int) {
        guard face >= 0 else { return }
        if face < World.localCount {
            localX[face] = x
            localY[face] = y
        }
        m.faceTag![face] = Int32(truncatingIfNeeded: World.tileFaceTag + face)
    }

    private func bridgeQuad(_ m: GameModel, _ x: Int, _ y: Int, _ fill: Int) {
        let ts = World.tileSize
        let v0 = m.vertexAt(x: x * ts, y: -terrainHeightAt(x, y), z: y * ts)
        let v1 = m.vertexAt(x: (x + 1) * ts, y: -terrainHeightAt(x + 1, y), z: y * ts)
        let v2 = m.vertexAt(x: (x + 1) * ts, y: -terrainHeightAt(x + 1, y + 1), z: (y + 1) * ts)
        let v3 = m.vertexAt(x: x * ts, y: -terrainHeightAt(x, y + 1), z: (y + 1) * ts)
        let face = m.createFace([v0, v1, v2, v3].map { UInt16(truncatingIfNeeded: $0) }, fillFront: fill,
                                fillBack: Scene.colourTransparent)
        tagTile(m, face, x, y)
        drawMapTile(x, y, 0, fill, fill)
    }

    func loadAssemble(x: Int, y: Int, plane: Int, isCurrentPlane: Bool) {
        let sectionX = (x + World.regionSize / 2) / World.regionSize
        let sectionY = (y + World.regionSize / 2) / World.regionSize
        loadSectionFiles(x: sectionX - 1, y: sectionY - 1, plane: plane, chunk: 0)
        loadSectionFiles(x: sectionX, y: sectionY - 1, plane: plane, chunk: 1)
        loadSectionFiles(x: sectionX - 1, y: sectionY, plane: plane, chunk: 2)
        loadSectionFiles(x: sectionX, y: sectionY, plane: plane, chunk: 3)
        fillEdges()

        let transparent = Scene.colourTransparent
        let ts = World.tileSize
        var parent = newParent()

        if isCurrentPlane {
            surface.blackScreen()
            for i in 0..<objectAdjacency.count { objectAdjacency[i] = 0 }
            parent = newParent()
            let m = parent

            for rx in 0..<World.regionWidth {
                for ry in 0..<World.regionHeight {
                    var height = -terrainHeightAt(rx, ry)
                    if isBridge(tileDecoration(rx, ry)) { height = 0 }
                    if isBridge(tileDecoration(rx - 1, ry)) { height = 0 }
                    if isBridge(tileDecoration(rx, ry - 1)) { height = 0 }
                    if isBridge(tileDecoration(rx - 1, ry - 1)) { height = 0 }
                    let v = m.vertexAt(x: rx * ts, y: height, z: ry * ts)
                    let ambience = Int(random.nextUnitFloat() * 10) - 5
                    m.setVertexAmbience(v, ambience)
                }
            }

            for rx in 0..<(World.regionWidth - 1) {
                for ry in 0..<(World.regionHeight - 1) {
                    var colour = Int(World.terrainColours[terrainColourAt(rx, ry)])
                    var colour1 = colour
                    var colour2 = colour
                    var direction = 0
                    if plane == 1 || plane == 2 {
                        colour = transparent; colour1 = transparent; colour2 = transparent
                    }
                    let decoration = tileDecoration(rx, ry)
                    if decoration > 0 {
                        let tile = gameData.tiles[decoration - 1]
                        let tileType = tile.type
                        let isFloor = self.tileType(rx, ry)
                        colour = tile.decoration
                        colour1 = tile.decoration
                        if tileType == World.bridgeTile {
                            colour = 1; colour1 = 1
                            if decoration == World.bridgeTileDecoration { colour = 31; colour1 = 31 }
                        } else if tileType == World.holeTile {
                            let diagonal = wallDiagonal(rx, ry)
                            if diagonal > 0 && diagonal < 24000 {
                                func d(_ x: Int, _ y: Int) -> Int { decorationOrColour(x, y, colour2) }
                                if d(rx - 1, ry) != transparent && d(rx, ry - 1) != transparent {
                                    colour = d(rx - 1, ry); direction = 0
                                } else if d(rx + 1, ry) != transparent && d(rx, ry + 1) != transparent {
                                    colour1 = d(rx + 1, ry); direction = 0
                                } else if d(rx + 1, ry) != transparent && d(rx, ry - 1) != transparent {
                                    colour1 = d(rx + 1, ry); direction = 1
                                } else if d(rx - 1, ry) != transparent && d(rx, ry + 1) != transparent {
                                    colour = d(rx - 1, ry); direction = 1
                                }
                            }
                        } else if tileType != World.floorTile ||
                                    (wallDiagonal(rx, ry) > 0 && wallDiagonal(rx, ry) < 24000) {
                            if self.tileType(rx - 1, ry) != isFloor && self.tileType(rx, ry - 1) != isFloor {
                                colour = colour2; direction = 0
                            } else if self.tileType(rx + 1, ry) != isFloor && self.tileType(rx, ry + 1) != isFloor {
                                colour1 = colour2; direction = 0
                            } else if self.tileType(rx + 1, ry) != isFloor && self.tileType(rx, ry - 1) != isFloor {
                                colour1 = colour2; direction = 1
                            } else if self.tileType(rx - 1, ry) != isFloor && self.tileType(rx, ry + 1) != isFloor {
                                colour = colour2; direction = 1
                            }
                        }
                        if tile.blocking != 0 { objectAdjacency[World.ai(rx, ry)] |= 0x40 }
                        if tileType == World.floorTile { objectAdjacency[World.ai(rx, ry)] |= 0x80 }
                    }

                    drawMapTile(rx, ry, direction, colour, colour1)

                    let slope = terrainHeightAt(rx + 1, ry + 1) - terrainHeightAt(rx + 1, ry) +
                        terrainHeightAt(rx, ry + 1) - terrainHeightAt(rx, ry)
                    let v = ry + rx * 96
                    func tri(_ a: Int, _ b: Int, _ c: Int, _ fill: Int) {
                        let face = m.createFace([UInt16(truncatingIfNeeded: a), UInt16(truncatingIfNeeded: b),
                                                 UInt16(truncatingIfNeeded: c)], fillFront: transparent, fillBack: fill)
                        tagTile(m, face, rx, ry)
                    }
                    if colour != colour1 || slope != 0 {
                        if direction == 0 {
                            if colour != transparent { tri(v + 96, v, v + 1, colour) }
                            if colour1 != transparent { tri(v + 1, v + 96 + 1, v + 96, colour1) }
                        } else {
                            if colour != transparent { tri(v + 1, v + 96 + 1, v, colour) }
                            if colour1 != transparent { tri(v + 96, v, v + 96 + 1, colour1) }
                        }
                    } else if colour != transparent {
                        let face = m.createFace([UInt16(truncatingIfNeeded: v + 96), UInt16(truncatingIfNeeded: v),
                                                 UInt16(truncatingIfNeeded: v + 1), UInt16(truncatingIfNeeded: v + 96 + 1)],
                                                fillFront: transparent, fillBack: colour)
                        tagTile(m, face, rx, ry)
                    }
                }
            }

            for rx in 1..<(World.regionWidth - 1) {
                for ry in 1..<(World.regionHeight - 1) {
                    let decoration = tileDecoration(rx, ry)
                    if isBridge(decoration) {
                        bridgeQuad(m, rx, ry, gameData.tiles[decoration - 1].decoration)
                    } else if decoration == 0 || gameData.tiles[decoration - 1].type != World.liquidTile {
                        let south = tileDecoration(rx, ry + 1)
                        if isBridge(south) { bridgeQuad(m, rx, ry, gameData.tiles[south - 1].decoration) }
                        let north = tileDecoration(rx, ry - 1)
                        if isBridge(north) { bridgeQuad(m, rx, ry, gameData.tiles[tileDecoration(rx, ry - 1) - 1].decoration) }
                        let east = tileDecoration(rx + 1, ry)
                        if isBridge(east) { bridgeQuad(m, rx, ry, gameData.tiles[east - 1].decoration) }
                        let west = tileDecoration(rx - 1, ry)
                        if isBridge(west) { bridgeQuad(m, rx, ry, gameData.tiles[west - 1].decoration) }
                    }
                }
            }

            m.setLight(gouraud: true, ambience: 40, diffuse: 48, x: -50, y: -10, z: -50)
            let pieces = parent.split(pieceDX: 1536, pieceDZ: 1536, rows: 8, count: 64, pieceMaxVertices: 233, pickable: false)
            for i in 0..<World.terrainCount {
                terrainModels[i] = i < pieces.count ? pieces[i] : nil
                scene.addModel(terrainModels[i])
            }
            for rx in 0..<World.regionWidth {
                for ry in 0..<World.regionHeight {
                    terrainHeightLocal[World.ai(rx, ry)] = terrainHeightAt(rx, ry)
                }
            }
        }

        parent = newParent()
        parentModel = parent
        let colour: Int32 = 0x606060

        for rx in 0..<(World.regionWidth - 1) {
            for ry in 0..<(World.regionHeight - 1) {
                var wall = wallEastWest(rx, ry)
                if wall > 0 && gameData.walls[wall - 1].interactive == 0 {
                    createWall(parent, wall - 1, rx, ry, rx + 1, ry)
                    if isCurrentPlane && gameData.walls[wall - 1].blocking != 0 {
                        objectAdjacency[World.ai(rx, ry)] |= 1
                        if ry > 0 { setBlocked(rx, ry - 1, 4) }
                    }
                    if isCurrentPlane { surface.drawLineHorizontal(x: rx * 3, y: ry * 3, width: 3, colour: colour) }
                }
                wall = wallNorthSouth(rx, ry)
                if wall > 0 && gameData.walls[wall - 1].interactive == 0 {
                    createWall(parent, wall - 1, rx, ry, rx, ry + 1)
                    if isCurrentPlane && gameData.walls[wall - 1].blocking != 0 {
                        objectAdjacency[World.ai(rx, ry)] |= 2
                        if rx > 0 { setBlocked(rx - 1, ry, 8) }
                    }
                    if isCurrentPlane { surface.drawLineVertical(x: rx * 3, y: ry * 3, height: 3, colour: colour) }
                }
                wall = wallDiagonal(rx, ry)
                if wall > 0 && wall < 12000 && gameData.walls[wall - 1].interactive == 0 {
                    createWall(parent, wall - 1, rx, ry, rx + 1, ry + 1)
                    if isCurrentPlane && gameData.walls[wall - 1].blocking != 0 {
                        objectAdjacency[World.ai(rx, ry)] |= 0x20
                    }
                    if isCurrentPlane {
                        surface.setPixel(x: rx * 3, y: ry * 3, colour: colour)
                        surface.setPixel(x: rx * 3 + 1, y: ry * 3 + 1, colour: colour)
                        surface.setPixel(x: rx * 3 + 2, y: ry * 3 + 2, colour: colour)
                    }
                } else if wall > 12000 && wall < 24000 && gameData.walls[wall - 12001].interactive == 0 {
                    createWall(parent, wall - 12001, rx + 1, ry, rx, ry + 1)
                    if isCurrentPlane && gameData.walls[wall - 12001].blocking != 0 {
                        objectAdjacency[World.ai(rx, ry)] |= 0x10
                    }
                    if isCurrentPlane {
                        surface.setPixel(x: rx * 3 + 2, y: ry * 3, colour: colour)
                        surface.setPixel(x: rx * 3 + 1, y: ry * 3 + 1, colour: colour)
                        surface.setPixel(x: rx * 3, y: ry * 3 + 2, colour: colour)
                    }
                }
            }
        }

        if isCurrentPlane {
            surface.drawSpriteReversed(id: baseMediaSprite - 1, x: 0, y: 0, width: Surface.minimapSpriteWidth,
                                       height: Surface.minimapSpriteWidth)
        }

        parent.setLight(gouraud: false, ambience: 60, diffuse: 24, x: -50, y: -10, z: -50)
        let walls = parent.split(pieceDX: 1536, pieceDZ: 1536, rows: 8, count: 64, pieceMaxVertices: 338, pickable: true)
        for i in 0..<World.terrainCount {
            wallModels[plane][i] = i < walls.count ? walls[i] : nil
            scene.addModel(wallModels[plane][i])
        }

        for rx in 0..<(World.regionWidth - 1) {
            for ry in 0..<(World.regionHeight - 1) {
                var id = wallEastWest(rx, ry)
                if id > 0 { raiseWallObject(id - 1, rx, ry, rx + 1, ry) }
                id = wallNorthSouth(rx, ry)
                if id > 0 { raiseWallObject(id - 1, rx, ry, rx, ry + 1) }
                id = wallDiagonal(rx, ry)
                if id > 0 && id < 12000 { raiseWallObject(id - 1, rx, ry, rx + 1, ry + 1) }
                if id > 12000 && id < 24000 { raiseWallObject(id - 12001, rx + 1, ry, rx, ry + 1) }
            }
        }

        let ph = World.planeHeight
        for rx in 1..<(World.regionWidth - 1) {
            for ry in 1..<(World.regionHeight - 1) {
                if wallRoof(rx, ry) <= 0 { continue }
                let ex = rx + 1, sy = ry + 1
                var height = 0
                var h = terrainHeightLocal[World.ai(rx, ry)]
                var he = terrainHeightLocal[World.ai(ex, ry)]
                var hse = terrainHeightLocal[World.ai(ex, sy)]
                var hs = terrainHeightLocal[World.ai(rx, sy)]
                if h > ph { h -= ph }
                if he > ph { he -= ph }
                if hse > ph { hse -= ph }
                if hs > ph { hs -= ph }
                if h > height { height = h }
                if he > height { height = he }
                if hse > height { height = hse }
                if hs > height { height = hs }
                if height >= ph { height -= ph }
                if h < ph { terrainHeightLocal[World.ai(rx, ry)] = height } else { terrainHeightLocal[World.ai(rx, ry)] -= ph }
                if he < ph { terrainHeightLocal[World.ai(ex, ry)] = height } else { terrainHeightLocal[World.ai(ex, ry)] -= ph }
                if hse < ph { terrainHeightLocal[World.ai(ex, sy)] = height } else { terrainHeightLocal[World.ai(ex, sy)] -= ph }
                if hs < ph { terrainHeightLocal[World.ai(rx, sy)] = height } else { terrainHeightLocal[World.ai(rx, sy)] -= ph }
            }
        }

        parent = newParent()
        parentModel = parent
        let slope = World.roofSlope

        for rx in 1..<(World.regionWidth - 1) {
            for ry in 1..<(World.regionHeight - 1) {
                var roofId = wallRoof(rx, ry)
                if roofId <= 0 { continue }
                let ex = rx + 1, sy = ry + 1
                var v1x = rx * ts, v1z = ry * ts
                var v2x = v1x + ts, v4z = v1z + ts
                var v3x = v1x, v2z = v1z
                var v4x = v2x, v3z = v4z
                var h = terrainHeightLocal[World.ai(rx, ry)]
                var he = terrainHeightLocal[World.ai(ex, ry)]
                var hse = terrainHeightLocal[World.ai(ex, sy)]
                var hs = terrainHeightLocal[World.ai(rx, sy)]
                let roofHeight = gameData.roofs[roofId - 1].height

                if hasRoof(rx, ry) && h < ph {
                    h += roofHeight + ph
                    terrainHeightLocal[World.ai(rx, ry)] = h
                }
                if hasRoof(ex, ry) && he < ph {
                    he += roofHeight + ph
                    terrainHeightLocal[World.ai(ex, ry)] = he
                }
                if hasRoof(ex, sy) && hse < ph {
                    hse += roofHeight + ph
                    terrainHeightLocal[World.ai(ex, sy)] = hse
                }
                if hasRoof(rx, sy) && hs < ph {
                    hs += roofHeight + ph
                    terrainHeightLocal[World.ai(rx, sy)] = hs
                }
                if h >= ph { h -= ph }
                if he >= ph { he -= ph }
                if hse >= ph { hse -= ph }
                if hs >= ph { hs -= ph }

                if !hasNeighbouringRoof(rx - 1, ry) { v1x -= slope }
                if !hasNeighbouringRoof(rx + 1, ry) { v1x += slope }
                if !hasNeighbouringRoof(rx, ry - 1) { v1z -= slope }
                if !hasNeighbouringRoof(rx, ry + 1) { v1z += slope }
                if !hasNeighbouringRoof(ex - 1, ry) { v2x -= slope }
                if !hasNeighbouringRoof(ex + 1, ry) { v2x += slope }
                if !hasNeighbouringRoof(ex, ry - 1) { v2z -= slope }
                if !hasNeighbouringRoof(ex, ry + 1) { v2z += slope }
                if !hasNeighbouringRoof(ex - 1, sy) { v4x -= slope }
                if !hasNeighbouringRoof(ex + 1, sy) { v4x += slope }
                if !hasNeighbouringRoof(ex, sy - 1) { v4z -= slope }
                if !hasNeighbouringRoof(ex, sy + 1) { v4z += slope }
                if !hasNeighbouringRoof(rx - 1, sy) { v3x -= slope }
                if !hasNeighbouringRoof(rx + 1, sy) { v3x += slope }
                if !hasNeighbouringRoof(rx, sy - 1) { v3z -= slope }
                if !hasNeighbouringRoof(rx, sy + 1) { v3z += slope }

                roofId = gameData.roofs[roofId - 1].fill
                h = -h; he = -he; hse = -hse; hs = -hs

                let p = parent
                func v1() -> Int { p.vertexAt(x: v1x, y: h, z: v1z) }
                func v2() -> Int { p.vertexAt(x: v2x, y: he, z: v2z) }
                func v3() -> Int { p.vertexAt(x: v3x, y: hs, z: v3z) }
                func v4() -> Int { p.vertexAt(x: v4x, y: hse, z: v4z) }
                func face(_ vs: [Int]) {
                    p.createFace(vs.map { UInt16(truncatingIfNeeded: $0) }, fillFront: roofId, fillBack: transparent)
                }

                let diagonal = wallDiagonal(rx, ry)
                if diagonal > 12000 && diagonal < 24000 && wallRoof(rx - 1, ry - 1) == 0 {
                    let a = v4(), b = v3(), c = v2()
                    face([a, b, c])
                } else if diagonal > 12000 && diagonal < 24000 && wallRoof(rx + 1, ry + 1) == 0 {
                    let a = v1(), b = v2(), c = v3()
                    face([a, b, c])
                } else if wallDiagonal(rx, ry) > 0 && wallDiagonal(rx, ry) < 12000 && wallRoof(rx + 1, ry - 1) == 0 {
                    let a = v3(), b = v1(), c = v4()
                    face([a, b, c])
                } else if wallDiagonal(rx, ry) > 0 && wallDiagonal(rx, ry) < 12000 && wallRoof(rx - 1, ry + 1) == 0 {
                    let a = v2(), b = v4(), c = v1()
                    face([a, b, c])
                } else if h == he && hse == hs {
                    let a = v1(), b = v2(), c = v4(), d = v3()
                    face([a, b, c, d])
                } else if h == hs && he == hse {
                    let a = v3(), b = v1(), c = v2(), d = v4()
                    face([a, b, c, d])
                } else {
                    var direction = true
                    if wallRoof(rx - 1, ry - 1) > 0 { direction = false }
                    if wallRoof(rx + 1, ry + 1) > 0 { direction = false }
                    if !direction {
                        let a = v2(), b = v4(), c = v1()
                        face([a, b, c])
                        let d = v3(), e = v1(), f = v4()
                        face([d, e, f])
                    } else {
                        let a = v1(), b = v2(), c = v3()
                        face([a, b, c])
                        let d = v4(), e = v3(), f = v2()
                        face([d, e, f])
                    }
                }
            }
        }

        parent.setLight(gouraud: true, ambience: 50, diffuse: 50, x: -50, y: -10, z: -50)
        let roofs = parent.split(pieceDX: 1536, pieceDZ: 1536, rows: 8, count: 64, pieceMaxVertices: 169, pickable: true)
        for i in 0..<World.terrainCount {
            roofModels[plane][i] = i < roofs.count ? roofs[i] : nil
            scene.addModel(roofModels[plane][i])
        }
        for i in 0..<terrainHeightLocal.count where terrainHeightLocal[i] >= ph {
            terrainHeightLocal[i] -= ph
        }
    }

    func createWall(_ m: GameModel, _ wallId: Int, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
        vertexShadow(x1, y1, 40)
        vertexShadow(x2, y2, 40)
        let wall = gameData.walls[wallId]
        let height = wall.height
        let front = wall.textureFront, back = wall.textureBack
        let ts = World.tileSize
        var vx1 = x1 * ts, vy1 = y1 * ts, vx2 = x2 * ts, vy2 = y2 * ts
        if thickWalls {
            let dx = (y1 - y2) * 8
            vx1 += dx; vx2 += dx
            let dy = (x1 - x2) * 8
            vy1 -= dy; vy2 -= dy
        }
        let h1 = terrainHeightLocal[World.ai(x1, y1)], h2 = terrainHeightLocal[World.ai(x2, y2)]
        let a = m.vertexAt(x: vx1, y: -h1, z: vy1)
        let b = m.vertexAt(x: vx1, y: -h1 - height, z: vy1)
        let c = m.vertexAt(x: vx2, y: -h2 - height, z: vy2)
        let d = m.vertexAt(x: vx2, y: -h2, z: vy2)
        let verts = [a, b, c, d].map { UInt16(truncatingIfNeeded: $0) }
        let wallFace = m.createFace(verts, fillFront: front, fillBack: thickWalls ? Scene.colourTransparent : back)
        if wallFace >= 0 { m.faceTag![wallFace] = 0 }
        if thickWalls {
            var px1 = x1 * ts, py1 = y1 * ts, px2 = x2 * ts, py2 = y2 * ts
            let dx = (y1 - y2) * 8
            px1 -= dx; px2 -= dx
            let dy = (x1 - x2) * 8
            py1 += dy; py2 += dy
            let pa = m.vertexAt(x: px1, y: -h1, z: py1)
            let pb = m.vertexAt(x: px1, y: -h1 - height, z: py1)
            let pc = m.vertexAt(x: px2, y: -h2 - height, z: py2)
            let pd = m.vertexAt(x: px2, y: -h2, z: py2)
            let pverts = [pa, pb, pc, pd].map { UInt16(truncatingIfNeeded: $0) }
            let parallel = m.createFace(pverts, fillFront: Scene.colourTransparent, fillBack: back)
            if parallel >= 0 { m.faceTag![parallel] = 0 }
            m.createFace([verts[1], pverts[1], pverts[2], verts[2]], fillFront: -7400, fillBack: -7400)
        }
    }

    func raiseWallObject(_ wallId: Int, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
        let height = gameData.walls[wallId].height
        if terrainHeightLocal[World.ai(x1, y1)] < World.planeHeight {
            terrainHeightLocal[World.ai(x1, y1)] += World.planeHeight + height
        }
        if terrainHeightLocal[World.ai(x2, y2)] < World.planeHeight {
            terrainHeightLocal[World.ai(x2, y2)] += World.planeHeight + height
        }
    }

    /// world_load_section: rebuilds the 96x96 tile area around (x, y) for `plane`.
    public func loadSection(x: Int, y: Int, plane: Int) {
        reset(dispose: true)
        let sectionX = (x + World.regionSize / 2) / World.regionSize
        let sectionY = (y + World.regionSize / 2) / World.regionSize
        loadAssemble(x: x, y: y, plane: plane, isCurrentPlane: true)
        if plane == 0 {
            loadAssemble(x: x, y: y, plane: 1, isCurrentPlane: false)
            loadAssemble(x: x, y: y, plane: 2, isCurrentPlane: false)
            loadSectionFiles(x: sectionX - 1, y: sectionY - 1, plane: plane, chunk: 0)
            loadSectionFiles(x: sectionX, y: sectionY - 1, plane: plane, chunk: 1)
            loadSectionFiles(x: sectionX - 1, y: sectionY, plane: plane, chunk: 2)
            loadSectionFiles(x: sectionX, y: sectionY, plane: plane, chunk: 3)
            fillEdges()
        }
        parentModel = nil
    }
}
