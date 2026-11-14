# Shell spacing and control consistency

Status: implemented geometry migration, 2026-11-14. The proposal below records
the design decisions; [UI_STANDARDS.md](UI_STANDARDS.md) is the current contributor
contract and `shell/check-ui.py` enforces its source conventions.

Shared controls and callers across Settings, panels, menus, dialogs, pickers,
widgets, capture and lock use the central geometry roles. Feature-specific
footprints, artwork, morph origins and existing keyboard flows remain explicit.
No universal keyboard-focus framework or new glass effects were introduced.
Structural cost and validation are recorded in [COMPONENT_LIBRARY.md](COMPONENT_LIBRARY.md).

Use the user's [macOS 26 kit](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=121-18094)
to make spacing, sizing, corners and interaction states consistent across Beskar.
Preserve the ring, islands, dock and panel morphs that give this shell its shape.
The inspected values and source nodes are in [DESIGN_REFERENCE.md](DESIGN_REFERENCE.md).
Existing rendering modules are documented in [COMPONENT_LIBRARY.md](COMPONENT_LIBRARY.md).

## Keyboard status before visual work

The user reported that Enter stopped activating Spotlight results and session
dialog choices, then confirmed it was working again during investigation.
Controlled Wayland keyboard checks with `wtype` passed for both `Return` and
`KP_Enter`: typing `?sound` and submitting opened Sound Settings; selecting
Cancel with Left and pressing Enter closed the session dialog. Synthetic key
checks through the desktop socket also reached the existing handlers.

No keyboard patch was made, and the intermittent failure's cause is unconfirmed.
A later live WhatsApp attempt did not populate the query, so it does not establish
whether WhatsApp activation itself fails. Avoid treating a shared-desktop focus
interruption as evidence of a broken launch handler. If the issue returns,
capture the failing key/focus path before adding bindings. Do not combine an
`on key Return` fallback with an input's existing submit action and risk executing
twice. Session tests must use Cancel or stubbed command execution.

## Current inconsistencies

| Area | Current evidence | Improvement |
| :--- | :--- | :--- |
| Geometry tokens | `theme.plm` has radii 8/12/16/24 and type sizes, but no shared spacing or control-height scale | Add named spacing and sizing roles alongside the existing theme values |
| Text buttons | `Btn`, `Seg` and `Chip` are 28 high with radius 8; `Pill` defaults to radius 9 or half its height | Give equivalent actions the same size, typography and radius; reserve pills for an intentional role |
| Icon controls | `IconButton` defaults to 28 square/radius 8; callers also use 24 and 36 | Define compact, regular and prominent variants with consistent glyph alignment |
| Switches | Shared `Switch` is 44×24; the inspected form uses 36×16, and the kit also has 44×20 and 54×24 variants | Choose sizes by context; keep drawing and hit geometry aligned |
| Form rows | Shared `ToggleRow` is 56 high; Settings has local 56/64-high rows and repeated inset constants | One single-line rhythm and one description-row rhythm, with longer descriptions allowed to grow |
| Panel content | `PanelHeader` uses one default origin, while callers choose different header and body offsets | Align header titles, body content and footer controls on deliberate content edges |
| Notifications | Live/history cards use different icon sizes and density; card radius already uses 16 | Keep intentional live/history hierarchy; align title, icon, timestamp and close action consistently |
| Search and lists | Spotlight, clipboard and Settings use different search presentations and row layouts | Share field geometry and row alignment while retaining their distinct search behaviour |
| Calendars and widgets | Shared month grid exists; widget cards have fixed footprints | Align surrounding padding, weekday labels and navigation without enlarging model capacities |
| Focus and selection | Several controls draw hover/selection; generic button keyboard navigation is not automatic | Make focus, default action and selected item visually distinct and verify actual key routing |

## Proposed geometry contract

These are **Beskar proposals**, informed by the kit. They are not claims that
Apple specifies one universal value. Figma coordinates are logical design units;
render them through the compositor's scale, not hand-multiplied physical pixels.

| Role | Proposed value | Basis and use |
| :--- | :--- | :--- |
| Spacing scale | 2, 4, 6, 8, 12, 16, 20, 24, 32 | Beskar scale; replace accidental one-off gaps, preserve deliberate optical offsets |
| Inline icon/label gap | 6 compact, 8 regular | Proposed; inspect actual icon bounds and baseline before migration |
| Related controls / sections | 8 / 16 or 24 | Proposed separation by relationship, rather than a different gap on every page |
| Card padding | 12 compact, 16 regular | Proposed; explicit exceptions for notification component geometry |
| Panel content inset | 20 regular, 16 compact, 24 roomy | Proposed; choose by panel role, then align header/list/footer to it |
| Button heights | 24 compact, 28 regular, 32 prominent | Kit push-button baseline is 24; retain Beskar's regular density and larger dialog actions |
| Text-button horizontal padding | 16 | Verified kit value; derive width from label plus padding or use equal widths within an action group |
| Icon-button square | 24 compact, 28 regular, 36 prominent | All appear in kit arrow-button examples; glyph size remains separately chosen |
| Button corner radius | 6 compact/regular, 8 prominent | 6 verified for kit push button; 8 is a Beskar proposal for the larger role |
| Row / card / window radius | 8 / 12 or 16 / 24 | Proposed semantic use of existing Beskar values; notification card radius 16 is verified |
| Pill radius | height / 2 | Only for intentionally pill-shaped controls, not every neutral action |
| List row | 42 single-line; 56 two-line baseline | 42 minimum verified in form example; 56 retains current Beskar description-row density |
| Switch | 36×16 compact; 44×20 regular | Both measured in the kit's Toggles examples; do not distort the knob when resizing |
| Checkbox / radio | 16 | Verified kit control size; allow surrounding row to supply a larger target |
| Search field | 28 compact; 36 regular | Both measured in kit Search Fields examples; Spotlight's large bottom search remains an explicit feature presentation |
| Body / secondary / caption type | 13 / 12 / 11 | Body 13 and caption 11 verified; secondary 12 is Beskar's proposed hierarchy |

