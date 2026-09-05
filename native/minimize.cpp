#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <format>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <dlfcn.h>
#include <algorithm>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/devices/IKeyboard.hpp>
#include <map>
#include <stdexcept>

// Owns runtime shortcuts and forwards protocol requests. Window placement stays in the shell plugin.
static std::map<void*, CHyprSignalListener> listeners;
static CHyprSignalListener onOpen, onClose, onReload;
static std::vector<SP<SKeybind>> shortcuts, displacedShortcuts;
static std::string helperCommand;
static SP<SHyprCtlCommand> parentsCommand, shortcutsCommand;
static std::filesystem::path shortcutsFile;
static HANDLE pluginHandle;

static std::string shellQuote(const std::string& text) {
    std::string out = "'";
    for (char c : text) out += c == '\'' ? "'\\''" : std::string(1, c);
    return out + "'";
}

static bool sameKey(xkb_keysym_t sym, xkb_keycode_t code, xkb_keysym_t wantedSym, xkb_keycode_t wantedCode) {
    if (code && wantedCode) return code == wantedCode;
    if (sym && wantedSym && xkb_keysym_to_lower(sym) == xkb_keysym_to_lower(wantedSym)) return true;
    // Compare symbolic and physical bindings against installed keyboard layouts.
    const auto physical = code ? code : wantedCode;
    const auto symbolic = code ? wantedSym : sym;
    if (!physical || !symbolic || !g_pInputManager) return false;
    for (const auto& keyboard : g_pInputManager->m_keyboards) {
        const auto keymap = keyboard->m_xkbKeymap;
        if (!keymap) continue;
        for (xkb_layout_index_t layout = 0; layout < xkb_keymap_num_layouts_for_key(keymap, physical); ++layout) {
            const xkb_keysym_t* symbols = nullptr;
            int count = xkb_keymap_key_get_syms_by_level(keymap, physical, layout, 0, &symbols);
            for (int i = 0; i < count; ++i)
                if (xkb_keysym_to_lower(symbols[i]) == xkb_keysym_to_lower(symbolic)) return true;
        }
    }
    return false;
}

static void removeShortcuts(bool restoreStock = true) {
    if (!g_pKeybindManager) { shortcuts.clear(); return; }
    // Remove by identity: never unbind another owner's matching key combination.
    for (const auto& bind : shortcuts) bind->enabled = false;
    std::erase_if(g_pKeybindManager->m_keybinds, [](const auto& bind) {
        return std::ranges::find(shortcuts, bind) != shortcuts.end();
    });
    shortcuts.clear();
    if (restoreStock) for (const auto& bind : displacedShortcuts)
        if (std::ranges::find(g_pKeybindManager->m_keybinds, bind) == g_pKeybindManager->m_keybinds.end())
            g_pKeybindManager->m_keybinds.push_back(bind);
    displacedShortcuts.clear();
}

static void installShortcuts() {
    removeShortcuts();
    if (helperCommand.empty()) return;
    auto add = [](uint32_t mods, const std::string& name, uint32_t code, const std::string& description, const std::string& action, bool overrideStock) {
        std::vector<SP<SKeybind>> stock;
        const auto sym = xkb_keysym_from_name(name.c_str(), XKB_KEYSYM_CASE_INSENSITIVE);
        for (const auto& bind : g_pKeybindManager->m_keybinds) {
            if ((!bind->submap.name.empty() && !bind->submapUniversal) || (!bind->ignoreMods && bind->modmask != mods)) continue;
            if (bind->catchAll) return;
            bool matches = sameKey(xkb_keysym_from_name(bind->key.c_str(), XKB_KEYSYM_CASE_INSENSITIVE), bind->keycode, sym, code);
            for (const auto& [otherSym, otherCode] : bind->sMkKeys)
                matches = matches || sameKey(otherSym, otherCode, sym, code);
            if (!matches) continue;
            const bool stockTab = overrideStock && (sym == XKB_KEY_Tab || code == 23) && (mods == 8 || mods == 9)
                && bind->handler == "__lua" && (bind->description == "Reveal active window on top"
                    || (mods == 8 && bind->description == "Focus on next window")
                    || (mods == 9 && bind->description == "Focus on previous window"));
            if (!stockTab) return;
            stock.push_back(bind);
        }
        for (const auto& bind : stock) {
            displacedShortcuts.push_back(bind);
            std::erase(g_pKeybindManager->m_keybinds, bind);
        }
        SKeybind bind;
        bind.modmask = mods;
        bind.key = code ? "" : name;
        bind.keycode = code;
        bind.handler = "exec";
        bind.arg = helperCommand + " " + action;
        bind.description = description;
        bind.hasDescription = true;
        shortcuts.push_back(g_pKeybindManager->addKeybind(bind));
    };
    std::ifstream input(shortcutsFile);
    std::string line;
    while (std::getline(input, line)) {
        std::istringstream row(line);
        std::string mods, name, code, description, action, overrideStock;
        if (!std::getline(row, mods, '\t') || !std::getline(row, name, '\t') || !std::getline(row, code, '\t')
            || !std::getline(row, description, '\t') || !std::getline(row, action, '\t') || !std::getline(row, overrideStock)) continue;
        try {
            if (code == "0" && xkb_keysym_from_name(name.c_str(), XKB_KEYSYM_CASE_INSENSITIVE) == XKB_KEY_NoSymbol) continue;
            add(std::stoul(mods), name, std::stoul(code), description, action, overrideStock == "1");
        } catch (const std::exception&) { continue; }
    }
}

