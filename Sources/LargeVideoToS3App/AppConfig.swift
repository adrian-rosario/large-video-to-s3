import Foundation

/// Runtime settings, loaded from `config.local.json` in the working directory
/// (gitignored). When run via `swift run`, that's the repo root.
struct AppConfig: Codable {
    var region: String
    var bucket: String
    var keyPrefix: String
    var partSizeMiB: Int
    var maxConcurrentParts: Int

    static func load(path: String = "config.local.json") throws -> AppConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
