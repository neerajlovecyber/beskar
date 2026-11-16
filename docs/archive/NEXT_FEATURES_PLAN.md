# Next features and unification

Planning snapshot: 2026-11-13; customization audit: 2026-11-14. Slice completion is recorded below; later milestones remain proposals.

Current customization sequence: [Customization plan](CUSTOMIZATION_PLAN.md), with the initial C1–C6 increments delivered: safe Appearance restore, wallpaper controls, frame/dock options, saved desktops/card options, appearance sharing, owned shortcuts and quiet/display recovery. Later increments remain listed there.

The next work should make Beskar more useful through search, persistent desktop tools and consistent shared state. Each milestone pairs a visible feature with the minimum unification that feature needs. The existing frame, island morphs and owner-scene model remain the foundation.

## Updated references

All existing reference shell checkouts were clean before updating and were updated with `git pull --ff-only`. None of their installers or desktop code was run. The pleamar runtime checkout remains pinned separately.

| Reference | Before → inspected revision | Useful evidence |
| --- | --- | --- |
| iNiR (`references/inir`) | `ae00074` → `edca6cc` | 3.1 changelog; `services/GlobalActions.qml`, `Weather.qml`, `DesktopWidgetStacks.qml`, `GameMode.qml`; `modules/shared/background/widgets/DesktopWidgetRegistry.qml` |
| iNiR (older duplicate in `cloned_repos/inir`) | `8a13badf` → `edca6cc9` | Same upstream; use `references/inir` for future comparison |
| Vitreus (`references/vitreus`) | `ec8f244` → `964a6e1` | `logic/notes.luau`, `logic/focus.luau`, `desktopclock/widget_place.luau`, `pages/SETTINGS-STYLE.md` |
| Minflair (`cloned_repos/minflair`) | `09fb1c5` → `1e42b04` | 2.3 launcher commands and quick settings under `config/quickshell/Modules/` |
| Yami (`cloned_repos/yami`) | `3a84046` → `dd8414f` | 3.0 search in `shell/src/launcher.rs`; capture tools in `shell/src/shot.rs`; documented display rollback and game mode |
| Marea (`cloned_repos/marea-plm`) | `d0cad02` → `d0cad02` (already current) | Apps/files finder in `scene/state/finder.plm` and `scene/draw/finder.plm`; focus and notification actions |

Adapt interaction and ownership ideas into Beskar's `.plm`/Luau design. The references use different runtimes, permissions and compositor extensions; their code and performance claims are not drop-in guarantees for Beskar.

## What already exists

Avoid proposing existing functionality again:

- Spotlight already has apps, a calculator, web prefixes, shell commands, shared timer commands, window search, Settings page results, files/folders, persistent ranking and a shared action catalogue (`shell/dockpanels.luau`, `actions.luau`). Individual setting results are the next customization improvement.
- Clipboard already supports pinned text and image thumbnails. Improve the existing panel if needed; do not build another clipboard manager.
- Widgets already have 12 kinds including shared notes, to-dos and timer controls, per-monitor placement, sizes, grid, tidy, undo and factory presets. Saved desktops and per-card lock/clock options are implemented. Stacks and world clocks remain future work (`widgets_data.luau`, `widgets.luau`).
- `System` already owns scalar battery/network/audio/brightness and shared media. Typed scene events and the `Panels` owner are already implemented. Completing those refactors again would add no feature.
- Weather now has one owner, a last-good cache and a restart-resynced widget snapshot (3A/3B). Panel IDs and opening routes share `panels_data.luau`.
- Notifications already have grouping, history, banners and DND. New work should add policy and supported actions, rather than repeat those features.

## Recommended order

