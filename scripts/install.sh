#!/bin/bash

# Termisol One-Command Installer
# This script installs Termisol with full system integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="termisol"
REPO_URL="https://github.com/termisol/termisol"
INSTALL_DIR="/opt/termisol"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
SERVICE_DIR="/etc/systemd/user"

# Functions
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Termisol Installer                      ║${NC}"
    echo -e "${BLUE}║              Unbreakable Terminal Emulator                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check for basic tools
    for cmd in curl wget git tar; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required dependency '$cmd' is not installed"
            exit 1
        fi
    done
    
    # Check for Flutter if building from source
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        if ! command -v flutter &> /dev/null; then
            print_error "Flutter is required for building from source"
            print_status "Please install Flutter: https://flutter.dev/docs/get-started/install"
            exit 1
        fi
    fi
    
    print_status "All dependencies satisfied"
}

detect_platform() {
    print_status "Detecting platform..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        PLATFORM="linux"
        ARCH=$(uname -m)
        if [ "$ARCH" = "x86_64" ]; then
            ARCH="x64"
        elif [ "$ARCH" = "aarch64" ]; then
            ARCH="arm64"
        else
            print_error "Unsupported architecture: $ARCH"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        PLATFORM="macos"
        ARCH=$(uname -m)
        if [ "$ARCH" = "x86_64" ]; then
            ARCH="x64"
        elif [ "$ARCH" = "arm64" ]; then
            ARCH="arm64"
        else
            print_error "Unsupported architecture: $ARCH"
            exit 1
        fi
    else
        print_error "Unsupported platform: $OSTYPE"
        exit 1
    fi
    
    print_status "Detected platform: $PLATFORM-$ARCH"
}

download_latest_release() {
    print_status "Fetching latest release information..."
    
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/termisol/termisol/releases/latest")
    VERSION=$(echo "$RELEASE_INFO" | grep -o '"tag_name": "[^"]*' | sed -E 's/"tag_name": "v?//')
    
    if [ -z "$VERSION" ]; then
        print_error "Failed to fetch latest version"
        exit 1
    fi
    
    print_status "Latest version: v$VERSION"
    
    # Find appropriate asset
    ASSET_NAME=""
    if [ "$PLATFORM" = "linux" ]; then
        ASSET_NAME="termisol-$VERSION-linux-$ARCH.AppImage"
    elif [ "$PLATFORM" = "macos" ]; then
        ASSET_NAME="termisol-$VERSION-macos-$ARCH.dmg"
    fi
    
    if [ -z "$ASSET_NAME" ]; then
        print_error "No suitable asset found for $PLATFORM-$ARCH"
        exit 1
    fi
    
    DOWNLOAD_URL="https://github.com/termisol/termisol/releases/download/v$VERSION/$ASSET_NAME"
    print_status "Download URL: $DOWNLOAD_URL"
    
    # Download the asset
    print_status "Downloading $ASSET_NAME..."
    curl -L -o "/tmp/$ASSET_NAME" "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        print_error "Download failed"
        exit 1
    fi
    
    print_status "Download completed"
}

build_from_source() {
    print_status "Building from source..."
    
    # Clone repository
    if [ ! -d "/tmp/termisol-source" ]; then
        git clone "$REPO_URL" /tmp/termisol-source
    fi
    
    cd /tmp/termisol-source
    
    # Get dependencies
    print_status "Getting Flutter dependencies..."
    flutter pub get
    
    # Build for current platform
    print_status "Building Termisol..."
    if [ "$PLATFORM" = "linux" ]; then
        flutter build linux --release
        BINARY_PATH="build/linux/x64/release/bundle/termisol"
    elif [ "$PLATFORM" = "macos" ]; then
        flutter build macos --release
        BINARY_PATH="build/macos/Build/Products/Release/termisol.app"
    fi
    
    if [ ! -f "$BINARY_PATH" ]; then
        print_error "Build failed - binary not found"
        exit 1
    fi
    
    print_status "Build completed successfully"
}

