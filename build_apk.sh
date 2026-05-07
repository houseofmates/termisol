#!/bin/bash
# build apks for android (mobile) and meta quest 2 (vr)
set -e

VERSION="1.0.0"

echo "[build] building termisol apks..."

mkdir -p releases
flutter clean

# mobile apk for pixel 10 pro and general android
echo "[build] mobile apk..."
flutter build apk --release --target-platform android-arm64

cp "build/app/outputs/flutter-apk/app-release.apk" "releases/termisol-mobile-${VERSION}.apk"

# vr apk for meta quest 2
echo "[build] vr apk..."
flutter build apk --release --target-platform android-arm64 --dart-define=IS_VR_BUILD=true

cp "build/app/outputs/flutter-apk/app-release.apk" "releases/termisol-vr-${VERSION}.apk"

# build info
cat > releases/build-info.json <<EOF
{
  "version": "$VERSION",
  "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mobile_apk": "termisol-mobile-$VERSION.apk",
  "vr_apk": "termisol-vr-$VERSION.apk",
  "mobile_features": [
    "gpu acceleration",
    "ai assistant",
    "hardware-accelerated rendering",
    "sub-16ms frame times"
  ],
  "vr_features": [
    "gpu acceleration",
    "ai assistant",
    "vr-optimized ui",
    "hand tracking ready"
  ],
  "supported_devices": {
    "mobile": ["google pixel 10 pro", "android 10+ devices"],
    "vr": ["meta quest 2", "meta quest pro", "meta quest 3"]
  }
}
EOF

echo "[build] complete."
echo "  mobile: releases/termisol-mobile-${VERSION}.apk"
echo "  vr:     releases/termisol-vr-${VERSION}.apk"
ls -lh releases/*.apk