| Order | Milestone | Visible result | Unification earned by the feature |
| --- | --- | --- | --- |
| 1 | Spotlight as the desktop command centre | Find a window or setting; return to frequent apps; search files | Shared action catalogue and panel metadata; bounded search providers |
| 2 | Notes and to-dos across desktop and Today | Keep useful information on the desktop and edit it from a panel | One writer for personal content; richer widget metadata |
| 3 | One weather source, richer weather and world clocks | All weather views agree; useful forecast details and chosen cities | One forecast owner, shared location and explicit cross-process snapshots |
| 4 | Focus, timers and presentation/game quiet mode | Timers with pause/resume and quiet sessions with automatic restoration | One activity/policy owner across pill, widgets, notifications and quick controls |
| 5 | Capture that finishes the job | Annotate, redact and choose save/copy/open actions | Shared capture-result actions, kept in the on-demand process |
| 6 | Coherent customization and display controls | Wallpaper favourites, transition choice, consistent controls, safer screen changes | Reusable setting descriptions and capability-aware controls |

Milestones 1, 2, 3A/B and the timer part of 4A are implemented. Initial C1–C6 customization increments are recorded in [Customization plan](CUSTOMIZATION_PLAN.md). Explicit quiet modes are implemented; automatic detection, world clocks and capture improvements remain separate feature slices. Finish and check each slice before taking the next; the plans do not imply implementing the whole roadmap at once.

## 1. Spotlight as the desktop command centre

**1A — windows, settings and recent apps.** Keep the existing bottom search field and island reveal. Add window-title/app matches that focus the selected window, settings matches that open the right tab, and useful recent/frequent app ranking. Preserve calculator and web-prefix behaviour. Use prefixes for explicit modes where mixed results become ambiguous.

**1A status (2026-11-13):** implemented window and Settings results (`@` / `?`), desktop-file keyword matching and bounded recent/frequent app ranking saved by the dock panel scene. `actions.luau` supplies commands and Settings metadata; `panels_data.luau` supplies the owner/frame routes. `spotlight_search.luau` is the pure matching/history interface. File search remains 1B.

**1B — files and folders.** Add an explicit file mode backed by bounded asynchronous `fd` queries. Start under user-selected folders or the home directory, respect exclusions, debounce typing, and discard results belonging to an older query. Cap results and execution time; never recursively scan the home directory on every keypress. Open through `xdg-open`; show the parent path to distinguish identical names.

**1B status (2026-11-13):** implemented `/` file/folder mode in `spotlight_files.luau`, with a 300 ms debounce, one in-flight query, a two-second timeout, 24-result/eight-level limits, optional search roots, parent-folder labels and `xdg-open`. Stale replies are discarded across queries, mode changes and reopening. Tests: `lua tests/spotlight.lua` and `python3 tests/spotlight-files-backend.py`.

**Unification.** Introduce a static `shell/actions.luau` catalogue with stable keys, labels, keywords and owner routes. Spotlight and the shortcuts view read it; owners still execute their own typed events. This is a catalogue, not a new owner of every scene's mutable state. Introduce `shell/panels_data.luau` for panel IDs, names, scene ownership, islands, widths and input behaviour, deriving Luau lookup maps from it. Keep `.plm` event/surface declarations explicit and validate their agreement; do not add a code generator just to eliminate those declarations. Continue accepting existing CLI aliases and panel IDs.

**Seam.** Search providers return bounded result records with a stable key, label, detail, kind, score and action. Matching/ranking can be exercised without launching programs. Application rows and icon conversion remain local to their scenes; a Lua table is not live shared state across scene threads.

**Done when:** window/settings/app results execute correctly on the intended monitor; repeated opens retain useful ranking; query changes cannot bring old results back; missing files and closed windows have a useful response; all existing Spotlight modes and keyboard navigation still work. Add file mode only after 1A ships.

## 2. Notes and to-dos across desktop and Today

**2A — persistent notes (implemented).** Add a note widget and a small Today section that open the same editor. Support create, edit, remove and Undo. A note has a stable ID, text and modification time, independent of a widget's placement record.

**2B — to-dos (implemented).** Add a checklist widget and Today list with add, complete, reorder, undo removal and a clear completed view. Defer recurrence, calendar sync and rich text.

