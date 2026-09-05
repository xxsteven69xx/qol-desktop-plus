# Windows for Omarchy

A window list integrated into the existing Omarchy Quickshell bar. The host bar,
fonts, palette, rounding and theme transitions remain Omarchy's. No second panel.

## Controls

- Click the active app's icon to minimize its window.
- Click a minimized icon to restore it to the current workspace.
- By default, click a window on another workspace to bring it here; optionally switch to its workspace instead. Click an inactive local window to focus it.
- An app's own minimize button also works (Wayland and X11).
- Right-click an icon for **Bring here**, **Go to window**, minimize, maximize, fullscreen or close.
- Hover for a live preview when the compositor can provide one. Minimized windows may show a placeholder.
- Drag icons to rearrange them; order survives shell reloads for this session.
- The **…** overflow button opens the full window picker when the bar fills up.
- Right-click the layout icon for **Group windows by app** and **Restore true fullscreen**.
- Grouping is optional. A grouped icon shows a count and opens a picker for that app's windows.
- Preview cards contain only the window image and title. Workspace details remain in the full window picker.
- Click the layout icon, or press **Super+Ctrl+Alt+L**, to toggle this workspace's tiling/floating mode.
- **Super+T** still toggles the individual window's floating state.
- **Super+left drag** moves a window; **Super+right drag** resizes it.
- **Alt+Tab** opens a theme-style window carousel. Keep Alt held, use Tab / Shift+Tab to cycle, then release Alt to select. Escape cancels.
- **Super+Ctrl+Alt+S** opens taskbar settings (also listed in Super+K).
- Right-click the empty area after the app icons and choose **Taskbar settings…** from the dropdown. App-icon context menus include the same entry. You can also use **Super+Space → Setup → Taskbar**.
- **Super+M** minimizes the focused window.
- **Super+Ctrl+Alt+1–0** activates taskbar slots 1–10 in icon order, including overflow (0 means 10). Active windows minimize; inactive windows focus or come to this workspace. Dragging icons changes this order. Empty slots do nothing.
- With app grouping enabled, a numbered shortcut toggles the group’s focused window, or its first window if none is focused.
- **Super+Ctrl+M** restores all minimized windows.

Windows from every regular workspace and all minimized windows appear by default.
The default click behavior brings windows here. Set `windows.otherWorkspace` to
`"switch"` to follow running windows instead; minimized windows still restore here
unless `windows.minimizedRestore` is changed.
Windows retain floating geometry and maximized state when restored. Fullscreen
windows restore maximized by default so the taskbar stays reachable. Enable
**Restore true fullscreen** if you prefer their original fullscreen state.
The bar on each monitor targets that monitor's visible workspace, even when
keyboard focus is elsewhere. Transient dialogs follow their parent when moved,
minimized or restored, and the deepest dialog receives focus.
Floating mode is remembered per workspace; new windows follow that mode.
Switching back to tiling retiles the windows floated by this plugin while keeping
windows which were already floating (such as dialogs).

## Theme integration

Imports `qs.Commons.Color` and `Style` directly from Omarchy. The bar's foreground,
Omarchy accent, font and spacing update with the regular theme selector. No
Plasma bridge or extra theme hook. App icons come from the installed icon theme.

## Settings

The themed settings panel has sharp corners, search, keyboard navigation, and
editors for every setting. Enter edits the selected row; Left/Right changes
choices; Ctrl+F searches; Ctrl+S applies. Changes stay in a draft until applied.
Invalid values and conflicting external edits are reported without overwriting
the file. Lists use one item per line; workspace modes use `1 = floating` or
`3 = tiled`. Individual settings can be returned to their defaults.

All taskbar settings live in `~/.config/omarchy/taskbar.json`, created automatically.
See [Configuration](CONFIGURATION.md) for every supported behavior and setting,
[defaults.json](defaults.json) for a complete example, and
[settings.schema.json](settings.schema.json) for validation metadata. Changes apply
live; the existing taskbar defaults are preserved. Omarchy's `shell.json` controls
only where the widget is placed.

