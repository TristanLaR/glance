// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process;
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tauri::Manager;

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

    // Require a file argument
    if args.len() < 2 {
        eprintln!("Error: No markdown file specified");
        eprintln!("Usage: glance <file.md> [options]");
        process::exit(1);
    }

    let file_path = PathBuf::from(&args[1]);

    // Check if file exists
    if !file_path.exists() {
        eprintln!("Error: File not found: {}", file_path.display());
        process::exit(1);
    }

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

    // Get absolute path and filename for window title
    let absolute_path = fs::canonicalize(&file_path).unwrap_or_else(|_| file_path.clone());
    let file_name = file_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Glance".to_string());

    // Run the Tauri application
    run_app(
        absolute_path.to_string_lossy().to_string(),
        file_name,
        content,
    );
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

#[tauri::command]
fn get_markdown_content(state: tauri::State<AppState>) -> MarkdownContent {
    let content = state.content.lock().unwrap();
    let file_path = state.file_path.lock().unwrap();
    let file_name = state.file_name.lock().unwrap();

    // Get directory of the markdown file for resolving relative image paths
    let file_dir = PathBuf::from(file_path.as_str())
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();

    MarkdownContent {
        content: content.clone(),
        file_path: file_path.clone(),
        file_name: file_name.clone(),
        file_dir,
    }
}

#[tauri::command]
fn open_dropped_file(
    path: String,
    state: tauri::State<AppState>,
    window: tauri::Window,
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
    if extension.as_deref() != Some("md") && extension.as_deref() != Some("markdown") {
        return Err("Only markdown files (.md, .markdown) are supported".to_string());
    }

    // Read file content
    let new_content = fs::read_to_string(&file_path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    if new_content.trim().is_empty() {
        return Err(format!("File is empty: {}", file_path.display()));
    }

    // Get absolute path and filename
    let absolute_path = fs::canonicalize(&file_path)
        .unwrap_or_else(|_| file_path.clone());
    let new_file_name = file_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Glance".to_string());

    // Update state
    {
        let mut content = state.content.lock().unwrap();
        *content = new_content;
    }
    {
        let mut file_path_state = state.file_path.lock().unwrap();
        *file_path_state = absolute_path.to_string_lossy().to_string();
    }
    {
        let mut file_name_state = state.file_name.lock().unwrap();
        *file_name_state = new_file_name.clone();
    }

    // Update window title
    let window_title = format!("{} - Glance", new_file_name);
    let _ = window.set_title(&window_title);

    // Tell watcher thread to watch new file
    if let Some(ref sender) = *state.watcher_control.lock().unwrap() {
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
}

struct AppState {
    content: Arc<Mutex<String>>,
    file_path: Arc<Mutex<String>>,
    file_name: Arc<Mutex<String>>,
    watcher_control: Arc<Mutex<Option<Sender<PathBuf>>>>,
}

fn run_app(file_path: String, file_name: String, content: String) {
    let window_title = format!("{} - Glance", file_name);
    let content = Arc::new(Mutex::new(content));
    let file_path_state = Arc::new(Mutex::new(file_path.clone()));
    let file_name_state = Arc::new(Mutex::new(file_name));
    let watcher_control: Arc<Mutex<Option<Sender<PathBuf>>>> = Arc::new(Mutex::new(None));
    let watch_path = PathBuf::from(&file_path);

    let watcher_control_for_setup = watcher_control.clone();

    tauri::Builder::default()
        .manage(AppState {
            content: content.clone(),
            file_path: file_path_state.clone(),
            file_name: file_name_state.clone(),
            watcher_control,
        })
        .invoke_handler(tauri::generate_handler![get_markdown_content, open_dropped_file])
        .setup(move |app| {
            // Update window title with file name
            if let Some(window) = app.get_window("main") {
                let _ = window.set_title(&window_title);
            }

            // Set up file watcher with path switching support
            let app_handle = app.handle();
            let content_for_watcher = content.clone();
            let file_path_for_watcher = file_path_state.clone();

            // Channel for switching watched files
            let (path_tx, path_rx) = channel::<PathBuf>();

            // Store sender in state for later use
            {
                let mut control = watcher_control_for_setup.lock().unwrap();
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

                let mut current_path = watch_path;

                if let Err(e) = watcher.watch(&current_path, RecursiveMode::NonRecursive) {
                    eprintln!("Failed to watch file: {}", e);
                    return;
                }

                loop {
                    // Check for new path to watch (non-blocking)
                    if let Ok(new_path) = path_rx.try_recv() {
                        // Stop watching old file
                        let _ = watcher.unwatch(&current_path);

                        // Start watching new file
                        if let Err(e) = watcher.watch(&new_path, RecursiveMode::NonRecursive) {
                            eprintln!("Failed to watch new file: {}", e);
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
                            let watched_path = file_path_for_watcher.lock().unwrap().clone();

                            // Read updated content
                            if let Ok(new_content) = fs::read_to_string(&watched_path) {
                                if !new_content.trim().is_empty() {
                                    // Update shared state
                                    if let Ok(mut content) = content_for_watcher.lock() {
                                        *content = new_content;
                                    }

                                    // Emit event to frontend
                                    if let Some(window) = app_handle.get_window("main") {
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
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
