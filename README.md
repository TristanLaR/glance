# Glance

A minimal, fast markdown viewer built with Rust.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/TristanLaR/glance/master/install.sh | bash
```

Supports **macOS** and **Linux** (Ubuntu 24.04+). Installs the `glance` CLI and registers as a file handler for `.md` files (right-click > Open With > Glance).

## Usage

```bash
glance README.md
```

## Uninstall

**macOS:**
```bash
sudo rm /usr/local/bin/glance
rm -rf /Applications/glance.app
```

**Linux:**
```bash
sudo rm /usr/local/bin/glance
sudo rm -rf /usr/local/lib/glance
rm ~/.local/share/applications/glance.desktop
```

## Features

- **Fast** — opens files in milliseconds
- **Live preview** — watches for changes and reloads automatically
- **Syntax highlighting** — 100+ languages, lazy-loaded
- **Native dark mode** — matches your system theme
- **Lightweight** — under 2 MB, minimal resource usage
- **Daemon mode** — subsequent invocations reuse the running instance

## License

MIT
