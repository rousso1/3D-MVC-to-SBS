#!/bin/bash
set -euo pipefail

# MVC-to-SBS macOS Setup Script
# Installs all dependencies for converting MVC 3D Blu-ray MKVs to SBS format.
# Works on both Intel and Apple Silicon Macs. Idempotent — safe to run multiple times.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"
FRIM_DIR="$TOOLS_DIR/FRIMDecode64"
WINEPREFIX_DIR="$TOOLS_DIR/wineprefix"

echo "=== MVC-to-SBS macOS Setup ==="
echo ""

# Step 1: Rosetta 2 (Apple Silicon only)
if [ "$(uname -m)" = "arm64" ]; then
  if /usr/bin/pgrep -q oahd 2>/dev/null; then
    echo "[1/5] Rosetta 2 already installed, skipping..."
  else
    echo "[1/5] Installing Rosetta 2..."
    softwareupdate --install-rosetta --agree-to-license 2>&1 || true
  fi
else
  echo "[1/5] Intel Mac detected, Rosetta 2 not needed."
fi
echo ""

# Step 2: Homebrew
if command -v brew &>/dev/null; then
  echo "[2/5] Homebrew already installed, skipping..."
else
  echo "[2/5] Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo ""

# Step 3: Wine, mkvtoolnix, ffmpeg
echo "[3/5] Installing/updating Homebrew packages..."

if ! brew tap | grep -q "gcenx/wine"; then
  echo "  Adding gcenx/wine tap..."
  brew tap gcenx/wine
else
  echo "  gcenx/wine tap already added."
fi

if brew list --cask wine-crossover &>/dev/null; then
  echo "  wine-crossover already installed."
else
  echo "  Installing wine-crossover..."
  brew install --cask --no-quarantine gcenx/wine/wine-crossover
fi

for pkg in mkvtoolnix ffmpeg; do
  if brew list "$pkg" &>/dev/null; then
    echo "  $pkg already installed."
  else
    echo "  Installing $pkg..."
    brew install "$pkg"
  fi
done
echo ""

# Step 4: FRIMDecode64
if [ -f "$FRIM_DIR/x64/FRIMDecode64.exe" ]; then
  echo "[4/5] FRIMDecode64 already downloaded, skipping..."
else
  echo "[4/5] Downloading FRIMDecode64 v1.29..."
  mkdir -p "$TOOLS_DIR"
  curl -L 'https://www.videohelp.com/download/FRIM_x64_version_1.29.zip' \
    -H 'Referer: https://www.videohelp.com/software/FRIM/old-versions' \
    -o "$TOOLS_DIR/FRIM_x64.zip"
  unzip -o "$TOOLS_DIR/FRIM_x64.zip" -d "$FRIM_DIR"
  rm "$TOOLS_DIR/FRIM_x64.zip"
fi
echo ""

# Step 5: Initialize Wine prefix
if [ -d "$WINEPREFIX_DIR/drive_c" ]; then
  echo "[5/5] Wine prefix already initialized, skipping..."
else
  echo "[5/5] Initializing Wine prefix..."
  WINEDEBUG=-all WINEPREFIX="$WINEPREFIX_DIR" wineboot -u
fi
echo ""

# Verify
echo "=== Verification ==="
echo -n "  wine64:       " && WINEDEBUG=-all wine64 --version
echo -n "  ffmpeg:       " && ffmpeg -version 2>&1 | head -1
echo -n "  mkvextract:   " && mkvextract --version 2>&1 | head -1
echo -n "  FRIMDecode64: "
WINEDEBUG=-all WINEPREFIX="$WINEPREFIX_DIR" wine64 "$FRIM_DIR/x64/FRIMDecode64.exe" 2>&1 | head -1 || true
echo ""
echo "=== Setup complete! ==="
echo "Run: ./convert.sh input.mkv output.mkv"
