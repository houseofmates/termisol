#!/bin/bash
# build .deb package for termisol linux desktop
set -e

VERSION="1.0.0"
ARCH="amd64"
PKG_NAME="termisol"
PKG_DIR="/tmp/termisol-deb"
BUNDLE="build/linux/x64/release/bundle"

echo "[build] building .deb for ${PKG_NAME}_${VERSION}_${ARCH}"

# build release
flutter build linux --release

# clean package dir
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/lib/${PKG_NAME}"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"

# control file with comprehensive dependencies
cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libglib2.0-0, libfontconfig1, libepoxy0, libharfbuzz0b, libpango-1.0-0, libcairo2, libgdk-pixbuf-2.0-0, libegl1, libgl1-mesa-dri
Maintainer: termisol <maintainer@termisol.dev>
Description: gpu-accelerated cross-platform terminal emulator
 termisol is a config-driven terminal emulator with ai assistance,
 hardware acceleration, and sub-16ms rendering performance.
EOF

# postinst: update desktop database and icon cache after install
cat > "$PKG_DIR/DEBIAN/postinst" <<'POSTINST'
#!/bin/bash
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache /usr/share/icons/hicolor/ || true
fi
exit 0
POSTINST
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# prerm: clean up desktop database on remove
cat > "$PKG_DIR/DEBIAN/prerm" <<'PRERM'
#!/bin/bash
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
exit 0
PRERM
chmod 755 "$PKG_DIR/DEBIAN/prerm"

# copy bundle to standard lib path
cp -r "$BUNDLE"/* "$PKG_DIR/usr/lib/${PKG_NAME}/"

# wrapper script in /usr/bin
cat > "$PKG_DIR/usr/bin/termisol" <<'WRAPPER'
#!/bin/bash
set -u

_have_display() {
    [ -n "${DISPLAY:-}" ] && return 0
    [ -n "${WAYLAND_DISPLAY:-}" ] && return 0
    # xdg-desktop-portal / snapcraft may clear DISPLAY/WAYLAND_DISPLAY.
    # loginctl -> seat0 -> first session -> Display=
    local sess display
    sess=$(loginctl show-seat seat0 -p Sessions 2>/dev/null | cut -d= -f2)
    [ -z "$sess" ] && return 1
    display=$(loginctl show-session "$sess" -p Display 2>/dev/null | cut -d= -f2)
    [ -n "$display" ] && export DISPLAY="$display" && return 0
    return 1
}

if ! _have_display; then
    echo "error: no display detected. termisol requires a graphical session."
    echo "       install with: sudo dpkg -i termisol.deb"
    echo "       then launch from your applications menu or run: termisol"
    exit 1
fi

_find_swrast() {
    for path in \
        /usr/lib/x86_64-linux-gnu/dri/llvmpipe_dri.so \
        /usr/lib/x86_64-linux-gnu/dri/swrast_dri.so \
        /usr/lib/dri/llvmpipe_dri.so \
        /usr/lib/dri/swrast_dri.so \
        /usr/lib64/dri/llvmpipe_dri.so \
        /usr/lib64/dri/swrast_dri.so
    do
        if [ -f "$path" ]; then
            basename "$path" .so | sed 's/_dri//'
            return 0
        fi
    done
    return 1
}

(set +m; /usr/lib/termisol/termisol "$@" 2>/tmp/termisol-error.log)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    swrast=$(_find_swrast)
    if [ -n "$swrast" ]; then
        [ -t 1 ] && echo "[termisol] hardware rendering failed. using mesa software rendering ($swrast)..."
        export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
        export __GLX_VENDOR_LIBRARY_NAME=mesa
        export LIBGL_ALWAYS_SOFTWARE=1
        export MESA_LOADER_DRIVER_OVERRIDE=$swrast
        export GDK_GL=gles
        exec /usr/lib/termisol/termisol "$@"
    else
        [ -t 1 ] && echo "error: termisol requires opengl. no software rasterizer found."
        [ -t 1 ] && echo "       try: sudo apt-get install libgl1-mesa-dri"
        exit $exit_code
    fi
fi
WRAPPER'
#!/bin/bash
chmod +x "$PKG_DIR/usr/bin/termisol"

# desktop entry
cat > "$PKG_DIR/usr/share/applications/termisol.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=termisol
Comment=gpu-accelerated terminal emulator
Exec=/usr/bin/termisol
Icon=termisol
Terminal=false
Categories=System;TerminalEmulator;
StartupWMClass=com.termisol
EOF

# icon placeholder
ICON_SRC="assets/icons/termisol.png"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/termisol.png"
else
  if command -v convert &> /dev/null; then
    convert -size 256x256 xc:"#f6b012" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/termisol.png"
  fi
fi

# permissions
find "$PKG_DIR" -type d -exec chmod 755 {} \;
find "$PKG_DIR" -type f -exec chmod 644 {} \;
chmod 755 "$PKG_DIR/usr/bin/termisol"
chmod 755 "$PKG_DIR/usr/lib/${PKG_NAME}/termisol"
chmod 755 "$PKG_DIR/DEBIAN/postinst"
chmod 755 "$PKG_DIR/DEBIAN/prerm"

# build package
mkdir -p releases
dpkg-deb --build "$PKG_DIR" "releases/termisol_${VERSION}_${ARCH}.deb"

echo "[build] done: releases/termisol_${VERSION}_${ARCH}.deb"
echo ""
echo "install:   sudo dpkg -i releases/termisol_${VERSION}_${ARCH}.deb"
echo "           sudo apt-get install -f   # if any dependencies are missing"
echo "launch:    termisol"
echo ""
ls -lh "releases/termisol_${VERSION}_${ARCH}.deb"
