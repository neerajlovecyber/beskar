# Customization plan

Audit and implementation date: 2026-11-14. Status: initial C1–C6 increments implemented; later increments remain scoped below.
This is the current sequence for customization work, expanding milestone 6 of
[NEXT_FEATURES_PLAN.md](NEXT_FEATURES_PLAN.md). Ship one slice at a time.

The goal is iNiR-level control over the parts people use every day: appearance,
bar and dock, wallpaper, widgets, shortcuts and saved setups. Beskar keeps its
frame, shared controls and ownership model. Success means choices are easy to
find, work together, survive restart and can be undone.

## Delivered increments

| Slice | Implemented | Deliberate boundary |
| --- | --- | --- |
| C1 | Individual Appearance search/reveal; stable control IDs; validated/versioned preference documents; atomic serialized saves; recovery messages; Appearance reset review and one-step undo | Restore is currently the Appearance group; corrupt/newer/unreadable documents remain protected |
| C2a | Wallpaper favourites, unavailable entries, validation before replacement, Circle/Fade/Wipe, previous-picture restore; named appearance looks | Configured folders, fit modes, per-output pictures and rotation are later increments |
| C3 | Workspace/app/update visibility; bounded dock size and hide/reveal timing; keyboard pin ordering; left/right optional module ordering; All/Focused/Named output policies with fallback; responsive overflow caps and tray-wheel paging | Core controls and ring remain on every output; named policy applies optional modules and dock. Alternate edges remain a separate geometry project |
| C4a/b | Named widget desktops with save/rename/load/duplicate/update/delete; per-card position lock and clock date/seconds/format in the existing bar's Card tab | Max 16 cards and 24 desktops; stacks and world clocks remain separate increments |
| C5 initial section | Named looks (max 16); strict appearance-only export/import with change review and undo; recursive shortcut include discovery; conflict-aware Beskar-owned shortcut editing | No combined cross-owner profile. Inline user niri bindings stay read-only when there is no reachable Beskar include |
| C6 initial policy/recovery | Explicit Focus/Presentation/Game modes; manual DND preserved; per-sender Normal/No banner/Muted rules; saved daily quiet hours; independent display Keep/Revert watchdog | No automatic game detection, inline reply or display arrangement |

Settings exposes saved looks under Appearance, quiet modes/hours/app delivery under
Notifications, and owned shortcut controls under Shortcuts. Widget editing keeps
Widgets/Desktops/Card tabs inside the existing dock panel. None adds a permanent
surface or a second feature owner. The bell and Control Center show effective quiet;
the Control Center toggle still changes only manual DND.

### Stores and recovery

- `preferences.luau` and `settings_store.luau` validate theme, preferences and palette
  separately. Loading writes nothing; a legacy document upgrades on an actual edit.
  Unknown keys survive. Invalid individual values use their defaults; corrupt,
  unreadable and newer documents are not overwritten. Writes use adjacent temporary
  files, backups and a serialized/coalesced queue.
- `appearance-looks.json` version 1 stores named appearance snapshots. A portable
  document has `kind: "beskar.appearance"`, `version: 1`, and stable Appearance IDs
  in `values`. It contains no commands, credentials, personal content, app integration,
  display modes or derived palette cache. Import accepts supported partial choices,
  rejects unknown/invalid values, stages a preview, checks for intervening changes,
  and gives one appearance undo when applied. Copy current exports through the clipboard.
- `widgets.json` and `widget-layouts.json` version 2 preserve per-card `opts` and read
  version 1. Widgets owns both. Loading a desktop is one undo, preserves disconnected
  outputs, and clamps connected cards to available space. Position lock prevents drag
  and affects tidy/resize; removing a locked card and replacing a desktop remain allowed.
- Wallpaper keeps the existing current/previous files. The picker serializes its own
  requests; the two atomic replacements are not a cross-file transaction. The pinned
  runtime has no image-loaded acknowledgement: full decode is checked before handoff
  when ImageMagick exists, otherwise only file/signature checks are available.
- Notifications owns its versioned scene-local `quiet.json`; matching uses the actual
  service's trimmed, case-sensitive `app_name` because no stronger identity is exposed.
  Muted senders remain in the centre/history but do not count on the bell/lock screen.
  Quiet hours use local time and the existing 30-second tick. Temporary modes are not
  persisted; ending one never rewrites manual DND.
