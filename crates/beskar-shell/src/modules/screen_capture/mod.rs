pub mod view;
pub use self::view::{CaptureMode, ScreenCaptureWidget};
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule, Slot};

#[derive(Debug, Clone)]
enum ScreenCapMsg {
    Trigger(CaptureMode),
    Close,
}

pub struct ScreenCaptureView {
    is_recording: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ScreenCapMsg>,
}

impl PanelModule for ScreenCaptureView {
    const ID: &'static str = "screen_capture";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn size() -> Size<Pixels> {
        Size::new(px(460.0), px(64.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(80.0), px(0.0), px(0.0), px(0.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl ScreenCaptureView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ScreenCapMsg>();

        cx.spawn(async move |this, cx| {
            loop {
                let is_rec = tokio::task::spawn_blocking(|| {
                    std::process::Command::new("pidof")
                        .arg("wf-recorder")
                        .output()
                        .map(|o| o.status.success())
                        .unwrap_or(false)
                })
                .await
                .unwrap_or(false);

                let res = this.update(cx, |this, cx| {
                    if this.is_recording != is_rec {
                        this.is_recording = is_rec;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
        })
        .detach();

        cx.spawn(async move |_this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    ScreenCapMsg::Trigger(mode) => {
                        let _ = cx.update(|cx| {
                            PanelHost::close(cx);
                        });
                        std::thread::spawn(move || {
                            std::thread::sleep(std::time::Duration::from_millis(200));
                            mode.execute();
                        });
                    }
                    ScreenCapMsg::Close => {
                        let _ = cx.update(|cx| {
                            PanelHost::close(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            is_recording: false,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for ScreenCaptureView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for ScreenCaptureView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_trig = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("screen-capture-card")
            .w(px(460.0))
            .h(px(64.0))
            .track_focus(&self.focus_handle)
            .key_context("ScreenCaptureView")
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                }
            }))
            .child(
                ScreenCaptureWidget::new()
                    .recording(self.is_recording)
                    .on_trigger(move |mode| {
                        let _ = tx_trig.send(ScreenCapMsg::Trigger(mode));
                    })
                    .on_close(move || {
                        let _ = tx_close.send(ScreenCapMsg::Close);
                    }),
            )
    }
}

#[cfg(test)]
mod tests {
    use super::CaptureMode;

    #[core::prelude::v1::test]
    fn test_capture_mode_properties() {
        assert_eq!(CaptureMode::FullScreen.label(), "Full Screen");
        assert_eq!(CaptureMode::SelectArea.label(), "Select Area");
        assert_eq!(CaptureMode::ExtractTextOcr.label(), "Extract Text (OCR)");
        assert_eq!(CaptureMode::RecordToggle.label(), "Screen Record");
    }
}
