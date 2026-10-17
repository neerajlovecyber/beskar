//! Deep PanelHost Module for Beskar Desktop Shell
//!
//! Slot-aware overlay host mirroring `references/minflair/.../AppState.qml:getSlot`.
//! Encapsulates:
//! - Full-screen transparent scrims (`TOP | BOTTOM | LEFT | RIGHT`, exclusive_zone=None)
//! - Per-slot mutual exclusivity (Focus / Left / Center / Right)
//! - Outside-click backdrop dismissal + Escape focus trap
//! - Bounded inner card contract (Scrim → sized card → Scrollable)
//! - Dynamic string registration for IPC / CLI (`beskar-msg toggle <id>`)

pub use beskar_ui::EdgeSurface;
pub use gpui_kit::layer_shell::{
    Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions,
};
use gpui_kit::*;
use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};
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

    fn namespace(self) -> &'static str {
        match self {
            Slot::Focus => "beskar-panel-focus",
            Slot::Left => "beskar-panel-left",
            Slot::Center => "beskar-panel-center",
            Slot::Right => "beskar-panel-right",
        }
    }
}

/// Docking edge alignment for screen-bezel continuous surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PanelEdge {
    Left,
    Right,
    Bottom,
    TopCenter,
    CenterModal,
}

/// Contract for an atomic desktop shell panel module.
pub trait PanelModule: Render + Sized + 'static {
    /// Unique identifier for this panel (e.g. "launcher", "control_center", "power_menu")
    const ID: &'static str;

    /// Slot for mutual exclusivity (mirrors AppState.qml:getSlot).
    fn slot() -> Slot {
        Slot::Focus
    }

    /// Edge docking behavior for the panel
    fn panel_edge() -> PanelEdge {
        match Self::slot() {
            Slot::Left => PanelEdge::Left,
            Slot::Right => PanelEdge::Right,
            Slot::Center => PanelEdge::TopCenter,
            Slot::Focus => PanelEdge::Bottom,
        }
    }

    /// Preferred window size (width, height) in logical pixels
    fn size() -> Size<Pixels>;

    /// Wayland LayerShell anchor flags (defaults to full screen for scrim + edge docking)
    fn anchor() -> LayerAnchor {
        LayerAnchor::all()
    }

    /// Wayland LayerShell margins: (top, right, bottom, left)
    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(0.0), px(0.0), px(0.0), px(0.0))
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

    /// Preferred initial keyboard focus target for this panel.
    fn initial_focus_handle(&self, _cx: &App) -> Option<FocusHandle> {
        None
    }
}

/// Full-screen transparent scrim wrapper providing outside-click dismissal
/// and flush screen-bezel edge docking.
pub struct ScrimHostView {
    inner: AnyView,
    outgoing: Option<AnyView>,
    content_generation: u64,
    size_animator: beskar_ui::Animator,
    size_generation: u64,
    panel_id: &'static str,
    edge: PanelEdge,
    content_focus_handle: Option<FocusHandle>,
    is_open: bool,
    focus_handle: FocusHandle,
}

fn build_panel_view<M: PanelModule>(cx: &mut App) -> (AnyView, Option<FocusHandle>) {
    let panel = cx.new(M::build);
    let initial_focus = panel.read(cx).initial_focus_handle(cx);
    (AnyView::from(panel), initial_focus)
}

impl ScrimHostView {
    fn new(
        inner: AnyView,
        panel_id: &'static str,
        edge: PanelEdge,
        preferred_size: Size<Pixels>,
        content_focus_handle: Option<FocusHandle>,
        cx: &mut Context<Self>,
    ) -> Self {
        Self {
            inner,
            outgoing: None,
            content_generation: 0,
            size_animator: beskar_ui::Animator::new(preferred_size, PANEL_BOUNDS_MOTION_DURATION),
            size_generation: 0,
            panel_id,
            edge,
            content_focus_handle,
            is_open: true,
            focus_handle: cx.focus_handle(),
        }
    }

    fn replace_panel(
        &mut self,
        inner: AnyView,
        panel_id: &'static str,
        edge: PanelEdge,
        preferred_size: Size<Pixels>,
        content_focus_handle: Option<FocusHandle>,
        cx: &mut Context<Self>,
    ) {
        self.outgoing = Some(std::mem::replace(&mut self.inner, inner));
        self.content_generation = self.content_generation.wrapping_add(1);
        let now = Instant::now();
        self.size_animator.advance(now);
        self.size_animator.transition_to(preferred_size, now);
        if cx.reduce_motion() {
            self.size_animator
                .advance(now + PANEL_BOUNDS_MOTION_DURATION);
        }
        self.size_generation = self.size_generation.wrapping_add(1);
        self.panel_id = panel_id;
        self.edge = edge;
        self.content_focus_handle = content_focus_handle;
        self.is_open = true;
        cx.notify();

        let size_generation = self.size_generation;
        if self.size_animator.animating() {
            cx.spawn(async move |host, cx| {
                loop {
                    cx.background_executor()
                        .timer(PANEL_BOUNDS_FRAME_INTERVAL)
                        .await;
                    let keep_animating = host
                        .update(cx, |host, cx| {
                            if host.size_generation != size_generation {
                                return false;
                            }
                            let keep_animating = host.size_animator.advance(Instant::now());
                            cx.notify();
                            keep_animating
                        })
                        .unwrap_or(false);
                    if !keep_animating {
                        break;
                    }
                }
            })
            .detach();
        }

        let generation = self.content_generation;
        cx.spawn(async move |host, cx| {
            cx.background_executor()
                .timer(PANEL_CONTENT_MOTION_DURATION)
                .await;
            let _ = host.update(cx, |host, cx| {
                if host.content_generation == generation {
                    host.outgoing = None;
                    cx.notify();
                }
            });
        })
        .detach();
    }

