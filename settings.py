"""Validated taskbar settings shared by the UI, window helper and native bindings."""
import copy
import ctypes
import ctypes.util
import fcntl
import json
import os
from pathlib import Path
import re

DEFAULTS = json.loads((Path(__file__).parent / 'defaults.json').read_text())
CONFIG = Path(os.environ.get('OMARCHY_TASKBAR_SETTINGS', str(Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'omarchy/taskbar.json')))
STATE = Path(os.environ.get('OMARCHY_TASKBAR_STATE', str(Path.home()/'.local/state/omarchy/taskbar')))
ERROR = ''
_XKB = ctypes.CDLL(ctypes.util.find_library('xkbcommon'))
_XKB.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
_XKB.xkb_keysym_from_name.restype = ctypes.c_uint32
ENUMS = {'windows.otherWorkspace':['bring','switch'], 'windows.activeClick':['minimize','maximize','focus'],
         'windows.minimizedRestore':['current','original'], 'grouping.clickAction':['picker','toggle'],
         'interaction.middleClick':['none','minimize','close','maximize','goto','restore'],
         'switcher.scope':['all','workspace'],'switcher.order':['recent','taskbar'],'switcher.otherWorkspace':['switch','bring','taskbar']}
BOUNDS = {'bar.settingsAreaWidth':(12,100),'bar.maxWidth':(40,4000),'bar.iconSize':(8,96),'bar.cellSize':(12,128),'bar.spacing':(0,32),
          'bar.minimizedOpacity':(0.1,1),'bar.animationDurationMs':(0,2000),
          'preview.delayMs':(0,5000),'preview.hideDelayMs':(0,5000),'preview.width':(100,1200),
          'preview.height':(60,800),'preview.titleLines':(1,6),'picker.width':(200,1200),
          'picker.maxHeight':(100,1600),'picker.rowHeight':(30,160),'interaction.dragThreshold':(1,64),
          'workspace.floatWidthPercent':(25,100),'workspace.floatHeightPercent':(25,100),
          'switcher.width':(200,1600),'switcher.height':(100,1000),'switcher.sliceWidth':(40,240),
          'switcher.backgroundScale':(0.5,1),'switcher.backgroundReveal':(0.25,1),'switcher.selectedCornerRadius':(0,32),'switcher.spacing':(-80,40),'switcher.skewOffset':(-50,50),'switcher.neighbors':(1,6),'switcher.animationDurationMs':(0,1000),
          'advanced.pollIntervalMs':(250,10000),'advanced.recoveryIntervalMs':(250,5000)}


def atomic_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name+'.tmp')
    temp.write_text(json.dumps(value, indent=2)+'\n')
    temp.replace(path)


def chord(value):
    if not isinstance(value, str): raise ValueError('shortcut must be a string')
    if not value: return None
    parts = [p.strip() for p in value.split('+')]
    modifiers = {'SUPER':64,'CTRL':4,'CONTROL':4,'ALT':8,'SHIFT':1}
    mask = 0
    for part in parts[:-1]:
        if part.upper() not in modifiers or mask & modifiers[part.upper()]: raise ValueError('invalid shortcut modifiers: '+value)
        mask |= modifiers[part.upper()]
    key = parts[-1]
    if key.startswith('code:'):
        if not key[5:].isdigit() or not 8 <= int(key[5:]) <= 255: raise ValueError('invalid keycode: '+value)
        code = int(key[5:]); name = str((code-9)%10) if 10 <= code <= 19 else ''
    else:
        if not re.fullmatch(r'[A-Za-z0-9_]+',key) or key.upper() in modifiers: raise ValueError('invalid shortcut key: '+value)
        if not _XKB.xkb_keysym_from_name(key.encode(),1): raise ValueError('unknown shortcut key: '+key)
        code = 0; name = key
    return mask,name,code


