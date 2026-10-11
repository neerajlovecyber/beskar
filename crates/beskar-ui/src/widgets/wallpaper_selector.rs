use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct WallpaperItem {
    pub path: PathBuf,
    pub name: String,
    pub is_active: bool,
}

/// Interactive Wallpaper Gallery Carousel Widget matching Minflair's WallpaperSelectorContent.qml
#[derive(IntoElement)]
pub struct WallpaperSelectorWidget {
    wallpapers: Vec<WallpaperItem>,
    search_query: String,
    on_select: Option<Arc<dyn Fn(PathBuf) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl WallpaperSelectorWidget {
    pub fn new(wallpapers: Vec<WallpaperItem>) -> Self {
        Self {
            wallpapers,
            search_query: String::new(),
            on_select: None,
            on_close: None,
        }
    }

    pub fn query(mut self, q: impl Into<String>) -> Self {
        self.search_query = q.into();
        self
    }

    pub fn on_select(mut self, handler: impl Fn(PathBuf) + Send + Sync + 'static) -> Self {
        self.on_select = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }

    /// Discovers system and user wallpapers from standard directories
    pub fn discover_wallpapers() -> Vec<WallpaperItem> {
        let mut results = Vec::new();
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let candidate_dirs = [
            format!("{}/Pictures/Wallpapers", home),
            format!("{}/Pictures", home),
            format!("{}/.local/share/wallpapers", home),
            "/usr/share/backgrounds".to_string(),
        ];

        let exts = ["jpg", "jpeg", "png", "webp"];

        for dir in &candidate_dirs {
            let path = Path::new(dir);
            if let Ok(entries) = std::fs::read_dir(path) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    let is_image = p.is_file()
                        && p.extension()
                            .and_then(|e| e.to_str())
                            .is_some_and(|ext| exts.contains(&ext.to_lowercase().as_str()));
                    if is_image {
                        let name = p.file_stem().and_then(|s| s.to_str()).unwrap_or("Wallpaper").to_string();
                        results.push(WallpaperItem {
                            path: p,
                            name,
                            is_active: false,
                        });
                    }
                }
            }
        }

        // If no wallpapers found on disk, add demo preset cards
        if results.is_empty() {
            for (name, path) in [
                ("Obsidian Dusk", "/usr/share/backgrounds/obsidian.png"),
                ("Catppuccin Mocha", "/usr/share/backgrounds/catppuccin.png"),
                ("Gruvbox Forest", "/usr/share/backgrounds/gruvbox.png"),
                ("Suzuha Aurora", "/usr/share/backgrounds/aurora.png"),
            ] {
                results.push(WallpaperItem {
                    path: PathBuf::from(path),
                    name: name.to_string(),
                    is_active: false,
                });
            }
        }

        results
    }
}

impl RenderOnce for WallpaperSelectorWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_select = self.on_select;
        let on_close = self.on_close;
        let q = self.search_query.to_lowercase();

        let filtered: Vec<WallpaperItem> = self
            .wallpapers
            .into_iter()
            .filter(|w| q.is_empty() || w.name.to_lowercase().contains(&q))
            .collect();

        div()
            .w(px(760.0))
            .flex()
            .flex_col()
            .gap(px(14.0))
            .p(px(18.0))
            .rounded(px(22.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::border())
            .shadow_lg()
            // Header with search & close
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pb(px(10.0))
                    .border_b_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(Icon::new(IconName::Image).size(px(16.0)).text_color(beskar_theme::Theme::accent()))
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child("Wallpaper Gallery"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(beskar_theme::Theme::muted())
                                    .child(format!("({} discovered)", filtered.len())),
                            ),
                    )
                    .when_some(on_close, |el, cb| {
                        el.child(
                            div()
                                .w(px(24.0))
                                .h(px(24.0))
                                .rounded_md()
                                .flex()
                                .items_center()
                                .justify_center()
                                .bg(beskar_theme::Theme::bg_secondary())
                                .text_color(beskar_theme::Theme::muted())
                                .hover(|s| s.bg(hsla(0.0, 0.8, 0.5, 0.25)).text_color(hsla(0.0, 0.9, 0.7, 1.0)).cursor_pointer())
                                .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                .child(Icon::new(IconName::X).size(px(12.0))),
                        )
                    }),
            )
            // Horizontal Carousel of 220x130 Wallpaper Cards
            .child(
                div()
                    .id("wallpaper-carousel-list")
                    .flex()
                    .gap(px(12.0))
                    .overflow_x_scroll()
                    .pb(px(8.0))
                    .children(filtered.into_iter().map(move |item| {
                        let on_sel = on_select.clone();
                        let p = item.path.clone();
                        let name = item.name.clone();

                        div()
                            .w(px(220.0))
                            .h(px(130.0))
                            .rounded(px(16.0))
                            .bg(beskar_theme::Theme::bg_secondary())
                            .border_1()
                            .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                            .flex()
                            .flex_col()
                            .justify_between()
                            .p(px(10.0))
                            .hover(|s| {
                                s.border_color(beskar_theme::Theme::accent())
                                    .bg(beskar_theme::Theme::bg_accent())
                                    .cursor_pointer()
                            })
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(ref cb) = on_sel {
                                    (cb)(p.clone());
                                }
                            })
                            // Top right checkmark or icon
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_between()
                                    .child(
                                        div()
                                            .w(px(24.0))
                                            .h(px(24.0))
                                            .rounded_full()
                                            .bg(hsla(0.0, 0.0, 0.0, 0.40))
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .text_color(beskar_theme::Theme::accent())
                                            .child(Icon::new(IconName::Sparkles).size(px(12.0))),
                                    ),
                            )
                            // Bottom title label
                            .child(
                                div()
                                    .p(px(6.0))
                                    .rounded_md()
                                    .bg(hsla(0.0, 0.0, 0.0, 0.60))
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child(name),
                            )
                    })),
            )
    }
}
