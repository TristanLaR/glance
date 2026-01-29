#!/bin/bash
set -euo pipefail

REPO="TristanLaR/glance"
INSTALL_DIR="/usr/local/bin"
DRY_RUN="${DRY_RUN:-0}"

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
    esac
done

# --- Helpers ---

info()  { printf '\033[0;32m==> %s\033[0m\n' "$1"; }
warn()  { printf '\033[0;33m==> %s\033[0m\n' "$1"; }
error() { printf '\033[0;31merror: %s\033[0m\n' "$1"; exit 1; }

need() {
    command -v "$1" &>/dev/null || error "'$1' is required but not found"
}

# --- Preflight ---

need curl
need tar

OS=$(uname -s)
ARCH=$(uname -m)

[ "$OS" = "Darwin" ] || [ "$OS" = "Linux" ] || error "Unsupported OS: $OS (macOS and Linux only)"

# --- Version (override: GLANCE_VERSION) ---

if [ -n "${GLANCE_VERSION:-}" ]; then
    VERSION="$GLANCE_VERSION"
else
    info "Fetching latest release..."
    VERSION=$(
        curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
            | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v'
    ) || true
    [ -n "$VERSION" ] || error "Could not determine latest version. Check your network connection."
fi

info "Installing Glance v$VERSION"

# --- Download (override: GLANCE_BASE_URL) ---

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

case "$OS" in
    Darwin) ASSET="glance-macos.tar.gz" ;;
    Linux)  ASSET="glance-linux-x86_64.tar.gz" ;;
esac

if [ -n "${GLANCE_BASE_URL:-}" ]; then
    URL="${GLANCE_BASE_URL}/${ASSET}"
else
    URL="https://github.com/$REPO/releases/download/v$VERSION/$ASSET"
fi

if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] OS=$OS ARCH=$ARCH"
    info "[dry-run] Version: $VERSION"
    info "[dry-run] Asset: $ASSET"
    info "[dry-run] URL: $URL"
    if [[ "$URL" != file://* ]]; then
        HTTP_CODE=$(curl -sL -o /dev/null -w '%{http_code}' "$URL")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            info "[dry-run] Asset reachable (HTTP $HTTP_CODE)"
        else
            warn "[dry-run] Asset returned HTTP $HTTP_CODE"
        fi
    fi
    info "[dry-run] Install would target: $INSTALL_DIR/glance"
    info "[dry-run] Done. No changes made."
    exit 0
fi

info "Downloading $ASSET..."
curl -fSL --progress-bar "$URL" -o "$TMPDIR/$ASSET"
tar -xzf "$TMPDIR/$ASSET" -C "$TMPDIR"

# --- Install ---

case "$OS" in

    # -------------------------------------------------------------------------
    # macOS
    # -------------------------------------------------------------------------
    Darwin)
        info "Installing to /Applications..."
        rm -rf /Applications/glance.app 2>/dev/null || true
        mv "$TMPDIR/glance.app" /Applications/

        info "Creating CLI command..."
        sudo mkdir -p "$INSTALL_DIR"
        sudo tee "$INSTALL_DIR/glance" >/dev/null <<'EOF'
#!/bin/bash
APP="/Applications/glance.app"
BIN="$APP/Contents/MacOS/glance"

FILE=""
if [ $# -gt 0 ]; then
    FILE="$1"
    [[ "$FILE" != /* ]] && FILE="$(pwd)/$FILE"
fi

if pgrep -f "glance.app/Contents/MacOS/glance" >/dev/null 2>&1; then
    "$BIN" "$FILE"
else
    if [ -n "$FILE" ]; then
        open "$APP" --args "$FILE"
    else
        open "$APP"
    fi
fi
EOF
        sudo chmod +x "$INSTALL_DIR/glance"
        ;;

    # -------------------------------------------------------------------------
    # Linux
    # -------------------------------------------------------------------------
    Linux)
        # Runtime dependencies
        if command -v apt-get &>/dev/null; then
            info "Installing dependencies..."
            sudo apt-get update -qq
            sudo apt-get install -y -qq libwebkit2gtk-4.1-0 libgtk-3-0 2>/dev/null \
                || sudo apt-get install -y -qq libwebkit2gtk-4.0-37 libgtk-3-0 2>/dev/null \
                || warn "Could not install dependencies. Ensure GTK3 and WebKit2GTK are installed."
        elif command -v pacman &>/dev/null; then
            info "Installing dependencies..."
            sudo pacman -S --noconfirm --needed webkit2gtk-4.1 gtk3 2>/dev/null \
                || sudo pacman -S --noconfirm --needed webkit2gtk gtk3 2>/dev/null \
                || warn "Could not install dependencies. Ensure GTK3 and WebKit2GTK are installed."
        elif command -v dnf &>/dev/null; then
            info "Installing dependencies..."
            sudo dnf install -y webkit2gtk4.1 gtk3 2>/dev/null \
                || sudo dnf install -y webkit2gtk4.0 gtk3 2>/dev/null \
                || warn "Could not install dependencies. Ensure GTK3 and WebKit2GTK are installed."
        else
            warn "Unrecognized package manager. Ensure GTK3 and WebKit2GTK are installed."
        fi

        info "Installing binary..."
        sudo mkdir -p /usr/local/lib/glance
        sudo install -m 755 "$TMPDIR/glance" /usr/local/lib/glance/glance

        info "Creating CLI command..."
        sudo mkdir -p "$INSTALL_DIR"
        sudo tee "$INSTALL_DIR/glance" >/dev/null <<'EOF'
#!/bin/bash
BIN="/usr/local/lib/glance/glance"

FILE=""
if [ $# -gt 0 ]; then
    FILE="$1"
    [[ "$FILE" != /* ]] && FILE="$(pwd)/$FILE"
fi

if pgrep -f "/usr/local/lib/glance/glance" >/dev/null 2>&1; then
    "$BIN" "$FILE"
else
    if [ -n "$FILE" ]; then
        setsid "$BIN" "$FILE" >/dev/null 2>&1 &
    else
        setsid "$BIN" >/dev/null 2>&1 &
    fi
fi
EOF
        sudo chmod +x "$INSTALL_DIR/glance"

        # Desktop integration (right-click > Open With)
        info "Setting up desktop integration..."
        DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        mkdir -p "$DESKTOP_DIR"
        cat > "$DESKTOP_DIR/glance.desktop" <<DESKTOP
[Desktop Entry]
Name=Glance
Comment=Minimal markdown viewer
Exec=/usr/local/bin/glance %f
Icon=text-markdown
Type=Application
Categories=Utility;Viewer;
MimeType=text/markdown;text/x-markdown;
Terminal=false
DESKTOP

        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
        fi
        if command -v xdg-mime &>/dev/null; then
            xdg-mime default glance.desktop text/markdown 2>/dev/null || true
        fi
        ;;
esac

# --- Done ---

echo ""
info "Glance v$VERSION installed successfully!"
echo ""
echo "  Usage:        glance file.md"
echo "  Open With:    Right-click any .md file → Open With → Glance"
echo ""
