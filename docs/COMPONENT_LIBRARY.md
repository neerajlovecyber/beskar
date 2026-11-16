# Shared shell controls

Beskar's reusable rendering code lives in `.plm` libraries under `shell/common/`.
Importing a library does not create a Wayland surface or a process. A control draws
inside its caller's existing surface. The frame remains the owner of panel glass.

Current sizing and contributor rules: [UI_STANDARDS.md](UI_STANDARDS.md).

## Existing modules

| File | Interface and responsibility |
| --- | --- |
| `geometry.plm` | Shared constant-only geometry: spacing, insets, heights, corners, typography; no drawing or state |
| `theme.plm`, `theme_owner.plm`, `theme_facts.plm` | Colour, typography and spacing tokens; Settings owns the saved look |
| `icons.plm` | `Sym` and `SymTile` |
| `buttons.plm` | `IconButton` and `IconTextButton`, with explicit colours, actions and numeric IDs |
| `calendar.plm` + `shell/calendar.luau` | One six-week `MonthGrid` and one pure date-data implementation for Today and widgets |
| `ui.plm` | Buttons, switches, sliders, cards, row frames, headers, empty states and scrollbars |
| `panelbody.plm` | `PanelBody`: the shared panel reveal and clipping behaviour |
| `scroll.plm` | `ScrollFade` and `ScrollChrome`: shared edge fading and scrollbar treatment |

`common/` also contains feature parts. For example, `personal_editor.plm` declares
an editor surface intentionally; it is not a surface-free rendering library.
Keep that distinction explicit when adding shared code.

## Ownership and cost

- Rendering libraries declare controls and accept values, events and colours. New
  libraries use `library … strict` so missing inputs fail compilation.
- Scenes own surfaces, permissions, data models and service subscriptions. Existing
  owners (`Settings`, `System`, `Weather`, `Personal`, `Panels`) retain their state.
- A control may own local interaction state, such as a hover spring. It must not
  create a new data owner, periodic poller or adjacent `.luau` plugin merely to draw.
- Pass theme colours explicitly. On exp.8, implicit colour reads in imported
  controls inside `PanelBody` can lose the calling scene's namespace. Existing
  `ui.plm` controls accept named `ui_*` arguments; new interfaces require their
  inputs rather than depending on ambient scene values.
- Import libraries consistently. The compiler reads a library reached through
  multiple imports once; do not copy its declarations into each scene with
  `include`, or import the same library under competing aliases.
- Used controls expand into drawing instructions, properties and zones. An import
  creates no surface, but an instance still has the cost of what it draws.
  Replacing duplicated code with a control is not itself a frame-time improvement.
- Keep model capacities small and window long lists. Each model's `max` capacity
  expands at compilation; a hidden oversized list still increases compiled size.
- Blur, glass, backdrop capture and group effects have additional rendering costs.
  In particular, group effects use intermediate rendering layers. Keep them opt-in
  and avoid them for basic controls. Preserve the separate wallpaper, widgets,
  lock and capture processes; sharing source does not require merging processes.

## ScrollFade

Import `common/scroll.plm` and place the control after the viewport content,
inside the caller's existing panel. Place its origin at the viewport's origin:

```text
group {
    move: viewport_x, viewport_y
    ScrollFade(width, viewport_height, list.scroll, list.content, bg_color)
}
```

The optional last argument is the fade depth (default 32 px). The caller owns
the list, clipping and scrolling. The control uses one small shader rectangle,
accepts its fill colour explicitly, and becomes transparent at the end of the
list or when everything fits. It creates no hit zone or offscreen group effect.
It is a coloured scrim, not an opacity mask on the underlying cards.

`ScrollChrome(w, viewport_h, sc, ct, ink, fill, depth=32, gutter=10)` combines
that fade with the shared scrollbar. Notifications, updates, notes and to-dos now
use it. The shader is hidden when there is no remaining overflow. The scrollbar
clamps its minimum-size thumb within the track even for very large content.

## Geometry migration — 2026-11-14

The existing controls and their callers now use shared geometry roles across
Settings, panels, menus, dialogs, pickers, widgets, capture and lock. Widget
sliders also use the shared `Slider`, preserving edit-mode guards. Spotlight
places its wheel catcher before result rows so clicks can reach them.

