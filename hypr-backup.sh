#!/usr/bin/env bash
# =============================================================================
# hypr-backup.sh — Hyprland Dotfiles Backup Script
# =============================================================================
#
# Working directory:
#   This script is designed to live inside ~/HyprBackup/.
#   All output archives are stored in that same directory — relative to where
#   this script is located, NOT in $HOME. This keeps everything self-contained:
#
#     ~/HyprBackup/
#       hypr-backup.sh               ← this script
#       hypr-restore.sh              ← companion restore script
#       hypr-dotfiles-2026-04-25.tar.gz   ← archives created here
#       hypr-dotfiles-2026-04-20.tar.gz
#       ...
#
# First-time setup (run once):
#   mkdir -p ~/HyprBackup
#   mv hypr-backup.sh hypr-restore.sh ~/HyprBackup/
#   chmod +x ~/HyprBackup/hypr-backup.sh ~/HyprBackup/hypr-restore.sh
#
# Usage (from any directory — the script resolves its own location):
#   ~/HyprBackup/hypr-backup.sh
#
# Alias for one-word backups (add to ~/.bashrc or ~/.zshrc):
#   alias hbk='bash ~/HyprBackup/hypr-backup.sh'
#
# Requirements:
#   - Run as your regular user (NOT root)
#   - hypr-restore.sh must be in the same ~/HyprBackup/ directory
#   - dnf must be available (Fedora)
# =============================================================================

set -e  # Exit immediately if any command returns a non-zero exit code

# =============================================================================
# WORKING DIRECTORY — Resolve the script's own location
# =============================================================================
# SELF    = absolute path of this script (resolves symlinks via realpath)
# WORK_DIR = the directory this script lives in (~/HyprBackup/ by convention)
#
# Using WORK_DIR as the output destination means archives are always stored
# next to the scripts — regardless of which directory you call the script from.
SELF="$(realpath "$0")"
WORK_DIR="$(dirname "$SELF")"

# Companion restore script — expected in the same WORK_DIR
RESTORE_SCRIPT="$WORK_DIR/hypr-restore.sh"

# ── Timestamp & naming ────────────────────────────────────────────────────────
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
BACKUP_NAME="hypr-dotfiles-$TIMESTAMP"
BACKUP_DIR="/tmp/$BACKUP_NAME"          # Temporary staging area (always in /tmp)
OUTPUT="$WORK_DIR/$BACKUP_NAME.tar.gz"  # ← Archive stored in WORK_DIR, not $HOME

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Hyprland Dotfiles Backup — Starting           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  📂 Working directory : $WORK_DIR"
echo "  📦 Output archive    : $OUTPUT"
echo ""

# =============================================================================
# SECTION 1 — Create temporary staging directory
# =============================================================================
# All files are assembled here first, then compressed into the final archive.
# Using /tmp ensures we have write access and it gets cleaned on reboot anyway.
mkdir -p "$BACKUP_DIR"

# =============================================================================
# SECTION 2 — Backup ~/.config directories
# =============================================================================
# Copies each Hyprland-related config folder. Silently skips any folder
# that does not exist on this machine (e.g., if you don't use Kitty).
echo "📁 Backing up config directories..."

CONFIG_DIRS=(
    "hypr"          # hyprland.conf, hyprpaper.conf, hyprlock.conf, hypridle.conf
    "waybar"        # config (JSON) + style.css
    "wofi"          # config + style.css
    "rofi"          # ← replaces wofi (you use Rofi on this machine)
    "mako"          # ← replaces dunst (notification daemon)
    "dunst"         # dunstrc (notification daemon)
    "kitty"         # kitty.conf (terminal emulator)
    "gtk-3.0"       # GTK3 theme — affects XWayland app appearance
    "gtk-4.0"       # GTK4 theme — affects modern apps
    "nwg-look"      # Wayland GTK theme/icon/font settings
    "nwg-panel"     # nwg-panel layout and config
    "nwg-displays"  # monitor/display layout
    "fastfetch"     # system fetch config
    "mpv"           # media player config
    "Thunar"        # file manager config and custom actions (capital T)
    "xsettingsd"    # forces GTK theme into XWayland apps
)

