# Glance — Product Requirements Document

**Version:** 1.0  
**Date:** January 2026

---

## Overview

Glance is a minimal, fast markdown viewer. Open a file, see it rendered. Nothing else.

---

## Problem

Reading markdown in the terminal sucks. Existing solutions are either bloated (Electron-based) or too feature-heavy. We want something that opens instantly, looks good, and stays out of the way.

---

## Solution

A native app that renders markdown in a clean window. No menus, no toolbars, no distractions. Just content.

---

## User Stories

### US-001: Open Markdown File via CLI

**As a** developer  
**I want to** run `glance file.md` from the terminal  
**So that** I can quickly preview markdown without leaving my workflow

**Acceptance Criteria:**
- Running `glance file.md` opens a window with rendered markdown
- Startup completes in under 200ms
- Exit code 0 on success, exit code 1 with error message if file not found or empty

---

### US-002: Hot Reload on File Changes

**As a** developer  
**I want** the preview to update automatically when I save the file  
**So that** I can see changes without manual refresh

**Acceptance Criteria:**
- File changes detected via filesystem watcher
- Re-render triggered automatically on save
- Scroll position preserved after reload

---

### US-003: View Syntax-Highlighted Code Blocks

**As a** reader  
**I want** code blocks to have syntax highlighting  
**So that** code is readable and scannable

**Acceptance Criteria:**
- Code blocks rendered with highlight.js
- Language auto-detected or specified via fence (```js, ```python, etc.)
- Copy button appears on hover

---

### US-004: View Mermaid Diagrams

**As a** documentation author  
**I want** Mermaid diagrams to render inline  
**So that** I can preview diagrams without external tools

**Acceptance Criteria:**
- Mermaid code blocks render as SVG diagrams
- Failed diagrams show inline error message
- Diagrams respect dark/light mode

---

### US-005: Drag and Drop File

**As a** user  
**I want to** drag a .md file onto the Glance window  
**So that** I can open files without using the terminal

**Acceptance Criteria:**
- Dropping .md file opens it in current window
- Window title updates to new filename
- Previous file's watch is stopped, new file is watched

---

### US-006: Open File via System Dialog

**As a** user  
**I want to** press Cmd+O to open a file picker  
**So that** I can browse for files visually

**Acceptance Criteria:**
- Cmd+O (Ctrl+O on Windows/Linux) opens native file picker
- Filter shows .md files by default
- Selected file opens in current window

---

### US-007: View Images in Markdown

**As a** reader  
**I want** images to display inline  
**So that** I can see the complete document

**Acceptance Criteria:**
- Local relative paths resolved from markdown file location
- Remote URLs fetched and displayed
- Base64 embedded images rendered
- Broken images show alt text or placeholder

---

### US-008: Follow System Theme

**As a** user  
**I want** the app to match my system's dark/light mode  
**So that** it fits my visual environment

**Acceptance Criteria:**
- Detects system theme preference on launch
- Responds to system theme changes in real-time
- GitHub-style markdown CSS adapts to theme

---

### US-009: Zoom Content

**As a** reader  
**I want to** increase or decrease text size  
**So that** I can read comfortably

**Acceptance Criteria:**
- Cmd+Plus zooms in, Cmd+Minus zooms out, Cmd+0 resets
- Zoom level persists for session
- Content remains readable at all zoom levels

---

### US-010: Remember Window State

**As a** user  
**I want** the window to remember its size and position  
**So that** I don't have to resize it every time

**Acceptance Criteria:**
- Window size and position saved on close
- Restored on next launch
- Falls back to sensible defaults if no saved state

---

### US-011: Handle Large Files Gracefully

**As a** user  
**I want** large files to load without freezing  
**So that** I can preview any markdown file

**Acceptance Criteria:**
- Files over 500KB show outline/TOC by default
- Sections expandable inline (accordion style)
- Multiple sections can be open simultaneously
- `--no-truncate` flag renders entire file
- Config file option: `no_truncate = true`

---

### US-012: Associate with OS File Handler

**As a** user  
**I want to** right-click a .md file and "Open with Glance"  
**So that** I can use Glance from Finder/Explorer

