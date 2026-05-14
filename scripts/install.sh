#!/bin/bash
set -e

# Build the flutter application
flutter build linux --release

# Ensure directories exist
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user

# Copy executable bundle
mkdir -p ~/.local/share/termisol
cp -r build/linux/x64/release/bundle/* ~/.local/share/termisol/
ln -sf ~/.local/share/termisol/termisol ~/.local/bin/termisol
chmod +x ~/.local/share/termisol/termisol

# Install Systemd user service
cp scripts/termisol-user.service ~/.config/systemd/user/termisol.service

# Enable and start the service
systemctl --user daemon-reload
systemctl --user enable termisol.service
systemctl --user restart termisol.service

echo "Termisol installed and background service started successfully."