**Unification.** A headless `Personal` scene owns content, atomic/debounced storage and mutations. Placement stays owned by the widgets process. Use typed events within `desktop`, and a documented snapshot/request protocol for widgets in their separate process, including a full resync after restart. Do not let the editor, Today and widgets all write the same JSON file.

Extend `widgets_data.luau` with category, supported sizes and option metadata so the picker and settings agree. Keep PLM faces explicit: this is a built-in widget catalogue, not a plugin marketplace.

**Done when:** edit from either view updates the other; restarting the shell preserves content; removing a widget does not delete its notes; undo restores the right item; rapid edits cannot corrupt the saved file. Validate with a throwaway configuration and nested session.

Implementation: `Personal` owns `content.json`, stable IDs, modification times, 300 ms atomic/debounced writes and bounded Undo. Today and the shared editor use typed events and read the owner's snapshot. Notes/To-dos widget kinds 10/11 keep content independent of placement. Widget checkboxes and Today checkboxes mutate the same owner. The widget picker now uses two rows to fit all eleven kinds. Category, supported sizes and options are declared once in `widgets_data.luau`.

The cross-process protocol is documented in `docs/PERSONAL_CONTENT.md`. Tests cover content invariants, persistence errors, rapid edits and restart resync. Undo is in memory for the current owner session; recurring tasks, rich text and calendar sync remain deferred.

## 3. One weather source, richer weather and world clocks

**3A — forecast owner. Implemented.** `Weather` in `desktop` owns location, forecast acquisition, refresh/loading/error state and a last-good disk cache. Topbar and Today read its texts; the weather panel formats its bounded snapshot. Widgets read an atomic versioned snapshot with restart resync and no forecast poller. Requests coalesce, time out after eight seconds and reject previous-location replies. Failed refreshes retain visibly labelled cached data; fresh matching cache avoids a restart fetch. See `docs/WEATHER.md`.

**3B — useful weather details. Implemented.** The forecast panel shows hourly precipitation chance, today's rain chance, explicit °C/km/h labels and last update time. One location choice updates all four weather views. Clock preference reformats forecast hours and sunrise/sunset without fetching. Air quality remains optional later because it needs a separate endpoint.

**3C — world clocks. Next; not started.** Add chosen cities/time zones in Today and a widget. Use system time-zone identifiers and DST-aware formatting, not fixed UTC offsets. Weather location and a world-clock city are different preferences. Share pure clock formatting where useful, without turning `System` into an unrelated-data catch-all.

**Done when:** all four weather views agree after a location change; a refresh causes one forecast request; widget restart restores data; offline display is useful; city clocks remain correct across DST and the 12/24-hour preference.

## 4. Focus, timers and quiet modes

**4A — shared timer and explicit quiet policies (implemented).** One Activities owner now provides presets/custom duration, pause/resume/cancel, a centre-pill completion card, restart recovery and timer widget kind 12. Spotlight and all controls operate on the same saved epoch deadline. Sleep counts toward running timers; paused timers remain paused. The owner saves transitions only, and widget display ticks/resync run only while its card is visible. See `docs/TIMERS.md` for clock-adjustment and delivery limits. Focus, Presentation and explicit Game quiet policies now preserve manual DND; quiet hours and per-app delivery live in Notifications/Settings. Automatic detection and multiple timers remain future work.

**4B — presentation/game quiet mode.** Add manual quiet mode and a Control Center power-profile tile first. Then offer opt-in game detection from explicit app rules and the focused window. Suppress banners while retaining history, reduce optional widget polling/motion, and show the active mode in the pill. Avoid compositor patches, automatic VRR changes or performance-profile changes as defaults.

**Unification.** An `Activities` owner holds timer/focus state; the frame keeps drawing and arbitrating the pill. A policy computes effective DND from the user's preference plus temporary focus/presentation/game reasons. Ending one reason must not clear another, and a user's change during a session must survive the session ending. Restore power settings only when the mode actually changed them and nobody has changed them since. Reuse the existing island priority rules.