Install and enable through Omarchy using the published repository URL:

```sh
omarchy plugin add https://github.com/xxsteven69xx/omarchy-taskbar --enable
```

The widget appears in the left bar section. On its first start it builds and loads
its Hyprland companion automatically; allow a few seconds for that first build.
The shortcuts register automatically and appear in **Super+K**. No configuration
include, setup script, additional panel or separate background service setup is
needed. The plugin registers a small marked entry in the user’s Omarchy menu
extension automatically; it is removed when the plugin is disabled or removed.
The visual selector replaces Omarchy’s stock Alt+Tab actions while
enabled; disabling it restores them. Other stock shortcuts remain available.
Custom conflicting combinations are skipped instead of replaced.

Numbered shortcuts target the monitor with keyboard focus and follow that bar's
workspace filter, grouping and current order. Reloading Hyprland registers a
fresh set of shortcuts without duplicates. Disabling/removing the plugin removes
its shortcuts and restores hidden windows automatically. It also removes its own
entry from the Omarchy menu, preserving other entries and comments.

For local development, copy the repository contents into
`~/.config/omarchy/plugins/legion.taskbar/`, then enable it with
`omarchy plugin enable legion.taskbar --section left --after omarchy.workspaces`.
After updating QML, run `omarchy restart shell` if cached code remains.
The plugin handles its own icon gestures without modifying the host bar.

## How minimizing works

Hyprland has no normal minimized-window state. The helper remembers each
window's workspace, size, position, pin and fullscreen state, then moves it to
`special:omarchy-minimized`. The bar keeps a button for restoring that window.
State is keyed by compositor instance, window address and PID and survives shell
reloads. Closing a window removes its saved state.

`native/minimize.cpp` is a small Hyprland companion which registers runtime
shortcuts and forwards app minimize requests to the shell through IPC. It checks
for conflicts using both physical keys and symbols, and removes its bindings by
identity. It disconnects its listeners on unload and does not modify Hyprland
binaries or the user's configuration files.

Supported environment: Omarchy Quattro with the Hyprland 0.56.2 API, Python 3,
g++, pkg-config and matching Hyprland headers. Standard Omarchy installations
include the development toolchain. No precompiled library is distributed; it
builds in `~/.local/state/omarchy/taskbar/native/` and checks the running
compositor's ABI before loading. Generated files stay outside the plugin checkout. After
an OS upgrade, the running compositor and installed headers must match. Compatible
updates rebuild automatically; Hyprland API changes can require a plugin update.

## Disable or recover

A small recovery process restores hidden windows automatically within about a
second after the widget is disabled or its plugin directory is removed. Shell
reloads preserve the minimized state. Settings are stored in
`~/.config/omarchy/taskbar.json`; per-window order is session state.

Use Omarchy's normal controls:

```sh
omarchy plugin disable legion.taskbar
omarchy plugin remove legion.taskbar
```

For manual recovery if state was lost:

```sh
python3 ~/.config/omarchy/plugins/legion.taskbar/taskbar.py restore-all
```

Upgrading from 1.1: any existing `dofile(...)` include of `bindings.lua` remains
harmless through a compatibility shim, and can be deleted. New installations
never add that line.


## Validation

Run `python3 -m unittest discover -s tests -v` for settings validation, safe writes,
and menu integration checks. See [TESTING.md](TESTING.md) for desktop checks and
supported versions.

## License

MIT. See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).

## Sharing

Keep `manifest.json` at the repository root with this README, the QML/Python/Lua
sources and `native/` sources. Do not ship compiled libraries, version stamps,
Python caches, local state or screenshots of personal windows. Run
`omarchy plugin validate .` before submitting the repository to the marketplace.
The native companion builds locally against each user's installed Hyprland.
