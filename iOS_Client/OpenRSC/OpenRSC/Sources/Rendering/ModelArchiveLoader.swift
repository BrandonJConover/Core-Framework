// Loads `models.orsc` — the OpenRSC 3D-model archive — and exposes named
// RSModel lookups + a one-call `instantiate(...)` helper that places a
// model on the scene at a tile position.
//
// Archive format (mirrors Client_Base/src/com/openrsc/data/DataOperations
// + mudclient.unpackData):
//
//   Outer wrapper (6 bytes):
//     [0..2] decompressed length (big-endian 24-bit)
//     [3..5] compressed length   (big-endian 24-bit)
//   If decmp_len != cmp_len the body would be BZIP2-decoded by
//   DataFileDecrypter — but for the bundled `models.orsc` they are equal so
//   the body is the archive directly.
//
//   Inner archive:
//     [0..1]              numEntries (BE u16)
//     [2 + i*10 .. +9]    per-entry directory (10 bytes each):
//                            4B hash         (filename hash, see below)
//                            3B decmp_len    (BE 24-bit)
//                            3B cmp_len      (BE 24-bit)
//     [2 + numEntries*10] start of payload, with each entry's bytes laid
//                          out back-to-back in directory order.
//
//   Filename hash: uppercase, ((hash * 61 + ch) - 32) accumulated for each
//   character. Identical to DataOperations.getDataFileOffset(name, data).
//
// Per-entry payload format ("*.ob3" model files): consumed directly by
// `RSModel(data:offset:)`. See Client_Base/src/orsc/graphics/three/RSModel.java
// constructor. We only need to point the existing parser at the correct
// offset within `archiveBody`.
//
// Lookup is lazy: we keep the body Data and a hash → (offset, length) map,
// and only build an RSModel the first time a name is requested. This avoids
// parsing thousands of models we'll never reference.

import Foundation

final class ModelArchiveLoader {
    static let shared = ModelArchiveLoader()

    /// Lazily-built RSModels keyed by lower-cased name.
    private var modelCache: [String: RSModel] = [:]

    /// Names that exist in the directory but failed to parse — we render a
    /// debug placeholder cube for these so the world is at least populated.
    private var failedNames: Set<String> = []

    /// Cached debug placeholder so we only build it once.
    private lazy var placeholderModel: RSModel = makePlaceholderCube()

    /// Raw archive body retained for on-demand parsing.
    private var archiveBody: Data?
    /// hash → (offset within `archiveBody`, decompressed length, compressed length).
    private var directory: [UInt32: (offset: Int, decmp: Int, cmp: Int)] = [:]

    private var isLoaded = false

    private init() {}

    // MARK: - Public API

    /// Loads `models.orsc` from the app bundle. The `bundlePath` parameter is
    /// kept for backward-compatibility with the existing call site but is
    /// ignored — we always try the bundle first.
    func loadModels(from bundlePath: String) throws {
        guard !isLoaded else { return }
        isLoaded = true

        guard let url = Bundle.main.url(forResource: "models", withExtension: "orsc") else {
            print("[Models] models.orsc not present in bundle — using placeholder cubes")
            return
        }

        let raw: Data
        do { raw = try Data(contentsOf: url) }
        catch {
            print("[Models] Failed reading models.orsc: \(error)")
            return
        }

        guard let body = unwrapDataFile(raw) else {
            print("[Models] models.orsc wrapper header malformed (\(raw.count) bytes)")
            return
        }

        buildDirectory(body: body)
        archiveBody = body

        print("[Models] Indexed \(directory.count) entries from models.orsc"
              + " (\(body.count) byte body)")
    }

    /// Returns the cached RSModel for `name`, or nil if the entry doesn't
    /// exist in the archive (or fails to parse).
    /// Names are matched case-insensitively against the entry hashes from the
    /// archive (which is what GameObjectDef.modelID stores).
    func getModel(named name: String) -> RSModel? {
        let key = name.lowercased()
        if let cached = modelCache[key] { return cached }
        if failedNames.contains(key)    { return nil }

        guard let body = archiveBody else { return nil }
        let hash = filenameHash(name + ".ob3")
        guard let entry = directory[hash] else {
            failedNames.insert(key)
            return nil
        }

        // Compressed entries inside the archive (decmp != cmp) would need the
        // BZIP2 unpacker. The bundled archive is fully uncompressed so this
        // branch shouldn't trip in practice.
        guard entry.decmp == entry.cmp else {
            failedNames.insert(key)
            return nil
        }

        // Bounds-check before handing off to RSModel's parser.
        guard entry.offset + entry.cmp <= body.count else {
            failedNames.insert(key)
            return nil
        }

        let model = RSModel(data: body, offset: entry.offset)
        modelCache[key] = model
        return model
    }

    /// Convenience used by older call-sites.
    func getModel(_ name: String) -> RSModel? { getModel(named: name) }

