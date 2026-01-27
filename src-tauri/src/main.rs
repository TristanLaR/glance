// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use directories::ProjectDirs;
use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process;
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tauri::{Manager, Emitter};

/// Threshold for large file mode (500KB)
const LARGE_FILE_THRESHOLD: u64 = 500 * 1024;

/// Get the path to the IPC socket for daemon mode
fn get_socket_path() -> Option<PathBuf> {
    ProjectDirs::from("com", "glance", "glance").and_then(|dirs| {
        // Try runtime_dir first, fall back to cache_dir
        dirs.runtime_dir()
            .map(|dir| dir.join("glance.sock"))
            .or_else(|| Some(dirs.cache_dir().join("glance.sock")))
    })
}

/// Window state for persistence
#[derive(Clone, serde::Serialize, serde::Deserialize)]
struct WindowState {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

impl Default for WindowState {
    fn default() -> Self {
        Self {
            x: 100,
            y: 100,
            width: 900,
            height: 700,
        }
    }
}

impl WindowState {
    fn config_path() -> Option<PathBuf> {
        ProjectDirs::from("com", "glance", "glance")
            .map(|dirs| dirs.config_dir().join("window.json"))
    }

    fn load() -> Self {
        Self::config_path()
            .and_then(|path| fs::read_to_string(&path).ok())
            .and_then(|content| serde_json::from_str(&content).ok())
            .unwrap_or_default()
    }

    fn save(&self) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(path) = Self::config_path() {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            let content = serde_json::to_string_pretty(self)?;
            fs::write(&path, content)?;
        }
        Ok(())
    }
}

/// Extension configuration
#[derive(Clone, Default, serde::Serialize, serde::Deserialize)]
struct ExtensionsConfig {
    #[serde(default)]
    plantuml: bool,
}

/// Application configuration from config.toml
#[derive(Clone, Default, serde::Serialize, serde::Deserialize)]
struct AppConfig {
    #[serde(default)]
    no_truncate: bool,
    #[serde(default)]
    extensions: ExtensionsConfig,
}

impl AppConfig {
    fn config_path() -> Option<PathBuf> {
        ProjectDirs::from("com", "glance", "glance")
            .map(|dirs| dirs.config_dir().join("config.toml"))
    }

    fn load() -> Self {
        Self::config_path()
            .and_then(|path| fs::read_to_string(&path).ok())
            .and_then(|content| toml::from_str(&content).ok())
            .unwrap_or_default()
    }
}

/// Section extracted from markdown for TOC/accordion display
#[derive(Clone, serde::Serialize)]
struct MarkdownSection {
    /// Heading level (1-6)
    level: u8,
    /// Heading title text
    title: String,
    /// Content of this section (including the heading)
    content: String,
    /// Line number where this section starts (0-indexed)
    start_line: usize,
}

