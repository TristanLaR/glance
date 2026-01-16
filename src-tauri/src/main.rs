// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process;
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
    let absolute_path = fs::canonicalize(&file_path)
        .unwrap_or_else(|_| file_path.clone());
    let file_name = file_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Glance".to_string());

    // Run the Tauri application
    run_app(absolute_path.to_string_lossy().to_string(), file_name, content);
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
    MarkdownContent {
        content: state.content.clone(),
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
    content: String,
    file_path: String,
    file_name: String,
}

fn run_app(file_path: String, file_name: String, content: String) {
    let window_title = format!("{} - Glance", file_name);

    tauri::Builder::default()
        .manage(AppState {
            content,
            file_path,
            file_name,
        })
        .invoke_handler(tauri::generate_handler![get_markdown_content])
        .setup(move |app| {
            // Update window title with file name
            if let Some(window) = app.get_window("main") {
                let _ = window.set_title(&window_title);
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