static std::string parents() {
    std::string result = "{";
    bool first = true;
    const auto& windows = Desktop::windowState()->windows();
    for (const auto& child : windows) {
        for (const auto& parent : windows) {
            if (child == parent) continue;
            bool related = child->m_xdgSurface && parent->m_xdgSurface && child->m_xdgSurface->m_toplevel && parent->m_xdgSurface->m_toplevel
                && child->m_xdgSurface->m_toplevel->m_parent == parent->m_xdgSurface->m_toplevel;
            related = related || (child->m_xwaylandSurface && parent->m_xwaylandSurface && child->m_xwaylandSurface->m_parent == parent->m_xwaylandSurface);
            if (!related) continue;
            if (!first) result += ",";
            first = false;
            result += std::format("\"0x{:x}\":\"0x{:x}\"", reinterpret_cast<uintptr_t>(child.get()), reinterpret_cast<uintptr_t>(parent.get()));
            break;
        }
    }
    return result + "}";
}

static void attach(PHLWINDOW window) {
    if (listeners.contains(window.get())) return;
    PHLWINDOWREF weak = window;
    auto report = [weak]() {
        auto w = weak.lock();
        if (!w) return;
        std::optional<bool> requested;
        if (w->m_xdgSurface && w->m_xdgSurface->m_toplevel)
            requested = w->m_xdgSurface->m_toplevel->m_state.requestsMinimize;
        else if (w->m_xwaylandSurface) {
            requested = w->m_xwaylandSurface->m_state.requestsMinimize;
            w->m_xwaylandSurface->m_state.requestsMinimize.reset();
        }
        if (requested.has_value())
            g_pEventManager->postEvent({"omarchy_minimize", std::format("{:x},{}", reinterpret_cast<uintptr_t>(w.get()), *requested ? 1 : 0)});
    };
    if (window->m_xdgSurface && window->m_xdgSurface->m_toplevel)
        listeners.emplace(window.get(), window->m_xdgSurface->m_toplevel->m_events.stateChanged.listen(report));
    else if (window->m_xwaylandSurface)
        listeners.emplace(window.get(), window->m_xwaylandSurface->m_events.stateChanged.listen(report));
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Omarchy Windows: rebuild minimize bridge for this Hyprland version");
    pluginHandle = handle;
    Dl_info location{};
    if (!dladdr(reinterpret_cast<void*>(&attach), &location) || !location.dli_fname)
        throw std::runtime_error("Omarchy Windows: cannot locate plugin helper");
    shortcutsFile = std::filesystem::path(location.dli_fname).parent_path() / "shortcuts";
    std::ifstream helperFile(std::filesystem::path(location.dli_fname).parent_path() / "helper-path");
    const std::string helper((std::istreambuf_iterator<char>(helperFile)), std::istreambuf_iterator<char>());
    if (helper.empty() || !std::filesystem::is_regular_file(helper))
        throw std::runtime_error("Omarchy Windows: missing helper path");
    helperCommand = "python3 " + shellQuote(helper);
    onReload = Event::bus()->m_events.config.reloaded.listen([] { removeShortcuts(false); installShortcuts(); });
    installShortcuts();
    shortcutsCommand = HyprlandAPI::registerHyprCtlCommand(handle, {"taskbar-shortcuts-reload", true, [](eHyprCtlOutputFormat, std::string) { installShortcuts(); return "ok"; }});
    parentsCommand = HyprlandAPI::registerHyprCtlCommand(handle, {"taskbar-parents", true, [](eHyprCtlOutputFormat, std::string) { return parents(); }});
    onOpen = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { attach(w); });
    onClose = Event::bus()->m_events.window.close.listen([](PHLWINDOW w) { listeners.erase(w.get()); });
    for (const auto& w : Desktop::windowState()->windows()) attach(w);
    return {"omarchy-taskbar-minimize", "Forward native app minimize requests to the Omarchy bar", "legion", "1.3.0"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    onReload.reset();
    removeShortcuts();
    HyprlandAPI::unregisterHyprCtlCommand(pluginHandle, parentsCommand);
    parentsCommand.reset();
    HyprlandAPI::unregisterHyprCtlCommand(pluginHandle, shortcutsCommand);
    shortcutsCommand.reset();
    onOpen.reset();
    onClose.reset();
    listeners.clear();
}
