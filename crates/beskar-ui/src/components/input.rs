use beskar_theme::Theme;
use gpui_kit::gpui::{
    AnyElement, App, ClickEvent, DefiniteLength, ElementId, FontWeight, Hsla, InteractiveElement,
    IntoElement, KeyDownEvent, ParentElement, Pixels, RenderOnce, SharedString,
    StatefulInteractiveElement, Styled, Window, div, px, svg,
};
use std::ops::Range;

pub type InputClickListener = Box<dyn Fn(&ClickEvent, &mut Window, &mut App) + 'static>;

#[derive(Clone, Debug, Default)]
pub struct InputState {
    pub chars: Vec<char>,
    pub cursor: usize,
    pub selection: Option<Range<usize>>,
    pub selection_anchor: Option<usize>,
    pub placeholder: String,
    pub masked: bool,
    pub focused: bool,
    pub max_len: usize,
}

impl InputState {
    pub fn new(text: impl Into<String>) -> Self {
        let text_str = text.into();
        let chars: Vec<char> = text_str.chars().collect();
        let cursor = chars.len();
        Self {
            chars,
            cursor,
            selection: None,
            selection_anchor: None,
            placeholder: String::new(),
            masked: false,
            focused: false,
            max_len: 120,
        }
    }

    pub fn with_placeholder(mut self, placeholder: impl Into<String>) -> Self {
        self.placeholder = placeholder.into();
        self
    }

    pub fn with_masked(mut self, masked: bool) -> Self {
        self.masked = masked;
        self
    }

    pub fn with_focused(mut self, focused: bool) -> Self {
        self.focused = focused;
        self
    }

    pub fn with_max_len(mut self, max_len: usize) -> Self {
        self.max_len = max_len;
        self
    }

    pub fn text(&self) -> String {
        self.chars.iter().collect()
    }

    pub fn set_text(&mut self, text: impl Into<String>) {
        self.chars = text.into().chars().collect();
        self.cursor = self.chars.len();
        self.selection = None;
        self.selection_anchor = None;
    }

    pub fn clear(&mut self) {
        self.chars.clear();
        self.cursor = 0;
        self.selection = None;
        self.selection_anchor = None;
    }

    pub fn is_empty(&self) -> bool {
        self.chars.is_empty()
    }

    pub fn len(&self) -> usize {
        self.chars.len()
    }

    pub fn cursor(&self) -> usize {
        self.cursor
    }

    pub fn set_cursor(&mut self, cursor: usize) {
        self.cursor = cursor.min(self.chars.len());
        self.selection = None;
        self.selection_anchor = None;
    }

    pub fn select_all(&mut self) {
        if !self.chars.is_empty() {
            self.selection = Some(0..self.chars.len());
            self.selection_anchor = Some(0);
            self.cursor = self.chars.len();
        }
    }

    pub fn selected_text(&self) -> Option<String> {
        let range = self.selection.as_ref()?;
        let start = range.start.min(self.chars.len());
        let end = range.end.min(self.chars.len());
        if start < end {
            Some(self.chars[start..end].iter().collect())
        } else {
            None
        }
    }

    pub fn delete_selection(&mut self) -> bool {
        if let Some(range) = self.selection.take() {
            let start = range.start.min(self.chars.len());
            let end = range.end.min(self.chars.len());
            if start < end {
                self.chars.drain(start..end);
                self.cursor = start;
                self.selection_anchor = None;
                return true;
            }
        }
        self.selection_anchor = None;
        false
    }

    pub fn insert(&mut self, text: &str) {
        self.delete_selection();
        let clean_chars: Vec<char> = text.chars().filter(|c| !c.is_control()).collect();
        let available = self.max_len.saturating_sub(self.chars.len());
        let to_insert = clean_chars.into_iter().take(available);

        for c in to_insert {
            if self.cursor <= self.chars.len() {
                self.chars.insert(self.cursor, c);
                self.cursor += 1;
            }
        }
    }

    pub fn insert_char(&mut self, c: char) {
        self.delete_selection();
        if self.chars.len() < self.max_len && self.cursor <= self.chars.len() {
            self.chars.insert(self.cursor, c);
            self.cursor += 1;
        }
    }

    pub fn backspace(&mut self) {
        if !self.delete_selection() && self.cursor > 0 {
            self.cursor -= 1;
            if self.cursor < self.chars.len() {
                self.chars.remove(self.cursor);
            }
        }
    }

    pub fn delete(&mut self) {
        if !self.delete_selection() && self.cursor < self.chars.len() {
            self.chars.remove(self.cursor);
        }
    }

