# Validation

Tested on Omarchy Quattro, Hyprland 0.56.2, with matching development headers.
The plugin uses the Hyprland 0.56.2 native API; future incompatible API changes
can require an update. Its native companion has its own version number (1.3.0),
independent of the taskbar/settings release (1.4.0).

## Reproducible checks

```sh
omarchy plugin validate .
python3 -m unittest discover -s tests -v
```

These tests use temporary settings and menu files. They do not change the
running desktop. Python 3 and libxkbcommon are required (included with Omarchy).

## Desktop verification completed for 1.4.0

The following checks were exercised in disposable nested Hyprland sessions:

- A clean source install compiles/loads the companion and registers shortcuts.
- Native app minimize requests, taskbar clicks, numbered shortcuts, and restore
  actions work; floating windows retain their saved geometry.
- Running windows either move here or switch workspace according to settings;
  minimized windows follow the configured restoration behavior.
- Transient dialogs follow their parent window.
- Workspace tiling/floating toggles visibly resize real terminal windows.
- Alt+Tab works forward/backward, on quick taps, and on Alt release. Disabling it
  restores stock Alt+Tab bindings; unrelated/custom shortcuts are preserved.
- Card transitions have intermediate animation frames across snapshot refreshes.
  Front and background cards preserve tall and wide windows' aspect ratios.
- Settings open through their native shortcut, the taskbar context menu, and
  the Super+Space menu action. Numeric/enum/workspace editors and Ctrl+S work.
- Invalid values do not overwrite saved configuration; changes made externally
  to the same settings are detected before saving.
- Disabling/removing the plugin restores minimized windows, unregisters native
  shortcuts, and removes only its marked user-menu entry.

The installed desktop was checked for valid configuration, duplicate shortcuts,
and taskbar QML errors after each release candidate.

For future changes, repeat the relevant desktop checks in a separate compositor
session. Do not inject test keys or remove outputs on the user's main session.
