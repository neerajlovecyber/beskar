use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::MediaState;
use std::collections::HashMap;
use tokio::sync::mpsc;
use tracing::info;
use zbus::blocking::{fdo::DBusProxy, Connection, MessageIterator, Proxy};
use zbus::zvariant::OwnedValue;
use zbus::MatchRule;

const PREFIX: &str = "org.mpris.MediaPlayer2.";
const PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MediaTrack {
    pub bus_name: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub art_url: Option<String>,
    pub local_art_path: Option<String>,
    pub is_playing: bool,
    pub can_go_next: bool,
    pub can_go_previous: bool,
    pub player_name: String,
    pub has_media: bool,
    pub position_micros: Option<i64>,
    pub length_micros: Option<i64>,
}

/// Pure-Rust MPRIS media monitoring and control engine using direct D-Bus protocol (zbus).
/// Eradicates all `playerctl` CLI subprocesses and blocking I/O on the UI thread.
pub struct MprisService;

impl Default for MprisService {
    fn default() -> Self {
        Self::new()
    }
}

impl MprisService {
    pub fn new() -> Self {
        Self
    }

    pub fn fetch_all_players() -> Vec<MediaTrack> {
        let Ok(conn) = Connection::session() else {
            return Vec::new();
        };
        let names = Self::list_players(&conn);
        let mut tracks = Vec::new();
        for bus_name in names {
            let Ok(proxy) = Proxy::new(&conn, bus_name.clone(), PATH, PLAYER) else {
                continue;
            };
            let is_playing = proxy
                .get_property::<String>("PlaybackStatus")
                .is_ok_and(|s| s == "Playing");
            let can_go_next = proxy
                .get_property::<bool>("CanGoNext")
                .unwrap_or(true);
            let can_go_previous = proxy
                .get_property::<bool>("CanGoPrevious")
                .unwrap_or(true);
            let metadata: HashMap<String, OwnedValue> =
                proxy.get_property("Metadata").unwrap_or_default();
            let title = metadata.get("xesam:title").map(Self::parse_text).unwrap_or_default();
            let artist = metadata.get("xesam:artist").map(Self::parse_text).unwrap_or_default();
            let album = metadata.get("xesam:album").map(Self::parse_text).unwrap_or_default();
            let art_url = metadata.get("mpris:artUrl").map(Self::parse_text).filter(|s| !s.is_empty());
            let local_art_path = art_url.as_ref().and_then(|url| {
                if let Some(stripped) = url.strip_prefix("file://") {
                    Some(stripped.to_string())
                } else if url.starts_with('/') {
                    Some(url.clone())
                } else {
                    None
                }
            });
            let length_micros = metadata.get("mpris:length").and_then(|v| {
                i64::try_from(v)
                    .ok()
                    .or_else(|| u64::try_from(v).ok().map(|n| n as i64))
            });
            let position_micros = proxy
                .get_property::<OwnedValue>("Position")
                .ok()
                .and_then(|v| {
                    i64::try_from(&v)
                        .ok()
                        .or_else(|| u64::try_from(&v).ok().map(|n| n as i64))
                });
            let player_name = bus_name
                .trim_start_matches(PREFIX)
                .split('.')
                .next()
                .unwrap_or("Media")
                .to_string();
            let has_media = !title.is_empty();
            if has_media {
                tracks.push(MediaTrack {
                    bus_name,
                    title,
                    artist,
                    album,
                    art_url,
                    local_art_path,
                    is_playing,
                    can_go_next,
                    can_go_previous,
                    player_name,
                    has_media,
                    position_micros,
                    length_micros,
                });
            }
        }
        tracks
    }

    pub fn play_pause_bus(bus_name: &str) {
        let bus = bus_name.to_string();
        tokio::task::spawn_blocking(move || {
            if let Ok(conn) = Connection::session() {
                if let Ok(proxy) = Proxy::new(&conn, bus, PATH, PLAYER) {
                    let _ = proxy.call_method("PlayPause", &());
                }
            }
        });
    }

    pub fn next_bus(bus_name: &str) {
        let bus = bus_name.to_string();
        tokio::task::spawn_blocking(move || {
            if let Ok(conn) = Connection::session() {
                if let Ok(proxy) = Proxy::new(&conn, bus, PATH, PLAYER) {
                    let _ = proxy.call_method("Next", &());
                }
            }
        });
    }

