# Shared weather

Implemented 2026-11-13 (plan slices 3A/3B). World clocks are a separate upcoming slice.

## Ownership

`desktop.plm` imports the headless `Weather` scene. It alone reads/writes the chosen
location and requests forecasts. Topbar and Today read its public texts; the weather
panel reads its JSON `snapshot` text and formats it through `weather_data.luau`.
The panel owns only geocoding search and local view state. Widgets run separately and
use the read-only `weather_client.luau` snapshot bridge.

| Event | Effect |
| --- | --- |
| `Weather.ensure` | Fetch only if missing/stale and outside the retry backoff |
| `Weather.refresh` | Explicit refresh; coalesces while a request is active |
| `Weather.choose_location({lat, lon, city})` | Validate, save location, then fetch once |
| `Weather.use_ip` | Resolve location from IP, save it, then fetch |
| `Weather.reload_location` | Re-read the existing location file |
| `Weather.resync(revision)` | Notify widgets if behind; retry a failed snapshot write |

Desktop readers send typed events and declare `uses scene "weather.plm" as Weather`.
Widgets send only numeric `say weather "emit resync REV"` and explicit refresh events.
The owner notifies `weather_changed(revision)` only after a successful snapshot write.

## Storage and restart

Location remains the compatible `LAT LON City name` line in
`~/.config/beskar/location`. Missing files trigger IP lookup; malformed existing files
report an error so the user can choose a city. Location saves serialize and replace an
atomic temporary file; the latest choice wins.

The files service writes these private atomic files below
`$XDG_DATA_HOME/pleamar/weather/` (default `~/.local/share/pleamar/weather/`):

- `cache.json`: `{version: 1, forecast: ...}`, written only after a successful forecast.
- `snapshot.json`: public state for widgets, including version, monotonic revision,
  loading/stale/status, location and an optional forecast.

On startup the cache renders immediately with a Cached label. After location resolution,
a matching cache younger than 15 minutes becomes current without a network request.
A different city discards the old reading before fetching. Invalid/future-dated cache
cannot count as fresh. Snapshot revisions continue from the previous valid snapshot.
Widgets request resync at startup and every 15 seconds; snapshot reads coalesce and
reject older revisions. These checks do not request forecasts.

## Requests and display

One bounded Open-Meteo request contains current conditions, eight current/future hourly
readings, five days, precipitation probabilities, sunrise/sunset and UV. Forecast curl
connect/total bounds are three/eight seconds. IP lookup and city search are bounded to
six seconds. A single owner timer checks freshness each minute; a failed forecast retries
no sooner than 60 seconds unless explicitly refreshed. Epochs reject replies from a
previous city or an older IP lookup; a new city waits behind an in-flight forecast.

`weather_data.luau` validates and bounds cached/network data, and shares presentation.
Temperatures use °C, wind km/h and pressure hPa. Unknown metrics show `--`, not zero.
Hourly and sunrise/sunset times use the forecast location's local times and the shell's
12/24-hour preference. Last update uses the local system clock. Cached readings carry
`Cached` in conditions and `~` in compact bar/widget temperatures. Widgets also mark
an aged snapshot or unavailable owner as cached. A successful refresh clears the label.

## Focused verification

```sh
lua tests/weather.lua
bin/exp/pleamar --check shell/desktop.plm
bin/exp/pleamar --check shell/widgets.plm
shell/smoke.sh weather today
```

The isolated suite covers bounded data, clock formatting, coalescing, timeout arguments,
offline retention/backoff, cache restart, stale city/IP replies, serialized location writes,
write failures and widget resync/older-read rejection. No network or user location changes
are needed for these tests. Visually inspect the forecast and city picker on both outputs.
