import Cocoa

class MainWindow: NSWindow {
    let webViewController = WebViewController()

    init(savedState: WindowState) {
        let frame = NSRect(
            x: CGFloat(savedState.x),
            y: CGFloat(savedState.y),
            width: CGFloat(savedState.width),
            height: CGFloat(savedState.height)
        )

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Glance"
        self.minSize = NSSize(width: 400, height: 300)
        self.contentViewController = webViewController
        self.delegate = self
        self.isReleasedWhenClosed = false
        self.titlebarAppearsTransparent = false
        self.titleVisibility = .visible
    }

    var windowState: WindowState {
        let frame = self.frame
        return WindowState(
            x: Int(frame.origin.x),
            y: Int(frame.origin.y),
            width: Int(frame.size.width),
            height: Int(frame.size.height)
        )
    }

    func showAndActivate() {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }

    func updateTitle(fileName: String) {
        if fileName.isEmpty || fileName == "Glance" {
            self.title = "Glance"
        } else {
            self.title = "\(fileName) - Glance"
        }
    }
}

extension MainWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Save window state then hide (daemon mode)
        ConfigManager.shared.saveWindowState(self.windowState)
        self.orderOut(nil)
        return false
    }

    func windowDidResize(_ notification: Notification) {
        // Save on resize
        ConfigManager.shared.saveWindowState(self.windowState)
    }

    func windowDidMove(_ notification: Notification) {
        // Save on move
        ConfigManager.shared.saveWindowState(self.windowState)
    }
}

// MARK: - Drag-and-drop via content view

class DragDropView: NSView {
    weak var mainWindow: MainWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              urls.first != nil else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" || ext == "puml" || ext == "plantuml" else {
            return false
        }

        let noTruncate = FileHandler.shared.noTruncate
        if let file = FileHandler.shared.loadFile(path: url.path, noTruncate: noTruncate) {
            mainWindow?.webViewController.updateContent(file)
            return true
        }
        return false
    }
}