mkdir -p "$BACKUP_DIR/.config"
for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$HOME/.config/$dir" ]; then
        cp -r "$HOME/.config/$dir" "$BACKUP_DIR/.config/"
        echo "  ✔  ~/.config/$dir"
    else
        echo "  ⚠  ~/.config/$dir not found — skipping"
    fi
done

# =============================================================================
# SECTION 3 — Backup user-installed fonts
# =============================================================================
# Backs up only fonts in ~/.local/share/fonts (e.g., Nerd Fonts downloaded
# manually). Does NOT touch system fonts in /usr/share/fonts.
echo ""
echo "🔤 Backing up user fonts..."

if [ -d "$HOME/.local/share/fonts" ]; then
    mkdir -p "$BACKUP_DIR/.local/share"
    cp -r "$HOME/.local/share/fonts" "$BACKUP_DIR/.local/share/"
    echo "  ✔  ~/.local/share/fonts"
else
    echo "  ⚠  ~/.local/share/fonts not found — skipping"
fi

# =============================================================================
# SECTION 4 — Backup wallpapers
# =============================================================================
# Backs up ~/Pictures/wallpapers. If you store wallpapers in a different
# location, update this path before running.
echo ""
echo "🖼  Backing up wallpapers..."

if [ -d "$HOME/Pictures/Wallpapers" ]; then
    mkdir -p "$BACKUP_DIR/Pictures"
    cp -r "$HOME/Pictures/Wallpapers" "$BACKUP_DIR/Pictures/"
    echo "  ✔  ~/Pictures/Wallpapers"
else
    echo "  ⚠  ~/Pictures/Wallpapers not found — skipping"
fi

# =============================================================================
# SECTION 5 — Export Fedora package list + Hyprland version stamp
# =============================================================================
# Saves Hyprland ecosystem packages installed on this machine and stamps the
# exact Hyprland version so the restore script can warn about version mismatches.
echo ""
echo "📦 Exporting package list..."

PKGFILE="$BACKUP_DIR/hypr-packages.txt"

# Filter only Hyprland-related packages — not the full system package list.
# awk '{print $1}' strips the version and repo columns, keeping only names.
dnf list --installed 2>/dev/null \
    | grep -E "hyprland|waybar|rofi|wofi|mako|dunst|hyprpaper|hyprlock|hypridle|kitty|playerctl|cliphist|grimblast|brightnessctl|polkit-gnome|wl-clipboard|nwg-look|nwg-panel|nwg-displays|fastfetch|mpv|thunar" \
    | awk '{print $1}' > "$PKGFILE"

# Append the Hyprland version as a comment (# prefix so dnf install skips it).
if command -v hyprctl &>/dev/null; then
    HYPR_VERSION=$(hyprctl version 2>/dev/null | head -1 || echo "unknown")
    echo "# HYPRLAND_VERSION: $HYPR_VERSION" >> "$PKGFILE"
    echo "  ✔  Package list saved (Hyprland: $HYPR_VERSION)"
else
    echo "  ⚠  hyprctl not found — Hyprland version not recorded"
    echo "  ✔  Package list saved (version unknown)"
fi

# =============================================================================
# SECTION 6 — Write a README inside the archive
# =============================================================================
# This README is the first thing visible after extracting the archive.
# It documents the contents and provides exact restore instructions.
echo ""
echo "📝 Writing README.txt..."

cat > "$BACKUP_DIR/README.txt" << 'EOF'
╔══════════════════════════════════════════════════════╗
║              Hyprland Dotfiles Backup                ║
╚══════════════════════════════════════════════════════╝

ARCHIVE CONTENTS:
  .config/hypr/          → hyprland.conf, hyprpaper.conf, hyprlock.conf, hypridle.conf
  .config/waybar/        → Waybar config (JSON) + style.css
  .config/wofi/          → Wofi config + style.css
  .config/dunst/         → Dunst notification daemon config (dunstrc)
  .config/kitty/         → Kitty terminal config
  .local/share/fonts/    → User-installed Nerd Fonts
  Pictures/wallpapers/   → Wallpaper image files
  hypr-packages.txt      → Fedora package list + Hyprland version stamp
  hypr-restore.sh        → Quick-access restore script (run this!)
  scripts/
    hypr-backup.sh       → Backup script (reinstalls to ~/HyprBackup/)
    hypr-restore.sh      → Restore script (reinstalls to ~/HyprBackup/)

