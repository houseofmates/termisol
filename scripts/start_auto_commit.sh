#!/bin/bash

# Start auto-commit monitoring script
# This script runs the auto-commit monitoring in background

REPO_DIR="/home/house/termisol"
SCRIPT_DIR="$REPO_DIR/scripts"
PID_FILE="$REPO_DIR/.git/auto_commit.pid"
LOG_FILE="$REPO_DIR/.git/auto_commit.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        log_message "Auto-commit monitoring already running with PID $PID"
        echo "Auto-commit monitoring is already running (PID: $PID)"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# Start the monitoring script
log_message "Starting auto-commit monitoring"
cd "$REPO_DIR" || exit 1

# Run the auto-commit script in background
nohup "$SCRIPT_DIR/watch_and_commit.sh" > /dev/null 2>&1 &
PID=$!

# Save PID
echo "$PID" > "$PID_FILE"

log_message "Auto-commit monitoring started with PID $PID"
echo "Auto-commit monitoring started (PID: $PID)"
echo "Log file: $LOG_FILE"
echo "To stop: kill $PID or run $SCRIPT_DIR/stop_auto_commit.sh"
