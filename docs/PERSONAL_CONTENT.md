# Personal content

`Personal` is a headless scene in `desktop.plm`. It is the sole writer of the files-service `content.json`, normally `$XDG_DATA_HOME/pleamar/personal/content.json` or `~/.local/share/pleamar/personal/content.json`. The runtime writes a sibling temporary file, renames it into place and uses private directory/file permissions.

Schema version 1 stores a monotonic `revision`, monotonic `next_id`, `notes`, `tasks` and optional `featured_id`. Notes contain `{id, text, modified}`; tasks add `done`. IDs are global to this store and are never reused after Undo. `featured_id` names the most recently created/edited note shown in Today and Notes widgets. `modified` is local date/time to the second. Array order defines note order and to-do order; moving a task operates among peers of the same completion state.

The store accepts up to 16 notes (4096 bytes each), 48 single-line to-dos (240 bytes each), and 20 in-memory Undo snapshots. Consecutive edits to the same note coalesce. Changes are published immediately inside `desktop`, saved after 300 ms and flushed when the editor closes. A failed save leaves edits in memory, reports the problem and retries after two seconds. Invalid/unreadable stored content disables mutation and leaves the file untouched. Undo history does not survive owner restart. A process killed during the debounce interval can lose the latest unsaved edits.

Within `desktop`, consumers declare `uses scene "personal.plm" as Personal`, read `Personal.snapshot` and the public count/status/preview fields, and send typed events: `add_note`, `edit_note({id,text})`, `remove_note(id)`, `add_task({text})`, `toggle_task(id)`, `remove_task(id)`, `move_task({id,delta})`, `undo`, `flush`. Content state stays out of `System`, `Settings` and `Panels`. Editor selection/draft/filter state belongs to Infopanels; widget placement belongs to Widgets.

Widgets run in a separate process. Its read-only client uses this bounded protocol:

1. After startup, Widgets sends `say personal "emit resync -1"`. Every 15 seconds it requests again with its last loaded revision, recovering whichever process starts first.
2. Personal emits `say widgets "emit personal_changed REV"` after a successful atomic save, and on a resync whose revision differs. Only a number crosses the socket; content is never interpolated into a command.
3. Widgets reads the owner's snapshot with `cat` and a single path argument, using its inherited `XDG_DATA_HOME`/`HOME`. It validates schema/limits, ignores older reads and renders the featured note plus the first four active tasks. One read can be in flight, with further notifications coalesced into one follow-up read. Both processes must share the normal session data-home environment.
4. Widget checkboxes send `say personal "emit toggle_task ID"`. Clicking a personal card sends `say infopanels "emit pe_open CODE"`, where `CODE = 1000 + 100 * output_ordinal + MODE` (0 notes, 1 to-dos). Today keeps its current panel monitor; widget clicks carry the clicked card’s monitor. `output_ordinal` is the zero-based position of its output name in the sorted connected-output list; the frame resolves it through its own screen mapping. Per-process screen indices are never assumed to agree. The editor asks Topbar to choose the monitor and open panel 25 through Panels.

The editor and widgets never write another scene's facts/texts. Widgets never writes the personal snapshot, and removing a card never sends a content removal event.

Validation: `lua tests/personal.lua`, combined `--check shell/desktop.plm`, standalone `--check shell/widgets.plm`, panel smoke, and a temporary-home nested niri session for persistence, widget restarts, checkboxes, Undo and screenshots. The nested fixture omits the polkit/notification agents and app theme changes so it cannot acquire live session services.
