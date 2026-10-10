use beskar_compositor::detect_compositor;
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("beskar=info".parse()?))
        .init();

    info!("Starting Beskar Shell (Pure Rust + GPUI Wayland Desktop Shell)...");

    // 1. Detect & initialize compositor backend (Niri first preference, then Umbriel)
    let compositor = detect_compositor();
    info!("Active compositor backend: {:?}", compositor.kind());

    // 2. Query initial workspaces
    match compositor.get_workspaces().await {
        Ok(workspaces) => {
            info!("Found {} workspaces from compositor", workspaces.len());
            for ws in workspaces {
                info!("  - Workspace {} (active: {}, focused: {})", ws.idx, ws.is_active, ws.is_focused);
            }
        }
        Err(e) => {
            info!("Notice: Could not query workspaces (compositor may not be running): {}", e);
        }
    }

    info!("Beskar Shell workspace engine initialized successfully.");
    Ok(())
}
