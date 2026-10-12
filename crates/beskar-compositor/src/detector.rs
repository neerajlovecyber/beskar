use std::sync::Arc;
use tracing::info;

use beskar_core::traits::CompositorBackend;
use crate::hyprland::HyprlandBackend;
use crate::niri::NiriBackend;
use crate::umbriel::UmbrielBackend;

/// Auto-detects the running compositor, checking Niri, Hyprland, and Umbriel.
pub fn detect_compositor() -> Arc<dyn CompositorBackend> {
    let niri = NiriBackend::new();
    if niri.is_available() {
        info!("Detected active compositor: Niri");
        return Arc::new(niri);
    }

    let hyprland = HyprlandBackend::new();
    if hyprland.is_available() {
        info!("Detected active compositor: Hyprland");
        return Arc::new(hyprland);
    }

    let umbriel = UmbrielBackend::new();
    if umbriel.is_available() {
        info!("Detected active compositor: Umbriel");
        return Arc::new(umbriel);
    }

    info!("No specific compositor socket found; defaulting to Niri backend handler");
    Arc::new(niri)
}
