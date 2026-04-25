#!/usr/bin/env bash
# =============================================================================
# hypr-restore.sh — Hyprland Dotfiles Restore Script
# =============================================================================
#
# Working directory:
#   After restoring, both scripts are reinstalled to ~/HyprBackup/ on the
#   target machine, mirroring the source machine's layout:
#
#     ~/HyprBackup/
#       hypr-backup.sh       ← ready for future backups immediately
#       hypr-restore.sh      ← this script
#       hypr-dotfiles-*.tar.gz   ← any archives stored here going forward
#
# Invocation modes:
#   Mode A — pass the archive path:
#     ./hypr-restore.sh ~/HyprBackup/hypr-dotfiles-2026-04-25.tar.gz
#
#   Mode B — run from inside the already-extracted archive folder:
#     ./hypr-restore.sh
#
# Safety features (in execution order):
#   1. Hyprland version mismatch warning — asks before proceeding
#   2. Full safety backup of existing configs before overwriting anything
#   3. Config / font / wallpaper restore
#   4. Scripts reinstalled to ~/HyprBackup/ for immediate reuse
#   5. Optional guarded package reinstall (safe on dirty machines)
#
# Requirements:
#   - Run as your regular user (NOT root). sudo is only used for dnf commands.
# =============================================================================

set -e  # Exit immediately if any command returns a non-zero exit code

# =============================================================================
# INSTALL DIRECTORY — where scripts are reinstalled on the target machine
# =============================================================================
# On the source machine, scripts live in ~/HyprBackup/.
# After restoring, the same layout is recreated on the target machine so
# the hbk alias and future backups work without any extra setup.
INSTALL_DIR="$HOME/HyprBackup"

# =============================================================================
# SECTION 1 — Determine source directory (archive or extracted folder)
# =============================================================================
EXTRACT_DIR=""  # Tracked for cleanup in Section 9 — empty if Mode B

if [ -n "$1" ] && [ -f "$1" ]; then
    # ── Mode A: an archive path was passed as an argument ─────────────────────
    ARCHIVE="$(realpath "$1")"           # Resolve to clean absolute path
    EXTRACT_DIR="/tmp/hypr-restore-$$"  # $$ = current PID, guarantees uniqueness
    mkdir -p "$EXTRACT_DIR"
    echo ""
    echo "📂 Extracting archive: $(basename "$ARCHIVE")..."
    # --strip-components=1 removes the top-level archive folder so that
    # $EXTRACT_DIR IS the archive root (avoids a nested subfolder)
    tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" --strip-components=1
    SOURCE_DIR="$EXTRACT_DIR"

elif [ -n "$1" ] && [ ! -f "$1" ]; then
    # ── Error: argument given but the file doesn't exist ──────────────────────
    echo ""
    echo "❌ File not found: $1"
    echo "   Usage: $0 [/path/to/hypr-dotfiles-*.tar.gz]"
    exit 1

else
    # ── Mode B: no argument — script is already inside the extracted folder ───
    # cd + pwd resolves any symlinks or relative path references cleanly
    SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
    echo ""
    echo "📂 Source directory: $SOURCE_DIR"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       Hyprland Dotfiles Restore — Starting           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  📂 Scripts will be reinstalled to : $INSTALL_DIR"
echo ""

# Convenience variable for the package list inside the archive
PKGFILE="$SOURCE_DIR/hypr-packages.txt"

# =============================================================================
# SECTION 2 — Hyprland version compatibility check
# =============================================================================
# The backup script stamps the running Hyprland version into hypr-packages.txt
# as a comment line:  # HYPRLAND_VERSION: Hyprland vX.XX.X ...
#
# If the backup and target machines run different Hyprland versions, some
# config keys may no longer be valid (syntax has changed across versions).
# This section warns and lets the user abort before any file is touched.
echo "🔍 Checking Hyprland version compatibility..."

