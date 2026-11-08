#!/bin/sh
# Makes the apps outside the shell (terminals, GTK / libadwaita apps such as Nautilus, Qt apps) wear the shell's colours.
#
#   appthemes.sh setup                     once (idempotent): one include line in each app's own config
#   appthemes.sh apply dark|light #rrggbb [scheme]   render the colours (matugen) and tell the apps
#   appthemes.sh remove                    take our include lines out again
#
# Everything it renders lives in ~/.config/beskar/themes/; the only things it touches in your own configs are the
# include lines below (the first time, the file is copied to <name>.beskar-bak). Settings → Appearance → "Theme
# other apps" runs `setup` + `apply` whenever the look changes.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$HOME/.config/beskar/themes"
MARK="beskar/themes"        # every include line we add contains this (no inline comments: kitty reads them as part of the path)
mkdir -p "$T"

backup() { [ -f "$1" ] && [ ! -f "$1.beskar-bak" ] && cp "$1" "$1.beskar-bak"; return 0; }

# add a line to a file once (after a given pattern if there is one, else at the end)
add_line() { # file line [after-pattern]
    f="$1"; line="$2"; after="$3"
    mkdir -p "$(dirname "$f")"
    [ -f "$f" ] || : > "$f"
    grep -qF "$MARK" "$f" && return 0
    backup "$f"
    n=""; [ -n "$after" ] && n=$(grep -n -m1 -F "$after" "$f" | cut -d: -f1)
    if [ -n "$n" ]; then
        awk -v n="$n" -v l="$line" 'NR==n {print; print l; next} {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
        printf '\n%s\n' "$line" >> "$f"
    fi
}

