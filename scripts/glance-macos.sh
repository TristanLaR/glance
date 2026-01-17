#!/bin/bash
APP="/Users/trilar/Documents/repos/glance/src-tauri/target/release/bundle/macos/glance.app"
BIN="$APP/Contents/MacOS/glance"

# Convert to absolute path if needed
FILE=""
if [ $# -gt 0 ]; then
    FILE="$1"
    [[ "$FILE" != /* ]] && FILE="$(pwd)/$FILE"
fi

# Check if daemon is already running
if pgrep -f "glance.app/Contents/MacOS/glance" > /dev/null 2>&1; then
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