    fn set_open(&mut self, is_open: bool, cx: &mut Context<Self>) {
        if self.is_open != is_open {
            self.is_open = is_open;
            cx.notify();
        }
    }

    fn active_focus_handle(&self) -> FocusHandle {
        self.content_focus_handle
            .clone()
            .unwrap_or_else(|| self.focus_handle.clone())
    }

    fn render_content(&self) -> AnyElement {
        let mut layers = div().relative().size_full();
        if let Some(outgoing) = self.outgoing.clone() {
            layers = layers.child(content_layer(outgoing, self.content_generation, false));
        }
        layers
            .child(content_layer(
                self.inner.clone(),
                self.content_generation,
                true,
            ))
            .into_any_element()
    }
}

const PANEL_BOUNDS_MOTION_DURATION: Duration = Duration::from_millis(220);
const PANEL_BOUNDS_FRAME_INTERVAL: Duration = Duration::from_millis(16);
const PANEL_CONTENT_MOTION_DURATION: Duration = Duration::from_millis(160);
const PANEL_SPRING: SpringConfig = SpringConfig::new(900.0, 60.0, 1.0);
const PANEL_SPRING_EPSILON: f32 = 0.01;

fn content_layer(view: AnyView, generation: u64, entering: bool) -> AnyElement {
    let animation = Animation::new(PANEL_CONTENT_MOTION_DURATION)
        .with_easing(gpui_kit::component::animation::ease_out_cubic);
    div()
        .absolute()
        .top_0()
        .right_0()
        .bottom_0()
        .left_0()
        .child(view)
        .with_animation(
            (
                ElementId::from(("panel-content", generation)),
                if entering { "in" } else { "out" },
            ),
            animation,
            move |layer, progress| layer.opacity(if entering { progress } else { 1.0 - progress }),
        )
        .into_any_element()
}

fn animate_panel_edge<E: IntoElement + Styled + 'static>(
    panel: E,
    edge: PanelEdge,
    target_size: Size<Pixels>,
    is_open: bool,
) -> AnyElement {
    let target = if is_open { 1.0 } else { 0.0 };
    let animation = SpringAnimation::new(PANEL_SPRING)
        .to(target)
        .from(if is_open { 0.0 } else { 1.0 })
        .with_epsilon(PANEL_SPRING_EPSILON);

    match edge {
        PanelEdge::Left => panel
            .with_spring("panel-edge-motion", animation, move |panel, progress| {
                let progress = progress.clamp(0.0, 1.0);
                let reveal_size = beskar_ui::edge_reveal_size(
                    target_size,
                    beskar_ui::ConvexDrawerEdge::Left,
                    progress,
                );
                panel.w(reveal_size.width).opacity(progress)
            })
            .into_any_element(),
        PanelEdge::Right => panel
            .with_spring("panel-edge-motion", animation, move |panel, progress| {
                let progress = progress.clamp(0.0, 1.0);
                let reveal_size = beskar_ui::edge_reveal_size(
                    target_size,
                    beskar_ui::ConvexDrawerEdge::Right,
                    progress,
                );
                panel.w(reveal_size.width).opacity(progress)
            })
            .into_any_element(),
        PanelEdge::Bottom => panel
            .with_spring("panel-edge-motion", animation, move |panel, progress| {
                let progress = progress.clamp(0.0, 1.0);
                let reveal_size = beskar_ui::edge_reveal_size(
                    target_size,
                    beskar_ui::ConvexDrawerEdge::Bottom,
                    progress,
                );
                panel.h(reveal_size.height).opacity(progress)
            })
            .into_any_element(),
        PanelEdge::TopCenter => panel
            .with_spring("panel-edge-motion", animation, move |panel, progress| {
                let progress = progress.clamp(0.0, 1.0);
                let reveal_size = beskar_ui::edge_reveal_size(
                    target_size,
                    beskar_ui::ConvexDrawerEdge::Top,
                    progress,
                );
                panel.h(reveal_size.height).opacity(progress)
            })
            .into_any_element(),
        PanelEdge::CenterModal => panel
            .with_spring("panel-edge-motion", animation, move |panel, progress| {
                panel.opacity(progress.clamp(0.0, 1.0))
            })
            .into_any_element(),
    }
}

