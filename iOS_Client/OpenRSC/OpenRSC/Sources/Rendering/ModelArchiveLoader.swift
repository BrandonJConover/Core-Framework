import Foundation

/// Loads 3D model data from the models.orsc ZIP archive and parses each .ob3 entry into RSModel objects.
/// Corresponds to the Java mudclient.loadModels() method.
final class ModelArchiveLoader {
    static let shared = ModelArchiveLoader()

    private(set) var modelCache: [String: RSModel] = [:]
    private(set) var isLoaded = false

    private init() {}

    /// Loads all models from the models.orsc archive in the app bundle.
    func loadModels() {
        guard !isLoaded else { return }

        guard let url = Bundle.main.url(forResource: "models", withExtension: "orsc") else {
            print("ModelArchiveLoader: models.orsc not found in bundle")
            return
        }

        guard let archiveData = try? Data(contentsOf: url) else {
            print("ModelArchiveLoader: Failed to read models.orsc")
            return
        }

        guard let archive = ZipArchiveReader(data: archiveData) else {
            print("ModelArchiveLoader: Failed to open models.orsc as ZIP archive")
            return
        }

        var loadedCount = 0
        var failedCount = 0

        for entryName in archive.entryNames {
            guard let entryData = archive.readEntry(named: entryName) else {
                failedCount += 1
                continue
            }

            // Strip .ob3 extension if present to get the model name
            let modelName: String
            if entryName.lowercased().hasSuffix(".ob3") {
                modelName = String(entryName.dropLast(4))
            } else {
                modelName = entryName
            }

            // Skip empty entries (directories, etc.)
            guard !entryData.isEmpty else { continue }

            // Parse the binary .ob3 model data
            let model = RSModel(data: entryData, offset: 0)
            modelCache[modelName] = model
            loadedCount += 1
        }

        isLoaded = true
        print("ModelArchiveLoader: Loaded \(loadedCount) models (\(failedCount) failed) from models.orsc")
    }

    /// Gets a model by name, returning a COPY since models have mutable state
    /// that gets modified during rendering (transforms, rotations, etc.).
    func getModel(named name: String) -> RSModel? {
        guard let template = modelCache[name] else { return nil }
        return template.copyModel()
    }

    /// Gets a model by name without copying. Use only when you need read-only
    /// access to the template (e.g., checking vertex counts).
    func getTemplate(named name: String) -> RSModel? {
        return modelCache[name]
    }

    /// Returns all loaded model names.
    var modelNames: [String] {
        return Array(modelCache.keys)
    }
}
