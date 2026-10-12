use beskar_ui::{WallpaperItem, WallpaperSelectorWidget};
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

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
                        let _ = std::process::Command::new("swww")
                            .args(["img", &path_str, "--transition-type", "wipe"])
                            .spawn();
                        let _ = std::process::Command::new("feh")
                            .args(["--bg-fill", &path_str])
                            .spawn();

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
            .id("wallpaper-selector-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(60.0))
            .track_focus(&self.focus_handle)
            .key_context("WallpaperSelectorView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(WallpaperSelectorView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    if !this.query.is_empty() {
                        this.query.clear();
                        cx.notify();
                    } else {
                        PanelHost::forget(WallpaperSelectorView::ID);
                        window.remove_window();
                    }
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .w(px(720.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        WallpaperSelectorWidget::new(self.wallpapers.clone())
                            .query(&self.query)
                            .on_select(move |path| {
                                let _ = tx_sel.send(WallpaperMsg::Select(path));
                            })
                            .on_close(move || {
                                let _ = tx_close.send(WallpaperMsg::Close);
                            }),
                    ),
            )
    }
}