    pub fn move_left(&mut self, select: bool) {
        if !select {
            if let Some(range) = self.selection.take() {
                self.selection_anchor = None;
                self.cursor = range.start;
                return;
            }
        }
        let new_cursor = self.cursor.saturating_sub(1);
        self.update_cursor(new_cursor, select);
    }

    pub fn move_right(&mut self, select: bool) {
        if !select {
            if let Some(range) = self.selection.take() {
                self.selection_anchor = None;
                self.cursor = range.end.min(self.chars.len());
                return;
            }
        }
        let new_cursor = (self.cursor + 1).min(self.chars.len());
        self.update_cursor(new_cursor, select);
    }

    pub fn move_to_start(&mut self, select: bool) {
        if !select {
            self.selection = None;
            self.selection_anchor = None;
        }
        self.update_cursor(0, select);
    }

    pub fn move_to_end(&mut self, select: bool) {
        if !select {
            self.selection = None;
            self.selection_anchor = None;
        }
        let len = self.chars.len();
        self.update_cursor(len, select);
    }

    fn update_cursor(&mut self, new_cursor: usize, select: bool) {
        if select {
            let anchor = self.selection_anchor.get_or_insert(self.cursor);
            self.cursor = new_cursor;
            let start = (*anchor).min(self.cursor);
            let end = (*anchor).max(self.cursor);
            if start < end {
                self.selection = Some(start..end);
            } else {
                self.selection = None;
            }
        } else {
            self.selection = None;
            self.selection_anchor = None;
            self.cursor = new_cursor;
        }
    }

    pub fn prev_word_boundary(&self) -> usize {
        if self.cursor == 0 {
            return 0;
        }
        let mut idx = self.cursor;
        while idx > 0 && self.chars[idx - 1].is_whitespace() {
            idx -= 1;
        }
        while idx > 0 && !self.chars[idx - 1].is_whitespace() {
            idx -= 1;
        }
        idx
    }

    pub fn next_word_boundary(&self) -> usize {
        let len = self.chars.len();
        if self.cursor >= len {
            return len;
        }
        let mut idx = self.cursor;
        while idx < len && !self.chars[idx].is_whitespace() {
            idx += 1;
        }
        while idx < len && self.chars[idx].is_whitespace() {
            idx += 1;
        }
        idx
    }

    pub fn delete_word_backward(&mut self) {
        if !self.delete_selection() && self.cursor > 0 {
            let prev = self.prev_word_boundary();
            self.chars.drain(prev..self.cursor);
            self.cursor = prev;
        }
    }

    pub fn delete_word_forward(&mut self) {
        if !self.delete_selection() && self.cursor < self.chars.len() {
            let next = self.next_word_boundary();
            self.chars.drain(self.cursor..next);
        }
    }

    pub fn copy(&self, cx: &mut App) {
        let text = self.selected_text().unwrap_or_else(|| self.text());
        if !text.is_empty() {
            cx.write_to_clipboard(gpui_kit::gpui::ClipboardItem::new_string(text));
        }
    }

    pub fn cut(&mut self, cx: &mut App) {
        let text = self.selected_text().unwrap_or_else(|| self.text());
        if !text.is_empty() {
            cx.write_to_clipboard(gpui_kit::gpui::ClipboardItem::new_string(text));
            if !self.delete_selection() {
                self.clear();
            }
        }
    }

    pub fn paste(&mut self, cx: &mut App) {
        if let Some(item) = cx.read_from_clipboard() {
            if let Some(text) = item.text() {
                self.insert(&text);
            }
        }
    }