fn main() {
    let args: Vec<String> = env::args().collect();

    // Handle --help and --version flags
    if args.len() > 1 {
        match args[1].as_str() {
            "--help" | "-h" => {
                print_help();
                process::exit(0);
            }
            "--version" | "-v" => {
                println!("glance {}", env!("CARGO_PKG_VERSION"));
                process::exit(0);
            }
            _ => {}
        }
    }

    // Parse --no-truncate flag
    let no_truncate_flag = args.iter().any(|arg| arg == "--no-truncate");

    // Find file argument (first non-flag argument after program name)
    let file_arg = args.iter().skip(1).find(|arg| !arg.starts_with("--"));

    // Load config file
    let config = AppConfig::load();
    let no_truncate = no_truncate_flag || config.no_truncate;

    // If a file is provided via CLI, load it; otherwise start with empty state
    // (file can be opened later via drag-drop, Cmd+O, or OS file association)
    let (file_path, file_name, content, is_large_file) = match file_arg {
        Some(path) => {
            let file_path = PathBuf::from(path);

            // Convert relative path to absolute using current working directory
            let file_path = if file_path.is_relative() {
                env::current_dir()
                    .map(|cwd| cwd.join(&file_path))
                    .unwrap_or(file_path)
            } else {
                file_path
            };

            // Check if file exists
            if !file_path.exists() {
                eprintln!("Error: File not found: {}", file_path.display());
                process::exit(1);
            }

            // Try to send to running daemon first
            let absolute_path = fs::canonicalize(&file_path).unwrap_or_else(|_| file_path.clone());
            if send_to_daemon(absolute_path.to_string_lossy().as_ref()) {
                // Daemon is running and received the file - show window via macOS open command
                let _ = std::process::Command::new("open")
                    .arg("-a")
                    .arg("glance")
                    .spawn();
                process::exit(0);
            }

            // Get file size
            let file_size = file_path.metadata().map(|m| m.len()).unwrap_or(0);

            // Read file content
            let content = match fs::read_to_string(&file_path) {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("Error: Failed to read file: {}", e);
                    process::exit(1);
                }
            };

            // Check if file is empty
            if content.trim().is_empty() {
                eprintln!("Error: File is empty: {}", file_path.display());
                process::exit(1);
            }

            // Determine if we should use large file mode
            let is_large_file = file_size > LARGE_FILE_THRESHOLD && !no_truncate;

            // Get absolute path and filename for window title
            let absolute_path = fs::canonicalize(&file_path).unwrap_or_else(|_| file_path.clone());
            let file_name = file_path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "Glance".to_string());

            (
                absolute_path.to_string_lossy().to_string(),
                file_name,
                content,
                is_large_file,
            )
        }
        None => {
            // No file provided - start with empty state
            // File will be opened via OS file association, drag-drop, or Cmd+O
            (String::new(), String::from("Glance"), String::new(), false)
        }
    };

    // Run the Tauri application
    run_app(file_path, file_name, content, is_large_file, no_truncate);
}

fn print_help() {
    println!("glance - A minimal markdown viewer");
    println!();
    println!("USAGE:");
    println!("    glance <file.md> [options]");
    println!();
    println!("OPTIONS:");
    println!("    --help, -h       Show this help message");
    println!("    --version, -v    Show version");
    println!("    --no-truncate    Render entire file regardless of size");
}

/// Try to send a file path to the running daemon
/// Returns true if successful (daemon is running), false otherwise
fn send_to_daemon(file_path: &str) -> bool {
    if let Some(socket_path) = get_socket_path() {
        if let Ok(mut stream) = UnixStream::connect(&socket_path) {
            if let Ok(_) = stream.write_all(file_path.as_bytes()) {
                return true;
            }
        }
    }
    false
}

