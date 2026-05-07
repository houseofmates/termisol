#!/bin/bash

# Stop auto-commit monitoring script

REPO_DIR="/home/house/termisol"
PID_FILE="$REPO_DIR/.git/auto_commit.pid"
LOG_FILE="$REPO_DIR/.git/auto_commit.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
    echo "Auto-commit monitoring is not running"
    exit 0
fi

# Read PID
PID=$(cat "$PID_FILE")

# Check if process is running
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "Auto-commit monitoring process (PID: $PID) is not running"
    rm -f "$PID_FILE"
    exit 0
fi

# Kill the process
kill "$PID"

# Wait a moment and check if it's still running
sleep 2
if ps -p "$PID" > /dev/null 2>&1; then
    echo "Force killing auto-commit monitoring process (PID: $PID)"
    kill -9 "$PID"
fi

# Remove PID file
rm -f "$PID_FILE"

log_message "Auto-commit monitoring stopped (PID: $PID)"
echo "Auto-commit monitoring stopped"