- `shortcuts.luau` discovers bounded recursive niri includes. `shortcuts_adapter.py`
  changes only Beskar-owned files using compare-and-swap, backups, full validation,
  rollback and reload. A conflict is shown before an explicit override; later user
  definitions that would shadow the change are refused. The current user's inline
  config is intentionally read-only. Fresh/reachable `beskar.kdl` installations can
  add the owned include. Niri may observe the brief invalid-file interval before a
  rejected write is rolled back; it retains its previous valid running config.
- `display-preview.py` journals under the private runtime directory and arms a
  detached watchdog before applying. Revert is the default; timeout, Settings closing
  or parent death restore the exact prior mode/refresh/scale. The adapter polls only
  during a preview. Killing both Settings and its recovery watchdog requires the
  next helper request to reconcile the journal; ordinary Settings crashes are covered.

### Focused verification

Native isolated fixtures cover Appearance search/reset/cancel/undo/restart; saved
looks and staged imports; quiet-hour validation and per-app event forwarding; recursive
shortcut discovery plus a real-niri-validated owned save with a fake reload; dock pin
keyboard ordering; wallpaper transition keys; saved-desktop navigation; Card-tab arrow
and keypad Enter forwarding. HOME, scene sockets and helper journals are isolated.
The display fixture uses fake niri state and native modal keys; no physical output is
changed. It covers default Revert, Keep, Escape, timeout, close/begin races, parent
crash recovery and exact refresh restoration. Testing found and fixed a stale status
response racing Keep/Revert and an apply error being hidden by the restoration message.

Relevant pure suites pass: preferences 101; Settings store 201; search 237; appearance
profiles 281; shortcut backend 466; quiet policy 98 and adapters 50; widget options 140,
layouts 184, bar layouts 172 and Card UI 99. Existing widget-bar layouts and wallpaper checks are scoped
to their features. `settings-runtime.py`, `settings-features-runtime.py`,
`customization-runtime.py`, `frame-runtime.py` and `display-runtime.py` are the native
fixtures. The affected live smoke (Settings, wallpapers, widget bar, notifications and
Control Center) passes without new runtime errors; no live preference mutation or
shell restart was needed for integration.

Initial increment desktop compile: 2411 properties, 13861 instructions, 23 layers,
3928 rules and 1279 zones. Widgets: 431 properties, 18832 instructions, 2376 rules,
900 zones. The only desktop warning is the existing Topbar `screens.count` reference.
Rendering libraries remain surface/feed-free; the UI guard passes.

A paired Settings-only nested fixture (same output, temporary preferences, stub owners;
9 seconds settling, then 5 seconds CPU/RSS sampling) measured before/after at 3.6/3.0%
of one CPU and 143.5/133.9 MiB RSS. Its compiled rules increased 424→546, zones 167→205.
Startup/open cycle means were 26.98/33.42 ms, worst cycle p99 130.41/66.62 ms, across
80/168 observed frames. These are noisy single paired diagnostics, include startup
and differ in font-cache warmth; they do not establish a speedup or zero overhead.
They are not full-shell frame-time measurements. Keep the current bounds and measure
again before expanding them.

### C3 follow-up evidence

`frame-options.lua` now passes 57 checks, including named-output disconnection
fallback and delayed reveal cancellation/stale-timer handling. `frame-runtime.py`
checks the real Settings pin editor and validates/saves output policy, output name,
module order and reveal delay in a temporary HOME. `frame-render-runtime.py` uses
the actual frame drawing with explicit owner snapshots on a 944-pixel output:
optional indicators fit, each group is instantiated once, swapping changes placement,
the actual renderer wheel command reaches hidden tray icons, and core routes survive
policy changes. The isolated Settings boundary keeps this drawing check independent
of unfinished Settings integrations; it is not a full-shell/persistence substitute.

One paired actual-frame diagnostic reversed only C3 geometry for its baseline,
using the same output, owner snapshots, eight-second settling period, three-second
idle sample and six menu open/close cycles. Before/after CPU was 2.0/0.67% of one
core and RSS 161.5/150.3 MiB; observed cycle means were 55.10/34.02 ms and worst
cycle p99 689.50/232.46 ms across 27/35 frames. Font-cache warmth and concurrent
GPU activity limit this single comparison; it proves neither zero overhead nor a
speedup. Expanded bounds still require fresh measurements.

## Original audit evidence and gaps

Compared against the local `references/inir` checkout at `edca6cc` (commit dated
2026-11-12). This is an inspected snapshot, not a claim about today's upstream.
No reference installer, shell or update command was run.