setup() {
    # kitty: later settings win, so ours goes at the end
    if command -v kitty >/dev/null 2>&1 || [ -d "$HOME/.config/kitty" ]; then
        add_line "$HOME/.config/kitty/kitty.conf" "include $T/kitty.conf"
    fi
    # alacritty: an import in [general]
    if command -v alacritty >/dev/null 2>&1 || [ -f "$HOME/.config/alacritty/alacritty.toml" ]; then
        f="$HOME/.config/alacritty/alacritty.toml"
        if [ -f "$f" ] && ! grep -qF "$MARK" "$f"; then
            if grep -q '^import *=' "$f"; then
                :   # the user has their own import list: leave it alone
            elif grep -q '^\[general\]' "$f"; then
                add_line "$f" "import = [\"$T/alacritty.toml\"]" '[general]'
            else
                backup "$f"
                { printf '[general]\nimport = ["%s"]\n\n' "$T/alacritty.toml"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
            fi
        elif [ ! -f "$f" ]; then
            mkdir -p "$(dirname "$f")"; printf '[general]\nimport = ["%s"]\n' "$T/alacritty.toml" > "$f"
        fi
    fi
    # ghostty
    if command -v ghostty >/dev/null 2>&1 || [ -d "$HOME/.config/ghostty" ]; then
        add_line "$HOME/.config/ghostty/config" "config-file = ?$T/ghostty.conf"
    fi
    # foot
    if command -v foot >/dev/null 2>&1 || [ -f "$HOME/.config/foot/foot.ini" ]; then
        add_line "$HOME/.config/foot/foot.ini" "include=$T/foot.ini"
    fi
    # GTK 3 and 4 / libadwaita: the CSS import goes LAST so its colours win
    for v in 3.0 4.0; do
        add_line "$HOME/.config/gtk-$v/gtk.css" "@import url(\"file://$T/gtk.css\");"
    done
    # Qt through qt5ct / qt6ct: our colour scheme, custom palette on
    for q in qt5ct qt6ct; do
        c="$HOME/.config/$q/$q.conf"
        [ -f "$c" ] || continue
        grep -qE "^color_scheme_path *= *$T/qt-colors.conf" "$c" && continue
        backup "$c"
        if grep -q '^color_scheme_path *=' "$c"; then
            sed -i "s|^color_scheme_path *=.*|color_scheme_path=$T/qt-colors.conf|" "$c"
        elif grep -q '^\[Appearance\]' "$c"; then
            sed -i "/^\[Appearance\]/a color_scheme_path=$T/qt-colors.conf" "$c"
        else
            printf '\n[Appearance]\ncolor_scheme_path=%s\n' "$T/qt-colors.conf" >> "$c"
        fi
        if grep -q '^custom_palette *=' "$c"; then sed -i 's|^custom_palette *=.*|custom_palette=true|' "$c"
        else sed -i "/^color_scheme_path=/a custom_palette=true" "$c"; fi
    done
}

remove() {
    for f in "$HOME/.config/kitty/kitty.conf" "$HOME/.config/alacritty/alacritty.toml" "$HOME/.config/ghostty/config" \
             "$HOME/.config/foot/foot.ini" "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"; do
        [ -f "$f" ] && sed -i "\\|beskar/themes|d" "$f"
    done
}

# ANSI colours that stay readable in both modes (blue is the accent, taken from the palette in the templates)
ansi() { # dark|light
    if [ "$1" = dark ]; then
        set -- "#3b3f4c" "#f38ba8" "#a6e3a1" "#f9e2af" x "#cba6f7" "#94e2d5" "#bac2de" "#585b70" "#f38ba8" "#a6e3a1" "#f9e2af" x "#cba6f7" "#94e2d5" "#cdd6f4"
    else
        set -- "#5c5f77" "#d20f39" "#40a02b" "#df8e1d" x "#8839ef" "#179299" "#acb0be" "#6c6f85" "#d20f39" "#40a02b" "#df8e1d" x "#8839ef" "#179299" "#bcc0cc"
    fi
    i=0
    for c in "$@"; do printf '%s %s\n' "$i" "$c"; i=$((i + 1)); done
}

apply() {
    mode="$1"; src="$2"; scheme="${3:-scheme-tonal-spot}"
    case "$mode" in dark|light) ;; *) echo "mode must be dark or light" >&2; exit 1;; esac
    case "$src" in \#??????) ;; *) echo "colour must be #rrggbb" >&2; exit 1;; esac
    command -v matugen >/dev/null 2>&1 || { echo "matugen is not installed" >&2; exit 1; }
    cfg="$HOME/.config/beskar/matugen.toml"
    sed "s|@DIR@|$DIR|g" "$DIR/assets/matugen/config.toml" > "$cfg"
    matugen color hex "$src" -m "$mode" -t "$scheme" -c "$cfg" >/tmp/beskar-appthemes.log 2>&1 || { echo "matugen failed (see /tmp/beskar-appthemes.log)" >&2; exit 1; }
    # the fixed ANSI colours
    ansi "$mode" | while read -r n c; do
        for f in kitty.conf alacritty.toml ghostty.conf; do
            [ -f "$T/$f" ] && sed -i "s|@A$n@|$c|g" "$T/$f"
        done
        [ -f "$T/foot.ini" ] && sed -i "s|@N$n@|${c#\#}|g" "$T/foot.ini"
    done
    # GTK / libadwaita: light or dark, and the adw-gtk3 theme where it is installed
    if command -v gsettings >/dev/null 2>&1; then
        if [ "$mode" = dark ]; then
            gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null
            [ -d /usr/share/themes/adw-gtk3-dark ] && gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark 2>/dev/null
        else
            gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null
            [ -d /usr/share/themes/adw-gtk3 ] && gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3 2>/dev/null
        fi
    fi
    # running terminals pick the colours up now (kitty reloads on USR1; alacritty live-reloads its config)
    pkill -USR1 -x kitty 2>/dev/null
    touch "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null
    return 0
}

case "$1" in
    setup) setup ;;
    apply) shift; apply "$@" ;;
    remove) remove ;;
    *) echo "usage: appthemes.sh setup | apply dark|light #rrggbb [scheme] | remove" >&2; exit 1 ;;
esac