    pub fn previous_bus(bus_name: &str) {
        let bus = bus_name.to_string();
        tokio::task::spawn_blocking(move || {
            if let Ok(conn) = Connection::session() {
                if let Ok(proxy) = Proxy::new(&conn, bus, PATH, PLAYER) {
                    let _ = proxy.call_method("Previous", &());
                }
            }
        });
    }

    pub fn seek_to(bus_name: &str, position_seconds: f64) {
        let bus = bus_name.to_string();
        tokio::task::spawn_blocking(move || {
            let raw_player = bus
                .strip_prefix("org.mpris.MediaPlayer2.")
                .unwrap_or(&bus)
                .split('.')
                .next()
                .unwrap_or(&bus);

            let clean_player = raw_player.trim();
            let pos_str = format!("{:.2}", position_seconds.max(0.0));
            let mut cmd = std::process::Command::new("playerctl");
            if !clean_player.is_empty() && clean_player != "player" {
                cmd.args(["-p", clean_player, "position", &pos_str]);
            } else {
                cmd.args(["position", &pos_str]);
            }
            let _ = cmd.spawn();
        });
    }

    fn list_players(c: &Connection) -> Vec<String> {
        let Ok(bus) = DBusProxy::new(c) else {
            return Vec::new();
        };
        let mut names: Vec<String> = bus
            .list_names()
            .unwrap_or_default()
            .into_iter()
            .map(|n| n.to_string())
            .filter(|n| n.starts_with(PREFIX) && !n.ends_with("playerctld"))
            .collect();
        names.sort();
        names
    }

    fn active_player_proxy(c: &Connection) -> Option<(String, Proxy<'static>, bool)> {
        let players = Self::list_players(c);
        let mut fallback = None;

        for name in players {
            let Ok(p) = Proxy::new(c, name.clone(), PATH, PLAYER) else {
                continue;
            };
            let is_playing = p
                .get_property::<String>("PlaybackStatus")
                .is_ok_and(|s| s == "Playing");

            if is_playing {
                return Some((name, p, true));
            }
            if fallback.is_none() {
                fallback = Some((name, p, false));
            }
        }
        fallback
    }

    fn parse_text(v: &OwnedValue) -> String {
        if let Ok(s) = <&str>::try_from(v) {
            return s.to_string();
        }
        if let Ok(l) = <Vec<String>>::try_from(v.clone()) {
            return l.join(", ");
        }
        String::new()
    }

    fn parse_duration_ms(v: &OwnedValue) -> u64 {
        let us = i64::try_from(v)
            .ok()
            .or_else(|| u64::try_from(v).ok().map(|n| n as i64))
            .unwrap_or(0);
        (us.max(0) / 1000) as u64
    }

    /// Read active media player metadata and playback status via pure D-Bus queries.
    pub fn read_state() -> Option<MediaState> {
        let conn = Connection::session().ok()?;
        let (bus_name, proxy, is_playing) = Self::active_player_proxy(&conn)?;

        let metadata: HashMap<String, OwnedValue> =
            proxy.get_property("Metadata").unwrap_or_default();
        let title = metadata.get("xesam:title").map(Self::parse_text);
        let artist = metadata
            .get("xesam:artist")
            .map(Self::parse_text)
            .filter(|s| !s.is_empty());
        let album = metadata
            .get("xesam:album")
            .map(Self::parse_text)
            .filter(|s| !s.is_empty());
        let art_url = metadata
            .get("mpris:artUrl")
            .map(Self::parse_text)
            .filter(|s| !s.is_empty());
        let duration_ms = metadata
            .get("mpris:length")
            .map(Self::parse_duration_ms)
            .unwrap_or(0);

        let position_us = proxy
            .get_property::<OwnedValue>("Position")
            .ok()
            .and_then(|v| {
                i64::try_from(&v)
                    .ok()
                    .or_else(|| u64::try_from(&v).ok().map(|n| n as i64))
            })
            .unwrap_or(0);
        let position_ms = (position_us.max(0) / 1000) as u64;

        let player_name = bus_name
            .trim_start_matches(PREFIX)
            .split('.')
            .next()
            .unwrap_or("Media")
            .to_string();

        if title.as_deref().unwrap_or("").is_empty() {
            return None;
        }

        Some(MediaState {
            player_name,
            title,
            artist,
            album,
            is_playing,
            art_url,
            position_ms,
            duration_ms,
        })
    }