install_binary() {
    print_status "Installing Termisol binary..."
    
    # Create installation directory
    sudo mkdir -p "$INSTALL_DIR"
    
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        # Copy from build
        if [ "$PLATFORM" = "macos" ]; then
            sudo cp -r "/tmp/termisol-source/$BINARY_PATH" "$INSTALL_DIR/"
            BINARY_PATH="$INSTALL_DIR/termisol.app/Contents/MacOS/termisol"
        else
            sudo cp -r "/tmp/termisol-source/$(dirname "$BINARY_PATH")" "$INSTALL_DIR/"
            BINARY_PATH="$INSTALL_DIR/termisol"
        fi
    else
        # Install from downloaded asset
        if [ "$PLATFORM" = "linux" ]; then
            sudo cp "/tmp/$ASSET_NAME" "$INSTALL_DIR/termisol.AppImage"
            sudo chmod +x "$INSTALL_DIR/termisol.AppImage"
            BINARY_PATH="$INSTALL_DIR/termisol.AppImage"
        elif [ "$PLATFORM" = "macos" ]; then
            # Mount DMG and copy app
            hdiutil attach "/tmp/$ASSET_NAME"
            sudo cp -r "/Volumes/Termisol/Termisol.app" "$INSTALL_DIR/"
            hdiutil detach "/Volumes/Termisol"
            BINARY_PATH="$INSTALL_DIR/Termisol.app/Contents/MacOS/termisol"
        fi
    fi
    
    # Create symlink in bin directory
    if [ "$PLATFORM" = "linux" ]; then
        sudo mkdir -p "$BIN_DIR"
        sudo ln -sf "$BINARY_PATH" "$BIN_DIR/termisol"
    elif [ "$PLATFORM" = "macos" ]; then
        sudo mkdir -p "$BIN_DIR"
        sudo ln -sf "$BINARY_PATH" "$BIN_DIR/termisol"
    fi
    
    print_status "Binary installed successfully"
}

install_desktop_integration() {
    print_status "Installing desktop integration..."
    
    if [ "$PLATFORM" = "linux" ]; then
        # Create .desktop file
        sudo mkdir -p "$DESKTOP_DIR"
        sudo tee "$DESKTOP_DIR/termisol.desktop" > /dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Termisol
Comment=Unbreakable terminal emulator with AI integration
Exec=$BIN_DIR/termisol
Icon=termisol
Terminal=false
Categories=System;TerminalEmulator;Utility;
Keywords=terminal;console;command;line;shell;ai;
StartupNotify=true
MimeType=text/plain;text/x-c;text/x-c++;text/x-java;text/x-perl;text/x-python;text/x-ruby;
EOF

        # Install icon (create a simple one if not available)
        sudo mkdir -p "$ICON_DIR"
        if [ ! -f "$ICON_DIR/termisol.png" ]; then
            # Create a simple icon using ImageMagick if available
            if command -v convert &> /dev/null; then
                convert -size 256x256 xc:#1e1e1e -font DejaVu-Sans-Bold -pointsize 72 -fill white -gravity center -annotate +0+0 "T" "$ICON_DIR/termisol.png" 2>/dev/null || true
            fi
        fi
        
        # Update desktop database
        if command -v update-desktop-database &> /dev/null; then
            update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
        fi
        
    elif [ "$PLATFORM" = "macos" ]; then
        # macOS apps are self-contained
        print_status "macOS app is self-contained"
    fi
    
    print_status "Desktop integration installed"
}

install_systemd_service() {
    if [ "$PLATFORM" = "linux" ]; then
        print_status "Installing systemd user service..."
        
        # Create systemd user service with security restrictions
        sudo mkdir -p "$SERVICE_DIR"
        sudo tee "$SERVICE_DIR/termisol.service" > /dev/null <<EOF
[Unit]
Description=Termisol Background Service
Documentation=https://github.com/termisol/termisol
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=$BIN_DIR/termisol --background
Restart=always
RestartSec=5
Environment=DISPLAY=:0
Environment=XDG_SESSION_TYPE=x11
Environment=TERM=xterm-256color
Environment=COLORTERM=truecolor

# Security restrictions
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$HOME/.termisol $HOME/.local/share/termisol
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
DevicePolicy=closed

# Resource limits
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=default.target
EOF

        # Reload systemd and enable service
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable termisol.service 2>/dev/null || true
        
        print_status "Systemd service installed"
    fi
}

setup_permissions() {
    print_status "Setting up permissions..."
    
    if [ "$PLATFORM" = "linux" ]; then
        # Set proper permissions
        sudo chmod 755 "$INSTALL_DIR"
        sudo chmod +x "$BINARY_PATH"
        
        # Add user to required groups if needed
        if groups $USER | grep -q "audio"; then
            print_status "User already in audio group"
        else
            print_warning "Consider adding user to audio group for terminal bell support"
        fi
        
    elif [ "$PLATFORM" = "macos" ]; then
        # Set macOS permissions
        sudo chown -R $USER:staff "$INSTALL_DIR"
        sudo chmod +x "$BINARY_PATH"
    fi
    
    print_status "Permissions configured"
}