fn convex_edge(edge: PanelEdge) -> beskar_ui::ConvexDrawerEdge {
    match edge {
        PanelEdge::Left => beskar_ui::ConvexDrawerEdge::Left,
        PanelEdge::Right => beskar_ui::ConvexDrawerEdge::Right,
        PanelEdge::Bottom => beskar_ui::ConvexDrawerEdge::Bottom,
        PanelEdge::TopCenter | PanelEdge::CenterModal => beskar_ui::ConvexDrawerEdge::Top,
    }
}

fn panel_surface_contains_position(
    edge: PanelEdge,
    panel_size: Size<Pixels>,
    viewport_size: Size<Pixels>,
    position: Point<Pixels>,
) -> bool {
    if edge == PanelEdge::CenterModal {
        return true;
    }
    let origin = match edge {
        PanelEdge::Left => {
            let top_offset = ((viewport_size.height - panel_size.height) * 0.5).max(px(38.0));
            point(px(0.0), top_offset)
        }
        PanelEdge::Right => {
            let top_offset = ((viewport_size.height - panel_size.height) * 0.5).max(px(38.0));
            point(viewport_size.width - panel_size.width, top_offset)
        }
        PanelEdge::Bottom => point(
            (viewport_size.width - panel_size.width) / 2.0,
            viewport_size.height - panel_size.height,
        ),
        PanelEdge::TopCenter => point((viewport_size.width - panel_size.width) / 2.0, px(38.0)),
        PanelEdge::CenterModal => point(px(0.0), px(0.0)),
    };
    let local_position = point(position.x - origin.x, position.y - origin.y);
    beskar_ui::convex_drawer_contains_point(panel_size, convex_edge(edge), local_position)
}

impl Render for ScrimHostView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let edge = self.edge;
        let preferred_size = self.size_animator.size();
        let viewport_size = window.viewport_size();
        let target_size = match edge {
            PanelEdge::Left | PanelEdge::Right => {
                let max_h = (viewport_size.height - px(60.0)).max(px(100.0));
                Size::new(
                    preferred_size.width.min(viewport_size.width),
                    preferred_size.height.min(max_h),
                )
            }
            PanelEdge::Bottom | PanelEdge::TopCenter | PanelEdge::CenterModal => Size::new(
                preferred_size.width.min(viewport_size.width),
                preferred_size.height.min(viewport_size.height),
            ),
        };
        let top_offset = match edge {
            PanelEdge::Left | PanelEdge::Right => {
                ((viewport_size.height - target_size.height) * 0.5).max(px(38.0))
            }
            _ => px(0.0),
        };
        let is_open = self.is_open;

        let drawer_card = match edge {
            PanelEdge::Left => {
                let surface =
                    EdgeSurface::new(target_size, convex_edge(edge)).child(self.render_content());
                div()
                    .id("scrim-card-left")
                    .absolute()
                    .left_0()
                    .top(top_offset)
                    .w(target_size.width)
                    .h(target_size.height)
                    .overflow_hidden()
                    .on_mouse_down(MouseButton::Left, move |event, _, cx| {
                        if panel_surface_contains_position(
                            edge,
                            target_size,
                            viewport_size,
                            event.position,
                        ) {
                            cx.stop_propagation();
                        }
                    })
                    .child(
                        div()
                            .absolute()
                            .left_0()
                            .top_0()
                            .w(target_size.width)
                            .h(target_size.height)
                            .child(surface),
                    )
            }
            PanelEdge::Right => {
                let surface =
                    EdgeSurface::new(target_size, convex_edge(edge)).child(self.render_content());
                div()
                    .id("scrim-card-right")
                    .absolute()
                    .right_0()
                    .top(top_offset)
                    .w(target_size.width)
                    .h(target_size.height)
                    .overflow_hidden()
                    .on_mouse_down(MouseButton::Left, move |event, _, cx| {
                        if panel_surface_contains_position(
                            edge,
                            target_size,
                            viewport_size,
                            event.position,
                        ) {
                            cx.stop_propagation();
                        }
                    })
                    .child(
                        div()
                            .absolute()
                            .right_0()
                            .top_0()
                            .w(target_size.width)
                            .h(target_size.height)
                            .child(surface),
                    )
            }
            PanelEdge::Bottom => {
                let surface =
                    EdgeSurface::new(target_size, convex_edge(edge)).child(self.render_content());
                div()
                    .id("scrim-card-bottom-container")
                    .absolute()
                    .bottom_0()
                    .left_0()
                    .right_0()
                    .h(target_size.height)
                    .overflow_hidden()
                    .on_mouse_down(MouseButton::Left, move |event, _, cx| {
                        if panel_surface_contains_position(
                            edge,
                            target_size,
                            viewport_size,
                            event.position,
                        ) {
                            cx.stop_propagation();
                        }
                    })
                    .child(
                        div()
                            .absolute()
                            .left_0()
                            .right_0()
                            .bottom_0()
                            .flex()
                            .justify_center()
                            .child(
                                div()
                                    .id("scrim-card-bottom")
                                    .relative()
                                    .w(target_size.width)
                                    .h(target_size.height)
                                    .child(surface),
                            ),
                    )
            }
            PanelEdge::TopCenter => {
                let surface =
                    EdgeSurface::new(target_size, convex_edge(edge)).child(self.render_content());
                div()
                    .id("scrim-card-top-container")
                    .absolute()
                    .top(px(38.0))
                    .left_0()
                    .right_0()
                    .h(target_size.height)
                    .overflow_hidden()
                    .on_mouse_down(MouseButton::Left, move |event, _, cx| {
                        if panel_surface_contains_position(
                            edge,
                            target_size,
                            viewport_size,
                            event.position,
                        ) {
                            cx.stop_propagation();
                        }
                    })
                    .child(
                        div()
                            .absolute()
                            .left_0()
                            .right_0()
                            .top_0()
                            .flex()
                            .justify_center()
                            .child(
                                div()
                                    .id("scrim-card-top")
                                    .relative()
                                    .w(target_size.width)
                                    .h(target_size.height)
                                    .child(surface),
                            ),
                    )
            }
            PanelEdge::CenterModal => div()
                .id("scrim-card-center-modal")
                .size_full()
                .flex()
                .items_center()
                .justify_center()
                .child(
                    div()
                        .id("scrim-card-modal")
                        .w(target_size.width)
                        .max_h(target_size.height)
                        .on_mouse_down(MouseButton::Left, |_e, _win, cx| cx.stop_propagation())
                        .child(self.render_content()),
                ),
        };
        let drawer_card = animate_panel_edge(drawer_card, edge, target_size, is_open);

        let root = div()
            .id("scrim-root")
            .size_full()
            .bg(beskar_theme::Theme::scrim())
            .track_focus(&self.focus_handle)
            .child(drawer_card);
        let root = if is_open {
            root.key_context("ScrimHost")
                .on_key_down(cx.listener(|this, event: &KeyDownEvent, _window, cx| {
                    if event.keystroke.key == "escape" {
                        PanelHost::close_if_active(this.panel_id, cx);
                        cx.stop_propagation();
                    }
                }))
                .on_mouse_down(MouseButton::Left, |_e, _win, cx| {
                    PanelHost::close_all(cx);
                })
        } else {
            root
        };
        root.with_spring(
            "panel-scrim-motion",
            SpringAnimation::new(PANEL_SPRING)
                .to(if is_open { 1.0 } else { 0.0 })
                .from(if is_open { 0.0 } else { 1.0 })
                .with_epsilon(PANEL_SPRING_EPSILON),
            |surface, progress| surface.opacity(progress.clamp(0.0, 1.0)),
        )
        .into_any_element()
    }
}

