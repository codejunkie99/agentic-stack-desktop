#!/usr/bin/env bash
# Install the verified Agentic Stack preview without requiring administrator access.
set -euo pipefail

RELEASE_TAG="v0.19.1-desktop-preview.11"
ASSET_NAME="Agentic-Stack-macOS-arm64.dmg"
EXPECTED_SHA256="18b1eb854d8cc5fcac08c4d6b41ad562b55a5e46306a800099fe87a9a33ae190"
DOWNLOAD_URL="https://github.com/codejunkie99/agentic-stack-desktop/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
INSTALL_DIR="${AGENTIC_STACK_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/Agentic Stack.app"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Agentic Stack Desktop requires macOS." >&2
  exit 1
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "This preview supports Apple Silicon Macs only." >&2
  exit 1
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 14 ]; then
  echo "Agentic Stack Desktop requires macOS 14 or later." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentic-stack-install.XXXXXX")"
MOUNT_DIR="$WORK_DIR/mount"
DMG_PATH="$WORK_DIR/$ASSET_NAME"
STAGED_APP="$INSTALL_DIR/.Agentic Stack.installing.$$.app"
MOUNTED=false

cleanup() {
  if [ "$MOUNTED" = true ]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR" "$STAGED_APP"
}
trap cleanup EXIT INT TERM

echo "Downloading Agentic Stack ${RELEASE_TAG}…"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  --output "$DMG_PATH" "$DOWNLOAD_URL"

ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "Download verification failed. The app was not installed." >&2
  exit 1
fi
echo "Verified SHA-256: $ACTUAL_SHA256"

mkdir -p "$MOUNT_DIR" "$INSTALL_DIR"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -readonly >/dev/null
MOUNTED=true

SOURCE_APP="$MOUNT_DIR/Agentic Stack.app"
if [ ! -d "$SOURCE_APP" ]; then
  echo "The release does not contain Agentic Stack.app." >&2
  exit 1
fi

ditto "$SOURCE_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

# curl does not normally add quarantine metadata. Clear it only after the
# published archive hash and the copied bundle signature have both verified.
xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

if [ -e "$TARGET_APP" ]; then
  BACKUP_APP="$INSTALL_DIR/Agentic Stack.previous-$(date +%s).app"
  mv "$TARGET_APP" "$BACKUP_APP"
  echo "Previous app saved as: $BACKUP_APP"
fi
mv "$STAGED_APP" "$TARGET_APP"

echo "Installed: $TARGET_APP"
if [ "${AGENTIC_STACK_SKIP_LAUNCH:-0}" != "1" ]; then
  open "$TARGET_APP"
fi
