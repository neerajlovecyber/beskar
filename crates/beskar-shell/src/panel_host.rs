//! Deep PanelHost Module for Beskar Desktop Shell
//!
//! Slot-aware overlay host mirroring `references/minflair/.../AppState.qml:getSlot`.
//! Encapsulates:
//! - Full-screen transparent scrims (`TOP | BOTTOM | LEFT | RIGHT`, exclusive_zone=None)
//! - Per-slot mutual exclusivity (Focus / Left / Center / Right)
//! - Outside-click backdrop dismissal + Escape focus trap
//! - Bounded inner card contract (Scrim → sized card → Scrollable)
//! - Dynamic string registration for IPC / CLI (`beskar-msg toggle <id>`)

pub use gpui_kit::layer_shell::{
    Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions,
};
use gpui_kit::*;
use std::collections::HashMap;
use std::sync::Mutex;
use tracing::info;

/// Mirrors `AppState.qml:getSlot` / `focusWidgets` vs bar slots.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Slot {
    /// launcher, clipboard, wallpaper_selector, screen_capture, power_menu
    Focus,
    /// dashboard
    Left,
    /// music_player
    Center,
    /// control_center, notification_center, clock detail, systemTray_* menus
    Right,
}

impl Slot {
    fn idx(self) -> usize {
        match self {
            Slot::Focus => 0,
            Slot::Left => 1,
            Slot::Center => 2,
            Slot::Right => 3,
        }
    }
}

/// Contract for an atomic desktop shell panel module.
pub trait PanelModule: Render + Sized + 'static {
    /// Unique identifier for this panel (e.g. "launcher", "control_center", "power_menu")
    const ID: &'static str;

    /// Slot for mutual exclusivity (mirrors AppState.qml:getSlot).
    fn slot() -> Slot {
        Slot::Focus
    }

    /// Preferred window size (width, height) in logical pixels
    fn size() -> Size<Pixels>;

    /// Wayland LayerShell anchor flags (defaults to TOP | RIGHT)
    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP | LayerAnchor::RIGHT
    }

    /// Wayland LayerShell margins: (top, right, bottom, left)
    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(48.0), px(16.0), px(0.0), px(0.0))
    }

    /// Wayland keyboard interactivity mode (defaults to OnDemand, LockScreen uses Exclusive)
    fn keyboard_interactivity() -> KeyboardInteractivity {
        KeyboardInteractivity::OnDemand
    }

    /// Wayland layer (defaults to Overlay)
    fn layer() -> Layer {
        Layer::Overlay
    }

    /// Construct the panel view
    fn build(cx: &mut Context<Self>) -> Self;
}

type PanelFactory = Box<dyn Fn(&mut App) -> bool + Send + Sync>;