/// Start a Unix socket server that listens for file paths from other glance instances
fn start_socket_server(state: Arc<AppState>, app_handle: tauri::AppHandle) {
    if let Some(socket_path) = get_socket_path() {
        // Remove old socket file if it exists
        let _ = fs::remove_file(&socket_path);

        // Create parent directories if needed
        if let Some(parent) = socket_path.parent() {
            let _ = fs::create_dir_all(parent);
        }

        thread::spawn(move || {
            if let Ok(listener) = UnixListener::bind(&socket_path) {
                for stream in listener.incoming() {
                    if let Ok(mut stream) = stream {
                        let state = state.clone();
                        let app_handle = app_handle.clone();

                        // Read file path from socket
                        let mut buffer = [0u8; 4096];
                        if let Ok(n) = stream.read(&mut buffer) {
                            let file_path_str = String::from_utf8_lossy(&buffer[..n]).to_string();
                            let file_path = PathBuf::from(&file_path_str);

                            // Security: Validate file exists
                            if !file_path.exists() {
                                eprintln!("Socket: File not found: {}", file_path.display());
                                continue;
                            }

                            // Security: Validate it's a markdown file (prevent arbitrary file access)
                            let extension = file_path
                                .extension()
                                .map(|e| e.to_string_lossy().to_lowercase());
                            if extension.as_deref() != Some("md")
                                && extension.as_deref() != Some("markdown")
                                && extension.as_deref() != Some("puml")
                                && extension.as_deref() != Some("plantuml")
                            {
                                eprintln!(
                                    "Socket: Invalid file type (only .md/.markdown/.puml/.plantuml allowed): {}",
                                    file_path.display()
                                );
                                continue;
                            }

                            // Security: Canonicalize path to prevent path traversal
                            let file_path = match fs::canonicalize(&file_path) {
                                Ok(p) => p,
                                Err(e) => {
                                    eprintln!("Socket: Failed to canonicalize path: {}", e);
                                    continue;
                                }
                            };

                            // Read file content
                            if let Ok(new_content) = fs::read_to_string(&file_path) {
                                if new_content.trim().is_empty() {
                                    continue;
                                }

                                // Get file metadata
                                let file_size = file_path.metadata().map(|m| m.len()).unwrap_or(0);
                                let no_truncate =
                                    *state.no_truncate.lock().unwrap_or_else(|e| e.into_inner());
                                let is_large_file =
                                    file_size > LARGE_FILE_THRESHOLD && !no_truncate;

                                let new_file_name = file_path
                                    .file_name()
                                    .map(|n| n.to_string_lossy().to_string())
                                    .unwrap_or_else(|| "Glance".to_string());

                                // Update state (handle poisoned locks gracefully)
                                {
                                    let mut content =
                                        state.content.lock().unwrap_or_else(|e| e.into_inner());
                                    *content = new_content;
                                }
                                {
                                    let mut fp =
                                        state.file_path.lock().unwrap_or_else(|e| e.into_inner());
                                    *fp = file_path.to_string_lossy().to_string();
                                }
                                {
                                    let mut fn_state =
                                        state.file_name.lock().unwrap_or_else(|e| e.into_inner());
                                    *fn_state = new_file_name.clone();
                                }
                                {
                                    let mut lf = state
                                        .is_large_file
                                        .lock()
                                        .unwrap_or_else(|e| e.into_inner());
                                    *lf = is_large_file;
                                }

                                // Emit event to frontend and show window
                                if let Some(window) = app_handle.get_webview_window("main") {
                                    let window_title = format!("{} - Glance", new_file_name);
                                    if let Err(e) = window.set_title(&window_title) {
                                        eprintln!("Failed to set window title: {}", e);
                                    }
                                    // Make sure window is visible
                                    if let Err(e) = window.show() {
                                        eprintln!("Failed to show window: {}", e);
                                    }
                                    if let Err(e) = window.set_focus() {
                                        eprintln!("Failed to focus window: {}", e);
                                    }
                                    if let Err(e) = window.emit("file-loaded", ()) {
                                        eprintln!("Failed to emit file-loaded event: {}", e);
                                    }
                                }

                                // Tell watcher about new file
                                if let Some(ref sender) = *state
                                    .watcher_control
                                    .lock()
                                    .unwrap_or_else(|e| e.into_inner())
                                {
                                    let _ = sender.send(file_path);
                                }
                            }
                        }
                    }
                }
            }
        });
    }
}

#[tauri::command]
fn get_markdown_content(state: tauri::State<AppState>) -> MarkdownContent {
    // Use unwrap_or_else to handle poisoned locks gracefully
    let content = state.content.lock().unwrap_or_else(|e| e.into_inner());
    let file_path = state.file_path.lock().unwrap_or_else(|e| e.into_inner());
    let file_name = state.file_name.lock().unwrap_or_else(|e| e.into_inner());
    let is_large_file = *state
        .is_large_file
        .lock()
        .unwrap_or_else(|e| e.into_inner());

    // Get directory of the markdown file for resolving relative image paths
    let file_dir = PathBuf::from(file_path.as_str())
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();

    // Extract sections if in large file mode
    let sections = if is_large_file {
        extract_sections(&content)
    } else {
        Vec::new()
    };

    // Load extensions config
    let config = AppConfig::load();

    // Check if this is a PlantUML file
    let is_plantuml_file = PathBuf::from(file_path.as_str())
        .extension()
        .map(|e| {
            let ext = e.to_string_lossy().to_lowercase();
            ext == "puml" || ext == "plantuml"
        })
        .unwrap_or(false);

    MarkdownContent {
        content: content.clone(),
        file_path: file_path.clone(),
        file_name: file_name.clone(),
        file_dir,
        is_large_file,
        sections,
        extensions: config.extensions,
        is_plantuml_file,
    }
}

