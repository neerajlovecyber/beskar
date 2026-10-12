use beskar_services::ClipboardEntry;
use beskar_ui::ClipboardWidget;
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum ClipboardMsg {
    Select(usize),
    Copy(String),
    Delete(String),
    ClearAll,
    ClearQuery,
    Close,
}

pub struct ClipboardView {
    query: String,
    items: Vec<ClipboardEntry>,
    selected_idx: usize,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ClipboardMsg>,
}

impl PanelModule for ClipboardView {
    const ID: &'static str = "clipboard";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl ClipboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let items = beskar_services::ClipboardService::list_history(50);
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ClipboardMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    ClipboardMsg::Select(idx) => {
                        this.selected_idx = idx;
                        cx.notify();
                    }
                    ClipboardMsg::Copy(id) => {
                        beskar_services::ClipboardService::copy_item(&id);
                        beskar_services::SoundService::play_volume_change();
                        PanelHost::close(cx);
                    }
                    ClipboardMsg::Delete(line) => {
                        beskar_services::ClipboardService::delete_item(&line);
                        this.items = beskar_services::ClipboardService::list_history(50);
                        this.selected_idx = this.selected_idx.min(this.items.len().saturating_sub(1));
                        cx.notify();
                    }
                    ClipboardMsg::ClearAll => {
                        beskar_services::ClipboardService::clear_history();
                        this.items.clear();
                        this.selected_idx = 0;
                        cx.notify();
                    }
                    ClipboardMsg::ClearQuery => {
                        this.query.clear();
                        this.selected_idx = 0;
                        cx.notify();
                    }
                    ClipboardMsg::Close => {
                        PanelHost::close(cx);
                    }
                });
            }
        })
        .detach();

        Self {
            query: String::new(),
            items,
            selected_idx: 0,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for ClipboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for ClipboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_cp = self.msg_tx.clone();
        let tx_del = self.msg_tx.clone();
        let tx_cp_key = self.msg_tx.clone();
        let tx_del_key = self.msg_tx.clone();
        let tx_clr = self.msg_tx.clone();
        let tx_clrq = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("clipboard-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(80.0))
            .track_focus(&self.focus_handle)
            .key_context("Clipboard")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(ClipboardView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                let key = event.keystroke.key.as_str();
                let mods = &event.keystroke.modifiers;

                match key {
                    "escape" => {
                        if !this.query.is_empty() {
                            this.query.clear();
                            this.selected_idx = 0;
                            cx.notify();
                        } else {
                            PanelHost::forget(ClipboardView::ID);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "up" => {
                        this.selected_idx = this.selected_idx.saturating_sub(1);
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "down" => {
                        let filtered = ClipboardWidget::filter_items(&this.items, &this.query);
                        this.selected_idx =
                            (this.selected_idx + 1).min(filtered.len().saturating_sub(1));
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        let filtered = ClipboardWidget::filter_items(&this.items, &this.query);
                        if let Some(item) = filtered.get(this.selected_idx) {
                            let id = item.id.clone();
                            let _ = tx_cp_key.send(ClipboardMsg::Copy(id));
                        }
                        cx.stop_propagation();
                    }
                    "delete" => {
                        let filtered = ClipboardWidget::filter_items(&this.items, &this.query);
                        if let Some(item) = filtered.get(this.selected_idx) {
                            let line = item.full_line.clone();
                            let _ = tx_del_key.send(ClipboardMsg::Delete(line));
                        }
                        cx.stop_propagation();
                    }
                    "backspace" => {
                        this.query.pop();
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "space" if !mods.control && !mods.alt && !mods.platform => {
                        this.query.push(' ');
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    _ => {
                        if key.chars().count() == 1 && !mods.control && !mods.alt && !mods.platform {
                            let ch = key.chars().next().unwrap();
                            if !ch.is_control() {
                                this.query.push(ch);
                                this.selected_idx = 0;
                                cx.notify();
                                cx.stop_propagation();
                            }
                        }
                    }
                }
            }))
            .child(
                div()
                    .w(px(640.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        ClipboardWidget::new(self.items.clone())
                            .query(&self.query)
                            .selected_idx(self.selected_idx)
                            .on_select(move |idx| {
                                let _ = tx_sel.send(ClipboardMsg::Select(idx));
                            })
                            .on_copy(move |id| {
                                let _ = tx_cp.send(ClipboardMsg::Copy(id));
                            })
                            .on_delete(move |line| {
                                let _ = tx_del.send(ClipboardMsg::Delete(line));
                            })
                            .on_clear_all(move || {
                                let _ = tx_clr.send(ClipboardMsg::ClearAll);
                            })
                            .on_clear_query(move || {
                                let _ = tx_clrq.send(ClipboardMsg::ClearQuery);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(ClipboardMsg::Close);
                            }),
                    ),
            )
    }
}
