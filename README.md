# Glance

A minimal, blazingly fast markdown viewer. Open markdown files from the command line and view them beautifully.

**Supported:** macOS, Linux | **Not supported:** Windows

## Features

- **Instant file opens** - Sequential files load in ~0.2s (vs 3s cold start)
- **Code highlighting** - Syntax highlighting for 100+ languages (lazy-loaded)
- **Live reloading** - Auto-updates when the file changes
- **Dark mode** - Follows your system theme preference
- **Large files** - Accordion sections for files over 500KB
- **Drag & drop** - Open files by dragging into the window
- **Window state** - Remembers position and size
- **Diagram support** - Render Mermaid diagrams (optional branch)

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