**Acceptance Criteria:**
- App registers as handler for .md files
- Double-click .md file opens in Glance (if set as default)
- Works on macOS, Windows, and Linux

---

### US-013: Copy Code from Code Blocks

**As a** developer  
**I want to** copy code with one click  
**So that** I can use snippets without manual selection

**Acceptance Criteria:**
- Copy button appears on hover over code blocks
- Click copies code content to clipboard
- Visual feedback confirms copy action

---

## Core Features

| Feature | Description |
|---------|-------------|
| Hot reload | Watch file for changes, re-render automatically |
| Syntax highlighting | Code blocks highlighted via highlight.js |
| GitHub-style rendering | Familiar, readable styling |
| Mermaid diagrams | Render diagrams inline |
| Image support | Local paths, remote URLs, and base64 embedded images |

---

## Quality of Life

| Feature | Description |
|---------|-------------|
| Scroll preservation | Maintain scroll position on reload |
| Drag and drop | Drop .md file onto window to open |
| CLI support | `glance file.md` |
| OS file association | Right-click → Open with Glance |

---

## Polish

| Feature | Description |
|---------|-------------|
| Dark/light mode | Follow system preference |
| Keyboard shortcuts | Cmd+O open, Cmd+W close, Cmd+Plus/Minus zoom |
| Window title | Shows current filename |
| Window memory | Remember size and position |
| Copy code button | Appears on hover over code blocks |

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Broken markdown/mermaid | Silent failure — render what works, skip broken parts |
| Inline errors | Show error message where content would appear (e.g., "Mermaid diagram failed to parse") |
| Console logging | Log all errors for debugging |
| Missing file | Exit with code 1: `Error: File not found: path/to/file.md` |
| Empty file | Exit with code 1: `Error: File is empty: path/to/file.md` |

---

## Large File Handling

| Setting | Value |
|---------|-------|
| Default threshold | 500KB |
| Default behavior | Truncate — show TOC/outline with expandable sections |
| Section expansion | Inline accordion, multiple sections can be open |
| Override | `--no-truncate` flag or config file |

**Truncated view:**
- Parse full file to extract headings
- Show clickable outline/TOC
- Click heading to expand that section inline
- Multiple sections can be expanded simultaneously
- Footer: "Large file mode. Use `--no-truncate` to render all."

---

## Configuration

**Location:** `~/.config/glance/config.toml`

```toml
# Glance configuration

# Disable truncation for large files (default: false)
no_truncate = false
```

**CLI flags override config file settings.**

---

## CLI Interface

```
glance <file.md> [options]

Options:
  --no-truncate    Render entire file regardless of size
  --help, -h       Show help
  --version, -v    Show version

Exit codes:
  0    Success
  1    Error (file not found, empty file, etc.)
```

---

## Non-Features

- No editing
- No tabs
- No sidebar
- No menu bar
- No toolbar
- No settings screen

---

## UI

Edge-to-edge rendered markdown with comfortable padding and max-width for readability. The only UI elements are:

- The rendered content
- Scrollbar
- Copy button (on hover over code blocks)

---

## Window Behavior

| Platform | Last window closed |
|----------|-------------------|
| macOS | Quit app entirely |
| Windows | Quit app entirely |
| Linux | Quit app entirely |

---

## Tech Stack

**Runtime:** Tauri (Rust + Webview)

**Rust crates:**
- `notify` — file watching

**Frontend libs:**
- `marked` — markdown parsing
- `highlight.js` — syntax highlighting
- `mermaid` — diagram rendering
- `github-markdown-css` — styling

---

## Target Metrics

| Metric | Target |
|--------|--------|
| Binary size | < 10MB |
| Startup time | < 200ms |
| Total codebase | < 500 lines |

---

## Platforms

- macOS
- Windows
- Linux

---

## Future Considerations (v2+)

- Table of contents sidebar (always visible)
- Recent files
- Frontmatter display
- LaTeX/math support
- Local .md link navigation
- Additional config options (theme override, default zoom)

---

## Success Criteria

You run `glance README.md` and it just works. Fast, pretty, done.