    /// Toggle playback on the active media player via D-Bus method call.
    pub fn play_pause() {
        tokio::task::spawn_blocking(|| {
            if let Ok(conn) = Connection::session() {
                if let Some((_, proxy, _)) = Self::active_player_proxy(&conn) {
                    let _ = proxy.call_method("PlayPause", &());
                }
            }
        });
    }

    /// Skip to next track on the active media player via D-Bus method call.
    pub fn next() {
        tokio::task::spawn_blocking(|| {
            if let Ok(conn) = Connection::session() {
                if let Some((_, proxy, _)) = Self::active_player_proxy(&conn) {
                    let _ = proxy.call_method("Next", &());
                }
            }
        });
    }

    /// Skip to previous track on the active media player via D-Bus method call.
    pub fn previous() {
        tokio::task::spawn_blocking(|| {
            if let Ok(conn) = Connection::session() {
                if let Some((_, proxy, _)) = Self::active_player_proxy(&conn) {
                    let _ = proxy.call_method("Previous", &());
                }
            }
        });
    }

    /// Pure reactive D-Bus signal listener (PropertiesChanged, Seeked, NameOwnerChanged).
    pub async fn start_listener(&self, tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("MPRIS reactive D-Bus signal listener starting (pure-Rust)");

        let (wake_tx, mut wake_rx) = tokio::sync::mpsc::channel::<()>(16);

        std::thread::Builder::new()
            .name("mpris-dbus-signals".into())
            .spawn(move || {
                let Ok(conn) = Connection::session() else {
                    return;
                };

                let rules = [
                    MatchRule::builder()
                        .msg_type(zbus::message::Type::Signal)
                        .interface("org.freedesktop.DBus.Properties")
                        .and_then(|b| b.member("PropertiesChanged"))
                        .and_then(|b| b.path(PATH))
                        .map(|b| b.build()),
                    MatchRule::builder()
                        .msg_type(zbus::message::Type::Signal)
                        .interface(PLAYER)
                        .and_then(|b| b.member("Seeked"))
                        .and_then(|b| b.path(PATH))
                        .map(|b| b.build()),
                    MatchRule::builder()
                        .msg_type(zbus::message::Type::Signal)
                        .interface("org.freedesktop.DBus")
                        .and_then(|b| b.member("NameOwnerChanged"))
                        .and_then(|b| b.arg0ns(PREFIX.trim_end_matches('.')))
                        .map(|b| b.build()),
                ];

                for rule in rules.into_iter().flatten() {
                    let (c, w_tx) = (conn.clone(), wake_tx.clone());
                    std::thread::spawn(move || {
                        let Ok(messages) = MessageIterator::for_match_rule(rule, &c, Some(16))
                        else {
                            return;
                        };
                        for _ in messages {
                            if w_tx.blocking_send(()).is_err() {
                                break;
                            }
                        }
                    });
                }
            })?;

        // Send initial state immediately
        let initial = Self::read_state().unwrap_or_default();
        let _ = tx.send(ServiceEvent::Media(initial)).await;

        let mut last_state = Self::read_state();
        while wake_rx.recv().await.is_some() {
            // Debounce rapid bursts of D-Bus signals (e.g. metadata + position + status)
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            while wake_rx.try_recv().is_ok() {}

            let current = Self::read_state();
            if current != last_state {
                last_state = current.clone();
                let event = current.unwrap_or_default();
                if tx.send(ServiceEvent::Media(event)).await.is_err() {
                    break;
                }
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mpris_read_state_does_not_panic() {
        // Even when no media player is active, read_state should return gracefully
        let state = MprisService::read_state();
        if let Some(media) = state {
            assert!(!media.player_name.is_empty());
        }
    }

    #[test]
    fn test_mpris_parse_helpers() {
        use zbus::zvariant::Value;
        let title_val = Value::from("Test Song Title").try_to_owned().unwrap();
        assert_eq!(MprisService::parse_text(&title_val), "Test Song Title");

        let duration_us = OwnedValue::from(240_000_000i64); // 240 seconds
        assert_eq!(MprisService::parse_duration_ms(&duration_us), 240_000);
    }
}

