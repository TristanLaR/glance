#!/bin/bash
# Glance launcher for macOS (native Swift app)
# Searches for the app in common locations

APP=""
# Check common install locations
for candidate in \
    "/Applications/Glance.app" \
    "$HOME/Applications/Glance.app" \
    "$(dirname "$0")/../macos/build/Build/Products/Debug/Glance.app" \
    "$(dirname "$0")/../macos/build/Build/Products/Release/Glance.app"; do
    if [ -d "$candidate" ]; then
        APP="$candidate"
        break
    fi
done

if [ -z "$APP" ]; then
    echo "Error: Glance.app not found. Build with: cd macos && xcodegen generate && xcodebuild -scheme Glance build"
    exit 1
fi

BIN="$APP/Contents/MacOS/Glance"

# Convert to absolute path if needed
FILE=""
if [ $# -gt 0 ]; then
    FILE="$1"
    [[ "$FILE" != /* ]] && FILE="$(pwd)/$FILE"
fi

# Check if daemon is already running
if pgrep -f "Glance.app/Contents/MacOS/Glance" > /dev/null 2>&1; then
    # Daemon running - use binary to send via socket (it exits immediately)
    "$BIN" "$FILE"
else
    # First run - use 'open' to launch detached from terminal
    if [ -n "$FILE" ]; then
        open "$APP" --args "$FILE"
    else
        open "$APP"
    fi
fi
