//! Satellite overlay engine for non-intrusive floating OSD panels.
//! Ported directly from `references/capsule/crates/app/src/capsule/satellite/mod.rs`
//! and `animator.rs`.

use std::time::{Duration, Instant};
use gpui_kit::gpui::{px, Bounds, Pixels, Size};

pub use crate::satellite_layout::{centered_y, SatelliteLayout, Side};

pub const CALENDAR_WIDTH: f32 = 300.0;
pub const CALENDAR_HEIGHT: f32 = 300.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SatelliteId {
    Calendar,
    Wifi,
    Bluetooth,
    Audio,
    Tray { bus: String, path: String },
}

impl SatelliteId {
    pub fn title_key(&self) -> &'static str {
        match self {
            Self::Calendar => "dashboard.calendar",
            Self::Wifi => "quick_settings.wifi_networks",
            Self::Bluetooth => "quick_settings.bt_devices",
            Self::Audio => "dashboard.audio_output",
            Self::Tray { .. } => "dashboard.tray",
        }
    }

    pub fn size(&self) -> Size<Pixels> {
        match self {
            Self::Calendar => Size {
                width: px(CALENDAR_WIDTH),
                height: px(CALENDAR_HEIGHT),
            },
            Self::Audio => Size {
                width: px(320.0),
                height: px(300.0),
            },
            _ => Size {
                width: px(320.0),
                height: px(400.0),
            },
        }
    }
}

pub struct SatelliteAnimator {
    progress: f32,
    start: f32,
    target: f32,
    started_at: Option<Instant>,
    duration: Duration,
}

impl Default for SatelliteAnimator {
    fn default() -> Self {
        Self::new()
    }
}

impl SatelliteAnimator {
    pub fn new() -> Self {
        Self {
            progress: 0.0,
            start: 0.0,
            target: 0.0,
            started_at: None,
            duration: Duration::ZERO,
        }
    }

    pub fn progress(&self) -> f32 {
        self.progress
    }

    pub fn open(&self) -> bool {
        self.target == 1.0
    }

    pub fn transition(&mut self, open: bool, duration: Duration, now: Instant) {
        self.advance(now);
        let target = if open { 1.0 } else { 0.0 };
        if (self.target - target).abs() < f32::EPSILON {
            return;
        }
        self.start = self.progress;
        self.target = target;
        self.duration = duration.mul_f32((target - self.start).abs());
        self.started_at = Some(now);
        self.advance(now);
    }

