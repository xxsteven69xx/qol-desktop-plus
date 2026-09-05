# Taskbar configuration

The plugin automatically creates `~/.config/omarchy/taskbar.json` on first start.
If `XDG_CONFIG_HOME` is set, it uses `$XDG_CONFIG_HOME/omarchy/taskbar.json`.
This file survives plugin updates. Changes normally apply within two seconds,
including keyboard remapping; no reinstall or compositor reload is needed.

[defaults.json](defaults.json) contains every supported option and its default.
[settings.schema.json](settings.schema.json) describes types, choices and ranges.
You may omit options; omitted values use the defaults. Use ordinary JSON (no
comments or trailing commas). Unknown fields and invalid values are rejected.
During an invalid edit the plugin retains the last working configuration, even
across helper restarts. It never overwrites a malformed file.

Validate your file:

```sh
python3 ~/.config/omarchy/plugins/legion.taskbar/taskbar.py config-check
```

Open the settings panel with **Super+Ctrl+Alt+S**, **Super+Space → Setup → Taskbar**,
or by right-clicking the empty area after the app icons and choosing
**Taskbar settings…** from the dropdown. App context menus also
include **Taskbar settings…**. Search spans all categories; Enter edits,
Left/Right changes choices, Ctrl+F searches, and Ctrl+S applies pending changes.

The panel and existing Group windows / Restore true fullscreen controls write
this same file. The panel only saves changed fields and rejects concurrent
changes to those same fields instead of silently overwriting them. First-time
migration preserves the old grouping, fullscreen, workspace modes and bar-width
preferences. Window addresses, minimized state and icon order stay in session
state, not in this human-editable configuration.

## Window behavior

| Setting | Values and behavior |
|---|---|
| `windows.otherWorkspace` | `bring` (default): move a running window here. `switch`: go to its workspace without moving it. |
| `windows.activeClick` | `minimize` (default), `maximize` (toggle maximized size), or `focus` (keep it visible). Applies when the window is already focused here. An inactive local window is focused first. |
| `windows.minimizedRestore` | `current` (default): restore hidden windows here. `original`: return to the saved workspace. |
| `windows.restoreFullscreen` | Restore true fullscreen instead of the default maximized state. |
| `windows.followDialogs` | Move/minimize/restore a window's transient family together and focus its deepest dialog. Default `true`. |
| `windows.restoreGeometry` | Reapply saved floating placement and size when restoring. Default `true`. |
| `windows.nativeMinimize` | Honor minimize requests from application title bars. Default `true`. Does not add title bars to applications that do not draw them. |

Mouse clicks, the full window picker and numbered shortcuts use the same window
behavior. Explicit **Bring here** / **Go to window** context actions keep their
literal meanings regardless of the default click behavior.

For the workspace-switching behavior discussed during development, set:

```json
{
  "windows": {
    "otherWorkspace": "switch",
    "activeClick": "minimize",
    "minimizedRestore": "current"
  }
}
```

This example can be the entire file; all other settings keep their defaults.

## Bar and icons

| Setting | Purpose |
|---|---|
| `bar.allWorkspaces` | List windows from all regular workspaces. Minimized windows remain available when false. |
| `bar.currentMonitorOnly` | Filter icons to the bar's monitor, using a minimized window's saved monitor. |
| `bar.settingsAreaWidth` | Empty area after the app icons for right-click settings access. Default 24. |
| `bar.maxWidth` | Space budget for app icons before the overflow picker appears. Default 260. |
| `bar.iconSize` | App image size. Default 17. |
| `bar.cellSize` | Width of each icon button. Default 30. |
| `bar.spacing` | Space between icon buttons. Default 2. |
| `bar.showLayoutButton` | Show the floating/tiling button before the app icons. Set false to hide it. |
| `bar.showGroupCounts` | Show the number of windows on grouped app icons. |
| `bar.showIndicators` | Show the marks beneath app icons. |
| `bar.minimizedOpacity` | Opacity of minimized app images. Default 0.48. |
| `bar.animationDurationMs` | Icon highlight transition duration; 0 disables it. Default 140. |
| `bar.excludedApps` | Array of exact Hyprland app classes to hide from the bar and its picker. Default `[]`. |