| Area | Beskar today | Next useful control | Local evidence |
| --- | --- | --- | --- |
| Settings | Eight categories; sidebar search filters category names; Spotlight finds pages | Search individual settings, reveal their control, restore a group | Beskar `shell/settings.luau`, `shell/actions.luau`; iNiR `modules/common/widgets/SettingsSearchRegistry.qml` |
| Appearance | Light/dark/time-based auto, three skins, seven accent choices, wallpaper palette with four styles, app theming | Named looks, bounded custom accent, motion preference; later font/size roles and per-app theme targets | Beskar `settings.plm`, `settings.luau`, `common/theme.plm`; iNiR `modules/common/ConfigOptions.qml`: appearance/typography/performance |
| Wallpaper | Mine/Built-in/All picker, cached thumbnails, saved current picture; circle/fade/wipe renderer | Expose existing transitions, favourites, configured folders, previous-picture restore; later per-output pictures | Beskar `dockpanels.luau` wallpaper module, `wallpaper.plm/.luau` |
| Bar and dock | Strip/Notch styles, seconds/weather/tray switches, dock auto-hide, persistent app pins | Module visibility/order, dock pin ordering, bounded sizes and hide timing, output policy | Beskar `settings.plm`, `topbar.plm/.luau`; iNiR README documents edge-specific families; exact family controls need another inspection |
| Widgets | 12 kinds; per-output placement; sizes, grid, tidy, undo; five factory layouts | Save/rename/load personal desktops, per-card settings/lock, then stacks | Beskar `widgets.luau`, `widgets_data.luau`; iNiR `services/DesktopPresets.qml`, `DesktopWidgetStacks.qml`, `DesktopWidgetLayout.qml` |
| Notifications | Banners, duration, grouping, history, manual DND | Per-app quiet delivery and quiet hours; explicit focus/presentation policy | Beskar `notif.luau`, `settings.luau`; iNiR `ConfigOptions.qml`: notifications/gameMode and `services/GameMode.qml` |
| Shortcuts | Searchable read-only list; shared shell action catalogue; niri bindings | Reliable included-file discovery, then conflict-aware editing of Beskar-owned bindings | Beskar `settings.luau` parse/load_binds, `actions.luau`, installer in `beskar`; iNiR `services/GlobalActions.qml` provides action metadata |
| Persistence | Several feature-owned files, manual Settings serialization; widgets already use debounced atomic writes | Validated/versioned preferences, atomic saves, backup/reset, then selective import/export | Beskar `settings.luau`, `widgets.luau`; iNiR `modules/common/Config.qml`, `modules/common/functions/ConfigMigrations.js` |
| Displays | Live output/scale/mode/refresh controls | Keep/Revert preview with independent recovery; arrangement only after capability verification | Beskar `settings.luau` niri_output; no rollback currently |

These are capability comparisons, not a count of switches. iNiR's `settings.qml`
loads Settings from a family plugin, and the main checkout does not contain those
families' complete interfaces. Shared services/schema verify presets, stacks,
typography, quiet-hours and performance preferences; they do not establish exact
bar editor behaviour or performance in Beskar.

## C1 — Settings people can find and safely restore

**First implementation slice: current Appearance settings.** Search an existing
control by name/keyword from Settings and Spotlight, open its category, reveal
and highlight it. Add Restore Appearance with a review of the affected values
and a one-step undo. This is a small visible feature while the saved-preference
contract becomes reliable.

- Extend the existing action/settings catalogue with stable setting IDs, title,
  category/section, keywords, type, default and allowed values. Keep dispatch
  explicit in Settings; do not create a universal event bus or UI generator.
- Include the existing appearance mode, skin, accent source/choice and palette
  style first. Preserve category results and existing `?` search behaviour.
- Route selection through a typed Settings event carrying the stable ID. A
  search result reveals a control; it never changes a value by itself.
- Build search results from metadata, not live copies of every Settings page.
  Reuse current rows and scrolling. Define keyboard entry, arrows/Tab,
  Return/keypad Enter, Escape and unavailable-control behaviour.
- Validate and normalize persisted values. Save atomically, serialize pending
  writes, report failure and retain the last good file. Add a schema version
  and backwards-compatible reads for the existing theme/prefs/palette files.
  Do not merge or relocate all stores in this slice.
- Settings keeps authoritative user choices. Existing handlers and consumers
  join the same validated setters; startup and `start.sh` restoration must agree.
- Reset only the described group. The initial appearance reset excludes external
  app integration, wallpaper choice, hardware settings and personal content.
  Undo restores automatic/manual accent choices as well as displayed colours.
