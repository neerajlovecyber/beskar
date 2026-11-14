# Session menu and shortcuts

The shared Session menu grows out of the dock in the existing Dialogs session
surface (panel 11). It lists Lock, Sleep, Log Out, Restart and Shut Down.
There is no new process, surface, polling loop or authentication agent.

## Opening and keyboard behaviour

- `Super+Shift+Q`: Session menu, matching iNiR's session shortcut.
- `Super+X`: retained Beskar alias for the same menu.
- `Super+Alt+L`: direct lock, matching the existing Beskar/iNiR binding.
- Top-left gem menu → **Session…**, Control Center → power button, or
  Spotlight → **Session Menu** all open this chooser.
- Left/Right, Up/Down, Tab and Shift+Tab move between actions, wrapping at the ends.
- Enter, keypad Enter or Space activates on key release, preventing a held key
  from repeating into a confirmation. Pointer hover/click selects the same actions.
- Escape closes the chooser. From a confirmation, Escape or Cancel returns to
  the chooser and retains its selection. Outside click closes the whole panel.

Lock activates the existing locker. The other choices enter confirmation on
Cancel; arrows/Tab change the button and Enter activates it. Sleep waits for
explicit confirmation. Shutdown/restart/logout preserve the existing 60-second
automatic confirmation countdown, cancelled by going back or closing the panel.
Browsing the chooser starts no timer. Direct action routes from Settings and
Spotlight still open their specific confirmation; cancelling those closes them.

The old reopen-windows checkbox was removed: it did not implement window restore.

## Routes and ownership

`session_menu.luau` is the controller installed by `dialogs.luau` through the
existing `panelclient` lifecycle. Dialogs owns selection and confirmation state.
The five-record model is static. `Dialogs.prepare_menu` resets the chooser;
`Dialogs.set_kind` prepares a specific confirmation, accepting its existing
scalar or named `{k=...}` payload. Internal controller transitions call functions
directly: Lua-emitted local events do not redispatch into the same Lua handler.

`Topbar.open_session` resets the chooser and reuses the frame's panel-opening
function, including focused-monitor lookup. The gem's Session entry keeps the
clicked bar's monitor. Panels remains the open/close owner and the frame draws
the glass. `session.plm` is not a separate scene.

CLI: `./beskar power-menu`, `./beskar session-menu` and `./beskar session` open
the chooser. `./beskar session 0|1|2|3` retains specific confirmations for
shutdown/restart/logout/sleep. Unknown kinds are rejected. New installs include
the session and direct-lock shortcuts; existing installations retain their
custom niri configuration. This session's Beskar-owned live bind block was
updated, validated and reloaded, with `config.kdl.beskar-session-bak` as backup.

There is no single shortcut standard shared by all shells. Existing Beskar
Spotlight, clipboard, overview and app-switcher choices remain unchanged.
Compositor movement keys stay in niri rather than being redefined by the shell.
Settings → Shortcuts reads the user's actual niri bindings; action labels also
come from `actions.luau`.

## Reference decisions

- Minflair: `cloned_repos/minflair/config/quickshell/Modules/PowerMenu/PowerMenuContent.qml`
  uses an action row, Lock without confirmation, and a separate Cancel/Confirm
  view initially focused on Cancel. Its binding is Ctrl+Alt+X in
  `config/hypr/keybinds.lua`. Beskar adapts that interaction to its own panel.
- iNiR/iRiS: `references/inir/modules/shared/sessionScreen/SessionScreen.qml`
  and `SessionActionButton.qml` provide exclusive keyboard focus, arrow
  navigation, Enter/keypad Enter, Escape and monitor-aware presentation.
  `defaults/niri/config.d/70-binds.kdl` supplies Super+Shift+Q and Super+Alt+L.
  Beskar retains its compact island presentation instead of copying a full-screen
  wallpaper/blur overlay or adding unsupported hibernate/firmware actions.

## Verification

Run `lua tests/session-menu.lua` for lifecycle, selection, cancellation, legacy
routes, timer invalidation and command dispatch with captured commands and lock
requests. Run `lua tests/spotlight.lua` for action routing, and compile desktop.
Relevant smoke labels are `session menu`, `session dialog` and `control center`.
Native-key testing uses confirmation Cancel only; never confirm a real power
action or activate the live lock. The physical Super+Shift+Q shortcut was
confirmed by the user after configuration reload.

Verification in this session passed: 29 isolated controller cases, 90 Spotlight
cases, combined compilation, targeted menu/confirmation/Control Center/Spotlight/
Settings smoke, real arrow/Tab/Enter/keypad/Escape navigation, both monitor routes,
and the existing direct Restart confirmation route. No real session action was
executed during verification.