Keep icon optical nudges where measured. A mathematical centre does not guarantee
that a Nerd Font glyph looks centred. Keep the installed shell font and assess
its real metrics; the reference's SF Pro measurements do not imply that SF Pro is
installed or should be downloaded.

Concentric corners should remain compatible with the parent's radius and inset.
Do not set every nested box to the panel radius. Keep shadows inside available
surface bounds and distinguish visible shadows from retained pixels after close.
Figma Liquid Glass parameters are not pleamar shader parameters.

## Implementation sequence

### 1. Foundations and a representative sample

Record current compiled desktop/widget counts and screenshots of Settings,
Control Center, notifications and Today. Fill the remaining reference gaps from
the kit: dark appearance, focused/disabled button and field states, slider track
and knob, menu rows, panel/window corners and dialog actions. Do not infer all
states from the light form example.

Extend the existing theme with semantic spacing, heights and control radii.
Implement size roles in the existing rendering modules; keep numeric overrides
only for real feature exceptions. First try one Settings form section and one
Control Center section so the proposed density can be assessed in context.

Done when: equivalent controls agree, labels fit, and the samples work in light,
dark, solid and translucent appearances. Finalise the proposed scale from these
samples before migrating the rest of the shell.

### 2. Shared controls and Settings

Update `Btn`, `Pill`, `Chip`, `Seg`, `IconButton`, `IconTextButton`, `Switch` and
slider drawing in place. Keep their current events and numeric payloads intact.
Use a small sizing interface; do not make each caller supply a dozen geometry
values or add a second button library. Align glyph/label baselines, action-group
gaps and selected/disabled styling. A default action and keyboard focus need
distinct treatment; a disabled control must be inactive as well as faded.

Migrate every Settings page, its sidebar/search, cards, segmented choices,
sliders and footer actions. Match title/subtitle leading edges and trailing
control alignment. Restore any preference changed during validation.

Done when: Settings has one coherent form rhythm and no clipped labels at the
tested scales, with current actions and saved preference ownership preserved.

### 3. Panel chrome and lists

Apply shared header/body/footer insets across Control Center, notifications,
Today, weather, music, updates and Personal. Keep section spacing and action
placement consistent. Share row background/selection geometry where there are
already equivalent callers; retain feature content and state at the caller.

For notifications, compare the existing 352-wide content against both source
variants (344 component default and 382 desktop example) before choosing final
width. Keep wrapped text, grouping, bounded rendering, the 720-height cap,
fixed header and scrolling history. Keep scrollbar gutter/fade out of text and
action targets. Account for changed row heights in the logic's offsets and total
content height, not only in the drawing.

When padding changes panel dimensions, update panel height/width reports and
frame targets together. Keep `PanelBody`'s stationary content and reveal contract.

### 4. Search, pickers and dialogs

Align Spotlight and clipboard search decorations, result text/icon columns,
selection frames and footer spacing. Keep their bottom search position and
search-specific keyboard behaviour. Make list scroll hit regions stop covering
selectable row hit regions; their layering is part of the input audit.

Apply the size roles to wallpaper paging, widget-picker controls, switcher and
overview labels, session/authentication dialogs and welcome actions. Preserve
preview aspect ratios and context-specific tile sizes. Verify Enter/keypad Enter,
arrows, Escape and visible default/cancel selection after migration. Add menu
keyboard behaviour only through a focused, explicit interaction change; drawing
a focus ring alone does not make a zone keyboard-focusable.

### 5. Frame, widgets and standalone scenes

Align bar hit targets and icon baselines within the existing islands, then dock
icon spacing, badges and context menus. Preserve dynamic island sizing, monitor
routing and auto-hide. Do not turn all bar items into fixed-width buttons.

Apply card insets and control roles to every widget face, including calendar
navigation, notes/tasks, weather and media. Preserve the 160/336 footprints,
16-unit placement gap and allowed widget sizes. Keep one calendar grid per card.

Apply matching control roles to capture and lock only after the desktop samples
are stable. Test their interaction in isolation; never activate the live lock or
run real shutdown, logout or restart actions as a keyboard check.

## Performance and verification

Geometry constants and shared rendering code create no new surfaces, processes,
owners, service subscriptions or timers. Keep the current process split and
existing owner/event contracts. No extra per-row wrappers, group blur/masks,
oversized models or permanent frame loops for ordinary controls.

For each slice, compile `desktop.plm` and affected standalone scenes, then run
only the relevant panel smoke checks and keyboard/visual checks. Include empty,
long-label, scrolling, disabled, selected and focused states; use both monitors
and a scaled nested output. Test persistence only where behaviour changed.
Do not rerun unrelated weather/search/storage suites for geometry-only edits.

Compare properties, drawing instructions, rules, zones and effect layers against
the slice's baseline; investigate unexpected growth. Measure frame time only if
adding effects, increasing drawing cost or changing repaint behaviour. Keep the
desktop swapchain workaround in place and verify that affected panels clear
after closing. Source reuse alone is not a performance benchmark.

The migration is complete when equivalent roles share geometry and states across
the shell, documented feature exceptions remain intentional, real keyboard
activation still works, overflow stays usable, and no new rendering infrastructure
has been introduced for styling.