// Four slots, each independently tracks its active panel.
static ACTIVE_BY_SLOT: Mutex<[Option<(&'static str, AnyWindowHandle)>; 4]> =
    Mutex::new([None, None, None, None]);
static PANEL_REGISTRY: Mutex<Option<HashMap<&'static str, PanelFactory>>> = Mutex::new(None);
static SLOT_BY_ID: Mutex<Option<HashMap<&'static str, Slot>>> = Mutex::new(None);

/// The Deep, Generic PanelHost Facade.
pub struct PanelHost;

impl PanelHost {
    /// Toggle any panel module atomically within its slot:
    /// - If this panel is currently open in its slot, close it (returns false).
    /// - If a different panel is open in the same slot, close it and open this one.
    /// - Panels in other slots are unaffected.
    pub fn toggle<M: PanelModule>(cx: &mut App) -> bool {
        if Self::close_if_active(M::ID, cx) {
            return false;
        }
        Self::open::<M>(cx);
        true
    }

    /// Open a panel module, closing any currently active panel in the same slot first.
    pub fn open<M: PanelModule>(cx: &mut App) {
        let slot_idx = M::slot().idx();
        // Close existing in same slot only
        let existing = {
            let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
            guard[slot_idx].take()
        };
        if let Some((id, handle)) = existing {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
            info!("PanelHost: closed slot {:?} panel '{}' to open '{}'", M::slot(), id, M::ID);
        }

        let options = WindowOptions {
            titlebar: None,
            window_bounds: Some(WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: M::size(),
            })),
            app_id: Some(format!("beskar-{}", M::ID)),
            window_background: WindowBackgroundAppearance::Transparent,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: format!("beskar-{}", M::ID),
                layer: M::layer(),
                anchor: M::anchor(),
                exclusive_zone: None,
                margin: Some(M::margin()),
                keyboard_interactivity: M::keyboard_interactivity(),
                ..Default::default()
            }),
            focus: true,
            ..Default::default()
        };

        match cx.open_window(options, move |_win, cx| cx.new(M::build)) {
            Ok(handle) => {
                let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
                guard[slot_idx] = Some((M::ID, handle.into()));
                info!("PanelHost: opened slot {:?} panel '{}'", M::slot(), M::ID);
            }
            Err(e) => {
                tracing::error!("PanelHost: failed to open panel '{}': {:?}", M::ID, e);
            }
        }
    }

    /// Close the active panel in any slot matching `id`. Scans all slots.
    /// Returns true if it was active and closed.
    pub fn close_if_active(id: &str, cx: &mut App) -> bool {
        let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
        for slot in guard.iter_mut() {
            if slot.as_ref().is_some_and(|(active_id, _)| *active_id == id) {
                if let Some((_, handle)) = slot.take() {
                    let _ = cx.update_window(handle, |_, window, _| {
                        window.remove_window();
                    });
                    info!("PanelHost: toggled off panel '{}'", id);
                    return true;
                }
            }
        }
        false
    }

    /// Close all panels (used for global dismiss like Escape on empty).
    pub fn close_all(cx: &mut App) -> Vec<&'static str> {
        let actives = {
            let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
            let mut out = Vec::new();
            for slot in guard.iter_mut() {
                if let Some((id, handle)) = slot.take() {
                    out.push((id, handle));
                }
            }
            out
        };
        let mut closed = Vec::new();
        for (id, handle) in actives {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
            closed.push(id);
        }
        if !closed.is_empty() {
            info!("PanelHost: closed all panels {:?}", closed);
        }
        closed
    }

    /// Close the active panel in the slot of the given id (legacy single-close alias).
    /// Prefer `close_all` or `close_if_active` for new code.
    pub fn close(cx: &mut App) -> Option<&'static str> {
        // Close the most recently relevant: scan Focus → Right priority, close first found
        // For backwards compat, close Focus slot first if occupied, otherwise any.
        let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
        for slot in guard.iter_mut() {
            if let Some((id, handle)) = slot.take() {
                let _ = cx.update_window(handle, |_, window, _| {
                    window.remove_window();
                });
                info!("PanelHost: closed active panel '{}'", id);
                return Some(id);
            }
        }
        None
    }

    /// Forget a panel that has already closed itself via internal window lifecycle.
    pub fn forget(id: &str) {
        let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
        for slot in guard.iter_mut() {
            if slot.as_ref().is_some_and(|(active_id, _)| *active_id == id) {
                slot.take();
            }
        }
    }

    /// Inspect currently active panel ID in a specific slot.
    pub fn active_in_slot(slot: Slot) -> Option<&'static str> {
        let guard = ACTIVE_BY_SLOT.lock().unwrap();
        guard[slot.idx()].as_ref().map(|(id, _)| *id)
    }

    /// Inspect any active panel (first found).
    pub fn active_panel() -> Option<&'static str> {
        let guard = ACTIVE_BY_SLOT.lock().unwrap();
        for slot in guard.iter().flatten() {
            return Some(slot.0);
        }
        None
    }

    /// True if any panel is open in the given slot.
    pub fn is_slot_open(slot: Slot) -> bool {
        let guard = ACTIVE_BY_SLOT.lock().unwrap();
        guard[slot.idx()].is_some()
    }

    /// Register a panel module for dynamic IPC / CLI invocation.
    pub fn register<M: PanelModule>() {
        {
            let mut guard = PANEL_REGISTRY.lock().unwrap();
            let map = guard.get_or_insert_with(HashMap::new);
            map.insert(M::ID, Box::new(|cx| Self::toggle::<M>(cx)));
        }
        {
            let mut guard = SLOT_BY_ID.lock().unwrap();
            let map = guard.get_or_insert_with(HashMap::new);
            map.insert(M::ID, M::slot());
        }
    }

    /// Toggle a panel by its string ID dynamically.
    pub fn toggle_by_id(id: &str, cx: &mut App) -> bool {
        let guard = PANEL_REGISTRY.lock().unwrap();
        if let Some(map) = guard.as_ref()
            && let Some(func) = map.get(id)
        {
            return func(cx);
        }
        tracing::warn!("PanelHost: no registered panel module with id '{}'", id);
        false
    }

    /// Slot for a registered id (for diagnostics).
    pub fn slot_for_id(id: &str) -> Option<Slot> {
        let guard = SLOT_BY_ID.lock().unwrap();
        guard.as_ref()?.get(id).copied()
    }

    #[cfg(test)]
    pub fn reset_for_tests() {
        let mut guard = ACTIVE_BY_SLOT.lock().unwrap();
        *guard = [None, None, None, None];
    }
}

