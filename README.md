# Glance

A minimal, blazingly fast markdown viewer for macOS. Open markdown files from the command line and view them beautifully.

## Features

- **Instant startup** - Opens markdown files in milliseconds
- **Daemon mode** - Reuses a running instance for 12x faster file loading (0.24s vs 3s)
- **Code highlighting** - Syntax highlighting for 100+ languages (lazy-loaded)
- **Diagram support** - Render Mermaid diagrams (optional branch)
- **File watching** - Auto-reloads when the markdown file changes
- **Dark mode** - Follows your system theme preference
- **Large file handling** - Accordion sections for files over 500KB
- **Drag & drop** - Drag files into the window to open them
- **Window state** - Remembers your window position and size

## Usage

```bash
glance README.md
glance path/to/file.md
glance --help
```

First invocation starts the daemon (~3 seconds). Subsequent invocations reuse the running daemon (~0.2 seconds).

## Installation

Build from source:

```bash
cargo tauri build
```

Then add to your PATH:

```bash
ln -s /path/to/glance.app/Contents/MacOS/glance ~/bin/glance
```

## Development

```bash
cargo tauri dev
```

## Branches

- **master** - Lightweight version without Mermaid diagrams (1.8 MB)
- **mermaid** - Full-featured with diagram support (2.6 MB, lazy-loaded)

Both use lazy-loading for highlight.js to keep startup fast.

## License

MIT
