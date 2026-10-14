use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureMode {
    FullScreen,
    FullScreen3s,
    SelectArea,
    SelectArea3s,
    ActiveWindow,
    ExtractTextOcr,
    RecordToggle,
}

impl CaptureMode {
    pub fn label(&self) -> &'static str {
        match self {
            CaptureMode::FullScreen => "Full Screen",
            CaptureMode::FullScreen3s => "Full (3s)",
            CaptureMode::SelectArea => "Select Area",
            CaptureMode::SelectArea3s => "Area (3s)",
            CaptureMode::ActiveWindow => "Active Window",
            CaptureMode::ExtractTextOcr => "Extract Text (OCR)",
            CaptureMode::RecordToggle => "Screen Record",
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            CaptureMode::FullScreen => IconName::Monitor,
            CaptureMode::FullScreen3s => IconName::Timer,
            CaptureMode::SelectArea => IconName::Maximize2,
            CaptureMode::SelectArea3s => IconName::Clock,
            CaptureMode::ActiveWindow => IconName::AppWindow,
            CaptureMode::ExtractTextOcr => IconName::ScanText,
            CaptureMode::RecordToggle => IconName::Video,
        }
    }

    pub fn execute(&self) {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let shot_dir = format!("{}/Pictures/Screenshots", home);
        let _ = std::fs::create_dir_all(&shot_dir);
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let target_file = format!("{}/Screenshot_{}.png", shot_dir, timestamp);
        let mode = *self;

        tokio::task::spawn_blocking(move || {
            match mode {
                CaptureMode::FullScreen => {
                    let cmd = format!("grim \"{}\" && wl-copy < \"{}\"", target_file, target_file);
                    let _ = std::process::Command::new("sh").args(["-c", &cmd]).spawn();
                }
                CaptureMode::FullScreen3s => {
                    let cmd = format!("sleep 3 && grim \"{}\" && wl-copy < \"{}\"", target_file, target_file);
                    let _ = std::process::Command::new("sh").args(["-c", &cmd]).spawn();
                }
                CaptureMode::SelectArea => {
                    let cmd = format!("grim -g \"$(slurp)\" \"{}\" && wl-copy < \"{}\"", target_file, target_file);
                    let _ = std::process::Command::new("sh").args(["-c", &cmd]).spawn();
                }
                CaptureMode::SelectArea3s => {
                    let cmd = format!("sleep 3 && grim -g \"$(slurp)\" \"{}\" && wl-copy < \"{}\"", target_file, target_file);
                    let _ = std::process::Command::new("sh").args(["-c", &cmd]).spawn();
                }
                CaptureMode::ActiveWindow => {
                    let cmd = format!("grim -g \"$(slurp)\" \"{}\" && wl-copy < \"{}\"", target_file, target_file);
                    let _ = std::process::Command::new("sh").args(["-c", &cmd]).spawn();
                }
                CaptureMode::ExtractTextOcr => {
                    let cmd = "grim -g \"$(slurp)\" /tmp/ocr_snip.png && tesseract /tmp/ocr_snip.png stdout | wl-copy";
                    let _ = std::process::Command::new("sh").args(["-c", cmd]).spawn();
                }
                CaptureMode::RecordToggle => {
                    let check = std::process::Command::new("pidof").arg("wf-recorder").output();
                    if check.map(|o| o.status.success()).unwrap_or(false) {
                        let _ = std::process::Command::new("pkill").arg("wf-recorder").spawn();
                        return;
                    }
                    let rec_file = format!("{}/Recording_{}.mp4", shot_dir, timestamp);
                    let cmd = format!("wf-recorder -g \"$(slurp)\" -f \"{}\"", rec_file);
                    let _ = std::process::Command::new("sh").args(["-c", &cmd]).spawn();
                }
            }
        });
    }
}

/// Interactive Screen Capture overlay widget matching Minflair's ScreenCaptureContent.qml
#[derive(IntoElement)]
pub struct ScreenCaptureWidget {
    is_recording: bool,
    on_trigger: Option<Arc<dyn Fn(CaptureMode) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl Default for ScreenCaptureWidget {
    fn default() -> Self {
        Self::new()
    }
}

impl ScreenCaptureWidget {
    pub fn new() -> Self {
        Self {
            is_recording: false,
            on_trigger: None,
            on_close: None,
        }
    }

    pub fn recording(mut self, is_rec: bool) -> Self {
        self.is_recording = is_rec;
        self
    }

    pub fn on_trigger(mut self, handler: impl Fn(CaptureMode) + Send + Sync + 'static) -> Self {
        self.on_trigger = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for ScreenCaptureWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_trigger = self.on_trigger;
        let on_close = self.on_close;

        let modes = [
            CaptureMode::FullScreen,
            CaptureMode::FullScreen3s,
            CaptureMode::SelectArea,
            CaptureMode::SelectArea3s,
            CaptureMode::ActiveWindow,
            CaptureMode::ExtractTextOcr,
            CaptureMode::RecordToggle,
        ];

        div()
            .w(px(460.0))
            .flex()
            .flex_col()
            .gap(px(14.0))
            .p(px(18.0))
            .rounded(px(22.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::border())
            .shadow_lg()
            // Header
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pb(px(8.0))
                    .border_b_1()
                    .border_color(beskar_theme::Theme::subtle_border())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(Icon::new(IconName::Camera).size(px(16.0)).text_color(beskar_theme::Theme::accent()))
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child("Screen Capture & Recording"),
                            ),
                    )
                    .when_some(on_close, |el, cb| {
                        el.child(
                            Button::new("screen-capture-close")
                                .ghost()
                                .compact()
                                .icon(Icon::new(IconName::X).size(px(14.0)))
                                .on_click(move |_, _, _| (cb)()),
                        )
                    }),
            )
            // Interactive 3-column Mode Tiles Grid
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .gap(px(10.0))
                    .children(modes.into_iter().map(move |m| {
                        let on_trig = on_trigger.clone();
                        let label = m.label();
                        let icon = m.icon();
                        let is_rec_btn = m == CaptureMode::RecordToggle;

                        div()
                            .w(px(134.0))
                            .h(px(72.0))
                            .p(px(10.0))
                            .rounded(px(14.0))
                            .bg(beskar_theme::Theme::bg_secondary())
                            .border_1()
                            .border_color(if is_rec_btn {
                                beskar_theme::Theme::danger_alpha(0.35)
                            } else {
                                beskar_theme::Theme::card_border()
                            })
                            .flex()
                            .flex_col()
                            .items_center()
                            .justify_center()
                            .gap(px(6.0))
                            .hover(move |s| {
                                s.bg(if is_rec_btn {
                                    beskar_theme::Theme::danger_alpha(0.25)
                                } else {
                                    beskar_theme::Theme::bg_accent()
                                })
                                .border_color(beskar_theme::Theme::accent())
                                .cursor_pointer()
                            })
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(ref cb) = on_trig {
                                    (cb)(m);
                                }
                            })
                            .child(
                                Icon::new(icon)
                                    .size(px(20.0))
                                    .text_color(if is_rec_btn {
                                        beskar_theme::Theme::danger()
                                    } else {
                                        beskar_theme::Theme::accent()
                                    }),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::MEDIUM)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child(label),
                            )
                    })),
            )
    }
}