if [ -f "$PKGFILE" ]; then
    BACKED_VERSION=$(grep "^# HYPRLAND_VERSION:" "$PKGFILE" 2>/dev/null \
        | sed 's/^# HYPRLAND_VERSION: //' || echo "")
    CURRENT_VERSION=$(hyprctl version 2>/dev/null | head -1 || echo "")

    if [ -n "$BACKED_VERSION" ] && [ -n "$CURRENT_VERSION" ]; then
        if [ "$BACKED_VERSION" != "$CURRENT_VERSION" ]; then
            echo ""
            echo "  ⚠  VERSION MISMATCH DETECTED"
            echo "     Backup was made on : $BACKED_VERSION"
            echo "     This machine runs  : $CURRENT_VERSION"
            echo ""
            echo "     Config syntax may differ between versions."
            echo "     Your existing configs will be saved before overwriting."
            echo ""
            echo "     Continue anyway? (y/N)"
            read -r REPLY
            if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
                echo ""
                echo "  Aborted. No files have been changed."
                [ -n "$EXTRACT_DIR" ] && rm -rf "$EXTRACT_DIR"
                exit 0
            fi
        else
            echo "  ✔  Version match: $CURRENT_VERSION"
        fi
    else
        echo "  ℹ  Could not fully compare versions — proceeding"
    fi
else
    echo "  ℹ  No hypr-packages.txt found — skipping version check"
fi

# =============================================================================
# SECTION 3 — Safety backup of all existing configs
# =============================================================================
# Before overwriting ANYTHING, every relevant existing config folder is copied
# to a timestamped directory. The restore is always fully reversible.
#
# Pattern: ~/.config-backup-before-restore-YYYYMMDDHHMM/
echo ""
echo "🛡  Creating safety backup of existing configs..."

SAFETY_BACKUP="$HOME/.config-backup-before-restore-$(date +%Y%m%d%H%M)"
mkdir -p "$SAFETY_BACKUP"

for dir in hypr waybar wofi dunst kitty; do
    if [ -d "$HOME/.config/$dir" ]; then
        cp -r "$HOME/.config/$dir" "$SAFETY_BACKUP/"
        echo "  ✔  ~/.config/$dir → $SAFETY_BACKUP/"
    fi
done

# Clean up empty safety backup folder on a fresh machine (nothing to save)
if [ -z "$(ls -A "$SAFETY_BACKUP" 2>/dev/null)" ]; then
    echo "  ℹ  No existing configs found — this appears to be a fresh machine"
    rmdir "$SAFETY_BACKUP"
    SAFETY_BACKUP="(none — fresh machine)"
fi

# =============================================================================
# SECTION 4 — Restore ~/.config directories
# =============================================================================
# The trailing /. after SOURCE_DIR/.config copies the CONTENTS of .config
# into ~/.config, preventing a nested ~/.config/.config/ from being created.
echo ""
echo "📁 Restoring config directories..."

if [ -d "$SOURCE_DIR/.config" ]; then
    cp -r "$SOURCE_DIR/.config/." "$HOME/.config/"
    echo "  ✔  All entries restored to ~/.config/"
else
    echo "  ⚠  No .config/ directory in archive — skipping"
fi

# =============================================================================
# SECTION 5 — Restore user-installed fonts
# =============================================================================
# Restores fonts to ~/.local/share/fonts and immediately rebuilds the font
# cache (fc-cache) so restored fonts are available to all applications.
echo ""
echo "🔤 Restoring fonts..."

if [ -d "$SOURCE_DIR/.local/share/fonts" ]; then
    mkdir -p "$HOME/.local/share/fonts"
    cp -r "$SOURCE_DIR/.local/share/fonts/." "$HOME/.local/share/fonts/"
    fc-cache -fv > /dev/null 2>&1  # -f = force rescan, output suppressed
    echo "  ✔  Fonts restored and font cache rebuilt"
else
    echo "  ⚠  No fonts directory in archive — skipping"
fi

# =============================================================================
# SECTION 6 — Restore wallpapers
# =============================================================================
echo ""
echo "🖼  Restoring wallpapers..."

if [ -d "$SOURCE_DIR/Pictures/Wallpapers" ]; then
    mkdir -p "$HOME/Pictures/Wallpapers"
    cp -r "$SOURCE_DIR/Pictures/Wallpapers/." "$HOME/Pictures/Wallpapers/"
    echo "  ✔  Wallpapers restored to ~/Pictures/Wallpapers/"
else
    echo "  ⚠  No wallpapers directory in archive — skipping"
fi

# =============================================================================
# SECTION 7 — Reinstall scripts to ~/HyprBackup/
# =============================================================================
# Creates ~/HyprBackup/ on the target machine (same layout as the source)
# and copies both scripts there. After this step, the hbk alias works
# immediately and future backups are stored in ~/HyprBackup/.
echo ""
echo "📎 Reinstalling scripts to $INSTALL_DIR ..."

