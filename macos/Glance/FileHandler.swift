import Foundation

/// Represents the current state of a loaded file
struct FileState {
    let content: String
    let filePath: String
    let fileName: String
    let fileDir: String
    let isLargeFile: Bool
    let sections: [MarkdownSection]
    let isPlantumlFile: Bool
}

/// Section extracted from markdown for TOC/accordion display
struct MarkdownSection: Codable {
    let level: Int
    let title: String
    let content: String
    let start_line: Int
}

/// JSON structure returned to the frontend via bridge
struct MarkdownContent: Codable {
    let content: String
    let file_path: String
    let file_name: String
    let file_dir: String
    let is_large_file: Bool
    let sections: [MarkdownSection]
    let extensions: ExtensionsConfig
    let is_plantuml_file: Bool
}

struct ExtensionsConfig: Codable {
    var plantuml: Bool = false
}

class FileHandler {
    static let shared = FileHandler()

    /// Threshold for large file mode (500KB)
    private let largeFileThreshold: UInt64 = 500 * 1024

    /// Whether to disable large file truncation
    var noTruncate = false

    private init() {}

    /// Load a file from disk and return its state
    func loadFile(path: String, noTruncate: Bool) -> FileState? {
        let fm = FileManager.default

        // Resolve to absolute path
        let absolutePath: String
        if path.hasPrefix("/") {
            absolutePath = path
        } else {
            absolutePath = fm.currentDirectoryPath + "/" + path
        }

        let resolvedURL = URL(fileURLWithPath: absolutePath).standardized

        guard fm.fileExists(atPath: resolvedURL.path) else {
            print("File not found: \(resolvedURL.path)")
            return nil
        }

        // Validate extension
        let ext = resolvedURL.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" || ext == "puml" || ext == "plantuml" else {
            print("Invalid file type: \(ext)")
            return nil
        }

        guard let content = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            print("Failed to read file: \(resolvedURL.path)")
            return nil
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("File is empty: \(resolvedURL.path)")
            return nil
        }

        // Check file size for large file mode
        let fileSize = (try? fm.attributesOfItem(atPath: resolvedURL.path)[.size] as? UInt64) ?? 0
        let isLargeFile = fileSize > largeFileThreshold && !noTruncate

        let fileName = resolvedURL.lastPathComponent
        let fileDir = resolvedURL.deletingLastPathComponent().path
        let isPlantuml = ext == "puml" || ext == "plantuml"

        let sections: [MarkdownSection]
        if isLargeFile {
            sections = extractSections(from: content)
        } else {
            sections = []
        }

        return FileState(
            content: content,
            filePath: resolvedURL.path,
            fileName: fileName,
            fileDir: fileDir,
            isLargeFile: isLargeFile,
            sections: sections,
            isPlantumlFile: isPlantuml
        )
    }

    /// Build the MarkdownContent response for the frontend
    func getMarkdownContent(currentFile: FileState?) -> MarkdownContent {
        let config = ConfigManager.shared.appConfig

        guard let file = currentFile else {
            return MarkdownContent(
                content: "",
                file_path: "",
                file_name: "Glance",
                file_dir: "",
                is_large_file: false,
                sections: [],
                extensions: ExtensionsConfig(plantuml: config.extensions.plantuml),
                is_plantuml_file: false
            )
        }

        return MarkdownContent(
            content: file.content,
            file_path: file.filePath,
            file_name: file.fileName,
            file_dir: file.fileDir,
            is_large_file: file.isLargeFile,
            sections: file.sections,
            extensions: ExtensionsConfig(plantuml: config.extensions.plantuml),
            is_plantuml_file: file.isPlantumlFile
        )
    }

    // MARK: - Section Extraction

    /// Extract sections from markdown content based on headings
    private func extractSections(from content: String) -> [MarkdownSection] {
        let lines = content.components(separatedBy: "\n")
        var sections: [MarkdownSection] = []
        var inCodeBlock = false

        for (lineNum, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeBlock = !inCodeBlock
                continue
            }

            if inCodeBlock { continue }

            if let (level, title) = parseHeading(trimmed) {
                sections.append(MarkdownSection(
                    level: level,
                    title: title,
                    content: "",
                    start_line: lineNum
                ))
            }
        }

        // Fill in content for each section
        var result: [MarkdownSection] = []
        for i in 0..<sections.count {
            let startLine = sections[i].start_line
            let endLine = (i + 1 < sections.count) ? sections[i + 1].start_line : lines.count
            let sectionContent = lines[startLine..<endLine].joined(separator: "\n")
            result.append(MarkdownSection(
                level: sections[i].level,
                title: sections[i].title,
                content: sectionContent,
                start_line: sections[i].start_line
            ))
        }

        // Add intro section if content before first heading
        if !result.isEmpty && result[0].start_line > 0 {
            let introContent = lines[0..<result[0].start_line].joined(separator: "\n")
            if !introContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.insert(MarkdownSection(
                    level: 0,
                    title: "Introduction",
                    content: introContent,
                    start_line: 0
                ), at: 0)
            }
        }

        // If no sections found, return single section
        if result.isEmpty {
            result.append(MarkdownSection(
                level: 0,
                title: "Document",
                content: content,
                start_line: 0
            ))
        }

        return result
    }

    /// Parse a heading line and return (level, title)
    private func parseHeading(_ line: String) -> (Int, String)? {
        var hashCount = 0
        for char in line {
            if char == "#" {
                hashCount += 1
            } else {
                break
            }
        }

        guard (1...6).contains(hashCount) else { return nil }

        let rest = String(line.dropFirst(hashCount))
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }

        let title = rest.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return (hashCount, title)
    }
}
