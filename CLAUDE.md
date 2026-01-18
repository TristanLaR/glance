# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glance is a minimal, fast markdown viewer built with Tauri v1.8 (Rust backend + WebView frontend). It features daemon mode for instant file reloading, lazy-loaded syntax highlighting, and cross-platform support (macOS, Linux).

## Build Commands

```bash
# Development with hot reload
cargo tauri dev

# Production build (creates .app bundle on macOS)
cargo tauri build

# Rust-only build (faster, no bundling)
cd src-tauri && cargo build --release
```

## Architecture

### Backend (src-tauri/src/main.rs)
- **Daemon Mode**: Uses Unix sockets (`~/.cache/glance/glance.sock`) for IPC. First invocation starts the daemon; subsequent calls send file paths via socket.
- **AppState**: Thread-safe state using `Arc<Mutex<T>>` for content, file path, file name, large file mode, and watcher control.
- **File Watcher**: Uses `notify` crate with kqueue on macOS. Watches current file and emits `file-changed` events to frontend.
- **Window Persistence**: Saves/restores position and size to `~/.config/glance/window.json`.
- **Large File Mode**: Files >500KB are split into collapsible sections based on markdown headings.

### Frontend (ui/index.html)
- Single HTML file with embedded CSS and vanilla JavaScript (~1020 lines)
- **Markdown**: `marked.min.js` with GitHub Flavored Markdown
- **Syntax Highlighting**: `highlight.min.js` (lazy-loaded only when code blocks detected)
- **XSS Protection**: `purify.min.js` (DOMPurify) sanitizes all rendered HTML
- **Tauri IPC**: Uses `window.__TAURI__.tauri.invoke()` for backend calls

### Key Data Flow
1. CLI args → Rust validates file → checks for daemon via socket
2. If daemon running: send path via socket → daemon updates state → emits `file-loaded` event
3. If no daemon: start Tauri app → setup socket server + file watcher
4. Frontend calls `get_markdown_content` → renders with marked.js + DOMPurify → highlight.js

## Tauri Commands

```rust
#[tauri::command]
fn get_markdown_content(state: State<AppState>) -> MarkdownContent  // Returns file content + metadata
fn open_dropped_file(path: String, state: State<AppState>, window: Window) -> Result<String, String>
```

## Frontend Events

```javascript
// Listen for backend events
await listen('file-changed', () => reloadWithScrollPreserve());  // File watcher triggered
await listen('file-loaded', () => reloadWithScrollPreserve());   // Daemon received new file
```

## Security Considerations

- Socket server validates file extensions (.md/.markdown only) and canonicalizes paths
- All markdown HTML is sanitized with DOMPurify before rendering
- CSP restricts scripts/styles to 'self' only (no external CDN)
- Mutex locks use `unwrap_or_else(|e| e.into_inner())` to handle poisoned locks

## File Structure

```
src-tauri/
  src/main.rs       # All Rust backend logic (735 lines)
  Cargo.toml        # Dependencies: tauri, notify, directories, serde, toml
  tauri.conf.json   # Tauri config: CSP, allowlist, window settings
ui/
  index.html        # Complete frontend (HTML + CSS + JS)
  marked.min.js     # Markdown parser
  highlight.min.js  # Syntax highlighter (lazy-loaded)
  purify.min.js     # XSS sanitizer
  *.css             # GitHub markdown styles
scripts/
  glance-macos.sh   # macOS launcher (uses `open` command)
  glance-linux.sh   # Linux launcher (uses `setsid`)
```

## Common Patterns

### Adding a new Tauri command
1. Add function with `#[tauri::command]` in main.rs
2. Register in `.invoke_handler(tauri::generate_handler![...])`
3. Call from frontend: `await invoke('command_name', { args })`

### Modifying shared state
```rust
// Always use unwrap_or_else for poisoned lock handling
let mut content = state.content.lock().unwrap_or_else(|e| e.into_inner());
*content = new_value;
```

### Emitting events to frontend
```rust
if let Some(window) = app_handle.get_window("main") {
    if let Err(e) = window.emit("event-name", payload) {
        eprintln!("Failed to emit event: {}", e);
    }
}
```
