pub mod view;
pub use self::view::{WallpaperItem, WallpaperSelectorWidget};
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum WallpaperMsg {
    Select(std::path::PathBuf),
    Close,
}

pub struct WallpaperSelectorView {
    wallpapers: Vec<WallpaperItem>,
    query: String,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<WallpaperMsg>,
}

impl PanelModule for WallpaperSelectorView {
    const ID: &'static str = "wallpaper_selector";

    fn size() -> Size<Pixels> {
        Size::new(px(720.0), px(520.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(60.0), px(0.0), px(0.0), px(0.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl WallpaperSelectorView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let wallpapers = WallpaperSelectorWidget::discover_wallpapers();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<WallpaperMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    WallpaperMsg::Select(path) => {
                        let path_str = path.to_string_lossy().to_string();
                        tokio::task::spawn_blocking(move || {
                            let _ = std::process::Command::new("swww")
                                .args(["img", &path_str, "--transition-type", "wipe"])
                                .spawn();
                            let _ = std::process::Command::new("feh")
                                .args(["--bg-fill", &path_str])
                                .spawn();
                        });

                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close(cx);
                        });
                    }
                    WallpaperMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close(cx);
                        });
                    }
                }
            }
        })
        .detach();

        // Reactive FileWatcher subscription for live wallpaper additions and deletions
        let mut watcher_rx = beskar_services::FileWatcherService::global().subscribe();
        cx.spawn(async move |this, cx| {
            while let Ok(event) = watcher_rx.recv().await {
                if matches!(
                    event,
                    beskar_services::WatchEvent::WallpaperDirectoryChanged(_)
                ) {
                    let updated = WallpaperSelectorWidget::discover_wallpapers();
                    let _ = this.update(cx, |this, cx| {
                        this.wallpapers = updated;
                        cx.notify();
                    });
                }
            }
        })
        .detach();

        Self {
            wallpapers,
            query: String::new(),
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for WallpaperSelectorView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for WallpaperSelectorView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("wallpaper-selector-card")
            .w(px(720.0))
            .max_h(px(520.0))
            .track_focus(&self.focus_handle)
            .key_context("WallpaperSelectorView")
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    if !this.query.is_empty() {
                        this.query.clear();
                        cx.notify();
                    } else {
                        PanelHost::close(cx);
                    }
                    cx.stop_propagation();
                }
            }))
            .child(
                WallpaperSelectorWidget::new(self.wallpapers.clone())
                    .query(&self.query)
                    .on_select(move |path| {
                        let _ = tx_sel.send(WallpaperMsg::Select(path));
                    })
                    .on_close(move || {
                        let _ = tx_close.send(WallpaperMsg::Close);
                    }),
            )
    }
}

#[cfg(test)]
mod tests {
    use super::WallpaperSelectorWidget;

    #[core::prelude::v1::test]
    fn test_wallpaper_discovery() {
        let walls = WallpaperSelectorWidget::discover_wallpapers();
        assert!(walls.is_empty() || !walls[0].name.is_empty());
    }
}
