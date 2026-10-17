pub mod bar;
pub mod convex;
pub mod pill;
pub mod spring;
pub mod widgets;

pub use bar::{BarActions, BarState, BarStyle, BeskarBar};
pub use convex::{ConvexBarShape, ConvexGeometry};
pub use pill::IslandPill;
pub use spring::Animator;
pub mod components;
pub mod tracker;
pub use components::*;
pub use tracker::*;
pub use widgets::{
    convex_shape::{ConvexDrawerEdge, convex_drawer_background},
    style, DynamicCenterWidget, VitalsWidget, WorkspacesWidget,
};