- Then expand search/reset coverage to other existing preference groups. DND is
  Notifications-owned and system audio/display values are not ordinary defaults.

**Acceptance:** old preferences load without losing choices; a stale/invalid value
has a defined fallback; corrupt/unreadable files are preserved with a recovery
message rather than overwritten. Search reaches the same control from both entry
points. Reset, undo, restart and a failed write are verified in a temporary HOME.
No new surface, service subscription or periodic task is needed.

## C2 — Wallpaper and appearance with meaningful choices

**C2a: finish controls for what already exists.** Put circle/fade/wipe selection
in the existing wallpaper picker, remember it through Settings, add favourites
and a previous-wallpaper restore action. Keep cached thumbnails and on-open scans.
Settings may link to the picker rather than duplicate it. Validate picture paths,
show unavailable favourites and keep the current wallpaper if loading fails.

Settings owns the transition preference; the picker owns favourites/folder
catalogue and selected-picture intent; the wallpaper process owns rendering.
Keep the existing current-wallpaper file contract compatible at this stage.

**C2b: saved looks and accessibility.** Save named combinations of existing
mode/skin/accent/palette choices. Add a validated custom accent and reduced motion
only after checking the pinned runtime's colour/font/animation contracts. Define
which palette roles remain derived and test foreground contrast. Reduced motion
must preserve panel reveal/focus and wallpaper final states.