══════════════════════════════════════════════════════════
HOW TO RESTORE ON A NEW MACHINE:

  Step 1 — Install Hyprland on Fedora:
    sudo dnf install hyprland -y

  Step 2 — Extract the archive:
    tar -xzf hypr-dotfiles-*.tar.gz

  Step 3 — Run the restore script inside the extracted folder:
    chmod +x hypr-dotfiles-*/hypr-restore.sh
    ./hypr-dotfiles-*/hypr-restore.sh

The restore script handles everything:
  - Backs up your existing configs before overwriting
  - Restores configs, fonts, and wallpapers
  - Warns about Hyprland version mismatches
  - Reinstalls ~/HyprBackup/ with both scripts ready for reuse
  - Optionally reinstalls all Hyprland ecosystem packages

══════════════════════════════════════════════════════════
EOF

echo "  ✔  README.txt written"

# =============================================================================
# SECTION 7 — Bundle both scripts inside the archive
# =============================================================================
# Both scripts travel INSIDE the archive so they are always available on a
# new machine after extraction — no need to copy them separately.
#
# Layout inside the archive:
#   scripts/hypr-backup.sh   → reinstalled to ~/HyprBackup/ by the restore script
#   scripts/hypr-restore.sh  → reinstalled to ~/HyprBackup/ by the restore script
#   hypr-restore.sh          → root-level copy for immediate access after extraction
echo ""
echo "📎 Bundling scripts into archive..."

mkdir -p "$BACKUP_DIR/scripts"

# Bundle this script using SELF (resolved absolute path)
cp "$SELF" "$BACKUP_DIR/scripts/hypr-backup.sh"
chmod +x "$BACKUP_DIR/scripts/hypr-backup.sh"
echo "  ✔  hypr-backup.sh → scripts/"

if [ -f "$RESTORE_SCRIPT" ]; then
    # Canonical versioned copy inside scripts/
    cp "$RESTORE_SCRIPT" "$BACKUP_DIR/scripts/hypr-restore.sh"
    chmod +x "$BACKUP_DIR/scripts/hypr-restore.sh"

    # Root-level copy for quick access right after tar extraction
    cp "$RESTORE_SCRIPT" "$BACKUP_DIR/hypr-restore.sh"
    chmod +x "$BACKUP_DIR/hypr-restore.sh"

    echo "  ✔  hypr-restore.sh → scripts/ + archive root"
else
    echo "  ⚠  hypr-restore.sh not found at: $RESTORE_SCRIPT"
    echo "     Place both scripts in the same directory (~/HyprBackup/) and re-run."
fi

# =============================================================================
# SECTION 8 — Compress the staging directory into a .tar.gz archive
# =============================================================================
# -c  → create new archive
# -z  → compress with gzip
# -f  → write to OUTPUT (inside WORK_DIR, not $HOME)
# -C  → change to /tmp before archiving so internal paths start at BACKUP_NAME/
echo ""
echo "🗜  Compressing archive..."

tar -czf "$OUTPUT" -C "/tmp" "$BACKUP_NAME"

# Clean up the temporary staging directory now that the archive is ready
rm -rf "$BACKUP_DIR"

# =============================================================================
# DONE
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                  Backup Complete! ✅                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  📁 Archive  : $OUTPUT"
echo "  📏 Size     : $(du -sh "$OUTPUT" | cut -f1)"
echo "  📂 Location : $WORK_DIR"
echo ""
echo "  To restore on any machine:"
echo "  tar -xzf $BACKUP_NAME.tar.gz && ./$BACKUP_NAME/hypr-restore.sh"
echo ""
echo "  Tip: add to ~/.bashrc for one-word backups:"
echo "  alias hbk='bash ~/HyprBackup/hypr-backup.sh'"
echo ""
