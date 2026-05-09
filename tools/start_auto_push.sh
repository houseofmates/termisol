#!/bin/bash

# Amnesia-proof AutoPush Service Starter
# This script ensures the auto-push service is always running

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE_SCRIPT="$SCRIPT_DIR/auto_push_service.dart"
PID_FILE="$REPO_DIR/.devin/auto_push.pid"
LOG_FILE="$REPO_DIR/.devin/auto_push.log"

echo "🚀 Starting Termisol AutoPush Service"
echo "📍 Repository: $REPO_DIR"

# Create .devin directory if it doesn't exist
mkdir -p "$REPO_DIR/.devin"

# Function to start the service
start_service() {
    echo "🔧 Starting auto-push service..."
    
    # Kill any existing service
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "🗑️  Killing existing service (PID: $OLD_PID)"
            kill "$OLD_PID" || true
            sleep 2
        fi
        rm -f "$PID_FILE"
    fi
    
    # Start the service in background
    cd "$REPO_DIR"
    nohup dart run "$SERVICE_SCRIPT" > "$LOG_FILE" 2>&1 &
    NEW_PID=$!
    
    # Save PID
    echo "$NEW_PID" > "$PID_FILE"
    
    echo "✅ AutoPush service started (PID: $NEW_PID)"
    echo "📄 Logs: $LOG_FILE"
}

# Function to check if service is running
check_service() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "✅ Service is running (PID: $PID)"
            return 0
        else
            echo "❌ Service is not running (stale PID file)"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "❌ Service is not running (no PID file)"
        return 1
    fi
}

# Main logic
if check_service; then
    echo "🔄 Service already running, checking health..."
    
    # Check if service is responsive (last heartbeat within 2 minutes)
    if [ -f "$REPO_DIR/.devin/auto_push_state.json" ]; then
        HEARTBEAT=$(jq -r '.heartbeat // "never"' "$REPO_DIR/.devin/auto_push_state.json" 2>/dev/null || echo "never")
        if [ "$HEARTBEAT" != "never" ]; then
            HEARTBEAT_TIME=$(date -d "$HEARTBEAT" +%s 2>/dev/null || echo 0)
            CURRENT_TIME=$(date +%s)
            AGE=$((CURRENT_TIME - HEARTBEAT_TIME))
            
            if [ $AGE -lt 120 ]; then
                echo "💓 Service is healthy (last heartbeat: ${AGE}s ago)"
                exit 0
            else
                echo "⚠️  Service appears unhealthy (last heartbeat: ${AGE}s ago)"
            fi
        fi
    fi
    
    echo "🔄 Restarting service..."
fi

# Start the service
start_service

# Verify it started
sleep 3
if check_service; then
    echo "🎉 AutoPush service is running successfully!"
else
    echo "❌ Failed to start AutoPush service"
    echo "📄 Check logs: $LOG_FILE"
    exit 1
fi