#[tauri::command]
fn open_dropped_file(
    path: String,
    state: tauri::State<AppState>,
    window: tauri::WebviewWindow,
) -> Result<String, String> {
    let file_path = PathBuf::from(&path);

    // Check if file exists
    if !file_path.exists() {
        return Err(format!("File not found: {}", file_path.display()));
    }

    // Check if it's a markdown file
    let extension = file_path
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase());
    if extension.as_deref() != Some("md")
        && extension.as_deref() != Some("markdown")
        && extension.as_deref() != Some("puml")
        && extension.as_deref() != Some("plantuml")
    {
        return Err("Only markdown and PlantUML files are supported".to_string());
    }

    // Get file size
    let file_size = file_path.metadata().map(|m| m.len()).unwrap_or(0);

    // Read file content
    let new_content =
        fs::read_to_string(&file_path).map_err(|e| format!("Failed to read file: {}", e))?;

    if new_content.trim().is_empty() {
        return Err(format!("File is empty: {}", file_path.display()));
    }

    // Get absolute path and filename
    let absolute_path = fs::canonicalize(&file_path).unwrap_or_else(|_| file_path.clone());
    let new_file_name = file_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Glance".to_string());

    // Check if no_truncate is set
    let no_truncate = *state.no_truncate.lock().unwrap_or_else(|e| e.into_inner());
    let is_large_file = file_size > LARGE_FILE_THRESHOLD && !no_truncate;

    // Update state (handle poisoned locks gracefully)
    {
        let mut content = state.content.lock().unwrap_or_else(|e| e.into_inner());
        *content = new_content;
    }
    {
        let mut file_path_state = state.file_path.lock().unwrap_or_else(|e| e.into_inner());
        *file_path_state = absolute_path.to_string_lossy().to_string();
    }
    {
        let mut file_name_state = state.file_name.lock().unwrap_or_else(|e| e.into_inner());
        *file_name_state = new_file_name.clone();
    }
    {
        let mut large_file_state = state
            .is_large_file
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        *large_file_state = is_large_file;
    }

    // Update window title
    let window_title = format!("{} - Glance", new_file_name);
    let _ = window.set_title(&window_title);

    // Tell watcher thread to watch new file
    if let Some(ref sender) = *state
        .watcher_control
        .lock()
        .unwrap_or_else(|e| e.into_inner())
    {
        let _ = sender.send(absolute_path);
    }

    Ok(new_file_name)
}

#[derive(Clone, serde::Serialize)]
struct MarkdownContent {
    content: String,
    file_path: String,
    file_name: String,
    file_dir: String,
    /// Whether this file should be displayed in large file mode (with sections)
    is_large_file: bool,
    /// Sections extracted from markdown for accordion display (only when is_large_file is true)
    sections: Vec<MarkdownSection>,
    /// Extension configuration
    extensions: ExtensionsConfig,
    /// Whether this is a PlantUML file (.puml, .plantuml)
    is_plantuml_file: bool,
}

struct AppState {
    content: Arc<Mutex<String>>,
    file_path: Arc<Mutex<String>>,
    file_name: Arc<Mutex<String>>,
    watcher_control: Arc<Mutex<Option<Sender<PathBuf>>>>,
    is_large_file: Arc<Mutex<bool>>,
    no_truncate: Arc<Mutex<bool>>,
}

