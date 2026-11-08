#!/bin/sh
# Night light through wlsunset (wlr-gamma-control; niri supports it).
#   nightlight.sh off
#   nightlight.sh on   <kelvin>      always warm
#   nightlight.sh auto <kelvin>      warm from sunset to sunrise at your place (~/.config/beskar/location: "LAT LON City"),
#                                    06:30 to 18:30 when there is none
pkill -x wlsunset 2>/dev/null
mode="${1:-off}"; k="${2:-3800}"
case "$k" in ''|*[!0-9]*) k=3800 ;; esac
[ "$k" -lt 2000 ] && k=2000
[ "$k" -gt 6000 ] && k=6000
command -v wlsunset >/dev/null 2>&1 || exit 0
case "$mode" in
    on)
        # wlsunset wants a high temperature above the low one: a one-minute "day" a day, the rest night
        setsid wlsunset -t "$k" -T $((k + 1)) -S 23:59 -s 00:00 </dev/null >/dev/null 2>&1 &
        ;;
    auto)
        loc=$(head -1 "$HOME/.config/beskar/location" 2>/dev/null)
        lat=$(echo "$loc" | awk '{print $1}'); lon=$(echo "$loc" | awk '{print $2}')
        if [ -n "$lat" ] && [ -n "$lon" ]; then
            setsid wlsunset -l "$lat" -L "$lon" -t "$k" -T 6500 </dev/null >/dev/null 2>&1 &
        else
            setsid wlsunset -t "$k" -T 6500 -S 06:30 -s 18:30 </dev/null >/dev/null 2>&1 &
        fi
        ;;
esac
exit 0