Sizes are Omarchy style units and follow its interface scaling. Colors, fonts,
corners and theme transitions continue to follow Omarchy. Bar position and the
widget's placement remain controlled by Omarchy's bar configuration.

## Grouping and interaction

| Setting | Purpose |
|---|---|
| `grouping.enabled` | Combine windows with the same app class into one icon. Default false. |
| `grouping.clickAction` | `picker` (default) opens the group's window list; `toggle` acts on its focused member or first member. Numbered shortcuts always use that member-selection rule. |
| `interaction.dragToReorder` | Allow rearranging app icons. Default true. |
| `interaction.dragThreshold` | Pointer movement needed to start a drag. Default 6. |
| `interaction.middleClick` | `none` (default), `minimize`, `close`, `maximize`, `goto`, or `restore`. Applies to app icons. |

Excluding an app hides its taskbar restore control. Super+Ctrl+M can still restore
all minimized windows. Empty numbered slots do nothing; the tenth slot uses 0.

## Previews and window picker

| Setting | Purpose |
|---|---|
| `preview.enabled` | Enable hover previews. |
| `preview.delayMs` | Hover delay before opening. Default 450. |
| `preview.hideDelayMs` | Delay after leaving the icon/card. Default 250. |
| `preview.width` / `preview.height` | Card width / window image height. Defaults 300 / 145. |
| `preview.live` | Continuously update visible window images; false takes a still capture. |
| `preview.showImage` | Include the window image. Set false for title-only previews. |
| `preview.showTitle` | Include the window title. |
| `preview.titleLines` | Maximum title lines. Default 2. |
| `picker.width` / `picker.maxHeight` | Full window picker's width / height limit. Defaults 370 / 420. |
| `picker.rowHeight` | Height of each window row. Default 54. |
| `picker.showWorkspace` | Include the workspace/action detail under each title. |

Previews contain only the selected image/title elements, without instruction
text or action buttons. Minimized windows may not provide capture content.

## Workspaces

`workspace.defaultFloating` defaults to false. Enable it to make unspecified
workspaces float. `workspace.modes` overrides individual workspaces by name;
true means floating, false means tiling:

```json
{"workspace":{"defaultFloating":false,"modes":{"1":true,"3":false,"chat":true}}}
```

Newly floated windows are capped at 75% of the monitor's available width and
height and centered, so a terminal visibly becomes a movable window instead of
retaining an almost-maximized tiled size. Smaller windows are not enlarged.

- `workspace.resizeOnFloat`: apply the size cap (default true).
- `workspace.floatWidthPercent` / `workspace.floatHeightPercent`: size caps,
  25–100 (defaults 75 / 75).
- `workspace.centerOnFloat`: center newly floated windows (default true).
- `workspace.showTooltip`: show the mode button’s next action on hover (default true).

These rules affect windows being converted by the plugin, not windows that were
already floating. Turn resizing/centering off to retain their tiled geometry.

The layout button and its shortcut update this mapping. New windows follow the
workspace's selected mode. Switching back to tiling retiles windows floated by
the plugin while preserving previously floating windows, such as dialogs.

## Keyboard

`keyboard.enabled` enables/disables automatic shortcut registration. Individual
shortcuts are strings; an empty string disables that binding:

- `keyboard.settings`: `SUPER + CTRL + ALT + S`
- `keyboard.minimize`: `SUPER + M`
- `keyboard.restoreAll`: `SUPER + CTRL + M`
- `keyboard.toggleLayout`: `SUPER + CTRL + ALT + L`
- `keyboard.slots`: ten shortcut strings, ordered from the first slot through the
  tenth. Defaults use `SUPER + CTRL + ALT + code:10` through `code:19`.