/// Backwards compatibility alias while transitioning code
pub type OverlayHost = PanelHost;

#[cfg(test)]
mod tests {
    use super::*;

    struct MockPanel;
    struct MockLeftPanel;

    impl Render for MockPanel {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            div()
        }
    }

    impl PanelModule for MockPanel {
        const ID: &'static str = "mock_panel";
        fn slot() -> Slot { Slot::Focus }

        fn size() -> Size<Pixels> {
            Size::new(px(320.0), px(400.0))
        }

        fn build(_: &mut Context<Self>) -> Self {
            MockPanel
        }
    }

    impl Render for MockLeftPanel {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            div()
        }
    }

    impl PanelModule for MockLeftPanel {
        const ID: &'static str = "mock_left_panel";
        fn slot() -> Slot { Slot::Left }

        fn size() -> Size<Pixels> {
            Size::new(px(320.0), px(400.0))
        }

        fn build(_: &mut Context<Self>) -> Self {
            MockLeftPanel
        }
    }

    #[test]
    fn test_panel_module_defaults() {
        assert_eq!(MockPanel::ID, "mock_panel");
        assert_eq!(MockPanel::slot(), Slot::Focus);
        assert_eq!(MockPanel::size(), Size::new(px(320.0), px(400.0)));
        assert_eq!(MockPanel::anchor(), LayerAnchor::TOP | LayerAnchor::RIGHT);
        assert_eq!(MockPanel::margin(), (px(48.0), px(16.0), px(0.0), px(0.0)));
        assert_eq!(MockPanel::keyboard_interactivity(), KeyboardInteractivity::OnDemand);
        assert_eq!(MockPanel::layer(), Layer::Overlay);
    }

    #[test]
    fn test_panel_registration() {
        PanelHost::register::<MockPanel>();
        let guard = PANEL_REGISTRY.lock().unwrap();
        assert!(guard.as_ref().unwrap().contains_key("mock_panel"));
        let sguard = SLOT_BY_ID.lock().unwrap();
        assert_eq!(sguard.as_ref().unwrap().get("mock_panel"), Some(&Slot::Focus));
    }

    #[test]
    fn test_slot_idx() {
        assert_eq!(Slot::Focus.idx(), 0);
        assert_eq!(Slot::Left.idx(), 1);
        assert_eq!(Slot::Center.idx(), 2);
        assert_eq!(Slot::Right.idx(), 3);
    }

    #[test]
    fn test_slot_distinctness() {
        assert_ne!(Slot::Focus, Slot::Left);
        assert_ne!(Slot::Right, Slot::Center);
    }
}
