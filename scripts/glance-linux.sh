#!/bin/bash
# Glance launcher for Linux
# Adjust BIN path to your installation

BIN="/path/to/glance"  # Update this to your binary location

# Convert to absolute path if needed
FILE=""
if [ $# -gt 0 ]; then
    FILE="$1"
    [[ "$FILE" != /* ]] && FILE="$(pwd)/$FILE"
fi

# Check if daemon is already running
if pgrep -f "glance" > /dev/null 2>&1; then
    # Daemon running - send via socket (exits immediately)
    "$BIN" "$FILE"
else
    # First run - launch detached from terminal
    if [ -n "$FILE" ]; then
        setsid "$BIN" "$FILE" > /dev/null 2>&1 &
    else
        setsid "$BIN" > /dev/null 2>&1 &
    fi
fi
