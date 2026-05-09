#!/bin/bash

# Stop script for AutoPush service
# Gracefully stops the service and cleans up

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$REPO_DIR/.devin/auto_push.pid"

echo "🛑 Stopping Termisol AutoPush Service"

# Stop systemd service if it exists
if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet termisol-autopush 2>/dev/null; then
        echo "🔄 Stopping systemd service..."
        sudo systemctl stop termisol-autopush
        echo "✅ Systemd service stopped"
    fi
fi

# Kill running process
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "🔄 Killing process (PID: $PID)"
        kill "$PID"
        sleep 2
        
        # Force kill if still running
        if kill -0 "$PID" 2>/dev/null; then
            echo "⚡ Force killing process..."
            kill -9 "$PID" || true
        fi
        
        echo "✅ Process stopped"
    else
        echo "⚠️  Process not running (stale PID file)"
    fi
    
    rm -f "$PID_FILE"
else
    echo "⚠️  No PID file found"
fi

# Remove lock file
LOCK_FILE="$REPO_DIR/.devin/auto_push.lock"
if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
    echo "🗑️  Lock file removed"
fi

echo "✅ AutoPush service stopped"