**Done when:** every entry point controls the same timer; completion happens once; suspend/resume follows the stated behaviour; restarting recovers the deadline; ending focus preserves manual DND; missing power-profile tools hide/disable the control with an explanation.

## 5. Capture that finishes the job

**5A — result actions.** After capture, offer copy, save, open and show in folder using the existing pill/result path. Remember the output preference; preserve cancellation and recording behaviour.

**5B — annotation.** Add rectangle, arrow, pen and a solid redaction tool, with undo and export from the frozen image. The preview and saved output must use the same coordinate transform on scaled and second monitors.

**5C — optional OCR.** Offer copy text when a supported OCR command exists. Keep it optional and out of the always-on desktop process. Defer QR reading and a general image editor.

**Done when:** saved pixels match the preview at mixed scales and monitor offsets; undo restores an annotation; redaction exports as opaque pixels; cancelling leaves no unintended output; the capture process still exits when unused.

## 6. Coherent customization and display controls

The detailed sequence, current iNiR comparison, ownership and acceptance criteria are now in [Customization plan](CUSTOMIZATION_PLAN.md). Its C1–C6 slices expand this milestone; the points below retain the original feature scope.

Ship independent slices:

- Wallpaper favourites and a transition picker for the effects already supported. Add fit/preview behaviour and a restore action before online wallpaper sources or video wallpaper.
- A consistent setting-control vocabulary (switch for on/off, segmented choice for mutually exclusive options, action button for a verb), empty/loading/error states, and per-page restore defaults. Adapt Vitreus's consistency; keep Beskar's own scale and density.
- A complete semantic palette, contrast checks and reduced-motion option. First reduce repeated call-site knowledge in shared controls; verify what the pinned exp.16 runtime supports before committing to a theme-record interface. Do not keep adding one colour argument per visual detail indefinitely.
- Display arrangement/scale/refresh with a reversible preview and a Keep/Revert countdown. A separate recovery path must survive Settings closing or crashing before offering risky modes. Probe niri capabilities; expose only supported controls.
- Notification actions and per-app quiet delivery, after verifying the actual pleamar notification contract. Inline reply is conditional on runtime support and should be marked unavailable until proven.

**Done when:** settings act on a supported capability, saved choices return after restart, defaults can be restored per group, themes stay readable, and an unconfirmed display change recovers automatically.

## Unification decisions

- Keep `Panels` as the panel-state owner, `Settings` as preference owner, `System` as system/media owner and the frame as glass/pill renderer. New features join these contracts; they do not introduce a second way to open panels or set another scene's facts.
- Unify repeated data acquisition and command descriptions where two or more consumers already exist. Keep view-specific rows, icons and interaction state local.
- Keep wallpaper, widgets, lock and capture in their current processes. Earlier measurements found extra repaint work when wallpaper/widgets were brought into `desktop`; the lock also needs crash isolation. A single process/surface is not the goal. Revisit only with a controlled before/after measurement and a demonstrated user benefit.
- New shared feeds should be headless scenes with narrow permissions. Do not require a plugin approval/install mechanism for built-in functionality.
- Optional backends are adapters at actual seams (file search, OCR, power profiles). Avoid a universal backend framework or a generic event bus over the typed events already available.

## Verification and limits

For each implemented slice: compile `desktop.plm` (individual imported scenes may fail alone on `System.*`), check any changed standalone scene, run the relevant panel smoke flows, and verify keyboard/focus/close behaviour on both monitors. Persistence uses a throwaway configuration; lock testing uses nested niri only. Add focused tests at the new search/store/policy interfaces, especially stale replies, write ownership and state restoration.

The runtime is pinned at exp.16; the desktop swapchain workaround and its limits are recorded in [Rendering notes](RENDERING_NOTES.md). Existing uncommitted work remains separate from this documentation audit. Planning does not restart the shell or change runtime settings.

Deferred: a widget/theme marketplace, AI chat, a replacement file manager, new compositor support, glyph/video wallpapers and calendar account sync. These add substantial dependencies or lifecycle requirements; none is required for the recommended first four milestones.