    pub fn handle_key_down(&mut self, event: &KeyDownEvent, cx: &mut App) -> bool {
        let key_lower = event.keystroke.key.to_lowercase();
        let key = key_lower.as_str();
        let ctrl = event.keystroke.modifiers.control || event.keystroke.modifiers.platform;
        let alt = event.keystroke.modifiers.alt;
        let shift = event.keystroke.modifiers.shift;

        if alt {
            return false;
        }

        if ctrl {
            match key {
                "a" => {
                    self.select_all();
                    return true;
                }
                "c" => {
                    self.copy(cx);
                    return true;
                }
                "x" => {
                    self.cut(cx);
                    return true;
                }
                "v" => {
                    self.paste(cx);
                    return true;
                }
                "u" => {
                    self.move_to_start(true);
                    self.delete_selection();
                    return true;
                }
                "w" | "backspace" => {
                    self.delete_word_backward();
                    return true;
                }
                "delete" => {
                    self.delete_word_forward();
                    return true;
                }
                "left" => {
                    let prev = self.prev_word_boundary();
                    self.update_cursor(prev, shift);
                    return true;
                }
                "right" => {
                    let next = self.next_word_boundary();
                    self.update_cursor(next, shift);
                    return true;
                }
                "home" => {
                    self.move_to_start(shift);
                    return true;
                }
                "end" => {
                    self.move_to_end(shift);
                    return true;
                }
                _ => return false,
            }
        }

        match key {
            "backspace" => {
                self.backspace();
                true
            }
            "delete" => {
                self.delete();
                true
            }
            "left" => {
                self.move_left(shift);
                true
            }
            "right" => {
                self.move_right(shift);
                true
            }
            "home" => {
                self.move_to_start(shift);
                true
            }
            "end" => {
                self.move_to_end(shift);
                true
            }
            "escape" | "enter" | "tab" | "up" | "down" => false,
            _ => {
                if let Some(ref key_str) = event.keystroke.key_char {
                    if let Some(c) = key_str.chars().next() {
                        if !c.is_control() {
                            self.insert_char(c);
                            return true;
                        }
                    }
                }
                if key.chars().count() == 1 {
                    let c = key.chars().next().unwrap();
                    if !c.is_control() {
                        self.insert_char(c);
                        return true;
                    }
                }
                false
            }
        }
    }
}

#[derive(IntoElement)]
pub struct Input {
    id: ElementId,
    value: SharedString,
    placeholder: SharedString,
    focused: bool,
    masked: bool,
    error: bool,
    disabled: bool,
    cleanable: bool,
    cursor: Option<usize>,
    selection: Option<Range<usize>>,
    prefix: Option<AnyElement>,
    suffix: Option<AnyElement>,
    height: Option<Pixels>,
    width: Option<DefiniteLength>,
    rounded: Option<Pixels>,
    bg: Option<Hsla>,
    border_color: Option<Hsla>,
    focused_border_color: Option<Hsla>,
    on_click: Option<InputClickListener>,
    on_clear: Option<InputClickListener>,
}

impl Input {
    pub fn new(id: impl Into<ElementId>, value: impl Into<SharedString>) -> Self {
        Self {
            id: id.into(),
            value: value.into(),
            placeholder: SharedString::default(),
            focused: false,
            masked: false,
            error: false,
            disabled: false,
            cleanable: false,
            cursor: None,
            selection: None,
            prefix: None,
            suffix: None,
            height: None,
            width: None,
            rounded: None,
            bg: None,
            border_color: None,
            focused_border_color: None,
            on_click: None,
            on_clear: None,
        }
    }

    pub fn from_state(id: impl Into<ElementId>, state: &InputState) -> Self {
        Self::new(id, state.text())
            .placeholder(state.placeholder.clone())
            .focused(state.focused)
            .masked(state.masked)
            .cursor(state.cursor)
            .selection(state.selection.clone())
    }

    pub fn placeholder(mut self, placeholder: impl Into<SharedString>) -> Self {
        self.placeholder = placeholder.into();
        self
    }

    pub fn focused(mut self, focused: bool) -> Self {
        self.focused = focused;
        self
    }

    pub fn masked(mut self, masked: bool) -> Self {
        self.masked = masked;
        self
    }

    pub fn error(mut self, error: bool) -> Self {
        self.error = error;
        self
    }

    pub fn disabled(mut self, disabled: bool) -> Self {
        self.disabled = disabled;
        self
    }

    pub fn cleanable(mut self, cleanable: bool) -> Self {
        self.cleanable = cleanable;
        self
    }

    pub fn cursor(mut self, cursor: usize) -> Self {
        self.cursor = Some(cursor);
        self
    }

    pub fn selection(mut self, selection: Option<Range<usize>>) -> Self {
        self.selection = selection;
        self
    }

    pub fn prefix(mut self, prefix: impl IntoElement) -> Self {
        self.prefix = Some(prefix.into_any_element());
        self
    }

    pub fn suffix(mut self, suffix: impl IntoElement) -> Self {
        self.suffix = Some(suffix.into_any_element());
        self
    }

    pub fn h_px(mut self, height: f32) -> Self {
        self.height = Some(px(height));
        self
    }

    pub fn w_full(mut self) -> Self {
        self.width = Some(gpui_kit::gpui::relative(1.0).into());
        self
    }

    pub fn rounded(mut self, radius: Pixels) -> Self {
        self.rounded = Some(radius);
        self
    }

    pub fn rounded_full(mut self) -> Self {
        self.rounded = Some(px(9999.0));
        self
    }

    pub fn bg(mut self, bg: Hsla) -> Self {
        self.bg = Some(bg);
        self
    }