Desktop compiled counts remain 2165 properties / 12295 instructions / 23 layers /
3157 rules / 1056 zones. Widgets remain 303 properties / 0 layers / 1796 rules /
772 zones; instructions increased from 17168 to 17424 when the two shared sliders
expanded across the max-16 cards. No surfaces, subscriptions or timers were added.
These are compiled structural counts, not a frame-time benchmark.

Validation passed: combined desktop, widgets, lock and capture compilation; the
full panel smoke and a final notification smoke; the geometry guard including
negative fixtures; dark/light/solid control renders; long-label notification
rendering; 125% nested-compositor rendering with an actual keyboard submit;
and live Spotlight Return, session Cancel keypad Enter and Settings-title routing.
The live lock was never activated, and theme variations used fixture-local facts.
The existing `screens.count` compile warning remains.


The geometry checker runs before smoke checks. See [UI_STANDARDS.md](UI_STANDARDS.md)
for its coverage and deliberate feature exceptions.

## Further consolidation

For the proposed Figma-based sizing, spacing and corner migration, see
[SHELL_CONSISTENCY_PLAN.md](archive/SHELL_CONSISTENCY_PLAN.md). Extend the controls listed
here and migrate their callers in stages.

1. Keep the existing theme, UI and panel wrapper as the foundation. Do not add a
   second button/card system or rebuild existing state owners.
2. Extract repeated behaviour when two real callers need it. Headers with actions,
   search fields and selectable rows are useful candidates to inspect next.
3. Keep content and state decisions at the caller. A shared scrolling interface
   should not know about notification IDs, packages, clipboard entries or weather.
4. Migrate one caller at a time. Compile the affected desktop scene and verify its
   actual interaction and rendering; run only relevant smoke checks. Compare
   compiled counts before/after and check that no surfaces or subscriptions were
   introduced. Measure frame time when adding effects or increasing list capacity.

## First extraction evidence

Moving notification fading to `ScrollFade` changed the combined desktop from
2166 to 2165 properties, 12041 to 12043 instructions, and 3138 to 3137 rules.
Layers stayed at 23 and zones at 1056. No surface declarations, permissions,
models or timers were added. These counts demonstrate the structural cost;
they are not a frame-time benchmark.


## Shell-wide reuse audit — 2026-11-14

The audit covered every production `.plm` scene and the shared feature parts.
Existing `Btn`, `Pill`, `Chip`, `Seg`, `ToggleRow`, `Switch`, `Slider`, `CardBg`,
`RowFrame`, `SelectCard`, `EmptyState`, `Sym` and `ScrollBar` remain the shell's
standard controls. Pleamar also ships `pleamar:ui`; Beskar already has its own
consistent themed equivalents, so this pass did not mix in another button system.
The runtime's built-in catalogue has no month-calendar control.

| Area | Shared controls now used | Feature-specific implementation retained |
| --- | --- | --- |
| Settings | Existing buttons, segmented choices, chips, toggle rows, sliders, cards and corrected scrollbars | Display/output rows, shortcut data, skin/accent previews and sidebar navigation |
| Control Center | Shared radio switches, icon buttons for media, icon/text back buttons, cards, sliders, pills and empty states | Connection/device rows, signal-strength drawing, seek behavior and quick-action routing |
| Today | `MonthGrid`, shared calendar arrow buttons, cards and icon rendering | Greeting, statistics, weather and Personal previews |
| Weather / music / updates | Existing standard pills/cards; shared media icon buttons and updates `ScrollChrome` | Forecast rows, seek interactions and package rows |
| Notifications | Shared `Pill` for Clear All, `CardBg` borders and `ScrollChrome` | Notification content, app stacks, grouping, history and banner arbitration |
| Personal editor | Existing pills/chips, shared move/remove icon buttons and shared list chrome | Note editing, task checkboxes and owner events |
| Dock panels | Shared icon/text widget-add buttons, existing chips for presets, pills, row frames and scrollbar | Search/keyboard selection, clipboard paging, wallpaper preview cards and page arrows |
| Widgets | The same `MonthGrid` and date data as Today; shared media icon buttons; existing `Sym` icons | Widget faces, placement, editing, drag/resize and service/client feeds |
| Session / authentication dialogs | Shared `SelectCard`, icon and `Pill` controls, including disabled authentication state | Five-action chooser, keyboard selection, confirmation/countdown and authentication |
| Window panels | Existing `SelectCard` and icon rendering | Thumbnail geometry, workspace tags and window selection |
| Top bar | Existing shared icon primitives | Monitor-aware routing, workspace/dock items, animated status indicators and island geometry |
| Capture / lock / wallpaper | Existing icon/theme primitives where applicable | Region/resize handles, capture selectors with right-click dismissal, lock actions with labels below, authentication and wallpaper transitions |

