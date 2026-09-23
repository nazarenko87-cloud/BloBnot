#!/usr/bin/env bash
# Packages a `flutter build linux --release` bundle as a .deb and an AppImage.
#
#   linux/packaging/build-packages.sh <version> <output-dir>
#
# Run from the repository root, on Linux, after the Flutter build. Needs
# dpkg-deb (any Debian/Ubuntu) and downloads appimagetool on first use.
set -euo pipefail

VERSION="${1:?usage: build-packages.sh <version> <output-dir>}"
OUT="${2:?usage: build-packages.sh <version> <output-dir>}"
APP_ID="dev.bloknot.blobnot"
BUNDLE="build/linux/x64/release/bundle"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ICON="$ROOT/assets/icon.png"
SYNC_SCRIPT="$ROOT/linux/rclone/blobnot-sync-setup.sh"

[[ -x "$ROOT/$BUNDLE/blobnot" ]] || {
  echo "No Linux build at $BUNDLE — run 'flutter build linux --release' first." >&2
  exit 1
}
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Debian versions must start with a digit; "2.5" becomes "2.5.0".
DEB_VERSION="$VERSION"
if [[ "$DEB_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  DEB_VERSION="$DEB_VERSION.0"
fi

# ---------- .deb ----------
DEB="$WORK/deb"
mkdir -p "$DEB/DEBIAN" "$DEB/opt/blobnot" "$DEB/usr/bin" \
  "$DEB/usr/share/applications" "$DEB/usr/share/icons/hicolor/512x512/apps"
cp -a "$ROOT/$BUNDLE/." "$DEB/opt/blobnot/"
ln -s /opt/blobnot/blobnot "$DEB/usr/bin/blobnot"
install -m 0755 "$SYNC_SCRIPT" "$DEB/usr/bin/blobnot-sync-setup"
install -m 0644 "$HERE/$APP_ID.desktop" "$DEB/usr/share/applications/$APP_ID.desktop"
install -m 0644 "$ICON" "$DEB/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

INSTALLED_KB="$(du -sk "$DEB" | cut -f1)"
cat > "$DEB/DEBIAN/control" <<EOF
Package: blobnot
Version: $DEB_VERSION
Section: editors
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0, libstdc++6
Recommends: rclone
Maintainer: Andrii Nazarenko <nazarenko87@gmail.com>
Homepage: https://github.com/nazarenko87-cloud/BloBnot
Description: Markdown notes with wiki links, a graph and hot tasks
 BloBnot keeps notes as plain Markdown files in a folder you choose,
 with [[wiki links]], a knowledge graph, reminders, hot tasks and a
 table of note fields. blobnot-sync-setup syncs the folder with Google
 Drive through rclone.
EOF

# Refresh the menu and icon caches so the app shows up straight away.
cat > "$DEB/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null; then
  update-desktop-database -q || true
fi
if command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
EOF
cp "$DEB/DEBIAN/postinst" "$DEB/DEBIAN/postrm"
chmod 0755 "$DEB/DEBIAN/postinst" "$DEB/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "$DEB" "$OUT/BloBnot-$VERSION-amd64.deb"

# ---------- AppImage ----------
APPDIR="$WORK/BloBnot.AppDir"
mkdir -p "$APPDIR/usr/bin"
cp -a "$ROOT/$BUNDLE/." "$APPDIR/usr/bin/"
install -m 0755 "$SYNC_SCRIPT" "$APPDIR/usr/bin/blobnot-sync-setup"
install -m 0644 "$HERE/$APP_ID.desktop" "$APPDIR/$APP_ID.desktop"
install -m 0644 "$ICON" "$APPDIR/$APP_ID.png"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/blobnot" "$@"
EOF
chmod 0755 "$APPDIR/AppRun"

TOOL="$WORK/appimagetool"
curl -fsSL -o "$TOOL" \
  https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x "$TOOL"
# Extract-and-run: CI runners have no FUSE.
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "$TOOL" --no-appstream \
  "$APPDIR" "$OUT/BloBnot-$VERSION-x86_64.AppImage"

# The sync script on its own too, for AppImage users.
install -m 0755 "$SYNC_SCRIPT" "$OUT/blobnot-sync-setup.sh"

ls -l "$OUT"