def validate(raw, defaults=DEFAULTS, prefix=''):
    if not isinstance(raw,dict): raise ValueError((prefix or 'config')+' must be an object')
    result=copy.deepcopy(defaults)
    for key,value in raw.items():
        path=prefix+'.'+key if prefix else key
        if key not in defaults: raise ValueError('unknown setting: '+path)
        expected=defaults[key]
        if path=='workspace.modes':
            if not isinstance(value,dict) or any(not isinstance(k,str) or not k or type(v) is not bool for k,v in value.items()): raise ValueError(path+' must map workspace names to booleans')
            result[key]=value; continue
        if isinstance(expected,dict): result[key]=validate(value,expected,path); continue
        if type(expected) is float:
            if type(value) not in (int,float): raise ValueError(path+' must be a number')
        elif type(value) is not type(expected): raise ValueError(path+' has the wrong type')
        if path in ENUMS and value not in ENUMS[path]: raise ValueError(path+' must be one of '+', '.join(ENUMS[path]))
        if path in BOUNDS and not BOUNDS[path][0] <= value <= BOUNDS[path][1]: raise ValueError(path+' is outside '+str(BOUNDS[path]))
        if path=='schemaVersion' and value!=1: raise ValueError('unsupported schemaVersion')
        if path=='bar.excludedApps' and any(not isinstance(x,str) for x in value): raise ValueError(path+' must contain app class strings')
        if path=='keyboard.slots':
            if len(value)!=10: raise ValueError(path+' must contain ten shortcuts (empty strings disable individual slots)')
            for item in value: chord(item)
        elif (prefix=='keyboard' and isinstance(value,str)) or path in ('switcher.forwardShortcut','switcher.backwardShortcut'): chord(value)
        result[key]=value
    return result


def migrated_defaults():
    result=copy.deepcopy(DEFAULTS)
    try:
        old=json.loads((STATE/'preferences.json').read_text())
        result['grouping']['enabled']=old.get('groupApps',False)
        result['windows']['restoreFullscreen']=old.get('restoreFullscreen',False)
    except (OSError,ValueError): pass
    try: result['workspace']['modes']=json.loads((STATE/'layouts.json').read_text())
    except (OSError,ValueError): pass
    try:
        shell=json.loads(Path(os.environ.get('OMARCHY_TASKBAR_CONFIG',str(Path.home()/'.config/omarchy/shell.json'))).read_text())
        widget=next(w for section in shell.get('bar',{}).get('layout',{}).values() for w in section if w.get('id')=='qol-desktop-plus')
        for key in ('allWorkspaces','maxWidth'):
            if key in widget: result['bar'][key]=widget[key]
    except (OSError,ValueError,StopIteration): pass
    return validate(result)


def load_settings():
    global ERROR
    STATE.mkdir(parents=True,exist_ok=True)
    with (STATE/'settings.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if not CONFIG.exists(): atomic_write(CONFIG, copy.deepcopy(DEFAULTS) if (STATE/'settings-last-good.json').exists() else migrated_defaults())
        try:
            result=validate(json.loads(CONFIG.read_text()))
            if ERROR: ERROR=''
            saved=STATE/'settings-last-good.json'
            if not saved.exists() or saved.read_text()!=json.dumps(result,indent=2)+'\n': atomic_write(saved,result)
            return result
        except (OSError,ValueError) as error:
            ERROR=str(error)
            try: return validate(json.loads((STATE/'settings-last-good.json').read_text()))
            except (OSError,ValueError): return copy.deepcopy(DEFAULTS)


def update_settings(patch):
    # Menu writes share the same file and validation as manual edits.
    load_settings()
    with (STATE/'settings.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        current=validate(json.loads(CONFIG.read_text()))
        for section,values in patch.items():
            if section not in current or not isinstance(current[section],dict): raise ValueError('invalid settings section')
            current[section].update(values)
        current=validate(current)
        atomic_write(CONFIG,current)
        atomic_write(STATE/'settings-last-good.json',current)
        return current


def shortcut_rows(config):
    keyboard=config['keyboard']
    if not keyboard['enabled']: return ''
    entries=[(keyboard['settings'],'Taskbar settings','settings'),
             (keyboard['minimize'],'Minimize window to bar','minimize'),
             (keyboard['restoreAll'],'Restore all minimized windows','restore-all'),
             (keyboard['toggleLayout'],'Toggle workspace floating/tiling','layout')]
    entries += [(value,'Activate taskbar window '+str(i),'activate '+str(i)) for i,value in enumerate(keyboard['slots'],1)]
    if not keyboard['enabled']: entries=[]
    entries=[(*entry,0) for entry in entries]
    switcher=config['switcher']
    if switcher['enabled']:
        entries += [(switcher['forwardShortcut'],'Visual app switcher','switcher 1',int(switcher['replaceStockAltTab'])),
                    (switcher['backwardShortcut'],'Visual app switcher (previous)','switcher -1',int(switcher['replaceStockAltTab']))]
    rows=[]
    for keys,description,action,override in entries:
        parsed=chord(keys)
        if parsed:
            mask,name,code=parsed
            rows.append('\t'.join(map(str,(mask,name,code,description,action,override))))
    return '\n'.join(rows)+'\n' if rows else ''