**C2c: bounded visual tuning.** Offer a small set of text/density and glass
strength choices, plus supported app-theme targets. Update shared controls and
all layout/height calculations together. `geometry.plm` stays constant-only;
selected roles belong in a separate shared style layer reading Settings (or the
standalone scene's mirrored theme facts). Avoid arbitrary per-control padding,
corner or font values. Missing fonts fall back; icon glyph fonts stay separate.
Per-output wallpaper follows once output identity and lock-screen fallback are
specified. Rotation and extra transitions follow later; online/video sources are
not prerequisites.

**Acceptance:** choices survive restart and reach desktop, widgets, lock and
capture through existing contracts. Missing files/fonts leave a usable result.
Dark/light and multi-output checks cover changed views. Motion-off ends in the
same layout; disabled effects do not keep repainting. Preview uses the existing
window/picker, not a continuously rendered duplicate desktop.

## C3 — A configurable frame and dock

Deliver independently:

1. Add visibility and ordered placement for supported modules within their
   current islands. Start with optional weather, tray, workspace/app indicators
   and update status. Protect a route to Settings/session and the centre's
   activity priorities. Do not let a hidden indicator disable its data owner.
2. Let users reorder existing dock pins, choose bounded icon sizes and hide/show
   delays, with pointer and keyboard access. Keep pinned IDs distinct from the
   running-app list. Persist order only after an edit completes.
3. Offer explicit output policies (all/focused/named where supported), with a
   missing-output fallback. Save names, never runtime screen indexes.
4. Consider alternate bar/dock edges only as a separate geometry project:
   frame silhouette, struts, morph origin, content anchor, outside hit regions
   and keyboard surface routing must move together. It is not a simple toggle.

Keep module descriptions pure data. Topbar still renders one frame per output,
Panels still arbitrates panels, and existing System/Weather owners stay shared.
Do not add one surface or watcher per module. Hide zones along with their drawing.
Small screens need a deterministic overflow policy, not overlapping buttons.

**Acceptance:** panel glass/content still align for every supported choice;
opening a panel still forces an auto-hidden dock up; optional module changes do
not break the pill or outside-close. Check output removal, long tray rows and
keyboard access to reordered pins. Measure the affected frame, not unrelated apps.

## C4 — Personal desktops and widget options

**C4a: save your desktop.** Add save, rename, duplicate, delete and load beside
existing factory presets in the widget bar. Store bounded named layouts in a
versioned `~/.config/beskar/widget-layouts.json`, written only by Widgets. Snapshot
card IDs/kinds/sizes/positions, output names and layout options; do not copy notes,
to-dos, timer deadlines or weather caches. Capture the prior layout for undo before
loading. Keep disconnected-output records and clamp/reflow onto smaller work areas
without overwriting the saved original. A layout restore never cancels a timer.

**C4b: configure a card.** Extend `widgets_data.luau` with explicit supported
options. Reuse the existing widget-bar surface for the selected card's editor.
Start with position lock and clock date/seconds/format overrides (default inherit).
Weather's location remains Weather-owned until independent locations are designed.
Store per-card options with Widgets and use explicit schema migration.

**C4c: stacks.** Group compatible-size cards in one place, manual paging first.
Keep one active face interactive; inactive members retain configuration without
starting redundant feeds. Add optional rotation later, paused during editing,
hover and hidden states. Preserve undo/unstack and the current max-16 card bound.
Profile compiled rules/zones and actual repaint cost before expanding catalogue
or bounds: hidden drawing does not eliminate model expansion cost.

World clocks remain a separate feature slice (milestone 3C). Useful new widget
kinds follow these ownership rules; they do not require a custom-widget marketplace.

**Acceptance:** saved layout and per-card choices recover on restart; applying
one has undo; missing outputs/kinds do not erase data; Personal/Activities content
is unchanged. Stacks do not multiply owner subscriptions or continue hidden ticks.

## C5 — Portable setups and owned shortcuts

After the preceding schemas stabilize, add selective export/import of appearance,
frame/dock preferences and widget layouts. Show a change preview, validate version,
types, limits and paths, and offer undo. Use a data-only format: no commands,
plugins, credentials, personal content, notification/clipboard history, active
timers or machine display modes. Report unsupported keys and missing resources.

Settings coordinates explicit snapshots and applies through each owner's API;
Widgets and Topbar keep writing their own files. Cross-owner apply is staged and
acknowledged, with a recovery journal and previous snapshots before mutation.
Do not imply several JSON writes form an atomic transaction. Start with a single
section import before offering a combined profile; cache/palette generation is
derived and may finish afterward with status.

For shortcuts, first resolve included niri files reliably (the current loader
reads only two named files). Then edit a Beskar-owned bindings include using
`actions.luau` metadata, explicit conflicts, backup and niri validation before
reload. A general KDL rewrite or arbitrary command editor is separate work.

**Acceptance:** invalid imports change nothing; a partial apply has recovery;
export/import round trips preserve supported choices. Shortcut conflicts are shown
before save, invalid KDL leaves the running configuration intact, and an existing
user binding is never silently overwritten.

## C6 — Quiet modes and display recovery

These share infrastructure with the feature roadmap rather than becoming duplicate
implementations:

- Continue milestone 4: focus, presentation and opt-in game quiet mode. Activities
  owns temporary policy, Notifications owns delivery/manual DND, Settings owns
  saved policy choices. Derive effective quiet state from manual choice plus active
  policies, so ending a mode preserves intervening manual changes. Start explicit;
  add event-driven detection only when there is a concrete capability.
- Add per-app quiet delivery and quiet hours using stable app identities and the
  actual notification-service contract. Unsupported inline reply stays unavailable.
- Before broadening display controls, add Keep/Revert with an independent recovery
  path that survives Settings closing/crashing. Test recovery in nested niri.
  Display modes stay out of portable appearance profiles.

## Ownership and cost rules for every slice

- Settings is the user-preference owner; Topbar owns frame/pins, Widgets owns
  layout/card configuration, Wallpaper renders, Notifications owns delivery,
  Activities owns timer/temporary policy, Personal owns user content. No second
  writer or generic replacement configuration daemon.
- Rendering libraries have no surfaces, models, feeds, timers or Luau plugins.
  Use [UI standards](UI_STANDARDS.md) and [shared controls](COMPONENT_LIBRARY.md).
- Preference changes use typed events within desktop and existing snapshot/say
  bridges to other processes. Batch/coalesce changes; do not broadcast every value
  every frame or persist slider movement every frame.
- Keep wallpaper/widgets/lock/capture process boundaries. No permanent preview
  surfaces, per-widget wallpaper samplers, directory scans while the picker is
  closed, or global polling added merely to support settings.
- Record compile properties/instructions/rules/zones and back-to-back idle CPU,
  memory and repaint/frame timings when a rendering slice changes them. Compare
  the same fixture/output/load. Counts identify cost; they do not prove frame time.
  No promise of zero overhead without measurement.

## Verification and implementation boundary

The original audit was documentation-only; the delivered increments above now have
focused checks at the relevant validation/store boundary, affected compiles, the UI guard for UI changes, and
smoke only for affected panels. Use temporary preferences for reset/import, nested
niri for lock/display risk, and native keyboard events for new interactions.

The first implementation delivered C1's Appearance slice, C2a, C3's existing-island
controls and C4a/b, then the bounded C5/C6 sections recorded above. C2b/c, stacks, portable combined profiles and edge changes
are separate reviewable increments, not part of the first implementation.
