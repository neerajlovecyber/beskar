//! Deep OverlayHost Module for Beskar Desktop Shell
//!
//! Provides a unified, encapsulated interface for opening, closing, and toggling
//! Wayland LayerShell overlay surfaces. Encapsulates:
//! - Full-screen transparent scrims (`TOP | BOTTOM | LEFT | RIGHT`)
//! - Outside-click backdrop dismissal
//! - Escape key handling
//! - Mutual exclusivity (`ACTIVE_OVERLAY` mutex)
//! - Focus traps and event propagation isolation

use gpui_kit::layer_shell::{
    Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions,
};
use gpui_kit::*;
use std::sync::Mutex;
use tracing::info;

use crate::overlays::*;

/// Discriminant for every managed interactive overlay.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OverlayKind {
    Launcher,
    ControlCenter,
    PowerMenu,
    Settings,
    Clipboard,
    Dashboard,
    Music,
    NotificationCenter,
    ScreenCapture,
    WallpaperSelector,
    LockScreen,
}

impl OverlayKind {
    pub fn app_id(&self) -> &'static str {
        match self {
            Self::Launcher => "beskar-launcher",
            Self::ControlCenter => "beskar-control-center",
            Self::PowerMenu => "beskar-power-menu",
            Self::Settings => "beskar-settings",
            Self::Clipboard => "beskar-clipboard",
            Self::Dashboard => "beskar-dashboard",
            Self::Music => "beskar-music",
            Self::NotificationCenter => "beskar-notifications",
            Self::ScreenCapture => "beskar-screencapture",
            Self::WallpaperSelector => "beskar-wallpapers",
            Self::LockScreen => "beskar-lockscreen",
        }
    }

    pub fn namespace(&self) -> &'static str {
        self.app_id()
    }

    pub fn keyboard_interactivity(&self) -> KeyboardInteractivity {
        match self {
            Self::LockScreen => KeyboardInteractivity::Exclusive,
            _ => KeyboardInteractivity::OnDemand,
        }
    }
}

/// Global tracking of the single active overlay window.
static ACTIVE_OVERLAY: Mutex<Option<(OverlayKind, AnyWindowHandle)>> = Mutex::new(None);

/// The Deep OverlayHost Facade.
pub struct OverlayHost;

impl OverlayHost {
    /// Toggle an overlay:
    /// - If the requested overlay is currently open, close it (toggle off).
    /// - If a different overlay is open, close it and open the requested one.
    /// - If no overlay is open, open the requested one.
    pub fn toggle(kind: OverlayKind, cx: &mut App) {
        if Self::close(cx) == Some(kind) {
            return;
        }
        Self::open(kind, cx);
    }

    /// Open an overlay, closing any existing active overlay first.
    pub fn open(kind: OverlayKind, cx: &mut App) {
        Self::close(cx);

        let options = WindowOptions {
            titlebar: None,
            app_id: Some(kind.app_id().to_string()),
            window_background: WindowBackgroundAppearance::Transparent,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: kind.namespace().to_string(),
                layer: Layer::Overlay,
                anchor: LayerAnchor::TOP
                    | LayerAnchor::BOTTOM
                    | LayerAnchor::LEFT
                    | LayerAnchor::RIGHT,
                exclusive_zone: None,
                keyboard_interactivity: kind.keyboard_interactivity(),
                ..Default::default()
            }),
            focus: true,
            ..Default::default()
        };

        let result: Result<AnyWindowHandle, _> = match kind {
            OverlayKind::Launcher => cx
                .open_window(options, move |_win, cx| cx.new(LauncherView::new))
                .map(|h| h.into()),
            OverlayKind::ControlCenter => cx
                .open_window(options, move |_win, cx| cx.new(ControlCenterView::new))
                .map(|h| h.into()),
            OverlayKind::PowerMenu => cx
                .open_window(options, move |_win, cx| cx.new(PowerMenuView::new))
                .map(|h| h.into()),
            OverlayKind::Settings => cx
                .open_window(options, move |_win, cx| cx.new(SettingsView::new))
                .map(|h| h.into()),
            OverlayKind::Clipboard => cx
                .open_window(options, move |_win, cx| cx.new(ClipboardView::new))
                .map(|h| h.into()),
            OverlayKind::Dashboard => cx
                .open_window(options, move |_win, cx| cx.new(DashboardView::new))
                .map(|h| h.into()),
            OverlayKind::Music => cx
                .open_window(options, move |_win, cx| cx.new(MusicPlayerView::new))
                .map(|h| h.into()),
            OverlayKind::NotificationCenter => cx
                .open_window(options, move |_win, cx| cx.new(NotificationCenterView::new))
                .map(|h| h.into()),
            OverlayKind::ScreenCapture => cx
                .open_window(options, move |_win, cx| cx.new(ScreenCaptureView::new))
                .map(|h| h.into()),
            OverlayKind::WallpaperSelector => cx
                .open_window(options, move |_win, cx| cx.new(WallpaperSelectorView::new))
                .map(|h| h.into()),
            OverlayKind::LockScreen => cx
                .open_window(options, move |_win, cx| cx.new(LockScreenView::new))
                .map(|h| h.into()),
        };

        if let Ok(handle) = result {
            let mut guard = ACTIVE_OVERLAY.lock().unwrap();
            *guard = Some((kind, handle));
            info!("OverlayHost: opened dedicated LayerShell overlay {:?}", kind);
        }
    }

    /// Close the active overlay if one is open. Returns the kind of overlay that was closed.
    pub fn close(cx: &mut App) -> Option<OverlayKind> {
        let active = {
            let mut guard = ACTIVE_OVERLAY.lock().unwrap();
            guard.take()
        };

        if let Some((kind, handle)) = active {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
            info!("OverlayHost: closed active overlay {:?}", kind);
            Some(kind)
        } else {
            None
        }
    }

    /// Forget an overlay that has closed itself via window lifecycle.
    pub fn forget(kind: OverlayKind) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        if guard.as_ref().is_some_and(|(k, _)| *k == kind) {
            guard.take();
        }
    }

    /// Inspect current active overlay kind.
    pub fn active_overlay() -> Option<OverlayKind> {
        let guard = ACTIVE_OVERLAY.lock().unwrap();
        guard.as_ref().map(|(k, _)| *k)
    }
}
