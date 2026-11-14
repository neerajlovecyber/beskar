# Beskar UI standards

Use `shell/common/geometry.plm` and the existing `ui.plm`, `buttons.plm`,
`icons.plm`, `calendar.plm` and `scroll.plm` rendering modules for all new UI.
`common/palette.plm` imports geometry once; libraries that need geometry also
import it directly. Geometry contains constants, not drawing, state or services.

The [design reference](DESIGN_REFERENCE.md) records measured macOS 26 sources.
Beskar adapts their proportions to its island layout and installed fonts; it
does not assume Figma's glass parameters are pleamar shader parameters.

## Shared roles

| Role | Tokens and values |
| :--- | :--- |
| Spacing | `space_2/4/6/8/12/16/20/24/32` |
| Insets | `inset_compact` 12, `inset_card` 16, `inset_panel` 20 |
| Relationships | `gap_icon` / `gap_controls` 8; `gap_sections` 16 |
| Text buttons | `control_h_compact` 24, `control_h` 28, `control_h_large` 32; `control_pad` 16 per side |
| Icon buttons | `icon_button_compact` 24, `icon_button_size` 28, `icon_button_large` 36 |
| Control corners | `control_r` 6; `control_r_large` 8 |
| Rows/cards/windows | `radius_row` 8, `radius_medium` 12, `radius_card` 16, `radius_window` 24 |
| Form rows | `row_h` 42, `row_detail_h` 56, `row_slider_h` 64 |
| Switch | `switch_w` 44, `switch_h` 20, `switch_knob_w` 26, `switch_inset` 2 |
| Search | `search_h_compact` 28, `search_h` 36 |
| Typography | `font_title` 15, `font_body` 13, `font_secondary` 12, `font_caption` 11, `font_micro` 10.5 |

The theme's existing `r_s/r_m/r_l/r_xl` and `t_*` names alias these roles.
Choose the role by meaning, not simply because its number happens to fit.

## Controls and layout

- Use `Btn` for simple actions; `Pill` adds tones and numeric payloads.
  Despite its historical name, `Pill` defaults to a rounded rectangle.
  `round: true` is reserved for an intentional capsule treatment.
- Use `Chip`/`Seg` for selection and `IconButton`/`IconTextButton` for glyph
  controls. Keep default dimensions or pass a named size role.
- Action labels need their measured width plus two `control_pad` insets.
  Widen a long-label button instead of squeezing its padding or font.
  Segmented choices have a separate denser label treatment.
- Pass scene theme colours through `ui_*` arguments or strict icon-control
  colour inputs. Icon controls default to a translucent neutral fill, avoiding
  white boxes with dark-mode `item_bg`; use `fill_op: 0` for bare glyphs.
- Preserve action payloads and `enabled`/`on_` guards. A disabled control has
  an inactive zone as well as faded drawing. Widget sliders use
  `Slider(..., enabled: not editing, ui_track_op: 1)`.
- Use `CardBg` for cards, `RowFrame` for selection and `ScrollChrome` for
  scrollbar/fade treatment. The caller owns content, paging and scrolling.
- Reuse `MonthGrid` without creating one module instance per calendar day.
- Align titles, descriptions and body content on the selected inset. Centre
  trailing controls in their row. Leave room for hit zones and focus rings.
- Declare broad wheel/dismiss zones before their child rows/buttons: the last
  overlapping zone receives a press. A fade must not become a hit zone.

`PanelBody` retains its stationary-content and reveal contract. Its x/y align a
surface to the frame's glass and are not ordinary card padding. Update panel
height/width reports and frame targets together when dimensions change. Bottom
search uses final `panel_h` and the shared `panel_search_*` geometry roles.
Changing a row height/gap must also update any Luau offsets and total heights;
notification row heights remain owned by `notif.luau`.

Hover, selection and keyboard focus have distinct meanings. Preserve existing
default/Cancel rings and key routing. A ring does not make an arbitrary zone
keyboard-focusable. New keyboard flows must define focus entry, navigation,
Return/keypad Enter, Escape and disabled behaviour explicitly. Do not duplicate
an input's submit action with another Return handler.

## Intentional feature geometry

Keep miniature icon paths, tiny meter caps, optical nudges and preview aspect
ratios. Preserve widget 160/336 footprints and placement gap, calendar cell
pitch, large clock/weather readouts, the launcher's large search presentation,
the lock's `auth_field_h` 46 capsule, capture handles/mode selectors, monitor
ring/struts, island joins and shadow room. Use a named role for a repeated new
treatment; document a feature exception where it is used.

## Required checks

Run `python3 shell/check-ui.py` after UI changes. It also runs automatically
before `shell/smoke.sh`. It rejects arbitrary layout gaps, common text sizes,
control size/corner overrides, literal UI corners of five units or more, and
surfaces/data feeds in rendering libraries. It handles nested arguments and
ignores quoted labels/comments. It checks source conventions, not visual fit.

Compile `desktop.plm` and affected standalone scenes with `bin/exp/pleamar`.
Smoke affected panels; when shared controls change across the shell, run the
full panel smoke once. Verify overflow, disabled/selected states and actual key
activation. Use isolated fixtures for theme/scale variations and dangerous
actions; never activate the live lock or confirm shutdown as a test.

Do not add surfaces, owners, service watchers or polling loops for styling.
Keep the process split, small model capacities and desktop swapchain workaround.
Compare compiled counts when changing shared drawing. Measure rather than
claiming a frame-time improvement from source reuse.
