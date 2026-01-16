// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process;
use std::sync::mpsc::channel;
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
    MarkdownContent {
        content: content.clone(),
        file_path: state.file_path.clone(),
        file_name: state.file_name.clone(),
    }
}

#[derive(Clone, serde::Serialize)]
struct MarkdownContent {
    content: String,
    file_path: String,
    file_name: String,
}

struct AppState {
    content: Arc<Mutex<String>>,
    file_path: String,
    file_name: String,
}

fn run_app(file_path: String, file_name: String, content: String) {
    let window_title = format!("{} - Glance", file_name);
    let content = Arc::new(Mutex::new(content));
    let watch_path = PathBuf::from(&file_path);

    tauri::Builder::default()
        .manage(AppState {
            content: content.clone(),
            file_path: file_path.clone(),
            file_name,
        })
        .invoke_handler(tauri::generate_handler![get_markdown_content])
        .setup(move |app| {
            // Update window title with file name
            if let Some(window) = app.get_window("main") {
                let _ = window.set_title(&window_title);
            }

            // Set up file watcher
            let app_handle = app.handle();
            let content_for_watcher = content.clone();
            let path_for_watcher = watch_path.clone();

            thread::spawn(move || {
                let (tx, rx) = channel();

                let mut watcher = match RecommendedWatcher::new(
                    move |res: Result<Event, notify::Error>| {
                        if let Ok(event) = res {
                            let _ = tx.send(event);
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

                if let Err(e) = watcher.watch(&path_for_watcher, RecursiveMode::NonRecursive) {
                    eprintln!("Failed to watch file: {}", e);
                    return;
                }

                // Keep watcher alive and process events
                while let Ok(event) = rx.recv() {
                    // Check for modify or write events
                    if matches!(
                        event.kind,
                        notify::EventKind::Modify(_) | notify::EventKind::Create(_)
                    ) {
                        // Small delay to ensure file write is complete
                        thread::sleep(Duration::from_millis(50));

                        // Read updated content
                        if let Ok(new_content) = fs::read_to_string(&path_for_watcher) {
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
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