    /// Returns a deep-copy of the named model translated to the given tile,
    /// rotated by `direction` (RSC dir 0..7 → 256-space yaw via `dir*32`),
    /// added to `scene`. If the model isn't in the archive a small placeholder
    /// cube is used so the caller can still see "an object exists here".
    ///
    /// Mirrors PacketHandler.gotObjectsPacket():
    ///   xWorld = (xTile*2 + xSize) * tileSize / 2
    ///   m.addRotation(0, dir*32, 0)
    ///   m.translate2(xWorld, -elevation, zWorld)
    @discardableResult
    func instantiate(named name: String,
                     atTileX tileX: Int,
                     atTileZ tileZ: Int,
                     direction: Int,
                     width: Int = 1,
                     height: Int = 1,
                     elevation: Int = 0,
                     scene: Scene) -> RSModel {
        let template = getModel(named: name) ?? placeholderModel
        let model = template.clone()

        // dir 0/4 keep object footprint; dir 2/6 swap width/height — same
        // logic mudclient + PacketHandler use to compute world-space size.
        let xSize: Int
        let zSize: Int
        if direction == 0 || direction == 4 {
            xSize = width
            zSize = height
        } else {
            xSize = height
            zSize = width
        }

        let tileSize: Int32 = 128
        let xWorld = Int32((tileX * 2 + xSize)) * tileSize / 2
        let zWorld = Int32((tileZ * 2 + zSize)) * tileSize / 2

        // 8-direction yaw: dir*32 in 0..255 space (RSC packs direction as
        // 0/2/4/6 most often, but the * 32 covers all 8 wedges).
        model.addRotation(0, Int32(direction & 7) &* 32, 0)
        model.translate2(xWorld, Int32(-elevation), zWorld)
        scene.addModel(model)
        return model
    }

    // MARK: - Wrapper unwrap

    /// Strips the 6-byte length-pair header. If the body is BZIP2-compressed
    /// (decmp_len != cmp_len) we do not decompress — the BZIP2 bitstream
    /// implementation in DataFileDecrypter.java is non-standard and not yet
    /// ported. The bundled `models.orsc` is stored uncompressed, so this is
    /// only relevant if a different cache file is dropped in.
    private func unwrapDataFile(_ raw: Data) -> Data? {
        guard raw.count >= 6 else { return nil }
        let decmp = (Int(raw[0]) << 16) | (Int(raw[1]) << 8) | Int(raw[2])
        let cmp   = (Int(raw[3]) << 16) | (Int(raw[4]) << 8) | Int(raw[5])
        guard cmp + 6 <= raw.count else { return nil }
        let body = raw.subdata(in: 6 ..< (6 + cmp))
        if decmp != cmp {
            // BZIP2-compressed — not yet supported.
            print("[Models] models.orsc body is BZIP2-compressed (decmp=\(decmp) cmp=\(cmp))"
                  + " — decompressor not yet ported, skipping")
            return nil
        }
        return body
    }

    // MARK: - Directory build

    private func buildDirectory(body: Data) {
        guard body.count >= 2 else { return }
        let numEntries = (Int(body[0]) << 8) | Int(body[1])
        let directorySize = 2 + numEntries * 10
        guard directorySize <= body.count else {
            print("[Models] Directory truncated (\(numEntries) entries, \(body.count) bytes)")
            return
        }

        var payloadOffset = directorySize
        directory.removeAll(keepingCapacity: true)
        directory.reserveCapacity(numEntries)

        for i in 0 ..< numEntries {
            let base = 2 + i * 10
            let hash = (UInt32(body[base])     << 24)
                     | (UInt32(body[base + 1]) << 16)
                     | (UInt32(body[base + 2]) << 8)
                     |  UInt32(body[base + 3])
            let decmp = (Int(body[base + 4]) << 16) | (Int(body[base + 5]) << 8) | Int(body[base + 6])
            let cmp   = (Int(body[base + 7]) << 16) | (Int(body[base + 8]) << 8) | Int(body[base + 9])
            directory[hash] = (offset: payloadOffset, decmp: decmp, cmp: cmp)
            payloadOffset += cmp
        }
    }

    /// Mirrors DataOperations.getDataFileOffset / loadData hash function:
    /// uppercase the name then accumulate `hash = (hash*61 + char) - 32`.
    private func filenameHash(_ filename: String) -> UInt32 {
        var hash: UInt32 = 0
        for ch in filename.uppercased().unicodeScalars {
            // Match Java int arithmetic with 32-bit wraparound. Casting
            // through Int32 ensures (hash*61) overflows the same way Java's
            // `int` does.
            hash = UInt32(bitPattern: Int32(bitPattern: hash) &* 61 &+ Int32(ch.value) &- 32)
        }
        return hash
    }

    // MARK: - Placeholder

    private func makePlaceholderCube() -> RSModel {
        // 96-unit cube, sitting on the ground (y=0) and centered horizontally.
        // Tile coordinate scale is 128, so this is roughly 3/4 of a tile.
        let m = RSModel(vertexCount: 8, faceCount: 6)
        let s: Int32 = 48
        let v0 = m.insertVertex(x: -s, y:    0, z: -s)
        let v1 = m.insertVertex(x:  s, y:    0, z: -s)
        let v2 = m.insertVertex(x:  s, y:    0, z:  s)
        let v3 = m.insertVertex(x: -s, y:    0, z:  s)
        let v4 = m.insertVertex(x: -s, y: -2*s, z: -s)
        let v5 = m.insertVertex(x:  s, y: -2*s, z: -s)
        let v6 = m.insertVertex(x:  s, y: -2*s, z:  s)
        let v7 = m.insertVertex(x: -s, y: -2*s, z:  s)
        // Bottom (ground), top, four sides — winding chosen so normals face out.
        m.insertFace(count: 4, indices: [v0, v3, v2, v1], texFront: -1, texBack: -1)
        m.insertFace(count: 4, indices: [v4, v5, v6, v7], texFront: -1, texBack: -1)
        m.insertFace(count: 4, indices: [v0, v1, v5, v4], texFront: -1, texBack: -1)
        m.insertFace(count: 4, indices: [v1, v2, v6, v5], texFront: -1, texBack: -1)
        m.insertFace(count: 4, indices: [v2, v3, v7, v6], texFront: -1, texBack: -1)
        m.insertFace(count: 4, indices: [v3, v0, v4, v7], texFront: -1, texBack: -1)
        return m
    }
}
