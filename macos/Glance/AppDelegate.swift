import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow?
    var daemonServer: DaemonServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CLIHandler.parse()

        // Handle --help and --version (already exits in CLIHandler)
        let config = ConfigManager.shared.appConfig
        let noTruncate = args.noTruncate || config.noTruncate

        var initialFile: FileState?
        if let filePath = args.filePath {
            // Try to send to running daemon first
            if DaemonServer.sendToDaemon(filePath: filePath) {
                NSApp.terminate(nil)
                return
            }

            initialFile = FileHandler.shared.loadFile(path: filePath, noTruncate: noTruncate)
        }

        FileHandler.shared.noTruncate = noTruncate

        // Create and show main window
        let savedState = ConfigManager.shared.loadWindowState()
        mainWindow = MainWindow(savedState: savedState)
        mainWindow?.makeKeyAndOrderFront(nil)

        if let file = initialFile {
            mainWindow?.webViewController.updateContent(file)
        }

        // Start daemon socket server
        daemonServer = DaemonServer { [weak self] path in
            DispatchQueue.main.async {
                let noTruncate = FileHandler.shared.noTruncate
                if let file = FileHandler.shared.loadFile(path: path, noTruncate: noTruncate) {
                    self?.mainWindow?.webViewController.updateContent(file)
                    self?.mainWindow?.showAndActivate()
                }
            }
        }
        daemonServer?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindow?.showAndActivate()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemonServer?.stop()
        if let window = mainWindow {
            ConfigManager.shared.saveWindowState(window.windowState)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let noTruncate = FileHandler.shared.noTruncate
        if let file = FileHandler.shared.loadFile(path: filename, noTruncate: noTruncate) {
            mainWindow?.webViewController.updateContent(file)
            mainWindow?.showAndActivate()
            return true
        }
        return false
    }
}
