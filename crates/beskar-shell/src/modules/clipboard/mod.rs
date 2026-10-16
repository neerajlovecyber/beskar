pub mod model;
pub mod widgets;
pub mod worker;

use std::collections::HashMap;
use std::sync::Arc;

use beskar_services::{ClipboardContent, ClipboardService};
use beskar_ui::components::InputState;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity};
use gpui_kit::prelude::*;
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule, Slot};
pub use model::ClipboardTab;
use worker::Request;

pub struct ClipboardView {
    pub model: model::ClipboardModel,
    pub search_input: InputState,
    pub loading: bool,
    pub busy: bool,
    pub error: Option<String>,
    pub pinned: Vec<String>,
    pub images: HashMap<String, Arc<gpui_kit::gpui::Image>>,
    pub scroll: ScrollHandle,
    pub focus: FocusHandle,
    active: bool,
    generation: u64,
    sender: tokio::sync::mpsc::UnboundedSender<Request>,
    _replies: Task<()>,
    worker: tokio::task::JoinHandle<()>,
}

impl PanelModule for ClipboardView {
    const ID: &'static str = "clipboard";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn size() -> Size<Pixels> {
        Size::new(px(widgets::WIDTH), px(widgets::MAX_HEIGHT))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(60.0), px(0.0), px(0.0), px(0.0))
    }

    fn keyboard_interactivity() -> KeyboardInteractivity {
        KeyboardInteractivity::Exclusive
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl ClipboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let (sender, mut receiver, worker) = worker::start(ClipboardService::global().clone());
        let replies = cx.spawn(async move |this, cx| {
            while let Some(reply) = receiver.recv().await {
                if this
                    .update(cx, |module: &mut Self, cx| {
                        let error = if reply.finished || reply.error.is_some() {
                            reply.error
                        } else {
                            module.error.clone()
                        };
                        let changed = module.loading
                            || reply.finished
                            || module.error != error
                            || module.model.items != reply.items
                            || module.model.snippets != reply.snippets
                            || module.pinned != reply.pinned;
                        module.loading = false;
                        if reply.finished {
                            module.busy = false;
                        }
                        module.error = error;
                        module.pinned = reply.pinned;
                        module.images = reply.images;
                        module.model.update(reply.items, reply.snippets);
                        if let Some((generation, content)) = reply.copied {
                            if let ClipboardContent::Text(text) = content {
                                cx.write_to_clipboard(gpui_kit::gpui::ClipboardItem::new_string(text));
                            }
                            if module.active && generation == module.generation {
                                PanelHost::close(cx);
                            }
                        }
                        if module.active && changed {
                            module
                                .scroll
                                .scroll_to_item(module.model.selected / widgets::COLUMNS);
                            cx.notify();
                        }
                    })
                    .is_err()
                {
                    break;
                }
            }
        });

        Self {
            model: model::ClipboardModel::default(),
            search_input: InputState::new("").with_focused(true).with_max_len(120),
            loading: true,
            busy: false,
            error: None,
            pinned: Vec::new(),
            images: HashMap::new(),
            scroll: ScrollHandle::new(),
            focus: cx.focus_handle(),
            active: true,
            generation: 1,
            sender,
            _replies: replies,
            worker,
        }
    }

    pub fn search(&mut self, query: String, cx: &mut Context<Self>) {
        if self.search_input.text() != query {
            self.search_input.set_text(&query);
        }
        self.model.search(query);
        self.scroll.scroll_to_item(0);
        cx.notify();
    }

    pub fn switch_tab(&mut self, tab: ClipboardTab, cx: &mut Context<Self>) {
        if self.model.tab == tab {
            return;
        }
        self.model.switch(tab);
        self.scroll.scroll_to_item(0);
        cx.notify();
    }

    pub fn select(&mut self, index: usize, scroll: bool, cx: &mut Context<Self>) {
        if index >= self.model.filtered.len() || index == self.model.selected {
            return;
        }
        self.model.selected = index;
        if scroll {
            self.scroll.scroll_to_item(index / widgets::COLUMNS);
        }
        cx.notify();
    }

    fn request(&mut self, request: Request, cx: &mut Context<Self>) {
        if self.busy {
            return;
        }
        self.error = None;
        if self.sender.send(request).is_ok() {
            self.busy = true;
        } else {
            self.error = Some("Failed to send clipboard request".into());
        }
        cx.notify();
    }

    pub fn copy(&mut self, index: usize, cx: &mut Context<Self>) {
        let Some(&index) = self.model.filtered.get(index) else {
            return;
        };
        let request = match self.model.tab {
            ClipboardTab::History => {
                Request::Copy(self.model.items[index].clone(), self.generation)
            }
            ClipboardTab::Snippets => {
                Request::CopyText(self.model.snippets[index].content.clone(), self.generation)
            }
        };
        self.request(request, cx);
    }

    pub fn pin(&mut self, index: usize, cx: &mut Context<Self>) {
        if self.model.tab != ClipboardTab::History {
            return;
        }
        let Some(&index) = self.model.filtered.get(index) else {
            return;
        };
        if !self.model.items[index].is_image {
            self.request(Request::Pin(self.model.items[index].clone()), cx);
        }
    }

    pub fn remove(&mut self, index: usize, cx: &mut Context<Self>) {
        if self.model.tab != ClipboardTab::Snippets {
            return;
        }
        let Some(&index) = self.model.filtered.get(index) else {
            return;
        };
        self.request(Request::Remove(self.model.snippets[index].id.clone()), cx);
    }

    pub fn clear(&mut self, cx: &mut Context<Self>) {
        self.request(Request::Clear, cx);
    }

    fn key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        let control = event.keystroke.modifiers.control || event.keystroke.modifiers.platform;
        let shift = event.keystroke.modifiers.shift;
        let key = event.keystroke.key.as_str();

        if key == "escape" {
            if !self.search_input.is_empty() {
                self.search_input.clear();
                self.search(String::new(), cx);
            } else {
                PanelHost::close(cx);
            }
            return;
        }

        if key == "enter" {
            self.copy(self.model.selected, cx);
            return;
        }

        if key == "tab" && !control && !shift {
            self.switch_tab(
                if self.model.tab == ClipboardTab::History {
                    ClipboardTab::Snippets
                } else {
                    ClipboardTab::History
                },
                cx,
            );
            return;
        }

        if (key == "up" || key == "down") && !control && !shift {
            self.model.navigate(match key {
                "up" => -(widgets::COLUMNS as i32),
                _ => widgets::COLUMNS as i32,
            });
            self.scroll
                .scroll_to_item(self.model.selected / widgets::COLUMNS);
            cx.notify();
            return;
        }

        if (key == "left" || key == "right") && !control && !shift && self.search_input.is_empty() {
            self.model.navigate(if key == "left" { -1 } else { 1 });
            self.scroll
                .scroll_to_item(self.model.selected / widgets::COLUMNS);
            cx.notify();
            return;
        }

        if (key == "home" || key == "end") && !control && !shift && self.search_input.is_empty() {
            self.select(
                if key == "home" {
                    0
                } else {
                    self.model.filtered.len().saturating_sub(1)
                },
                true,
                cx,
            );
            return;
        }

        if self.search_input.handle_key_down(event, cx) {
            let text = self.search_input.text();
            self.search(text, cx);
        }
    }
}

impl Drop for ClipboardView {
    fn drop(&mut self) {
        self.worker.abort();
    }
}

impl Focusable for ClipboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for ClipboardView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        widgets::render(self, cx)
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::key_down))
    }
}