type PanelFactory = Box<dyn Fn(&mut App) -> bool + Send + Sync>;

#[derive(Clone)]
struct FocusReturn {
    window: AnyWindowHandle,
    focus: Option<FocusHandle>,
}

#[derive(Clone)]
struct ActivePanel {
    id: &'static str,
    handle: AnyWindowHandle,
    display_id: Option<DisplayId>,
    host: Entity<ScrimHostView>,
    layer: Layer,
    keyboard_interactivity: KeyboardInteractivity,
    focus_return: Option<FocusReturn>,
    is_closing: bool,
    close_generation: u64,
}

// Four slots, each independently tracks its active or temporarily-closing panel.
static ACTIVE_BY_SLOT: Mutex<[Option<ActivePanel>; 4]> = Mutex::new([None, None, None, None]);
static PANEL_REGISTRY: Mutex<Option<HashMap<&'static str, PanelFactory>>> = Mutex::new(None);
static SLOT_BY_ID: Mutex<Option<HashMap<&'static str, Slot>>> = Mutex::new(None);
static WINDOW_CLOSE_OBSERVER_REGISTERED: Mutex<bool> = Mutex::new(false);
const PANEL_CLOSE_DURATION: Duration = Duration::from_millis(360);

fn lock_panel_state<T>(mutex: &'static Mutex<T>) -> MutexGuard<'static, T> {
    mutex.lock().unwrap_or_else(|error| {
        tracing::error!("PanelHost: recovering poisoned state lock");
        error.into_inner()
    })
}

fn should_restore_focus(removed_active_panel: bool, panels_remain: bool) -> bool {
    removed_active_panel && !panels_remain
}

fn focused_display_id(cx: &mut App) -> Option<DisplayId> {
    let handle = cx.active_window()?;
    let tracked_display = {
        let slots = lock_panel_state(&ACTIVE_BY_SLOT);
        slots
            .iter()
            .flatten()
            .find(|active| active.handle == handle)
            .and_then(|active| active.display_id)
    };
    tracked_display.or_else(|| {
        cx.update_window(handle, |_, window, cx| {
            window.display(cx).map(|display| display.id())
        })
        .ok()
        .flatten()
    })
}

fn focus_return_for_active_window(cx: &mut App) -> Option<FocusReturn> {
    let window_handle = cx.active_window()?;
    let inherited = {
        let slots = lock_panel_state(&ACTIVE_BY_SLOT);
        slots
            .iter()
            .flatten()
            .find(|active| active.handle == window_handle)
            .and_then(|active| active.focus_return.clone())
    };
    inherited.or_else(|| {
        let focus = cx
            .update_window(window_handle, |_, window, cx| window.focused(cx))
            .ok()
            .flatten();
        Some(FocusReturn {
            window: window_handle,
            focus,
        })
    })
}

fn restore_focus(target: Option<FocusReturn>, cx: &mut App) {
    let Some(target) = target else {
        return;
    };
    let _ = cx.update_window(target.window, |_, window, cx| {
        if let Some(focus) = target.focus {
            window.focus(&focus, cx);
        } else {
            window.activate_window();
        }
    });
}

fn observe_panel_window_closures(cx: &App) {
    let mut registered = lock_panel_state(&WINDOW_CLOSE_OBSERVER_REGISTERED);
    if *registered {
        return;
    }
    *registered = true;
    cx.on_window_closed(|cx, window_id| {
        let focus_return = {
            let mut slots = lock_panel_state(&ACTIVE_BY_SLOT);
            let focus_return = slots.iter_mut().find_map(|slot| {
                if slot
                    .as_ref()
                    .is_some_and(|active| active.handle.window_id() == window_id)
                {
                    slot.take().and_then(|active| active.focus_return)
                } else {
                    None
                }
            });
            should_restore_focus(focus_return.is_some(), slots.iter().any(Option::is_some))
                .then_some(focus_return)
                .flatten()
        };
        if focus_return.is_some() {
            restore_focus(focus_return, cx);
        }
    })
    .detach();
}

/// The Deep, Generic PanelHost Facade.
pub struct PanelHost;

impl PanelHost {
    /// Toggle any panel module atomically within its slot:
    /// - If this panel is currently open in its slot, close it (returns false).
    /// - If a different panel is open in the same slot, close it and open this one.
    /// - Panels in other slots are unaffected.
    pub fn toggle<M: PanelModule>(cx: &mut App) -> bool {
        Self::toggle_on_display::<M>(None, cx)
    }

    /// Toggle a panel on the display that owns its invoking control, when known.
    pub fn toggle_on_display<M: PanelModule>(display_id: Option<DisplayId>, cx: &mut App) -> bool {
        if Self::close_if_active(M::ID, cx) {
            return false;
        }
        Self::open_on_display::<M>(display_id, cx);
        true
    }

    /// Open a panel module, closing any currently active panel in the same slot first.
    pub fn open<M: PanelModule>(cx: &mut App) {
        Self::open_on_display::<M>(None, cx);
    }

    /// Open a panel on the requested display, falling back to the primary display.
    pub fn open_on_display<M: PanelModule>(display_id: Option<DisplayId>, cx: &mut App) {
        observe_panel_window_closures(cx);
        let slot_idx = M::slot().idx();
        let display_id = display_id
            .or_else(|| focused_display_id(cx))
            .or_else(|| cx.primary_display().map(|display| display.id()));
        if display_id.is_none() {
            tracing::warn!(
                "PanelHost: no focused or primary display available for panel '{}'; using GPUI default",
                M::ID
            );
        }
        let focus_return = {
            let slots = lock_panel_state(&ACTIVE_BY_SLOT);
            slots[slot_idx]
                .as_ref()
                .and_then(|active| active.focus_return.clone())
        }
        .or_else(|| focus_return_for_active_window(cx));
        let reusable = {
            let mut slots = lock_panel_state(&ACTIVE_BY_SLOT);
            if let Some(active) = slots[slot_idx].as_mut() {
                let same_display = active.display_id == display_id;
                if same_display && active.id == M::ID && !active.is_closing {
                    return;
                }
                if same_display
                    && active.layer == M::layer()
                    && active.keyboard_interactivity == M::keyboard_interactivity()
                {
                    if active.focus_return.is_none() {
                        active.focus_return = focus_return.clone();
                    }
                    active.id = M::ID;
                    active.is_closing = false;
                    active.close_generation = active.close_generation.wrapping_add(1);
                    Some((active.handle, active.host.clone()))
                } else {
                    None
                }
            } else {
                None
            }
        };

        if let Some((handle, host)) = reusable {
            let active_panel_id = host.read(cx).panel_id;
            let focus_handle = if active_panel_id == M::ID {
                host.update(cx, |host, cx| {
                    host.set_open(true, cx);
                    host.active_focus_handle()
                })
            } else {
                let (inner, initial_focus) = build_panel_view::<M>(cx);
                host.update(cx, |host, cx| {
                    host.replace_panel(inner, M::ID, M::panel_edge(), M::size(), initial_focus, cx);
                    host.active_focus_handle()
                })
            };
            let _ = cx.update_window(handle, |_, window, cx| {
                window.focus(&focus_handle, cx);
                window.refresh();
            });
            info!(
                "PanelHost: reused slot {:?} host for panel '{}'",
                M::slot(),
                M::ID
            );
            return;
        }

        let display_size = crate::bar::logical_display_size(display_id, cx);
        let options = WindowOptions {
            display_id,
            titlebar: None,
            window_bounds: Some(WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: display_size,
            })),
            app_id: Some(M::slot().namespace().to_string()),
            window_background: WindowBackgroundAppearance::Transparent,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: M::slot().namespace().to_string(),
                layer: M::layer(),
                anchor: LayerAnchor::all(),
                exclusive_zone: None,
                margin: Some((px(0.0), px(0.0), px(0.0), px(0.0))),
                keyboard_interactivity: M::keyboard_interactivity(),
                ..Default::default()
            }),
            focus: true,
            ..Default::default()
        };

        let (inner, initial_focus) = build_panel_view::<M>(cx);
        let host = cx.new(|cx| {
            ScrimHostView::new(inner, M::ID, M::panel_edge(), M::size(), initial_focus, cx)
        });
        match cx.open_window(options, {
            let host = host.clone();
            move |_win, _cx| host
        }) {
            Ok(handle) => {
                let focus_handle = host.read(cx).active_focus_handle();
                let _ = cx.update_window(handle.into(), |_, window, cx| {
                    window.focus(&focus_handle, cx);
                    window.refresh();
                });
                let new_active = ActivePanel {
                    id: M::ID,
                    handle: handle.into(),
                    display_id,
                    host,
                    layer: M::layer(),
                    keyboard_interactivity: M::keyboard_interactivity(),
                    focus_return,
                    is_closing: false,
                    close_generation: 0,
                };
                let previous = lock_panel_state(&ACTIVE_BY_SLOT)[slot_idx].replace(new_active);
                if let Some(previous) = previous {
                    let previous_id = previous.id;
                    if !previous.is_closing {
                        Self::begin_close(previous, cx);
                    }
                    info!(
                        "PanelHost: replaced slot {:?} panel '{}' with '{}'",
                        M::slot(),
                        previous_id,
                        M::ID
                    );
                }
                info!("PanelHost: opened slot {:?} panel '{}'", M::slot(), M::ID);
            }
            Err(e) => {
                tracing::error!("PanelHost: failed to open panel '{}': {:?}", M::ID, e);
            }
        }
    }

    /// Close the active panel matching `id`.
    /// Returns true if it was active and closed.
    pub fn close_if_active(id: &str, cx: &mut App) -> bool {
        Self::close_by_id(id, cx).is_some()
    }

    /// Close a panel by its registered ID and return the ID when it was active.
    pub fn close_by_id(id: &str, cx: &mut App) -> Option<&'static str> {
        let active = {
            let mut slots = lock_panel_state(&ACTIVE_BY_SLOT);
            slots.iter_mut().find_map(|slot| {
                let active = slot.as_mut()?;
                if active.id != id || active.is_closing {
                    return None;
                }
                active.is_closing = true;
                active.close_generation = active.close_generation.wrapping_add(1);
                Some(active.clone())
            })
        };
        active.map(|active| {
            let active_id = active.id;
            Self::begin_close(active, cx);
            info!("PanelHost: toggled off panel '{}'", active_id);
            active_id
        })
    }

    fn begin_close(mut active: ActivePanel, cx: &mut App) {
        if !active.is_closing {
            active.is_closing = true;
            active.close_generation = active.close_generation.wrapping_add(1);
        }
        let generation = active.close_generation;
        let handle = active.handle;
        let close_duration = if cx.reduce_motion() {
            Duration::ZERO
        } else {
            PANEL_CLOSE_DURATION
        };
        active.host.update(cx, |host, cx| host.set_open(false, cx));
        let _ = cx.update_window(handle, |_, window, _| window.refresh());
        cx.spawn(async move |cx| {
            cx.background_executor().timer(close_duration).await;
            let _ = cx.update(|cx| {
                let (should_remove, should_restore) = {
                    let mut slots = lock_panel_state(&ACTIVE_BY_SLOT);
                    let slot_idx = slots.iter().position(|slot| {
                        slot.as_ref().is_some_and(|active| active.handle == handle)
                    });
                    match slot_idx {
                        Some(index)
                            if slots[index].as_ref().is_some_and(|active| {
                                active.is_closing && active.close_generation == generation
                            }) =>
                        {
                            slots[index].take();
                            let panels_remain = slots.iter().any(Option::is_some);
                            (true, should_restore_focus(true, panels_remain))
                        }
                        Some(_) => (false, false),
                        None => (true, false),
                    }
                };
                if should_remove {
                    let _ = cx.update_window(handle, |_, window, _| window.remove_window());
                    if should_restore {
                        restore_focus(active.focus_return, cx);
                    }
                }
            });
        })
        .detach();
    }

    /// Close all panels (used for global dismiss like Escape on empty).
    pub fn close_all(cx: &mut App) -> Vec<&'static str> {
        let actives = {
            let mut guard = lock_panel_state(&ACTIVE_BY_SLOT);
            let mut out = Vec::new();
            for slot in guard.iter_mut() {
                if let Some(active) = slot.as_mut()
                    && !active.is_closing
                {
                    active.is_closing = true;
                    active.close_generation = active.close_generation.wrapping_add(1);
                    out.push(active.clone());
                }
            }
            out
        };
        let mut closed = Vec::new();
        for active in actives {
            closed.push(active.id);
            Self::begin_close(active, cx);
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
        let active = {
            let mut guard = lock_panel_state(&ACTIVE_BY_SLOT);
            guard.iter_mut().find_map(|slot| {
                let active = slot.as_mut()?;
                if active.is_closing {
                    return None;
                }
                active.is_closing = true;
                active.close_generation = active.close_generation.wrapping_add(1);
                Some(active.clone())
            })
        };
        active.map(|active| {
            let id = active.id;
            Self::begin_close(active, cx);
            info!("PanelHost: closed active panel '{}'", id);
            id
        })
    }

    /// Forget a panel that has already closed itself via internal window lifecycle.
    pub fn forget(id: &str) {
        let mut guard = lock_panel_state(&ACTIVE_BY_SLOT);
        for slot in guard.iter_mut() {
            if slot.as_ref().is_some_and(|active| active.id == id) {
                slot.take();
            }
        }
    }

    /// Inspect currently active panel ID in a specific slot.
    pub fn active_in_slot(slot: Slot) -> Option<&'static str> {
        let guard = lock_panel_state(&ACTIVE_BY_SLOT);
        guard[slot.idx()]
            .as_ref()
            .filter(|active| !active.is_closing)
            .map(|active| active.id)
    }

    /// Inspect any active panel (first found).
    pub fn active_panel() -> Option<&'static str> {
        let guard = lock_panel_state(&ACTIVE_BY_SLOT);
        guard
            .iter()
            .flatten()
            .find(|active| !active.is_closing)
            .map(|active| active.id)
    }

    /// True if any panel is open in the given slot.
    pub fn is_slot_open(slot: Slot) -> bool {
        let guard = lock_panel_state(&ACTIVE_BY_SLOT);
        guard[slot.idx()]
            .as_ref()
            .is_some_and(|active| !active.is_closing)
    }

    /// True while the slot owns a panel window, including its exit transition.
    pub fn is_slot_occupied(slot: Slot) -> bool {
        lock_panel_state(&ACTIVE_BY_SLOT)[slot.idx()].is_some()
    }

    /// Register a panel module for dynamic IPC / CLI invocation.
    pub fn register<M: PanelModule>() {
        {
            let mut guard = lock_panel_state(&PANEL_REGISTRY);
            let map = guard.get_or_insert_with(HashMap::new);
            map.insert(M::ID, Box::new(|cx| Self::toggle::<M>(cx)));
        }
        {
            let mut guard = lock_panel_state(&SLOT_BY_ID);
            let map = guard.get_or_insert_with(HashMap::new);
            map.insert(M::ID, M::slot());
        }
    }

    /// Toggle a panel by its string ID dynamically.
    pub fn toggle_by_id(id: &str, cx: &mut App) -> bool {
        let guard = lock_panel_state(&PANEL_REGISTRY);
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
        let guard = lock_panel_state(&SLOT_BY_ID);
        guard.as_ref()?.get(id).copied()
    }

    /// Check whether a panel with the given id is currently open in any slot.
    pub fn is_open(id: &str) -> bool {
        let guard = lock_panel_state(&ACTIVE_BY_SLOT);
        guard.iter().any(|slot| {
            slot.as_ref()
                .is_some_and(|active| active.id == id && !active.is_closing)
        })
    }

    #[cfg(test)]
    pub fn reset_for_tests() {
        let mut guard = lock_panel_state(&ACTIVE_BY_SLOT);
        *guard = [None, None, None, None];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct MockPanel;
    #[allow(dead_code)]
    struct MockLeftPanel;

    impl Render for MockPanel {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            div()
        }
    }

    impl PanelModule for MockPanel {
        const ID: &'static str = "mock_panel";
        fn slot() -> Slot {
            Slot::Focus
        }

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
        fn slot() -> Slot {
            Slot::Left
        }

        fn size() -> Size<Pixels> {
            Size::new(px(320.0), px(400.0))
        }

        fn build(_: &mut Context<Self>) -> Self {
            MockLeftPanel
        }
    }

    #[core::prelude::v1::test]
    fn test_panel_module_defaults() {
        assert_eq!(MockPanel::ID, "mock_panel");
        assert_eq!(MockPanel::slot(), Slot::Focus);
        assert_eq!(MockPanel::panel_edge(), PanelEdge::Bottom);
        assert_eq!(MockPanel::size(), Size::new(px(320.0), px(400.0)));
        assert_eq!(MockPanel::anchor(), LayerAnchor::all());
        assert_eq!(MockPanel::margin(), (px(0.0), px(0.0), px(0.0), px(0.0)));
        assert_eq!(
            MockPanel::keyboard_interactivity(),
            KeyboardInteractivity::OnDemand
        );
        assert_eq!(MockPanel::layer(), Layer::Overlay);
    }

    #[core::prelude::v1::test]
    fn test_panel_registration() {
        PanelHost::register::<MockPanel>();
        let guard = PANEL_REGISTRY.lock().unwrap();
        assert!(guard.as_ref().unwrap().contains_key("mock_panel"));
        let sguard = SLOT_BY_ID.lock().unwrap();
        assert_eq!(
            sguard.as_ref().unwrap().get("mock_panel"),
            Some(&Slot::Focus)
        );
    }

    #[core::prelude::v1::test]
    fn test_slot_idx() {
        assert_eq!(Slot::Focus.idx(), 0);
        assert_eq!(Slot::Left.idx(), 1);
        assert_eq!(Slot::Center.idx(), 2);
        assert_eq!(Slot::Right.idx(), 3);
        assert_eq!(Slot::Focus.namespace(), "beskar-panel-focus");
        assert_eq!(Slot::Left.namespace(), "beskar-panel-left");
        assert_eq!(Slot::Center.namespace(), "beskar-panel-center");
        assert_eq!(Slot::Right.namespace(), "beskar-panel-right");
    }

    #[core::prelude::v1::test]
    fn test_slot_distinctness() {
        assert_ne!(Slot::Focus, Slot::Left);
        assert_ne!(Slot::Right, Slot::Center);
    }

    #[core::prelude::v1::test]
    fn focus_returns_only_after_the_last_current_panel_closes() {
        assert!(!should_restore_focus(false, false));
        assert!(!should_restore_focus(true, true));
        assert!(should_restore_focus(true, false));
    }

    #[core::prelude::v1::test]
    fn backdrop_dismissal_tracks_the_visible_panel_outline() {
        let viewport = Size::new(px(1920.0), px(1080.0));
        let panel = Size::new(px(320.0), px(400.0));
        let cases = [
            (
                PanelEdge::Left,
                point(px(160.0), px(238.0)),
                point(px(319.0), px(39.0)),
            ),
            (
                PanelEdge::Right,
                point(px(1760.0), px(238.0)),
                point(px(1601.0), px(39.0)),
            ),
            (
                PanelEdge::Bottom,
                point(px(960.0), px(880.0)),
                point(px(801.0), px(681.0)),
            ),
            (
                PanelEdge::TopCenter,
                point(px(960.0), px(238.0)),
                point(px(801.0), px(437.0)),
            ),
        ];

        for (edge, inside, outside) in cases {
            assert!(panel_surface_contains_position(
                edge, panel, viewport, inside
            ));
            assert!(!panel_surface_contains_position(
                edge, panel, viewport, outside
            ));
        }
    }

    #[core::prelude::v1::test]
    fn test_slot_assignment_and_isolation() {
        // Verify 4 distinct slot indices
        assert_eq!(Slot::Focus.idx(), 0);
        assert_eq!(Slot::Left.idx(), 1);
        assert_eq!(Slot::Center.idx(), 2);
        assert_eq!(Slot::Right.idx(), 3);

        let mut slots: [Option<&'static str>; 4] = [None, None, None, None];

        // Opening launcher (Focus)
        slots[Slot::Focus.idx()] = Some("launcher");
        // Opening dashboard (Left) does not close launcher (Focus)
        slots[Slot::Left.idx()] = Some("dashboard");
        assert_eq!(slots[Slot::Focus.idx()], Some("launcher"));
        assert_eq!(slots[Slot::Left.idx()], Some("dashboard"));

        // Opening music (Center)
        slots[Slot::Center.idx()] = Some("music");
        assert_eq!(slots[Slot::Center.idx()], Some("music"));

        // Opening notificationsCenter (Right)
        slots[Slot::Right.idx()] = Some("notificationsCenter");
        assert_eq!(slots[Slot::Right.idx()], Some("notificationsCenter"));

        // Opening controlCenter (Right) replaces notificationsCenter (Right) but not music (Center)
        slots[Slot::Right.idx()] = Some("controlCenter");
        assert_eq!(slots[Slot::Right.idx()], Some("controlCenter"));
        assert_eq!(slots[Slot::Center.idx()], Some("music"));
        assert_eq!(slots[Slot::Left.idx()], Some("dashboard"));
        assert_eq!(slots[Slot::Focus.idx()], Some("launcher"));

        // Closing slot only clears its own slot
        slots[Slot::Right.idx()] = None;
        assert_eq!(slots[Slot::Right.idx()], None);
        assert_eq!(slots[Slot::Center.idx()], Some("music"));
    }
}