This is a reuse audit, not a claim that every piece of drawing must be a generic
control. A notification stack, a window thumbnail and a wallpaper preview are
feature presentations. Their content stays with the feature. The capture selectors'
right-click dismissal and the bar's monitor routing also differ from an ordinary
button; those interactions remain explicit.

Seven duplicated card-border drawings were removed by enabling `CardBg`'s existing
edge argument. No second text-button or scrolling engine was introduced. Lists use
native `column … view:` scrolling where already appropriate. Spotlight's offset
and clipboard/wallpaper paging remain tied to keyboard/selection behavior; they
reuse the appearance primitives without acquiring a competing scroll controller.

### Buttons

`buttons.plm` is a strict rendering library. `IconButton` takes a glyph, accessible
label, event, ink/fill colours, optional geometry, fill opacity, numeric payload and
enabled state. `IconTextButton` adds a text label and optional hover treatment.
Callers supply theme opacities as well as colours (for example `item_bg_op` when
using `item_bg`). A flat icon button uses `fill_op: 0`. There are no periodic timers.

The glyph is drawn directly in the button using the same Mono icon font as `Sym`.
On exp.8, forwarding a conditional text parameter through another component can
lose its text binding; the button keeps that binding local. Dynamic play/pause
glyphs therefore work without introducing an icon service or another data owner.

Numeric button payloads preserve record IDs; scenes keep handling the actions.
Disabled controls keep their hit zones inactive. The optional `enabled` input was
also added to the existing shared `Switch`, so Bluetooth keeps its hardware-present
guard while using the same switch as Settings.

### Calendar

`shell/calendar.luau` is pure date preparation, called by the owners' existing clock
updates and month-navigation events. It adds no timer or service watcher. It returns
a title and 42 Monday-first cells (`d` text, `kind`: 0 current month, 1 adjacent
month, 2 today). Today and widgets each own a one-record model containing that cell
list; `MonthGrid` receives its record and explicit dimensions/colours. Both render
the same dates, six-week grid, weekend accent and today marker at their own density.

`MonthGrid(month, w, row_h, ink, muted, accent, on_accent, compact=false,
day_size=12, heading_size=9)` expands one fixed grid. There is no component instance
per day and no date formatting performed every animation frame. Calendar data stays
local to each existing scene; sharing a pure function does not require cross-process
polling or a new owner scene.

### Verification and structural cost

- `lua tests/calendar.lua`: leap days, century rules, Monday-first placement, year
  navigation, adjacent-month dates and today-marker invariants.
- Shared-control render fixture: both calendar densities, enabled/disabled icon
  buttons, icon/text buttons, switches, dialog buttons and overflowing list chrome.
  Its synthetic button interaction produced payloads 7 and 11; disabled payload 8
  never appeared. The fixture has no services and was run separately from user data.
- Combined desktop/widgets compilation and smoke checks limited to affected panels:
  Control Center, notifications, Personal, Today, music, Spotlight, widget bar,
  session dialog, updates and Settings. No file-search/backend, weather, lock or
  authentication traffic was tested as part of this rendering refactor.

| Compiled output | Before this audit | After |
| --- | ---: | ---: |
| Desktop properties | 2165 | 2165 |
| Desktop instructions | 12043 | 12295 |
| Desktop layers / rules / zones | 23 / 3137 / 1056 | 23 / 3146 / 1056 |
| Widgets properties | 303 | 303 |
| Widgets instructions | 16336 | 17168 |
| Widgets layers / rules / zones | 0 / 1796 / 772 | 0 / 1796 / 772 |

No production surfaces, processes, permissions, service subscriptions or periodic
callbacks were added. The compiled instruction increases are explicit overhead of
instantiating shared controls; they are not a measured frame-time regression or a
claim of zero rendering cost. Per-control shapes still render, and optional fades
only draw on overflowing views. Early calendar prototypes that expanded a wrapper
for every day were discarded because they enlarged the widget scene substantially.
