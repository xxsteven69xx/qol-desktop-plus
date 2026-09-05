# QoL Desktop+

Omarchy’s feel. A few familiar desktop comforts.

Keep Omarchy’s themes, keyboard workflow, and tiling. Add familiar desktop controls where you want them, through the bar you already use.

https://github.com/user-attachments/assets/14b43b29-6801-45b5-969e-3e4bec6f70c9

- **Float selected workspaces** — keep the rest tiled.
- **Minimize when useful** — taskbar and keyboard controls, plus support for app minimize buttons.
- **Switch visually** — optional Alt+Tab cards over your wallpaper.
- **Make the bar yours** — choose previews, app grouping, and icon order.

![The same apps in tiled mode on the left and floating mode on the right](docs/media/tiled-floating.webp)

*Keep your tiled workspaces. Float the ones where you want a little more freedom.*

## Install

```sh
omarchy plugin add https://github.com/xxsteven69xx/qol-desktop-plus --enable
```

The taskbar, hotkeys, and settings menu set themselves up. Shortcuts appear in **Super+K**.

| Action | Shortcut |
| --- | --- |
| Switch apps | Alt+Tab |
| Minimize | Super+M |
| Toggle workspace layout | Super+Ctrl+Alt+L |
| Activate taskbar slot | Super+Ctrl+Alt+1–0 |
| Settings | Super+Ctrl+Alt+S |

Settings also open from the taskbar’s right-click menu or **Super+Space → Setup → Taskbar**.

Requires Omarchy Quattro and Hyprland 0.56.2, with Python 3, g++, pkg-config, and matching Hyprland headers. The native companion builds locally on first use. Hyprland API changes may require a plugin update.

## Remove

```sh
omarchy plugin remove legion.taskbar
```

Removal restores minimized windows and removes the plugin’s shortcuts and menu entry. Personal settings remain saved.

[Controls and behavior](USAGE.md) · [Configuration](CONFIGURATION.md) · [Testing](TESTING.md) · [MIT license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
