#!/usr/bin/env sh
# One-line install:  curl -fsSL https://raw.githubusercontent.com/neerajlovecyber/beskar/master/install.sh | sh
# Clones Beskar into ~/.local/share/beskar-shell (or updates it) and runs ./beskar install.
# Extra arguments go to ./beskar install:  ... | sh -s -- --dry-run
set -eu
DEST="${BESKAR_DIR:-$HOME/.local/share/beskar-shell}"
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
if [ -d "$DEST/.git" ]; then
    echo "Updating $DEST"
    git -C "$DEST" pull --ff-only
else
    echo "Cloning into $DEST"
    git clone --depth 1 https://github.com/neerajlovecyber/beskar "$DEST"
fi
cd "$DEST"
exec ./beskar install "$@"
