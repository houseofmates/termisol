#!/bin/bash

# Termisol Build Script
# Handles snap environments and provides robust cross-platform building

set -e

echo "🔧 Termisol Build Script Starting..."

# Detect build environment
if [ "$FLUTTER_VERSION" = "snap" ]; then
    echo "📦 Detected Snap environment"
    export FLUTTER_ROOT="/snap/flutter/current"
    export LD_LIBRARY_PATH="$FLUTTER_ROOT/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
    export PATH="$FLUTTER_ROOT/usr/bin:$PATH"
    
    # Fix common snap build issues
    export CMAKE_PREFIX_DIR="$FLUTTER_ROOT"
    export CMAKE_INCLUDE_PATH="$FLUTTER_ROOT/usr/include"
    
    # Ensure proper permissions for snap
    if [ -w "/snap/flutter/current" ]; then
        echo "🔧 Fixing snap permissions..."
        sudo chown -R $USER:$USER "/snap/flutter/current"
    fi
    
    # Use system libraries for snap
    export SYSTEM_LIBS="/usr/lib/x86_64-linux-gnu"
    
elif command -v flutter >/dev/null 2>&1; then
    echo "📦 Flutter SDK detected"
    FLUTTER_VERSION=$(flutter --version | head -n1 | cut -d' ' -f2)
    echo "🔧 Flutter version: $FLUTTER_VERSION"
    
else
    echo "❌ Flutter not found. Please install Flutter SDK first."
    exit 1
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf build/
rm -rf .dart_tool/
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Determine build target
TARGET=${1:-linux}
BUILD_MODE=${2:-release}

echo "🎯 Building for $TARGET in $BUILD_MODE mode..."

# Create build directory structure
mkdir -p build/$TARGET
mkdir -p assets/profiles

# Build with proper error handling
if flutter build $TARGET --$BUILD_MODE --verbose; then
    echo "✅ Build successful for $TARGET"
    
    # Create release directory
    if [ "$BUILD_MODE" = "release" ]; then
        mkdir -p releases
        TIMESTAMP=$(date +"%Y%m%d_%H%M")
        
        # Copy build artifacts
        cp build/linux/x64/release/bundle/* releases/termisol-$TARGET-$TIMESTAMP/ 2>/dev/null || true
        
        # Create symbolic link for latest
        cd releases
        ln -sf termisol-$TARGET-$TIMESTAMP termisol-latest-$TARGET
        cd ..
        
        echo "📦 Release created: releases/termisol-latest-$TARGET/"
        echo "🔗 Build artifacts:"
        ls -la releases/termisol-latest-$TARGET/
        
        # Generate build info
        cat > releases/build-info-$TARGET.json << EOF
{
  "build_time": "$(date -Iseconds)",
  "flutter_version": "$FLUTTER_VERSION",
  "target": "$TARGET",
  "mode": "$BUILD_MODE",
  "git_commit": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
  "build_environment": "$(if [ "$FLUTTER_VERSION" = "snap" ]; then echo 'snap'; else echo 'native'; fi)"
}
EOF
        
        echo "📋 Build info saved to releases/build-info-$TARGET.json"
    fi
    
else
    echo "❌ Build failed for $TARGET"
    exit 1
fi

echo "🎉 Build script completed!"
