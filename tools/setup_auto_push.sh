#!/bin/bash

# setup script for amnesia-proof, restart-proof autopush system
# this script installs the necessary components and sets up automatic restart

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔧 Setting up Termisol AutoPush System"
echo "📍 Repository: $REPO_DIR"

# check if we're in a git repository
cd "$REPO_DIR"
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Error: Not in a git repository"
    exit 1
fi

# check if dart is available
if ! command -v dart &> /dev/null; then
    echo "❌ Error: Dart is not installed or not in PATH"
    exit 1
fi

# check if jq is available (for json parsing in the starter script)
if ! command -v jq &> /dev/null; then
    echo "⚠️  Warning: jq is not installed, some features may not work"
    echo "   Install with: sudo apt-get install jq (Ubuntu/Debian)"
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p "$REPO_DIR/.devin"
mkdir -p "$REPO_DIR/tools"

# Make scripts executable
echo "🔐 Making scripts executable..."
chmod +x "$SCRIPT_DIR/start_auto_push.sh"
chmod +x "$SCRIPT_DIR/setup_auto_push.sh"

# Create systemd service (if systemd is available and sudo works)
if command -v systemctl &> /dev/null && [ -w "/etc/systemd/system" ]; then
    echo "🔧 Setting up systemd service..."
    
    SERVICE_FILE="/etc/systemd/system/termisol-autopush.service"
    
    # Create systemd service file
    tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Termisol AutoPush Service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$REPO_DIR
ExecStart=/usr/bin/dart run $SCRIPT_DIR/auto_push_service.dart
Restart=always
RestartSec=10
StandardOutput=append:$REPO_DIR/.devin/auto_push.log
StandardError=append:$REPO_DIR/.devin/auto_push.log

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload 2>/dev/null || echo "⚠️  Could not reload systemd (need sudo?)"
    systemctl enable termisol-autopush.service 2>/dev/null || echo "⚠️  Could not enable systemd service (need sudo?)"
    
    echo "✅ Systemd service created"
    echo "   Start with: sudo systemctl start termisol-autopush"
    echo "   Status with: sudo systemctl status termisol-autopush"
else
    echo "⚠️  Systemd not available or no write access, using manual startup"
fi

# Create crontab entry for fallback (runs every 5 minutes to check if service is running)
echo "⏰ Setting up crontab fallback..."
TEMP_CRON=$(mktemp)
crontab -l > "$TEMP_CRON" 2>/dev/null || echo "" > "$TEMP_CRON"

# Check if entry already exists
if ! grep -q "termisol-auto-push" "$TEMP_CRON"; then
    echo "*/5 * * * * $SCRIPT_DIR/start_auto_push.sh >> $REPO_DIR/.devin/cron.log 2>&1 # termisol-auto-push" >> "$TEMP_CRON"
    crontab "$TEMP_CRON"
    echo "✅ Crontab fallback added (runs every 5 minutes)"
else
    echo "✅ Crontab entry already exists"
fi

rm -f "$TEMP_CRON"

# Create startup script in user's shell profile
echo "🖥️  Setting up shell startup..."
SHELL_NAME=$(basename "$SHELL")
PROFILE_FILE=""

case "$SHELL_NAME" in
    bash)
        PROFILE_FILE="$HOME/.bashrc"
        ;;
    zsh)
        PROFILE_FILE="$HOME/.zshrc"
        ;;
    *)
        PROFILE_FILE="$HOME/.profile"
        ;;
esac

# Add startup command if not already present
if ! grep -q "termisol-auto-push" "$PROFILE_FILE" 2>/dev/null; then
    echo "" >> "$PROFILE_FILE"
    echo "# Termisol AutoPush Service" >> "$PROFILE_FILE"
    echo "if [ -f \"$SCRIPT_DIR/start_auto_push.sh\" ]; then" >> "$PROFILE_FILE"
    echo "    \"$SCRIPT_DIR/start_auto_push.sh\" >/dev/null 2>&1 &" >> "$PROFILE_FILE"
    echo "fi" >> "$PROFILE_FILE"
    echo "✅ Added to $PROFILE_FILE"
else
    echo "✅ Shell startup already configured"
fi

# Start the service immediately
echo "🚀 Starting AutoPush service..."
"$SCRIPT_DIR/start_auto_push.sh"

echo ""
echo "🎉 AutoPush system setup complete!"
echo ""
echo "📋 Summary:"
echo "   • Service is now running"
echo "   • Will auto-push changes older than 10 seconds"
echo "   • Systemd service: termisol-autopush"
echo "   • Crontab fallback: every 5 minutes"
echo "   • Shell startup: configured"
echo ""
echo "📁 Files created:"
echo "   • $REPO_DIR/tools/auto_push_service.dart"
echo "   • $REPO_DIR/tools/start_auto_push.sh"
echo "   • $REPO_DIR/.devin/ (state and logs)"
echo ""
echo "🔧 Management:"
echo "   • Start: $SCRIPT_DIR/start_auto_push.sh"
echo "   • Logs: $REPO_DIR/.devin/auto_push.log"
echo "   • State: $REPO_DIR/.devin/auto_push_state.json"
echo ""
echo "✅ Your Termisol project is now amnesia-proof and restart-proof!"