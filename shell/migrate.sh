#!/usr/bin/env sh
# One-time data moves between releases; idempotent (never overwrites). Run by supervise.sh before the desktop process starts.
#
# The Dockpanels scene was merged into the frame (common/dock_panels.plm). pleamar keeps a scene's saved files in a folder named
# after its file, so Spotlight's launch history, the clipboard pins and the wallpaper favourites that were saved in `dockpanels/`
# are copied to `topbar/`, where the merged logic now reads them.
base="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar"
if [ -d "$base/dockpanels" ]; then
    mkdir -p "$base/topbar"
    for f in spotlight-history.json spotlight-files.json pins.json wallpaper-favourites.json; do
        [ -f "$base/dockpanels/$f" ] && [ ! -e "$base/topbar/$f" ] && cp "$base/dockpanels/$f" "$base/topbar/$f"
    done
fi
exit 0