    pub fn advance(&mut self, now: Instant) -> bool {
        let Some(started_at) = self.started_at else {
            return false;
        };
        let elapsed = now.saturating_duration_since(started_at);
        if elapsed >= self.duration {
            self.progress = self.target;
            self.started_at = None;
            return false;
        }
        let t = elapsed.as_secs_f32() / self.duration.as_secs_f32();
        let eased = 1.0 - (1.0 - t).powi(3);
        self.progress = self.start + (self.target - self.start) * eased;
        true
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct SatelliteVisual {
    pub id: SatelliteId,
    pub layout: SatelliteLayout,
    pub progress: f32,
    pub open: bool,
}

pub struct Panel {
    pub id: SatelliteId,
    pub side: Side,
    pub animator: SatelliteAnimator,
}

pub struct Satellite {
    pub panels: Vec<Panel>,
}

impl Default for Satellite {
    fn default() -> Self {
        Self::new()
    }
}

impl Satellite {
    pub fn new() -> Self {
        Self { panels: Vec::new() }
    }

    pub fn open(&self) -> bool {
        self.panels.iter().any(|panel| panel.animator.open())
    }

    pub fn contains(&self, id: &SatelliteId) -> bool {
        self.panels.iter().any(|panel| &panel.id == id)
    }

    pub fn maximum_size() -> Size<Pixels> {
        Size {
            width: px(320.0),
            height: px(400.0),
        }
    }

    pub fn next_side(&self, id: &SatelliteId) -> Side {
        if let Some(panel) = self.panels.iter().find(|panel| &panel.id == id) {
            return panel.side;
        }
        [Side::Left, Side::Right]
            .into_iter()
            .find(|side| {
                !self
                    .panels
                    .iter()
                    .any(|panel| panel.side == *side && panel.animator.open())
            })
            .or_else(|| {
                self.panels
                    .iter()
                    .find(|panel| panel.animator.open())
                    .map(|panel| panel.side)
            })
            .unwrap_or(Side::Left)
    }

    pub fn transition(&mut self, id: SatelliteId, open: bool, duration: Duration, side: Side) {
        if open {
            self.panels
                .retain(|panel| panel.id == id || panel.side != side);
            if let Some(index) = self.panels.iter().position(|panel| panel.id == id) {
                let panel = self.panels.remove(index);
                self.panels.push(panel);
            }
        } else if !self.contains(&id) {
            return;
        }
        if !self.contains(&id) {
            self.panels.push(Panel {
                id: id.clone(),
                side,
                animator: SatelliteAnimator::new(),
            });
        }
        if let Some(panel) = self.panels.iter_mut().find(|panel| panel.id == id) {
            panel.side = side;
            panel.animator.transition(open, duration, Instant::now());
        }
    }

    pub fn advance(&mut self, now: Instant) -> bool {
        let mut running = false;
        for panel in &mut self.panels {
            running |= panel.animator.advance(now);
        }
        self.panels
            .retain(|panel| panel.animator.open() || panel.animator.progress() > 0.0);
        running
    }

    pub fn layout(
        &self,
        viewport: Size<Pixels>,
        capsule: Bounds<Pixels>,
        gap: Pixels,
        measured: &[(SatelliteId, Bounds<Pixels>)],
    ) -> Vec<SatelliteVisual> {
        let mut visuals: Vec<_> = self
            .panels
            .iter()
            .filter(|panel| panel.animator.progress() > 0.0)
            .map(|panel| SatelliteVisual {
                id: panel.id.clone(),
                layout: SatelliteLayout::new(
                    viewport,
                    capsule,
                    panel.id.size(),
                    gap,
                    panel.side,
                    panel.animator.progress(),
                ),
                progress: panel.animator.progress(),
                open: panel.animator.open(),
            })
            .collect();
        for visual in &mut visuals {
            if visual.layout.side == Side::Below {
                continue;
            }
            let maximum = visual.id.size().height.min(viewport.height);
            visual.layout.content_size.height = maximum;
            visual.layout.bounds.size.height = maximum;
            let visible = measured
                .iter()
                .find(|(id, _)| *id == visual.id)
                .map(|(_, bounds)| bounds.size.height)
                .unwrap_or(px(72.0))
                .min(maximum);
            visual.layout.bounds.origin.y = centered_y(capsule, visible, viewport.height);
        }
        visuals
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gpui_kit::gpui::point;

    fn transition(satellites: &mut Satellite, id: SatelliteId, open: bool, duration: Duration) {
        let side = satellites.next_side(&id);
        satellites.transition(id, open, duration, side);
    }

    #[test]
    fn reversing_preserves_position_and_finishes_without_idle_frames() {
        let now = Instant::now();
        let mut animator = SatelliteAnimator::new();
        animator.transition(true, Duration::from_millis(200), now);
        assert!(animator.advance(now + Duration::from_millis(100)));
        let displayed = animator.progress();
        animator.transition(
            false,
            Duration::from_millis(200),
            now + Duration::from_millis(100),
        );
        assert_eq!(animator.progress(), displayed);
        assert!(!animator.advance(now + Duration::from_millis(300)));
        assert_eq!(animator.progress(), 0.0);
        assert!(!animator.advance(now + Duration::from_secs(1)));
    }

    #[test]
    fn zero_duration_opens_and_closes_immediately() {
        let mut animator = SatelliteAnimator::new();
        let now = Instant::now();
        animator.transition(true, Duration::ZERO, now);
        assert_eq!(animator.progress(), 1.0);
        animator.transition(false, Duration::ZERO, now);
        assert_eq!(animator.progress(), 0.0);
    }

    #[test]
    fn panels_fill_both_sides_and_replace_the_oldest() {
        let mut satellites = Satellite::new();
        transition(&mut satellites, SatelliteId::Wifi, true, Duration::ZERO);
        transition(
            &mut satellites,
            SatelliteId::Bluetooth,
            true,
            Duration::ZERO,
        );
        assert_eq!(satellites.panels[0].side, Side::Left);
        assert_eq!(satellites.panels[1].side, Side::Right);
        transition(&mut satellites, SatelliteId::Audio, true, Duration::ZERO);
        assert!(!satellites.contains(&SatelliteId::Wifi));
        assert_eq!(satellites.panels[1].side, Side::Left);
        transition(&mut satellites, SatelliteId::Calendar, true, Duration::ZERO);
        assert!(!satellites.contains(&SatelliteId::Bluetooth));
        assert_eq!(satellites.panels[1].side, Side::Right);
        assert_eq!(satellites.panels.len(), 2);
    }

    #[test]
    fn reopening_a_closing_panel_makes_it_the_newest() {
        let mut satellites = Satellite::new();
        transition(&mut satellites, SatelliteId::Wifi, true, Duration::ZERO);
        transition(
            &mut satellites,
            SatelliteId::Bluetooth,
            true,
            Duration::ZERO,
        );
        transition(
            &mut satellites,
            SatelliteId::Wifi,
            false,
            Duration::from_millis(130),
        );
        transition(&mut satellites, SatelliteId::Wifi, true, Duration::ZERO);
        transition(&mut satellites, SatelliteId::Audio, true, Duration::ZERO);
        assert!(satellites.contains(&SatelliteId::Wifi));
        assert!(!satellites.contains(&SatelliteId::Bluetooth));
    }

    #[test]
    fn a_closed_side_is_reused_without_evicting_the_other() {
        let mut satellites = Satellite::new();
        transition(&mut satellites, SatelliteId::Wifi, true, Duration::ZERO);
        transition(
            &mut satellites,
            SatelliteId::Bluetooth,
            true,
            Duration::ZERO,
        );
        transition(&mut satellites, SatelliteId::Wifi, false, Duration::ZERO);
        satellites.advance(Instant::now());
        transition(&mut satellites, SatelliteId::Audio, true, Duration::ZERO);
        assert!(satellites.contains(&SatelliteId::Bluetooth));
        assert_eq!(satellites.panels[1].side, Side::Left);
    }

    #[test]
    fn opening_and_closing_panels_preserves_the_others() {
        let mut satellites = Satellite::new();
        transition(&mut satellites, SatelliteId::Wifi, true, Duration::ZERO);
        transition(
            &mut satellites,
            SatelliteId::Tray {
                bus: "test".into(),
                path: "/test".into(),
            },
            true,
            Duration::ZERO,
        );
        assert_eq!(satellites.panels.len(), 2);
        transition(
            &mut satellites,
            SatelliteId::Tray {
                bus: "test".into(),
                path: "/test".into(),
            },
            false,
            Duration::ZERO,
        );
        assert!(!satellites.advance(Instant::now()));
        assert!(satellites.contains(&SatelliteId::Wifi));
        assert!(!satellites.contains(&SatelliteId::Tray {
            bus: "test".into(),
            path: "/test".into(),
        }));
        assert!(satellites.open());
        transition(
            &mut satellites,
            SatelliteId::Tray {
                bus: "test".into(),
                path: "/test".into(),
            },
            true,
            Duration::ZERO,
        );
        assert_eq!(satellites.panels.len(), 2);
    }

    #[test]
    fn one_panel_per_side_is_centered_on_the_capsule() {
        let mut satellites = Satellite::new();
        transition(&mut satellites, SatelliteId::Wifi, true, Duration::ZERO);
        transition(
            &mut satellites,
            SatelliteId::Tray {
                bus: "test".into(),
                path: "/test".into(),
            },
            true,
            Duration::ZERO,
        );
        transition(&mut satellites, SatelliteId::Calendar, true, Duration::ZERO);
        assert_eq!(satellites.panels.len(), 2);
        assert!(!satellites.contains(&SatelliteId::Wifi));
        assert!(satellites.contains(&SatelliteId::Tray {
            bus: "test".into(),
            path: "/test".into(),
        }));
        assert!(satellites.contains(&SatelliteId::Calendar));
        let viewport = Size {
            width: px(1400.0),
            height: px(900.0),
        };
        let capsule = Bounds {
            origin: point(px(380.0), px(8.0)),
            size: Size {
                width: px(640.0),
                height: px(480.0),
            },
        };
        for height in [72.0, 150.0, 320.0] {
            let measured = [(
                SatelliteId::Tray {
                    bus: "test".into(),
                    path: "/test".into(),
                },
                Bounds {
                    origin: point(px(0.0), px(0.0)),
                    size: Size {
                        width: px(320.0),
                        height: px(height),
                    },
                },
            )];
            let visuals = satellites.layout(viewport, capsule, px(8.0), &measured);
            assert_eq!(visuals.len(), 2);
            let tray = visuals
                .iter()
                .find(|visual| {
                    visual.id
                        == SatelliteId::Tray {
                            bus: "test".into(),
                            path: "/test".into(),
                        }
                })
                .expect("tray satellite");
            assert_eq!(tray.layout.side, Side::Right);
            assert_eq!(
                tray.layout.bounds.origin.y + px(height / 2.0),
                capsule.origin.y + capsule.size.height / 2.0
            );
            let calendar = visuals
                .iter()
                .find(|visual| visual.id == SatelliteId::Calendar)
                .expect("calendar satellite");
            assert_eq!(calendar.layout.side, Side::Left);
            assert_eq!(calendar.layout.content_size.height, px(300.0));
        }
    }
}