    pub fn border_color(mut self, color: Hsla) -> Self {
        self.border_color = Some(color);
        self
    }

    pub fn focused_border_color(mut self, color: Hsla) -> Self {
        self.focused_border_color = Some(color);
        self
    }

    pub fn on_clear<F>(mut self, listener: F) -> Self
    where
        F: Fn(&ClickEvent, &mut Window, &mut App) + 'static,
    {
        self.on_clear = Some(Box::new(listener));
        self
    }

    pub fn on_click<F>(mut self, listener: F) -> Self
    where
        F: Fn(&ClickEvent, &mut Window, &mut App) + 'static,
    {
        self.on_click = Some(Box::new(listener));
        self
    }
}

impl RenderOnce for Input {
    fn render(self, _: &mut Window, _: &mut App) -> impl IntoElement {
        let is_empty = self.value.is_empty();
        let chars: Vec<char> = if self.masked {
            self.value.chars().map(|_| '•').collect()
        } else {
            self.value.chars().collect()
        };

        let bg = self.bg.unwrap_or_else(Theme::bg_secondary);
        let border_color = if self.focused {
            self.focused_border_color.unwrap_or_else(Theme::accent)
        } else {
            self.border_color.unwrap_or_else(Theme::border)
        };

        let mut container = div()
            .id(self.id)
            .h(self.height.unwrap_or(px(36.0)))
            .px(px(12.0))
            .flex()
            .items_center()
            .gap(px(8.0))
            .bg(bg)
            .border_1()
            .border_color(border_color)
            .font_family(Theme::font_family())
            .text_size(px(13.0));

        if let Some(w) = self.width {
            container = container.w(w);
        } else {
            container = container.w_full();
        }

        if let Some(r) = self.rounded {
            container = container.rounded(r);
        } else {
            container = container.rounded(px(crate::widgets::style::INNER_RADIUS));
        }

        if let Some(prefix) = self.prefix {
            container = container.child(prefix);
        }

        let mut text_container = div()
            .flex_1()
            .min_w_0()
            .h_full()
            .overflow_hidden()
            .flex()
            .items_center();

        if is_empty {
            if self.focused {
                text_container = text_container.child(
                    div()
                        .flex_shrink_0()
                        .font_weight(FontWeight::BOLD)
                        .text_color(Theme::accent())
                        .child("│"),
                );
            }
            text_container = text_container.child(
                div()
                    .flex_1()
                    .min_w_0()
                    .text_ellipsis()
                    .whitespace_nowrap()
                    .text_color(Theme::muted())
                    .child(self.placeholder),
            );
        } else if self.focused {
            let cursor_pos = self.cursor.unwrap_or(chars.len()).min(chars.len());
            let before_cursor: String = chars[..cursor_pos].iter().collect();
            let after_cursor: String = chars[cursor_pos..].iter().collect();

            if !before_cursor.is_empty() {
                text_container = text_container.child(
                    div()
                        .min_w_0()
                        .whitespace_nowrap()
                        .text_color(Theme::fg())
                        .child(before_cursor),
                );
            }

            text_container = text_container.child(
                div()
                    .flex_shrink_0()
                    .font_weight(FontWeight::BOLD)
                    .text_color(Theme::accent())
                    .child("│"),
            );

            if !after_cursor.is_empty() {
                text_container = text_container.child(
                    div()
                        .min_w_0()
                        .whitespace_nowrap()
                        .text_color(Theme::fg())
                        .child(after_cursor),
                );
            }
        } else {
            let text_val: String = chars.iter().collect();
            text_container = text_container.child(
                div()
                    .flex_1()
                    .min_w_0()
                    .text_ellipsis()
                    .whitespace_nowrap()
                    .text_color(Theme::fg())
                    .child(text_val),
            );
        }

        container = container.child(text_container);

        if self.cleanable && !is_empty {
            let mut clear_btn = div()
                .id("input-clear-btn")
                .size(px(20.0))
                .flex_shrink_0()
                .rounded_full()
                .bg(Theme::bg_secondary())
                .hover(|s| s.bg(Theme::surface_hover()))
                .flex()
                .items_center()
                .justify_center()
                .cursor_pointer()
                .child(
                    svg()
                        .path("close.svg")
                        .size(px(10.0))
                        .text_color(Theme::muted()),
                );

            if let Some(on_clear) = self.on_clear {
                clear_btn = clear_btn.on_click(on_clear);
            }

            container = container.child(clear_btn);
        }

        if let Some(suffix) = self.suffix {
            container = container.child(suffix);
        }

        container
    }
}
