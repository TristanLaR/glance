# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glance is a minimal, fast markdown viewer with cross-platform support. It uses a native Swift app on macOS and Tauri (Rust backend + WebView) on Linux. Both platforms share the same frontend UI. Features include daemon mode for instant file reloading, lazy-loaded syntax highlighting, and file watching.

## Build Commands

```bash
# macOS (native Swift app)
cd macos && xcodegen generate && xcodebuild -scheme Glance -configuration Release build

# Linux (Tauri/Rust)
cd src-tauri && cargo build --release

# Linux development with hot reload
cargo tauri dev
```

## Architecture

### Shared Frontend (ui/)
- `index.html` - Complete frontend (HTML + CSS + vanilla JS)
- `bridge.js` - Platform abstraction layer (GlanceBridge) that abstracts Tauri IPC vs WKWebView messageHandlers
- `marked.min.js` - Markdown parser (GitHub Flavored Markdown)
- `highlight.min.js` - Syntax highlighter (lazy-loaded)
- `purify.min.js` - XSS sanitizer (DOMPurify)
- `pako.min.js` - Deflate compression (for PlantUML encoding)
- `mermaid.min.js` - Mermaid diagram renderer
- All JS dependencies are bundled locally (no CDN)

### Bridge Layer (ui/bridge.js)
Abstracts platform differences so index.html works on both Tauri and native macOS:
- `GlanceBridge.invoke(cmd, args)` - Backend command invocation
- `GlanceBridge.convertFileSrc(path)` - Local file URL conversion
- `GlanceBridge.openFileDialog()` - Native file picker
- `GlanceBridge.listen(event, cb)` - Backend event listener
- `GlanceBridge._resolve/_reject/_dispatch` - Internal callbacks from native side

### macOS Native (macos/)
- **AppDelegate.swift** - App lifecycle, daemon setup, CLI arg handling, file open events
- **MainWindow.swift** - NSWindow with state persistence, drag-and-drop via DragDropView
- **WebViewController.swift** - WKWebView + WKScriptMessageHandler bridge
- **FileHandler.swift** - File state, section extraction, markdown content API
- **FileWatcher.swift** - DispatchSource (kqueue) file watching
- **DaemonServer.swift** - Unix socket server for single-instance daemon mode
- **ConfigManager.swift** - config.toml + window.json persistence
- **CLIHandler.swift** - CLI argument parsing (--help, --version, --no-truncate)
- **LocalFileScheme.swift** - WKURLSchemeHandler for `glance-asset://` local images
- **Info.plist** - File associations (.md/.markdown UTI)
- **project.yml** - XcodeGen project spec (generates Glance.xcodeproj)

### Linux Backend (src-tauri/src/main.rs)
- **Daemon Mode**: Unix sockets for IPC
- **AppState**: Thread-safe state using `Arc<Mutex<T>>`
- **File Watcher**: `notify` crate with kqueue/inotify
- **Window Persistence**: window.json
- **Large File Mode**: Files >500KB split into collapsible sections

### Key Data Flow
1. CLI args → validate file → check for daemon via Unix socket
2. If daemon running: send path via socket → daemon updates state → emits `file-loaded` event
3. If no daemon: start app → setup socket server + file watcher
4. Frontend calls `GlanceBridge.invoke('get_markdown_content')` → renders with marked.js + DOMPurify → highlight.js

## Frontend Events

```javascript
// Listen for backend events (works on both platforms via bridge)
await GlanceBridge.listen('file-changed', () => reloadWithScrollPreserve());
await GlanceBridge.listen('file-loaded', () => reloadWithScrollPreserve());
```

## Security Considerations

- Socket server validates file extensions (.md/.markdown/.puml/.plantuml) and canonicalizes paths
- All markdown HTML is sanitized with DOMPurify before rendering
- CSP restricts scripts/styles to 'self' only (no external CDN)
- macOS: `glance-asset://` scheme only serves local files from disk
- Rust: Mutex locks use `unwrap_or_else(|e| e.into_inner())` for poisoned lock handling

## File Structure

```
ui/                          # SHARED web assets (both platforms)
  index.html                 # Complete frontend
  bridge.js                  # Platform abstraction layer
  marked.min.js, purify.min.js, highlight.min.js
  pako.min.js, mermaid.min.js
  *.css                      # GitHub markdown styles

macos/                       # Native Swift app (macOS)
  project.yml                # XcodeGen spec
  Glance.xcodeproj/          # Generated Xcode project
  Glance/
    AppDelegate.swift, MainWindow.swift, WebViewController.swift
    FileHandler.swift, FileWatcher.swift, DaemonServer.swift
    ConfigManager.swift, CLIHandler.swift, LocalFileScheme.swift
    Info.plist, Assets.xcassets/

src-tauri/                   # Tauri/Rust (Linux)
  src/main.rs
  Cargo.toml, tauri.conf.json

scripts/
  glance-macos.sh            # macOS launcher
  glance-linux.sh            # Linux launcher
```

## Common Patterns

### Adding a new bridge command
1. Add handler in `WebViewController.swift` `userContentController` switch
2. Add handler in `src-tauri/src/main.rs` with `#[tauri::command]`
3. Call from frontend: `await GlanceBridge.invoke('command_name', { args })`

### macOS: Emitting events to frontend
```swift
webView.evaluateJavaScript("GlanceBridge._dispatch('event-name')")
```

### Linux: Adding a Tauri command
1. Add function with `#[tauri::command]` in main.rs
2. Register in `.invoke_handler(tauri::generate_handler![...])`
3. Call from frontend: `await GlanceBridge.invoke('command_name', { args })`
