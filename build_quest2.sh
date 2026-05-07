#!/bin/bash

# Termisol Quest 2 VR Build Script
# Builds APK specifically for Meta Quest 2 VR headset

set -e

echo "🎯 Building Termisol for Meta Quest 2..."

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter SDK."
    exit 1
fi

# Check if Android SDK is available
if [ -z "$ANDROID_SDK_ROOT" ] && [ -z "$ANDROID_HOME" ]; then
    echo "❌ Android SDK not found. Please set ANDROID_SDK_ROOT or ANDROID_HOME."
    exit 1
fi

echo "🔧 Configuring for Quest 2..."

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build for Quest 2 (ARM64, landscape, VR mode)
echo "🏗️ Building APK for Quest 2..."
flutter build apk \
    --target-platform android-arm64 \
    --release \
    --build-name=1.0.0 \
    --build-number=1 \
    --dart-define=VR_MODE=true \
    --dart-define=QUEST_BUILD=true

if [ $? -eq 0 ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$APK_PATH" ]; then
        echo "✅ Quest 2 APK built successfully!"
        echo "📱 APK location: $APK_PATH"
        echo ""
        echo "📋 Installation instructions:"
        echo "1. Connect Quest 2 to your computer via USB"
        echo "2. Enable Developer Mode in Quest settings"
        echo "3. Run: adb install -r $APK_PATH"
        echo "4. Launch Termisol from Unknown Sources in Quest Library"
        echo ""
        echo "🎮 VR Features enabled:"
        echo "  • Stereoscopic 3D rendering"
        echo "  • Hand tracking gestures"
        echo "  • Gaze-based cursor"
        echo "  • Haptic feedback"
        echo "  • Comfortable viewing distance"
    else
        echo "❌ APK not found at expected location"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi