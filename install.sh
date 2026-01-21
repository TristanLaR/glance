#!/bin/bash
set -e

# Glance installer script
# Usage: curl -fsSL https://raw.githubusercontent.com/TristanLaR/glance/master/install.sh | bash

VERSION="0.1.1"
REPO="TristanLaR/glance"

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

if [ "$OS" = "darwin" ]; then
    echo "Installing Glance for macOS..."
    URL="https://github.com/$REPO/releases/download/v$VERSION/glance-macos.tar.gz"

    # Download and extract
    curl -fsSL "$URL" -o /tmp/glance.tar.gz
    tar -xzf /tmp/glance.tar.gz -C /tmp

    # Move to Applications
    rm -rf /Applications/glance.app 2>/dev/null || true
    mv /tmp/glance.app /Applications/

    # Create symlink in /usr/local/bin
    sudo mkdir -p /usr/local/bin
    sudo ln -sf /Applications/glance.app/Contents/MacOS/glance /usr/local/bin/glance

    rm /tmp/glance.tar.gz
    echo "✓ Glance installed! Run: glance file.md"

elif [ "$OS" = "linux" ]; then
    echo "Installing Glance for Linux..."

    # Install runtime dependencies
    if command -v apt-get &> /dev/null; then
        echo "Installing dependencies..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq libwebkit2gtk-4.0-37 libgtk-3-0 > /dev/null
    else
        echo "Warning: Please install GTK3 and WebKit2GTK manually"
    fi

    URL="https://github.com/$REPO/releases/download/v$VERSION/glance-linux-x86_64.tar.gz"

    # Download and extract
    curl -fsSL "$URL" -o /tmp/glance.tar.gz
    tar -xzf /tmp/glance.tar.gz -C /tmp

    # Install to /usr/local/bin
    sudo mv /tmp/glance /usr/local/bin/glance
    sudo chmod +x /usr/local/bin/glance

    rm /tmp/glance.tar.gz
    echo "✓ Glance installed! Run: glance file.md"

else
    echo "Unsupported OS: $OS"
    exit 1
fi
