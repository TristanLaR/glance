import Cocoa
import WebKit

class WebViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var currentFile: FileState?
    private var fileWatcher: FileWatcher?

    override func loadView() {
        let config = WKWebViewConfiguration()

        // Register custom URL scheme for local images
        let schemeHandler = LocalFileScheme()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "glance-asset")

        // Set up user content controller for bridge
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "glance")
        config.userContentController = userContentController

        // Preferences
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self

        // Wrap in DragDropView to handle file drops
        let container = DragDropView(frame: .zero)
        container.autoresizingMask = [.width, .height]
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        self.view = container

        loadUI()
    }

    private func loadUI() {
        // Load index.html from the shared ui/ directory
        let uiDir = Bundle.main.resourceURL?.appendingPathComponent("ui")
            ?? URL(fileURLWithPath: findUIDirectory())

        let indexURL = uiDir.appendingPathComponent("index.html")

        if FileManager.default.fileExists(atPath: indexURL.path) {
            webView.loadFileURL(indexURL, allowingReadAccessTo: uiDir)
        } else {
            let html = "<html><body><p style='text-align:center;padding:50px;color:#666;'>Failed to load UI. index.html not found.</p></body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// Find the ui/ directory relative to the app
    private func findUIDirectory() -> String {
        // During development, look relative to the source
        let fm = FileManager.default
        let candidates = [
            // Inside app bundle Resources/ui/
            Bundle.main.resourcePath.map { "\($0)/ui" },
            // Development: relative to executable
            Bundle.main.executablePath.flatMap { path in
                let url = URL(fileURLWithPath: path)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("ui")
                return url.path
            }
        ].compactMap { $0 }

        for candidate in candidates {
            if fm.fileExists(atPath: "\(candidate)/index.html") {
                return candidate
            }
        }

        return "ui"
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let dragView = self.view as? DragDropView {
            dragView.mainWindow = self.view.window as? MainWindow
        }
    }

    func updateContent(_ file: FileState) {
        let previousFile = currentFile
        currentFile = file

        // Update window title
        if let window = view.window as? MainWindow {
            window.updateTitle(fileName: file.fileName)
        }

        // Start watching the new file
        setupFileWatcher(for: file.filePath)

        // Notify frontend to reload
        dispatchEvent("file-loaded")

        // If this is the first file or a different file, we also need to tell the frontend
        if previousFile == nil || previousFile?.filePath != file.filePath {
            dispatchEvent("file-loaded")
        }
    }

    private func setupFileWatcher(for path: String) {
        fileWatcher?.stop()
        guard !path.isEmpty else { return }

        fileWatcher = FileWatcher(path: path) { [weak self] in
            DispatchQueue.main.async {
                // Re-read file content
                guard let self = self, let current = self.currentFile else { return }
                let noTruncate = FileHandler.shared.noTruncate
                if let updated = FileHandler.shared.loadFile(path: current.filePath, noTruncate: noTruncate) {
                    self.currentFile = updated
                    self.dispatchEvent("file-changed")
                }
            }
        }
        fileWatcher?.start()
    }

    // MARK: - Bridge: JS -> Swift

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let command = body["command"] as? String else {
            return
        }

        let args = body["args"] as? [String: Any] ?? [:]

        switch command {
        case "get_markdown_content":
            handleGetMarkdownContent(id: id)

        case "open_dropped_file":
            if let path = args["path"] as? String {
                handleOpenDroppedFile(id: id, path: path)
            } else {
                rejectBridge(id: id, error: "Missing 'path' argument")
            }

        case "open_file_dialog":
            handleOpenFileDialog(id: id)

        default:
            rejectBridge(id: id, error: "Unknown command: \(command)")
        }
    }

    private func handleGetMarkdownContent(id: Int) {
        let data = FileHandler.shared.getMarkdownContent(currentFile: currentFile)
        if let jsonData = try? JSONEncoder().encode(data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            resolveBridge(id: id, data: jsonString)
        } else {
            rejectBridge(id: id, error: "Failed to encode content")
        }
    }

    private func handleOpenDroppedFile(id: Int, path: String) {
        let noTruncate = FileHandler.shared.noTruncate
        if let file = FileHandler.shared.loadFile(path: path, noTruncate: noTruncate) {
            currentFile = file
            if let window = view.window as? MainWindow {
                window.updateTitle(fileName: file.fileName)
            }
            setupFileWatcher(for: file.filePath)
            resolveBridge(id: id, data: "\"\(file.fileName)\"")
        } else {
            rejectBridge(id: id, error: "Failed to open file: \(path)")
        }
    }

    private func handleOpenFileDialog(id: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: view.window!) { [weak self] response in
            if response == .OK, let url = panel.url {
                let path = url.path
                let noTruncate = FileHandler.shared.noTruncate
                if let file = FileHandler.shared.loadFile(path: path, noTruncate: noTruncate) {
                    self?.currentFile = file
                    if let window = self?.view.window as? MainWindow {
                        window.updateTitle(fileName: file.fileName)
                    }
                    self?.setupFileWatcher(for: file.filePath)
                    self?.resolveBridge(id: id, data: "\"\(path)\"")
                } else {
                    self?.rejectBridge(id: id, error: "Failed to open file")
                }
            } else {
                self?.resolveBridge(id: id, data: "null")
            }
        }
    }

    // MARK: - Bridge: Swift -> JS

    func dispatchEvent(_ event: String, payload: String? = nil) {
        let payloadArg = payload ?? "null"
        let js = "GlanceBridge._dispatch('\(event)', \(payloadArg))"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("Failed to dispatch event '\(event)': \(error)")
            }
        }
    }

    private func resolveBridge(id: Int, data: String) {
        let js = "GlanceBridge._resolve(\(id), \(data))"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("Bridge resolve error: \(error)")
            }
        }
    }

    private func rejectBridge(id: Int, error: String) {
        let escaped = error.replacingOccurrences(of: "'", with: "\\'")
        let js = "GlanceBridge._reject(\(id), '\(escaped)')"
        webView.evaluateJavaScript(js) { _, err in
            if let err = err {
                print("Bridge reject error: \(err)")
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow file:// and glance-asset:// URLs to load normally
        if let url = navigationAction.request.url {
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "file" || scheme == "glance-asset" || scheme == "about" {
                decisionHandler(.allow)
                return
            }
            // External URLs: open in default browser
            if scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
}
