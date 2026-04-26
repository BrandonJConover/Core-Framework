// Port of mudclient.loadModels() — loads model archive from bundle

import Foundation

final class ModelArchiveLoader {
    static let shared = ModelArchiveLoader()

    private var modelCache: [String: RSModel] = [:]
    private var isLoaded = false

    private init() {}

    // MARK: - Loading

    /// Loads models from models.orsc ZIP archive in the app bundle.
    /// Each .ob3 file in the ZIP is parsed as a binary RSModel.
    /// If the archive is not present, stub models are created for testing.
    func loadModels(from bundlePath: String) throws {
        guard !isLoaded else { return }

        // Try to load models.orsc from bundle
        guard let archiveURL = Bundle.main.url(forResource: "models", withExtension: "orsc") else {
            // Archive not present in bundle yet — create stub models
            loadStubModels()
            isLoaded = true
            return
        }

        let archiveData = try Data(contentsOf: archiveURL)

        // Parse ZIP entries and load each .ob3 model
        try parseZipArchive(archiveData)

        isLoaded = true
    }

    // MARK: - Access

    /// Returns a cached model by name, or nil if not found.
    func getModel(_ name: String) -> RSModel? {
        return modelCache[name]
    }

    /// Returns all cached models.
    func getAllModels() -> [String: RSModel] {
        return modelCache
    }

    // MARK: - ZIP Parsing

    /// Parses a ZIP archive (models.orsc) and loads each .ob3 file as an RSModel.
    private func parseZipArchive(_ data: Data) throws {
        var offset = 0
        let length = data.count

        // Iterate through ZIP local file headers
        while offset < length {
            // Check for local file header signature: 0x04034b50
            guard offset + 30 <= length else { break }

            let signature = readUInt32LE(from: data, offset: offset)

            // End of central directory reached or no more local headers
            if signature != 0x04034b50 {
                break
            }

            offset += 4 // skip signature

            // Read local file header
            let versionNeeded = readUInt16LE(from: data, offset: offset + 0)
            let flags = readUInt16LE(from: data, offset: offset + 2)
            let compression = readUInt16LE(from: data, offset: offset + 4)
            let fileNameLength = readUInt16LE(from: data, offset: offset + 26)
            let extraFieldLength = readUInt16LE(from: data, offset: offset + 28)

            offset += 26 // move past fixed header fields
            offset += 2  // skip extra field length field

            // Read file name
            let fileNameData = data.subdata(in: offset..<offset + fileNameLength)
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""
            offset += fileNameLength

            // Skip extra field
            offset += extraFieldLength

            // Read compressed/uncompressed size and get data
            let crc32 = readUInt32LE(from: data, offset: offset - fileNameLength - extraFieldLength - 16)
            let compressedSize = readUInt32LE(from: data, offset: offset - fileNameLength - extraFieldLength - 8)
            let uncompressedSize = readUInt32LE(from: data, offset: offset - fileNameLength - extraFieldLength - 4)

            // Only process .ob3 files
            if fileName.lowercased().hasSuffix(".ob3") {
                let fileData = data.subdata(in: offset..<offset + compressedSize)

                // Parse as RSModel with data and offset 0
                let model = RSModel(data: fileData, offset: 0)

                // Cache by filename without extension
                let modelName = (fileName as NSString).deletingPathExtension.lowercased()
                modelCache[modelName] = model
            }

            offset += compressedSize
        }

        // If no models were loaded, fall back to stubs
        if modelCache.isEmpty {
            loadStubModels()
        }
    }

    // MARK: - Helper Functions

    private func readUInt16LE(from data: Data, offset: Int) -> Int {
        let lo = Int(data[offset])
        let hi = Int(data[offset + 1])
        return lo | (hi << 8)
    }

    private func readUInt32LE(from data: Data, offset: Int) -> Int {
        let b0 = Int(data[offset])
        let b1 = Int(data[offset + 1])
        let b2 = Int(data[offset + 2])
        let b3 = Int(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    // MARK: - Stub initialization

    /// Creates placeholder models for testing when models.orsc is not available.
    /// In production, models are loaded from the ZIP archive.
    private func loadStubModels() {
        // Simple cube model for testing
        let cubeModel = RSModel()
        let v0 = cubeModel.insertVertex(x: -64, y: -64, z: -64)
        let v1 = cubeModel.insertVertex(x: 64, y: -64, z: -64)
        let v2 = cubeModel.insertVertex(x: 64, y: 64, z: -64)
        let v3 = cubeModel.insertVertex(x: -64, y: 64, z: -64)
        let v4 = cubeModel.insertVertex(x: -64, y: -64, z: 64)
        let v5 = cubeModel.insertVertex(x: 64, y: -64, z: 64)
        let v6 = cubeModel.insertVertex(x: 64, y: 64, z: 64)
        let v7 = cubeModel.insertVertex(x: -64, y: 64, z: 64)

        // Front face
        cubeModel.insertFace(count: 4, indices: [v0, v1, v2, v3], texFront: -1, texBack: -1)
        // Back face
        cubeModel.insertFace(count: 4, indices: [v4, v7, v6, v5], texFront: -1, texBack: -1)
        // Left face
        cubeModel.insertFace(count: 4, indices: [v0, v3, v7, v4], texFront: -1, texBack: -1)
        // Right face
        cubeModel.insertFace(count: 4, indices: [v1, v5, v6, v2], texFront: -1, texBack: -1)
        // Top face
        cubeModel.insertFace(count: 4, indices: [v3, v2, v6, v7], texFront: -1, texBack: -1)
        // Bottom face
        cubeModel.insertFace(count: 4, indices: [v0, v4, v5, v1], texFront: -1, texBack: -1)

        modelCache["cube"] = cubeModel
    }
}
