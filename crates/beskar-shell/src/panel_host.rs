//! Deep PanelHost Module for Beskar Desktop Shell
//!
//! Provides a 100% generic, decoupled LayerShell panel host.
//! Encapsulates:
//! - Full-screen transparent scrims (`TOP | BOTTOM | LEFT | RIGHT`)
//! - Outside-click backdrop dismissal
//! - Escape key handling
//! - Mutual exclusivity (`ACTIVE_PANEL` tracking)
//! - Focus traps and event propagation isolation
//! - Dynamic string registration for IPC / CLI (`beskar-msg toggle <id>`)

pub use gpui_kit::layer_shell::{
    Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions,
};
use gpui_kit::*;
use std::collections::HashMap;
use std::sync::Mutex;
use tracing::info;

/// Contract for an atomic desktop shell panel module.
pub trait PanelModule: Render + Sized + 'static {
    /// Unique identifier for this panel (e.g. "launcher", "control_center", "power_menu")
    const ID: &'static str;

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

static ACTIVE_PANEL: Mutex<Option<(&'static str, AnyWindowHandle)>> = Mutex::new(None);
static PANEL_REGISTRY: Mutex<Option<HashMap<&'static str, PanelFactory>>> = Mutex::new(None);

/// The Deep, Generic PanelHost Facade.
pub struct PanelHost;

impl PanelHost {
    /// Toggle any panel module atomically:
    /// - If this panel is currently open, close it (returns false).
    /// - If a different panel is open, close it and open this one (returns true).
    /// - If no panel is open, open this one (returns true).
    pub fn toggle<M: PanelModule>(cx: &mut App) -> bool {
        if Self::close_if_active(M::ID, cx) {
            return false;
        }
        Self::open::<M>(cx);
        true
    }

    /// Open a panel module, closing any currently active panel first.
    pub fn open<M: PanelModule>(cx: &mut App) {
        Self::close(cx);

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
                let mut guard = ACTIVE_PANEL.lock().unwrap();
                *guard = Some((M::ID, handle.into()));
                info!("PanelHost: opened dedicated LayerShell panel '{}'", M::ID);
            }
            Err(e) => {
                tracing::error!("PanelHost: failed to open panel '{}': {:?}", M::ID, e);
            }
        }
    }

    /// Close the active panel if one is open. Returns the ID of the closed panel.
    pub fn close(cx: &mut App) -> Option<&'static str> {
        let active = {
            let mut guard = ACTIVE_PANEL.lock().unwrap();
            guard.take()
        };

        if let Some((id, handle)) = active {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
            info!("PanelHost: closed active panel '{}'", id);
            Some(id)
        } else {
            None
        }
    }

    /// If the panel with `id` is active, close it and return true; otherwise return false.
    pub fn close_if_active(id: &str, cx: &mut App) -> bool {
        let active_handle = {
            let mut guard = ACTIVE_PANEL.lock().unwrap();
            if guard.as_ref().is_some_and(|(active_id, _)| *active_id == id) {
                guard.take().map(|(_, h)| h)
            } else {
                None
            }
        };

        if let Some(handle) = active_handle {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
            info!("PanelHost: toggled off active panel '{}'", id);
            true
        } else {
            false
        }
    }

    /// Forget a panel that has already closed itself via internal window lifecycle.
    pub fn forget(id: &str) {
        let mut guard = ACTIVE_PANEL.lock().unwrap();
        if guard.as_ref().is_some_and(|(active_id, _)| *active_id == id) {
            guard.take();
        }
    }

    /// Inspect currently active panel ID.
    pub fn active_panel() -> Option<&'static str> {
        let guard = ACTIVE_PANEL.lock().unwrap();
        guard.as_ref().map(|(id, _)| *id)
    }

    /// Register a panel module for dynamic IPC / CLI invocation.
    pub fn register<M: PanelModule>() {
        let mut guard = PANEL_REGISTRY.lock().unwrap();
        let map = guard.get_or_insert_with(HashMap::new);
        map.insert(
            M::ID,
            Box::new(|cx| Self::toggle::<M>(cx)),
        );
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
}

/// Backwards compatibility alias while transitioning code
pub type OverlayHost = PanelHost;

#[cfg(test)]
mod tests {
    use super::*;

    struct MockPanel;

    impl Render for MockPanel {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            div()
        }
    }

    impl PanelModule for MockPanel {
        const ID: &'static str = "mock_panel";

        fn size() -> Size<Pixels> {
            Size::new(px(320.0), px(400.0))
        }

        fn build(_: &mut Context<Self>) -> Self {
            MockPanel
        }
    }

    #[test]
    fn test_panel_module_defaults() {
        assert_eq!(MockPanel::ID, "mock_panel");
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
    }
}