# Create ~/HyprBackup/ if it doesn't exist yet
mkdir -p "$INSTALL_DIR"

if [ -f "$SOURCE_DIR/scripts/hypr-backup.sh" ]; then
    cp "$SOURCE_DIR/scripts/hypr-backup.sh" "$INSTALL_DIR/hypr-backup.sh"
    chmod +x "$INSTALL_DIR/hypr-backup.sh"
    echo "  ✔  $INSTALL_DIR/hypr-backup.sh"
else
    echo "  ⚠  hypr-backup.sh not found in archive/scripts/ — skipping"
fi

if [ -f "$SOURCE_DIR/scripts/hypr-restore.sh" ]; then
    cp "$SOURCE_DIR/scripts/hypr-restore.sh" "$INSTALL_DIR/hypr-restore.sh"
    chmod +x "$INSTALL_DIR/hypr-restore.sh"
    echo "  ✔  $INSTALL_DIR/hypr-restore.sh"
else
    echo "  ⚠  hypr-restore.sh not found in archive/scripts/ — skipping"
fi

# =============================================================================
# SECTION 8 — Optional Fedora package reinstall
# =============================================================================
# Interactive — asks before installing anything. Two guards protect against
# issues on machines that already have packages or repos configured:
#
#   Guard A (COPR): checks with `dnf copr list --enabled` before enabling —
#     skips if solopasha/hyprland is already active on this machine.
#
#   Guard B (packages): uses `rpm -q` before each install — skips packages
#     already installed. `|| true` prevents a single failure from aborting
#     the loop so other packages continue to install.
echo ""
if [ -f "$PKGFILE" ] && command -v dnf &>/dev/null; then
    echo "📦 Package list found. Reinstall Hyprland ecosystem packages? (y/N)"
    read -r REPLY

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then

        # ── Guard A: Only enable COPR if not already active ───────────────────
        echo ""
        echo "  🔧 Checking solopasha/hyprland COPR status..."
        if dnf copr list --enabled 2>/dev/null | grep -q "solopasha/hyprland"; then
            echo "  ℹ  solopasha/hyprland COPR already enabled — skipping"
        else
            sudo dnf copr enable solopasha/hyprland -y
            echo "  ✔  solopasha/hyprland COPR enabled"
        fi

        echo ""
        echo "  📋 Processing package list..."

        # ── Guard B: Per-package skip if already installed ────────────────────
        while IFS= read -r line; do
            # Skip comment lines (e.g., # HYPRLAND_VERSION: ...)
            [[ "$line" =~ ^#.*$ ]] && continue
            # Skip empty lines
            [ -z "$line" ] && continue

            # Strip architecture suffix for rpm -q: "waybar.x86_64" → "waybar"
            PKGNAME="${line%%.*}"

            if rpm -q "$PKGNAME" &>/dev/null; then
                echo "  ℹ  $PKGNAME already installed — skipping"
            else
                # --best: use best available version
                # || true: skip without aborting the loop if install fails
                if sudo dnf install -y --best "$line"; then
                    echo "  ✔  $PKGNAME installed"
                else
                    echo "  ⚠  $PKGNAME could not be installed — skipping"
                fi
            fi
        done < "$PKGFILE"

        echo ""
        echo "  ✔  Package reinstall complete"
    else
        echo "  ℹ  Skipping package reinstall"
    fi

elif ! command -v dnf &>/dev/null; then
    # Non-Fedora machine: config/font/wallpaper restore still worked above
    echo "  ℹ  dnf not found — not a Fedora machine"
    echo "     Configs, fonts, and wallpapers were still fully restored."
fi

# =============================================================================
# SECTION 9 — Cleanup temporary extraction directory
# =============================================================================
# Only runs in Mode A (archive path was passed). In Mode B, EXTRACT_DIR is
# empty, so nothing is removed.
if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
    rm -rf "$EXTRACT_DIR"
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                  Restore Complete! ✅                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  🛡  Old configs saved to   : $SAFETY_BACKUP"
echo "  📂  Scripts reinstalled at : $INSTALL_DIR"
echo ""
echo "  Next steps:"
echo "  1. Reload config without a full restart:"
echo "       hyprctl reload"
echo ""
echo "  2. Add to ~/.bashrc or ~/.zshrc for one-word backups:"
echo "       alias hbk='bash ~/HyprBackup/hypr-backup.sh'"
echo ""