create_config_directories() {
    print_status "Creating configuration directories..."
    
    # Create user config directories
    mkdir -p "$HOME/.config/termisol"
    mkdir -p "$HOME/.local/share/termisol"
    mkdir -p "$HOME/.cache/termisol"
    
    # Create default config if not exists
    if [ ! -f "$HOME/.config/termisol/config.json" ]; then
        cat > "$HOME/.config/termisol/config.json" <<EOF
{
  "version": "1.0.0",
  "theme": "dark",
  "font_family": "DroidSansMono",
  "font_size": 14,
  "background_opacity": 0.95,
  "enable_ai": true,
  "auto_save": true,
  "minimize_to_tray": true,
  "start_on_boot": false,
  "accessibility": {
    "screen_reader": false,
    "high_contrast": false,
    "reduced_motion": false
  }
}
EOF
    fi
    
    print_status "Configuration directories created"
}

post_install_setup() {
    print_status "Running post-install setup..."
    
    # Create desktop shortcut
    if [ "$PLATFORM" = "linux" ]; then
        # Add to desktop if desktop directory exists
        if [ -d "$HOME/Desktop" ]; then
            cp "$DESKTOP_DIR/termisol.desktop" "$HOME/Desktop/" 2>/dev/null || true
        fi
    fi
    
    # Add to PATH (if not already there)
    if ! echo $PATH | grep -q "$BIN_DIR"; then
        echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
        echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.zshrc" 2>/dev/null || true
        print_status "Added $BIN_DIR to PATH in shell configs"
    fi
    
    print_status "Post-install setup completed"
}

cleanup() {
    print_status "Cleaning up temporary files..."
    
    rm -rf /tmp/termisol-source
    rm -f /tmp/termisol-*.AppImage
    rm -f /tmp/termisol-*.dmg
    
    print_status "Cleanup completed"
}

show_completion_message() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Installation Complete!                   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Termisol v$VERSION has been successfully installed!${NC}"
    echo
    echo -e "${YELLOW}Quick Start:${NC}"
    echo -e "  • Run 'termisol' from any terminal"
    echo -e "  • Find Termisol in your applications menu"
    echo -e "  • Check the configuration: ~/.config/termisol/config.json"
    echo
    echo -e "${YELLOW}Features:${NC}"
    echo -e "  • ✅ Crash-proof session persistence"
    echo -e "  • ✅ Background service with system tray"
    echo -e "  • ✅ Re-attachable PTY architecture"
    echo -e "  • ✅ AI-powered command suggestions"
    echo -e "  • ✅ Full accessibility support"
    echo -e "  • ✅ Auto-update mechanism"
    echo
    echo -e "${YELLOW}System Integration:${NC}"
    if [ "$PLATFORM" = "linux" ]; then
        echo -e "  • Systemd user service: systemctl --user status termisol"
        echo -e "  • Auto-start enabled: systemctl --user is-enabled termisol-autostart"
    fi
    echo -e "  • Desktop file: $DESKTOP_DIR/termisol.desktop"
    echo -e "  • Binary location: $BINARY_PATH"
    echo
    echo -e "${BLUE}Enjoy your unbreakable terminal experience! 🚀${NC}"
    echo
}

# Parse command line arguments
BUILD_FROM_SOURCE="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --build-from-source)
            BUILD_FROM_SOURCE="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--build-from-source]"
            echo "  --build-from-source  Build from source instead of downloading release"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main installation flow
main() {
    print_header
    
    # Check if running as root for system-wide installation
    if [ "$EUID" -ne 0 ] && [ "$PLATFORM" = "linux" ]; then
        print_warning "Some operations require sudo privileges"
        echo "You may be prompted for your password..."
        echo
    fi
    
    check_dependencies
    detect_platform
    
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        build_from_source
    else
        download_latest_release
    fi
    
    install_binary
    install_desktop_integration
    install_systemd_service
    setup_permissions
    create_config_directories
    post_install_setup
    cleanup
    show_completion_message
}

# Error handling
trap 'print_error "Installation failed at line $LINENO"' ERR

# Run main function
main "$@"