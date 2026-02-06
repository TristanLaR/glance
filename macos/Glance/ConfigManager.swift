import Foundation

struct WindowState: Codable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    static let `default` = WindowState(x: 100, y: 100, width: 900, height: 700)
}

struct AppConfig: Codable {
    var noTruncate: Bool = false
    var extensions: AppExtensionsConfig = AppExtensionsConfig()

    enum CodingKeys: String, CodingKey {
        case noTruncate = "no_truncate"
        case extensions
    }
}

struct AppExtensionsConfig: Codable {
    var plantuml: Bool = false
}

class ConfigManager {
    static let shared = ConfigManager()

    private let configDir: URL?
    private let cacheDir: URL?

    private init() {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            configDir = appSupport.appendingPathComponent("com.glance.glance")
        } else {
            configDir = nil
        }
        cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.glance.glance")
    }

    // MARK: - Window State

    private var windowStatePath: URL? {
        configDir?.appendingPathComponent("window.json")
    }

    func loadWindowState() -> WindowState {
        guard let path = windowStatePath,
              let data = try? Data(contentsOf: path),
              let state = try? JSONDecoder().decode(WindowState.self, from: data) else {
            return .default
        }
        return state
    }

    func saveWindowState(_ state: WindowState) {
        guard let path = windowStatePath else { return }

        if let dir = path.deletingLastPathComponent() as URL? {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: path)
        }
    }

    // MARK: - App Config (config.toml)

    private var configTomlPath: URL? {
        configDir?.appendingPathComponent("config.toml")
    }

    var appConfig: AppConfig {
        guard let path = configTomlPath,
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return AppConfig()
        }
        return parseToml(content)
    }

    /// Minimal TOML parser for the simple config format we use
    private func parseToml(_ content: String) -> AppConfig {
        var config = AppConfig()
        var inExtensions = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Section headers
            if trimmed == "[extensions]" {
                inExtensions = true
                continue
            } else if trimmed.hasPrefix("[") {
                inExtensions = false
                continue
            }

            // Key-value pairs
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if inExtensions {
                if key == "plantuml" {
                    config.extensions.plantuml = (value == "true")
                }
            } else {
                if key == "no_truncate" {
                    config.noTruncate = (value == "true")
                }
            }
        }

        return config
    }
}