/// Extract sections from markdown content based on headings
fn extract_sections(content: &str) -> Vec<MarkdownSection> {
    let lines: Vec<&str> = content.lines().collect();
    let mut sections: Vec<MarkdownSection> = Vec::new();
    let mut in_code_block = false;

    for (line_num, line) in lines.iter().enumerate() {
        // Track code block state to ignore headings inside code blocks
        if line.starts_with("```") || line.starts_with("~~~") {
            in_code_block = !in_code_block;
            continue;
        }

        if in_code_block {
            continue;
        }

        // Check for ATX-style headings (# Heading)
        if let Some(heading_match) = parse_heading(line) {
            sections.push(MarkdownSection {
                level: heading_match.0,
                title: heading_match.1,
                content: String::new(), // Will be filled in later
                start_line: line_num,
            });
        }
    }

    // Now fill in the content for each section
    for i in 0..sections.len() {
        let start_line = sections[i].start_line;
        let end_line = if i + 1 < sections.len() {
            sections[i + 1].start_line
        } else {
            lines.len()
        };

        sections[i].content = lines[start_line..end_line].join("\n");
    }

    // If there's content before the first heading, add it as an intro section
    if !sections.is_empty() && sections[0].start_line > 0 {
        let intro_content = lines[0..sections[0].start_line].join("\n");
        if !intro_content.trim().is_empty() {
            sections.insert(
                0,
                MarkdownSection {
                    level: 0,
                    title: "Introduction".to_string(),
                    content: intro_content,
                    start_line: 0,
                },
            );
        }
    }

    // If no sections found, return a single section with all content
    if sections.is_empty() {
        sections.push(MarkdownSection {
            level: 0,
            title: "Document".to_string(),
            content: content.to_string(),
            start_line: 0,
        });
    }

    sections
}

/// Parse a heading line and return (level, title)
fn parse_heading(line: &str) -> Option<(u8, String)> {
    let trimmed = line.trim();

    // Count leading # characters
    let hash_count = trimmed.chars().take_while(|c| *c == '#').count();

    // Valid headings have 1-6 # characters followed by a space
    if (1..=6).contains(&hash_count) {
        let rest = &trimmed[hash_count..];
        if rest.starts_with(' ') || rest.is_empty() {
            let title = rest.trim().trim_end_matches('#').trim().to_string();
            return Some((hash_count as u8, title));
        }
    }

    None
}

