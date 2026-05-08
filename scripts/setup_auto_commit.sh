#!/bin/bash

# Setup script for auto-commit functionality
# This script configures and starts the auto-commit system

REPO_DIR="${TERMISOL_REPO_DIR:-$(pwd)}"
SCRIPT_DIR="$REPO_DIR/scripts"
BASHRC="$HOME/.bashrc"
AUTO_COMMIT_LINE="cd $REPO_DIR && $SCRIPT_DIR/start_auto_commit.sh > /dev/null 2>&1"

echo "Setting up auto-commit for Termisol..."
echo "Repository: $REPO_DIR"
echo "Script directory: $SCRIPT_DIR"

# Check if auto-commit line is already in .bashrc
if ! grep -q "start_auto_commit.sh" "$BASHRC"; then
    echo ""
    echo "# Auto-start Termisol auto-commit monitoring" >> "$BASHRC"
    echo "$AUTO_COMMIT_LINE" >> "$BASHRC"
    echo "Added auto-start to ~/.bashrc"
else
    echo "Auto-start already configured in ~/.bashrc"
fi

# Start auto-commit now
echo "Starting auto-commit monitoring..."
"$SCRIPT_DIR/start_auto_commit.sh"

echo ""
echo "Auto-commit setup complete!"
echo ""
echo "Features:"
echo "- Automatically commits changes older than 10 seconds"
echo "- Pushes to remote repository automatically"
echo "- Generates intelligent commit messages"
echo "- Logs all activity to .git/auto_commit.log"
echo ""
echo "Commands:"
echo "- Start manually: $SCRIPT_DIR/start_auto_commit.sh"
echo "- Stop manually: $SCRIPT_DIR/stop_auto_commit.sh"
echo "- View logs: cat $REPO_DIR/.git/auto_commit.log"
echo ""
echo "The auto-commit system will start automatically on next login."
