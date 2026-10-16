pub mod navigation;
pub mod widgets;

use std::sync::Arc;
use std::time::{Duration, Instant};

use chrono::Local;
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule, Slot};
use beskar_services::{
    AudioService, BacklightService, BatteryService, BatteryState, MediaTrack, MprisService,
    NotificationItem, NotificationStore,
};
use beskar_ui::widgets::dashboard::{
    module_size, BOTTOM_PADDING, CONTENT, GAP, LEFT, NOTIFICATIONS, PADDING, RIGHT,
};
use beskar_ui::widgets::dashboard::media::render_media_card;
use beskar_ui::DimensionTracker;

pub use self::navigation::Navigation;
use self::widgets::*;

#[derive(Clone, PartialEq, Default)]
pub struct Snapshot {
    pub network_connected: bool,
    pub wifi_enabled: bool,
    pub wifi_ssid: String,
    pub bluetooth_enabled: bool,
    pub bluetooth_device: String,
    pub volume: u32,
    pub is_muted: bool,
    pub brightness: u32,
    pub battery: Option<BatteryState>,
    pub players: Vec<MediaTrack>,
    pub notifications: Vec<NotificationItem>,
    pub dnd: bool,
    pub date: String,
}

impl Snapshot {
    pub fn read() -> Self {
        let audio = AudioService::read_state();
        let volume = (audio.volume * 100.0).round() as u32;
        let is_muted = audio.is_muted;
        let brightness = BacklightService::get_brightness() as u32;
        let battery = Some(BatteryService::new().read_state());
        let players = MprisService::fetch_all_players();
        let notifications = NotificationStore::global().get_all_notifications();
        let dnd = NotificationStore::global().is_dnd_enabled();

        let now = Local::now();
        let date = now.format("%A, %B %-d · %H:%M").to_string();

        Self {
            network_connected: true,
            wifi_enabled: true,
            wifi_ssid: "Wi-Fi".to_string(),
            bluetooth_enabled: false,
            bluetooth_device: "Disconnected".to_string(),
            volume,
            is_muted,
            brightness,
            battery,
            players,
            notifications,
            dnd,
            date,
        }
    }
}

pub struct DashboardView {
    pub snapshot: Snapshot,
    pub snapshot_at: Instant,
    pub wave_phase: f32,
    pub player_bus: Option<String>,
    pub pending: bool,
    pub volume_bounds: DimensionTracker,
    pub brightness_bounds: DimensionTracker,
    pub seek_bounds: DimensionTracker,
    pub dragging_volume: bool,
    pub dragging_brightness: bool,
    pub dragging_seek: bool,
    pub navigation: Navigation,
    focus_handle: FocusHandle,
}

impl PanelModule for DashboardView {
    const ID: &'static str = "dashboard";

    fn slot() -> Slot {
        Slot::Left
    }

