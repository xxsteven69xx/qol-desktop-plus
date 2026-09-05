#!/usr/bin/env python3
"""Hyprland window actions. State survives shell reloads, scoped to compositor."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import socket
import subprocess
import sys
import time
import settings as settings_store
import menu_integration

SPECIAL = 'special:omarchy-minimized'
SIGNATURE = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
BASE = Path(os.environ.get('OMARCHY_TASKBAR_STATE', str(Path.home() / '.local/state/omarchy/taskbar')))
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid())))
SESSION = RUNTIME / ('omarchy-taskbar-' + re.sub(r'[^a-zA-Z0-9_-]', '', SIGNATURE))


def ctl(command, argument=None, json_output=False):
    args = ['hyprctl'] + (['-j'] if json_output else []) + [command]
    if argument is not None:
        args.extend(argument if isinstance(argument, list) else [argument])
    result = subprocess.run(args, capture_output=True, text=True, timeout=4)
    if result.returncode or (not json_output and re.search(r'error|invalid|not found', result.stdout, re.I)):
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout) if json_output else result.stdout


def lua(value):
    # JSON strings are Lua-safe for addresses/workspace names after unicode escaping disabled.
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'


def dispatch(operation, **kwargs):
    return ctl('dispatch', 'hl.dsp.' + operation + '({' + ','.join(k + '=' + lua(v) for k, v in kwargs.items()) + '})')


def read(path, fallback):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        return fallback


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data))
    temporary.replace(path)


def key(client):
    return client['address'] + ':' + str(client['pid'])


def workspace_name(name):
    return name if str(name).isdigit() or name.startswith('special:') else 'name:' + name


def restore(client, saved, focus=True, destination=None, preserve_fullscreen=False, preserve_geometry=True):
    selector = 'address:' + client['address']
    destination = destination or saved.get('workspace', {}).get('name') or ctl('activeworkspace', json_output=True)['name']
    if destination.startswith('special:'):
        destination = ctl('activeworkspace', json_output=True)['name']
    if client.get('pinned'):
        dispatch('window.pin', window=selector, action='off')
    dispatch('window.move', window=selector, workspace=workspace_name(destination), follow=False)
    if saved.get('floating') and preserve_geometry:
        dispatch('window.float', window=selector, action='on')
        size = saved.get('size', [900, 650])
        at = saved.get('at', [40, 60])
        dispatch('window.resize', window=selector, x=size[0], y=size[1])
        # Keep floating geometry on the destination monitor, even across displays.
        moved = next((c for c in ctl('clients', json_output=True) if c['address'] == client['address']), client)
        monitors = ctl('monitors', json_output=True)
        if any(m['id'] == moved['monitor'] and m['x'] <= at[0] < m['x'] + m['width']/m['scale'] and m['y'] <= at[1] < m['y'] + m['height']/m['scale'] for m in monitors):
            dispatch('window.move', window=selector, x=at[0], y=at[1])
        else:
            dispatch('window.center', window=selector)
    if saved.get('pinned'):
        dispatch('window.pin', window=selector, action='on')
    if focus:
        dispatch('focus', window=selector)
    if saved.get('fullscreen'):
        dispatch('window.fullscreen', window=selector, mode='fullscreen' if saved['fullscreen'] == 2 and preserve_fullscreen else 'maximized', action='set')


def parent_map():
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(2)
            connection.connect(str(RUNTIME / 'hypr' / SIGNATURE / '.socket.sock'))
            connection.sendall(b'j/taskbar-parents')
            chunks = []
            while data := connection.recv(65536):
                chunks.append(data)
            return json.loads(b''.join(chunks))
    except (OSError, ValueError):
        return {}


def family_for(target, clients, parents):
    by_address = {c['address']: c for c in clients}
    root = target['address']
    seen = set()
    while parents.get(root) in by_address and root not in seen:
        seen.add(root)
        root = parents[root]
    addresses = [root]
    for address in addresses:
        for child, parent in parents.items():
            if parent == address and child in by_address and child not in addresses:
                addresses.append(child)
    return [by_address[a] for a in addresses]


def target_workspace(monitors, screen):
    if screen:
        monitor = next((m for m in monitors if m['name'] == screen), None)
        if monitor is None:
            raise RuntimeError('The clicked monitor is no longer connected.')
        return dict(monitor['activeWorkspace'], monitorID=monitor['id'], monitor=screen)
    return ctl('activeworkspace', json_output=True)


def transaction(action='snapshot', address=None, options=None):
    options = options or {}
    SESSION.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (SESSION / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = read(SESSION / 'windows.json', {'minimized': {}, 'floated': {}})
        config = settings_store.load_settings()
        prefs = {'groupApps':config['grouping']['enabled'], 'restoreFullscreen':config['windows']['restoreFullscreen']}
        modes = config['workspace']['modes']
        default_floating = config['workspace']['defaultFloating']
        clients = ctl('clients', json_output=True)
        monitors = ctl('monitors', json_output=True)
        active = ctl('activewindow', json_output=True).get('address', '')
        workspace = target_workspace(monitors, options.get('screen'))
        live = {key(c) for c in clients}
        state['minimized'] = {k:v for k,v in state['minimized'].items() if k in live}
        state['floated'] = {k:v for k,v in state['floated'].items() if k in live}
        parents = parent_map()
        target = next((c for c in clients if c['address'] == (address or active)), None)
        if target and options.get('windowKey') and options['windowKey'] != key(target):
            target = None
        family = (family_for(target, clients, parents) if config['windows']['followDialogs'] else [target]) if target else []
        if action == 'preferences':
            mapping = {'groupApps':('grouping','enabled'), 'restoreFullscreen':('windows','restoreFullscreen')}
            patch = {}
            for name,(section,field) in mapping.items():
                if isinstance(options.get(name),bool): patch.setdefault(section,{})[field]=options[name]
            settings_store.update_settings(patch)
        elif action == 'reorder' and target:
            order = [k for k in state.get('order', []) if k in live]
            order += [key(c) for c in clients if key(c) not in order]
            moving = [key(c) for c in clients if c['class'] == target['class']] if prefs.get('groupApps') else [key(target)]
            before = next((key(c) for c in clients if c['address'] == options.get('before')), None)
            if before not in moving:
                order = [k for k in order if k not in moving]
                at = order.index(before) if before in order else len(order)
                order[at:at] = moving
                state['order'] = order
        elif action == 'layout':
            name = workspace['name']
            modes[name] = not modes.get(name, default_floating)
            settings_store.update_settings({'workspace':{'modes':modes}})
            if not modes[name]:
                for c in clients:
                    if c['workspace']['name'] == name and key(c) in state['floated']:
                        dispatch('window.float', window='address:' + c['address'], action='off')
                        state['floated'].pop(key(c), None)
        elif action == 'restore-all':
            for c in clients:
                if c['workspace']['name'] == SPECIAL:
                    restore(c, state['minimized'].get(key(c), {}), False, preserve_fullscreen=prefs.get('restoreFullscreen', False), preserve_geometry=config['windows']['restoreGeometry'])
                    state['minimized'].pop(key(c), None)
        elif target and action in ('toggle', 'minimize', 'restore', 'goto', 'close', 'maximize', 'fullscreen'):
            selector = 'address:' + target['address']
            minimized = target['workspace']['name'] == SPECIAL
            is_here = target['workspace']['name'] == workspace['name'] or (target.get('pinned') and target['monitor'] == workspace['monitorID'])
            family_active = any(c['address'] == active for c in family)
            if action == 'toggle':
                if (minimized and config['windows']['minimizedRestore'] == 'original') or (not minimized and not is_here and config['windows']['otherWorkspace'] == 'switch'):
                    action = 'goto'
                elif not minimized and is_here and family_active and config['windows']['activeClick'] == 'maximize':
                    action = 'maximize'
            should_minimize = action == 'minimize' or (action == 'toggle' and is_here and family_active and not minimized and config['windows']['activeClick'] == 'minimize')
            if action == 'close':
                dispatch('window.close', window=selector)
            elif should_minimize:
                for c in family:
                    if c['workspace']['name'].startswith('special:'):
                        continue
                    state['minimized'][key(c)] = c
                write(SESSION / 'windows.json', state)
                for c in reversed(family):
                    if c['workspace']['name'].startswith('special:'):
                        continue
                    select_window = 'address:' + c['address']
                    if c.get('pinned'):
                        dispatch('window.pin', window=select_window, action='off')
                    if c.get('fullscreen'):
                        dispatch('window.fullscreen', window=select_window, action='unset')
                    dispatch('window.move', window=select_window, workspace=SPECIAL, follow=False)
            else:
                destination = workspace['name']
                if action == 'goto':
                    destination = state['minimized'].get(key(target), target)['workspace']['name']
                for c in family:
                    hidden = c['workspace']['name'] == SPECIAL
                    if hidden or (action != 'goto' and c['workspace']['name'] != destination and not (c.get('pinned') and c['monitor'] == workspace['monitorID'])):
                        restore(c, state['minimized'].get(key(c), c), False, destination, prefs.get('restoreFullscreen', False), config['windows']['restoreGeometry'])
                        state['minimized'].pop(key(c), None)
                # Focus the deepest dialog so modal prompts don't hide behind their parent.
                focus_target = family[-1] if len(family) > 1 else target
                dispatch('focus', window='address:' + focus_target['address'])
                if action in ('maximize', 'fullscreen'):
                    dispatch('window.fullscreen', window='address:' + family[0]['address'], mode='maximized' if action == 'maximize' else 'fullscreen', action='set' if minimized else 'toggle')
        clients = ctl('clients', json_output=True)
        for c in clients:
            if not c['workspace']['name'].startswith('special:') and modes.get(c['workspace']['name'], default_floating) and not c['floating'] and not c.get('fullscreen'):
                selector = 'address:' + c['address']
                dispatch('window.float', window=selector, action='on')
                monitor = next((m for m in monitors if m['id'] == c['monitor']), None)
                if config['workspace']['resizeOnFloat'] and monitor:
                    reserved = monitor.get('reserved', [0,0,0,0])
                    available_width = monitor['width']/monitor['scale'] - reserved[0] - reserved[2]
                    available_height = monitor['height']/monitor['scale'] - reserved[1] - reserved[3]
                    width = max(100, min(c['size'][0], int(available_width*config['workspace']['floatWidthPercent']/100)))
                    height = max(100, min(c['size'][1], int(available_height*config['workspace']['floatHeightPercent']/100)))
                    dispatch('window.resize', window=selector, x=width, y=height)
                if config['workspace']['centerOnFloat']:
                    dispatch('window.center', window=selector)
                state['floated'][key(c)] = True
        order = [k for k in state.get('order', []) if k in live]
        order += [key(c) for c in clients if key(c) not in order]
        state['order'] = order
        write(SESSION / 'windows.json', state)
        clients = ctl('clients', json_output=True)
        active = ctl('activewindow', json_output=True).get('address', '')
        result = []
        for c in clients:
            minimized = c['workspace']['name'] == SPECIAL
            if not c['mapped'] or (c['workspace']['name'].startswith('special:') and not minimized):
                continue
            saved = state['minimized'].get(key(c), c)
            result.append({'address': c['address'], 'key': key(c), 'title': c['title'], 'app': c['class'],
                           'workspace': saved['workspace']['name'], 'monitor': saved['monitor'] if minimized else c['monitor'], 'minimized': minimized,
                           'size': saved['size'] if minimized else c['size'],
                           'parent': parents.get(c['address'], ''), 'fullscreen': c['fullscreen'],
                           'active': c['address'] == active, 'floating': c['floating'], 'focusHistory':c.get('focusHistoryID',9999)})
        result.sort(key=lambda c: order.index(c['key']) if c['key'] in order else len(order))
        return {'windows': result, 'workspace': workspace['name'], 'floating': bool(modes.get(workspace['name'], default_floating)),
                'modes': modes, 'monitors': monitors, 'preferences': prefs, 'config':settings_store.load_settings(), 'configError':settings_store.ERROR}


def activate_slot(value):
    """Use the focused monitor's rendered taskbar order, including overflow."""
    slot = int(value)
    if not 1 <= slot <= 10:
        raise ValueError('Taskbar slot must be between 1 and 10 (0 key selects 10).')
    monitor = next((m for m in ctl('monitors', json_output=True) if m.get('focused')), None)
    if not monitor:
        return
    result = subprocess.run(['omarchy', 'shell', 'qol-desktop-plus.' + monitor['name'],
                             'activate', str(slot)], capture_output=True, text=True, timeout=4)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def open_switcher(value):
    direction = int(value)
    if direction not in (-1,1): raise ValueError('Switcher direction must be 1 or -1')
    monitor = next((m for m in ctl('monitors', json_output=True) if m.get('focused')), None)
    if monitor:
        result = subprocess.run(['omarchy','shell','qol-desktop-plus.'+monitor['name'],'switcher',str(direction)], capture_output=True,text=True,timeout=4)
        if result.returncode: raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def ensure_native():
    """Build the companion locally and serialize loads across bar instances."""
    native = Path(__file__).resolve().parent / 'native'
    SESSION.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (SESSION / 'native.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        version = ctl('version', json_output=True)
        runtime_version = version.get('commit', '')
        header = Path('/usr/include/hyprland/src/version.h').read_text()
        if not runtime_version or runtime_version not in header:
            raise RuntimeError('Taskbar companion awaits matching Hyprland headers. Restart the desktop after an upgrade.')
        build_id = hashlib.sha256((version.get('abiHash', runtime_version)).encode()
                                  + (native / 'minimize.cpp').read_bytes()
                                  + (native / 'build.sh').read_bytes()
                                  + str(Path(__file__).resolve()).encode()).hexdigest()
        build_dir = BASE / 'native' / build_id
        binary = build_dir / 'minimize.so'
        stamp = build_dir / 'version.txt'
        installed = read(SESSION / 'native.json', {})
        loaded_path = installed.get('path', str(native / 'minimize.so'))
        current = binary.exists() and stamp.exists() and stamp.read_text().strip() == build_id
        loaded = next((p for p in ctl('plugin', ['list'], json_output=True)
                       if p.get('name') == 'omarchy-taskbar-minimize'), None)
        build_dir.mkdir(parents=True, exist_ok=True)
        shortcuts_file = build_dir / 'shortcuts'
        if not loaded or loaded_path != str(binary): shortcuts_file.write_text(settings_store.shortcut_rows(settings_store.load_settings()))
        if loaded and loaded.get('version') == '1.3.0' and current and loaded_path == str(binary):
            return
        if not current:
            subprocess.run([str(native / 'build.sh'), str(binary)], check=True, timeout=120, stdout=sys.stderr)
            stamp.write_text(build_id)
        if loaded:
            ctl('plugin', ['unload', loaded_path])
        ctl('plugin', ['load', str(binary)])
        write(SESSION / 'native.json', {'path':str(binary)})


def sync_shortcuts(config):
    installed = read(SESSION / 'native.json', {})
    if not installed.get('path'): return
    path = Path(installed['path']).parent / 'shortcuts'
    content = settings_store.shortcut_rows(config)
    if path.exists() and path.read_text() == content: return
    with (SESSION / 'native.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        temporary = path.with_suffix('.tmp')
        temporary.write_text(content)
        temporary.replace(path)
        # Custom commands are sent through the compositor IPC socket.
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(3)
            connection.connect(str(RUNTIME / 'hypr' / SIGNATURE / '.socket.sock'))
            connection.sendall(b'/taskbar-shortcuts-reload')
            reply = connection.recv(4096).decode()
            if reply.strip() != 'ok': raise RuntimeError(reply)


def unload_native():
    native = Path(__file__).resolve().parent / 'native'
    with (SESSION / 'native.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if any(p.get('name') == 'omarchy-taskbar-minimize' for p in ctl('plugin', ['list'], json_output=True)):
            ctl('plugin', ['unload', read(SESSION / 'native.json', {}).get('path', str(native / 'minimize.so'))])


def process_events(pending, data):
    pending += data
    lines = pending.split(b'\n')
    for line in lines[:-1]:
        match = re.fullmatch(rb'omarchy_minimize>>([0-9a-f]+),([01])', line)
        if match and settings_store.load_settings()['windows']['nativeMinimize']:
            address = '0x' + match[1].decode()
            if match[2] == b'1':
                transaction('minimize', address)
            else:
                clients = ctl('clients', json_output=True)
                if any(c['address'] == address and c['workspace']['name'] == SPECIAL for c in clients):
                    transaction('restore', address)
    return lines[-1]


def guard():
    """Survives shell reloads and restores hidden windows after plugin removal."""
    SESSION.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (SESSION / 'guard.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        config = Path(os.environ.get('OMARCHY_TASKBAR_CONFIG', str(Path.home() / '.config/omarchy/shell.json')))
        while (RUNTIME / 'hypr' / SIGNATURE / '.socket.sock').exists():
            try:
                content = json.loads(config.read_text())
                enabled = any(w.get('id') == 'qol-desktop-plus' for section in content.get('bar', {}).get('layout', {}).values() for w in section)
                if not enabled or not Path(__file__).exists():
                    transaction('restore-all')
                    unload_native()
                    menu_integration.sync(False)
                    return
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                pass  # Atomic config replacement/reload must never restore windows accidentally.
            time.sleep(settings_store.load_settings()['advanced']['recoveryIntervalMs']/1000)


def watch():
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), 'guard'], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ensure_native()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr, flush=True)
    try:
        menu_integration.sync()
    except (OSError, ValueError) as error:
        print("Taskbar menu: "+str(error), file=sys.stderr, flush=True)
    previous = None
    while True:
        try:
            with socket.socket(socket.AF_UNIX) as events:
                events.connect(str(RUNTIME / 'hypr' / SIGNATURE / '.socket2.sock'))
                pending = b''
                while True:
                    data_snapshot = transaction()
                    sync_shortcuts(data_snapshot['config'])
                    snapshot = json.dumps(data_snapshot, ensure_ascii=False)
                    if snapshot != previous:
                        print(snapshot, flush=True)
                        previous = snapshot
                    ready, _, _ = select.select([events], [], [], data_snapshot['config']['advanced']['pollIntervalMs']/1000)
                    if ready:
                        data = events.recv(65536)
                        if not data:
                            return
                        pending = process_events(pending, data)
                        time.sleep(.04)
                        while select.select([events], [], [], 0)[0]:
                            data = events.recv(65536)
                            if not data:
                                return
                            pending = process_events(pending, data)
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            print(str(error), file=sys.stderr, flush=True)
            time.sleep(2)


if __name__ == '__main__':
    if not SIGNATURE:
        sys.exit('This plugin runs inside Hyprland.')
    action = sys.argv[1] if len(sys.argv) > 1 else 'snapshot'
    if action == 'config-check':
        try:
            settings_store.validate(json.loads(settings_store.CONFIG.read_text()))
            print(str(settings_store.CONFIG) + ': valid')
        except (OSError, ValueError) as error:
            sys.exit(str(error))
    elif action == 'settings':
        try:
            monitor = next((m for m in ctl('monitors', json_output=True) if m.get('focused')), None)
            if monitor: subprocess.run(['omarchy','shell','qol-desktop-plus.'+monitor['name'],'settings'],check=True,timeout=4)
        except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as error:
            sys.exit(str(error))
    elif action == 'switcher':
        try:
            open_switcher(sys.argv[2] if len(sys.argv)>2 else '1')
        except (OSError,RuntimeError,ValueError,subprocess.TimeoutExpired) as error:
            sys.exit(str(error))
    elif action == 'activate':
        try:
            activate_slot(sys.argv[2] if len(sys.argv) > 2 else '')
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            sys.exit(str(error))
    elif action == 'guard':
        guard()
    elif action == 'watch':
        watch()
    else:
        try:
            print(json.dumps(transaction(action, sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None, json.loads(sys.argv[3]) if len(sys.argv) > 3 else {})))
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            sys.exit(str(error))