fn run_app(
    file_path: String,
    file_name: String,
    content: String,
    is_large_file: bool,
    no_truncate: bool,
) {
    let window_title = if file_name == "Glance" {
        "Glance".to_string()
    } else {
        format!("{} - Glance", file_name)
    };
    let has_initial_file = !file_path.is_empty();
    let content = Arc::new(Mutex::new(content));
    let file_path_state = Arc::new(Mutex::new(file_path.clone()));
    let file_name_state = Arc::new(Mutex::new(file_name));
    let watcher_control: Arc<Mutex<Option<Sender<PathBuf>>>> = Arc::new(Mutex::new(None));
    let is_large_file_state = Arc::new(Mutex::new(is_large_file));
    let no_truncate_state = Arc::new(Mutex::new(no_truncate));
    let watch_path = PathBuf::from(&file_path);

    let watcher_control_for_setup = watcher_control.clone();

    // Load saved window state
    let saved_state = WindowState::load();

    // Create clones for socket server thread
    let content_for_socket = content.clone();
    let file_path_for_socket = file_path_state.clone();
    let file_name_for_socket = file_name_state.clone();
    let is_large_file_for_socket = is_large_file_state.clone();
    let no_truncate_for_socket = no_truncate_state.clone();
    let watcher_control_for_socket = watcher_control.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(AppState {
            content: content.clone(),
            file_path: file_path_state.clone(),
            file_name: file_name_state.clone(),
            watcher_control: watcher_control.clone(),
            is_large_file: is_large_file_state.clone(),
            no_truncate: no_truncate_state.clone(),
        })
        .invoke_handler(tauri::generate_handler![
            get_markdown_content,
            open_dropped_file
        ])
        .setup(move |app| {
            // Start the socket server for daemon mode
            let app_handle = app.handle().clone();
            let socket_app_state = AppState {
                content: content_for_socket.clone(),
                file_path: file_path_for_socket.clone(),
                file_name: file_name_for_socket.clone(),
                watcher_control: watcher_control_for_socket.clone(),
                is_large_file: is_large_file_for_socket.clone(),
                no_truncate: no_truncate_for_socket.clone(),
            };
            start_socket_server(Arc::new(socket_app_state), app_handle);
            // Update window title and restore saved position/size
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_title(&window_title);

                // Restore saved window position and size
                let _ =
                    window.set_position(tauri::PhysicalPosition::new(saved_state.x, saved_state.y));
                let _ = window.set_size(tauri::PhysicalSize::new(
                    saved_state.width,
                    saved_state.height,
                ));
            }

            // Set up file watcher with path switching support
            let app_handle = app.handle().clone();
            let content_for_watcher = content.clone();
            let file_path_for_watcher = file_path_state.clone();

            // Channel for switching watched files
            let (path_tx, path_rx) = channel::<PathBuf>();

            // Store sender in state for later use
            {
                let mut control = watcher_control_for_setup
                    .lock()
                    .unwrap_or_else(|e| e.into_inner());
                *control = Some(path_tx);
            }

            thread::spawn(move || {
                let (event_tx, event_rx) = channel();
                let event_tx_clone = event_tx.clone();

                let mut watcher = match RecommendedWatcher::new(
                    move |res: Result<Event, notify::Error>| {
                        if let Ok(event) = res {
                            let _ = event_tx_clone.send(event);
                        }
                    },
                    Config::default().with_poll_interval(Duration::from_millis(500)),
                ) {
                    Ok(w) => w,
                    Err(e) => {
                        eprintln!("Failed to create file watcher: {}", e);
                        return;
                    }
                };

                // Only start watching if we have an initial file
                let mut current_path = watch_path;
                let mut watching = has_initial_file && current_path.exists();

                if watching {
                    if let Err(e) = watcher.watch(&current_path, RecursiveMode::NonRecursive) {
                        eprintln!("Failed to watch file: {}", e);
                        watching = false;
                    }
                }

                loop {
                    // Check for new path to watch (non-blocking)
                    if let Ok(new_path) = path_rx.try_recv() {
                        // Stop watching old file if we were watching
                        if watching {
                            let _ = watcher.unwatch(&current_path);
                        }

                        // Start watching new file
                        if let Err(e) = watcher.watch(&new_path, RecursiveMode::NonRecursive) {
                            eprintln!("Failed to watch new file: {}", e);
                            watching = false;
                        } else {
                            watching = true;
                        }

                        current_path = new_path;
                    }

                    // Check for file events (with timeout to allow path switching)
                    if let Ok(event) = event_rx.recv_timeout(Duration::from_millis(100)) {
                        // Check for modify or write events
                        if matches!(
                            event.kind,
                            notify::EventKind::Modify(_) | notify::EventKind::Create(_)
                        ) {
                            // Small delay to ensure file write is complete
                            thread::sleep(Duration::from_millis(50));

                            // Get current watched path from state
                            let watched_path = file_path_for_watcher
                                .lock()
                                .unwrap_or_else(|e| e.into_inner())
                                .clone();

                            // Read updated content
                            if let Ok(new_content) = fs::read_to_string(&watched_path) {
                                if !new_content.trim().is_empty() {
                                    // Update shared state
                                    if let Ok(mut content) = content_for_watcher.lock() {
                                        *content = new_content;
                                    }

                                    // Emit event to frontend
                                    if let Some(window) = app_handle.get_webview_window("main") {
                                        let _ = window.emit("file-changed", ());
                                    }
                                }
                            }
                        }
                    }
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            match event {
                tauri::WindowEvent::CloseRequested { api, .. } => {
                    // Save window state before closing
                    if let Ok(position) = window.outer_position() {
                        if let Ok(size) = window.outer_size() {
                            let state = WindowState {
                                x: position.x,
                                y: position.y,
                                width: size.width,
                                height: size.height,
                            };
                            if let Err(e) = state.save() {
                                eprintln!("Failed to save window state: {}", e);
                            }
                        }
                    }
                    // Hide window instead of closing (daemon mode)
                    if let Err(e) = window.hide() {
                        eprintln!("Failed to hide window: {}", e);
                    }
                    // Prevent the default close behavior
                    api.prevent_close();
                }
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