    fn size() -> Size<Pixels> {
        module_size(false)
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP | LayerAnchor::LEFT
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(48.0), px(0.0), px(0.0), px(12.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl DashboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let snapshot = Snapshot::read();
        let player_bus = retain_player(None, &snapshot.players);

        // 250ms periodic polling loop for hardware/media/notification state
        cx.spawn(async move |this, cx| {
            loop {
                tokio::time::sleep(Duration::from_millis(250)).await;
                let current = Snapshot::read();
                let res = this.update(cx, |this, cx| {
                    if this.snapshot != current {
                        this.player_bus = retain_player(this.player_bus.as_deref(), &current.players);
                        this.snapshot = current;
                        this.snapshot_at = Instant::now();
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 60fps media wave animation loop while track is playing
        cx.spawn(async move |this, cx| {
            let start = Instant::now();
            loop {
                tokio::time::sleep(Duration::from_millis(16)).await;
                let epoch = start.elapsed().as_secs_f32();
                let res = this.update(cx, |this, cx| {
                    let is_playing = this
                        .player()
                        .map(|p| p.is_playing)
                        .unwrap_or(false);
                    if is_playing {
                        this.wave_phase = epoch * 3.0;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        Self {
            snapshot,
            snapshot_at: Instant::now(),
            wave_phase: 0.0,
            player_bus,
            pending: false,
            volume_bounds: DimensionTracker::new(),
            brightness_bounds: DimensionTracker::new(),
            seek_bounds: DimensionTracker::new(),
            dragging_volume: false,
            dragging_brightness: false,
            dragging_seek: false,
            navigation: Navigation::default(),
            focus_handle,
        }
    }

    pub fn player(&self) -> Option<&MediaTrack> {
        self.player_bus
            .as_ref()
            .and_then(|bus| self.snapshot.players.iter().find(|p| p.bus_name == *bus))
            .or_else(|| self.snapshot.players.first())
    }

    pub fn volume_at(&mut self, x: f32, cx: &mut Context<Self>) {
        if let Some(fraction) =
            slider_fraction(x, self.volume_bounds.left(), self.volume_bounds.width(0.0))
        {
            let vol = (fraction * 100.0).round() as u8;
            AudioService::set_volume_percent(vol);
            self.snapshot.volume = vol as u32;
            cx.notify();
        }
    }

    pub fn seek_at(&mut self, x: f32, cx: &mut Context<Self>) {
        if let Some(fraction) =
            slider_fraction(x, self.seek_bounds.left(), self.seek_bounds.width(0.0))
            && let Some(track) = self.player()
            && let Some(length) = track.length_micros
        {
            let bus = track.bus_name.clone();
            let pos_seconds = f64::from(fraction) * (length as f64 / 1_000_000.0);
            MprisService::seek_to(&bus, pos_seconds);
            cx.notify();
        }
    }
}

pub fn retain_player(current: Option<&str>, players: &[MediaTrack]) -> Option<String> {
    players
        .iter()
        .find(|p| Some(p.bus_name.as_str()) == current)
        .or_else(|| players.iter().find(|p| p.is_playing))
        .or_else(|| players.first())
        .map(|p| p.bus_name.clone())
}

pub fn slider_fraction(x: f32, left: f32, width: f32) -> Option<f32> {
    if width > 0.0 {
        Some(((x - left) / width).clamp(0.0, 1.0))
    } else {
        None
    }
}

impl Focusable for DashboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for DashboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let player = self.player().cloned();
        let elapsed = self.snapshot_at.elapsed();
        let wave_phase = self.wave_phase;
        let seek_tracker = self.seek_bounds.clone();
        let volume_tracker = self.volume_bounds.clone();

        let cb_toggle_wifi = Arc::new({
            let _ = cx;
            move || {
                let _ = beskar_services::networkmanager::command("network.wifi", &[beskar_services::SysValue::Bool(true)]);
            }
        });

        let cb_toggle_bluetooth = Arc::new(move || {
            // Bluez toggle placeholder
        });

        let cb_toggle_dnd = Arc::new(move || {
            NotificationStore::global().toggle_dnd();
        });

        let cb_mute = Arc::new(move || {
            AudioService::toggle_mute();
        });

        let cb_clear_notifs = Arc::new(move || {
            NotificationStore::global().clear_all_notifications();
        });

        let cb_remove_notif = Arc::new(move |id: u32| {
            NotificationStore::global().remove_notification(id);
        });

        let cb_open_settings = Arc::new({
            let _ = cx;
            move || {
                // Open settings
            }
        });

        let bus_clone = self.player_bus.clone();
        let cb_play = Arc::new({
            let bus = bus_clone.clone();
            move || {
                if let Some(ref b) = bus {
                    MprisService::play_pause_bus(b);
                } else {
                    MprisService::play_pause();
                }
            }
        });

        let cb_prev = Arc::new({
            let bus = bus_clone.clone();
            move || {
                if let Some(ref b) = bus {
                    MprisService::previous_bus(b);
                } else {
                    MprisService::previous();
                }
            }
        });

        let cb_next = Arc::new({
            let bus = bus_clone.clone();
            move || {
                if let Some(ref b) = bus {
                    MprisService::next_bus(b);
                } else {
                    MprisService::next();
                }
            }
        });

        let cb_seek = Arc::new({
            let bus = bus_clone;
            move |sec: f64| {
                if let Some(ref b) = bus {
                    MprisService::seek_to(b, sec);
                }
            }
        });

        let media_callbacks = beskar_ui::widgets::dashboard::media::MediaCardCallbacks {
            on_play_pause: cb_play,
            on_prev: cb_prev,
            on_next: cb_next,
            on_seek: cb_seek,
        };

        let media_card = render_media_card(
            player.as_ref(),
            elapsed,
            wave_phase,
            18.0,
            Some(media_callbacks),
            Some(&seek_tracker),
        );

        let header = render_header(
            &self.snapshot.date,
            self.snapshot.battery.as_ref(),
            cb_open_settings,
        );

        let controls = div()
            .w(px(LEFT))
            .h_full()
            .flex_shrink_0()
            .flex()
            .flex_col()
            .gap(px(GAP))
            .child(render_connectivity_pill(
                "dashboard-wifi",
                "Wi-Fi",
                &self.snapshot.wifi_ssid,
                "wifi.svg",
                self.snapshot.wifi_enabled,
                cb_toggle_wifi,
            ))
            .child(render_connectivity_pill(
                "dashboard-bluetooth",
                "Bluetooth",
                &self.snapshot.bluetooth_device,
                "bluetooth.svg",
                self.snapshot.bluetooth_enabled,
                cb_toggle_bluetooth,
            ))
            .child(render_connectivity_pill(
                "dashboard-dnd",
                "Do Not Disturb",
                if self.snapshot.dnd {
                    "Enabled"
                } else {
                    "Disabled"
                },
                "moon.svg",
                self.snapshot.dnd,
                cb_toggle_dnd,
            ));

        let content_row = div()
            .w_full()
            .h(px(CONTENT))
            .flex_shrink_0()
            .flex()
            .gap(px(GAP))
            .child(controls)
            .child(
                div()
                    .w(px(RIGHT))
                    .h_full()
                    .flex_shrink_0()
                    .flex()
                    .flex_col()
                    .gap(px(GAP))
                    .child(media_card),
            );

        let sound_slider = render_sound_slider(
            self.snapshot.volume,
            self.snapshot.is_muted,
            &volume_tracker,
            cb_mute,
            cx.listener(|this, event: &MouseDownEvent, _window, cx| {
                this.volume_at(event.position.x.into(), cx);
            }),
        );

        let notifications = render_notifications_section(
            &self.snapshot.notifications,
            cb_clear_notifs,
            cb_remove_notif,
        );

        div()
            .id("dashboard-home")
            .relative()
            .w_full()
            .h(module_size(false).height)
            .flex_shrink_0()
            .px(px(PADDING))
            .pt(px(PADDING))
            .pb(px(BOTTOM_PADDING))
            .rounded(px(22.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::border())
            .flex()
            .flex_col()
            .gap(px(GAP))
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                }
            }))
            .on_mouse_move(cx.listener(|this, event: &MouseMoveEvent, _window, cx| {
                if this.dragging_volume {
                    this.volume_at(event.position.x.into(), cx);
                }
            }))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(|this, event: &MouseUpEvent, _window, cx| {
                    if this.dragging_volume {
                        this.dragging_volume = false;
                        this.volume_at(event.position.x.into(), cx);
                    }
                    if this.dragging_seek {
                        this.dragging_seek = false;
                        this.seek_at(event.position.x.into(), cx);
                    }
                }),
            )
            .child(header)
            .child(content_row)
            .child(sound_slider)
            .child(
                div()
                    .w_full()
                    .min_w_0()
                    .max_w_full()
                    .min_h(px(NOTIFICATIONS))
                    .h(px(NOTIFICATIONS))
                    .flex_shrink_0()
                    .overflow_hidden()
                    .child(notifications),
            )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selection_survives_reordering_and_falls_back_when_player_disappears() {
        let a = MediaTrack {
            bus_name: "a".into(),
            ..Default::default()
        };
        let b = MediaTrack {
            bus_name: "b".into(),
            is_playing: true,
            ..Default::default()
        };
        assert_eq!(retain_player(Some("a"), &[b.clone(), a]), Some("a".into()));
        assert_eq!(retain_player(Some("a"), &[b]), Some("b".into()));
        assert_eq!(retain_player(Some("a"), &[]), None);
    }

    #[test]
    fn slider_uses_actual_bounds_and_clamps_pointer() {
        assert_eq!(slider_fraction(40.0, 50.0, 100.0), Some(0.0));
        assert_eq!(slider_fraction(100.0, 50.0, 100.0), Some(0.5));
        assert_eq!(slider_fraction(200.0, 50.0, 100.0), Some(1.0));
        assert_eq!(slider_fraction(100.0, 50.0, 0.0), None);
    }
}