Modifiers are SUPER, CTRL (or CONTROL), ALT and SHIFT. The final token is an XKB
key name, such as `M`, `Return`, or `KP_1`, or a physical keycode such as `code:10`.
Physical number-row keys preserve placement across keyboard layouts.

Existing stock and user bindings take priority, except for the explicit stock
Alt+Tab replacement described below. Other conflicting plugin shortcuts are skipped. Changes update the
registered shortcuts and Super+K list automatically. This does not change
Omarchy's workspace or grouped-window shortcuts.

## Alt+Tab app selector

Hold Alt and press Tab to open a theme-style carousel with window previews and
only the selected window's title. Tab advances, Shift+Tab goes backward, and
releasing Alt selects. Escape cancels. Arrow keys, Enter and clicks also work.
Selecting a window focuses/restores it and never minimizes it.

| Setting | Purpose |
|---|---|
| `switcher.enabled` | Enable the visual selector (default true). False restores displaced stock Alt+Tab bindings. |
| `switcher.forwardShortcut` / `switcher.backwardShortcut` | Defaults `ALT + Tab` / `ALT + SHIFT + Tab`; empty strings disable individual bindings. |
| `switcher.replaceStockAltTab` | Replace only Omarchy's recognized stock Alt+Tab actions (default true). Custom bindings are preserved. False respects the stock bindings too. |
| `switcher.releaseAltToSelect` | Select on Alt release (default true). Set false when using shortcuts without Alt; use Enter or click to select. |
| `switcher.scope` | `all` workspaces (default), or `workspace`. |
| `switcher.includeMinimized` | Include minimized windows (default true). |
| `switcher.order` | `recent` focus order (default) or `taskbar` window order. |
| `switcher.otherWorkspace` | `switch` (default), `bring`, or `taskbar` to follow `windows.otherWorkspace`. Minimized windows follow `windows.minimizedRestore`. |
| `switcher.width` / `switcher.height` | Maximum expanded preview dimensions (defaults 768 / 475); also limited to fit the screen. |
| `switcher.adaptiveSize` | Fit the selected card to the window’s proportions (default true). Neighboring cards move inward for portrait windows. |
| `switcher.selectedCornerRadius` | Corner radius on the uncropped selected preview (default 0 for sharp corners). Background cards retain their angled edges. |
| `switcher.sliceWidth` / `switcher.spacing` | Minimum exposed portion of a background card / extra spacing (defaults 108 / 12). Cards keep their full proportions; `sliceWidth` no longer sets their width. |
| `switcher.backgroundScale` | Size of background previews relative to their fitted window size (default 0.9). |
| `switcher.backgroundReveal` | Fraction of each background card exposed outside its nearer neighbor (default 0.62). Remaining content overlaps behind the nearer card. |
| `switcher.skewOffset` | Angled card edges, matching the theme selector (default 28; 0 gives straight edges). |
| `switcher.neighbors` | Maximum side previews in each direction (default 3). |
| `switcher.animationDurationMs` | Carousel transition duration (default 220; 0 disables animation). |
| `switcher.showDesktop` | Show the current Omarchy wallpaper behind the cards (default true). False shows the windows underneath. This does not move or minimize windows. |
| `switcher.livePreview` | Continuously update the selected visible window (default true). |

The selector uses Omarchy's image-picker palette and hides classes listed in
`bar.excludedApps`. Minimized windows can show an app icon when capture is
unavailable. The keyboard master switch, `keyboard.enabled`, also disables its
shortcuts. Omarchy's Ctrl+Alt+Tab monitor and Super+Alt+Tab group shortcuts remain
available. Disabling/removing the plugin restores its displaced stock bindings.

## Refresh and recovery

`advanced.pollIntervalMs` controls the fallback refresh/config check interval
(default 2000, range 250–10000). Window events also refresh the bar immediately.
`advanced.recoveryIntervalMs` controls checks for plugin disable/removal
(default 1000, range 250–5000). Recovery restores hidden windows and unloads
plugin-owned shortcuts; it cannot be disabled through this file.
