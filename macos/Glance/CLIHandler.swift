import Foundation

struct CLIArgs {
    let filePath: String?
    let noTruncate: Bool
}

struct CLIHandler {
    static func parse() -> CLIArgs {
        let args = CommandLine.arguments
        var noTruncate = false
        var filePath: String?

        for arg in args.dropFirst() {
            switch arg {
            case "--help", "-h":
                printHelp()
                exit(0)

            case "--version", "-v":
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                print("glance \(version)")
                exit(0)

            case "--no-truncate":
                noTruncate = true

            default:
                if !arg.hasPrefix("--") && !arg.hasPrefix("-") {
                    filePath = arg
                }
            }
        }

        // Resolve relative path
        if var path = filePath, !path.hasPrefix("/") {
            let cwd = FileManager.default.currentDirectoryPath
            path = (cwd as NSString).appendingPathComponent(path)
            filePath = path
        }

        return CLIArgs(filePath: filePath, noTruncate: noTruncate)
    }

    private static func printHelp() {
        print("glance - A minimal markdown viewer")
        print()
        print("USAGE:")
        print("    glance <file.md> [options]")
        print()
        print("OPTIONS:")
        print("    --help, -h       Show this help message")
        print("    --version, -v    Show version")
        print("    --no-truncate    Render entire file regardless of size")
    }
}
