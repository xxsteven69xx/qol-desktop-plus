"""Own a small JSONC block in Omarchy's user menu, preserving other entries."""
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import settings as store

MENU = Path(os.environ.get('OMARCHY_TASKBAR_MENU', str(Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config'))) / 'omarchy/extensions/omarchy-menu.jsonc')))
START = '\n  // BEGIN legion.taskbar settings (managed by plugin)\n'
END = '  // END legion.taskbar settings\n'
BLOCK = re.compile(re.escape(START)+r'.*?'+re.escape(END),re.S)

def parsed(raw):
    raw = re.sub(r'^\s*//[^\n]*(\n|$)','',raw,flags=re.M)
    return json.loads(re.sub(r',(\s*[}\]])',r'\1',raw))

def sync(enabled=True):
    store.STATE.mkdir(parents=True,exist_ok=True)
    with (store.STATE/'menu.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if not MENU.exists() and not enabled: return
        raw = MENU.read_text() if MENU.exists() else '{\n}\n'
        data = parsed(raw)
        if not isinstance(data,dict): raise ValueError('Omarchy menu must be an object')
        original=raw
        raw=BLOCK.sub('',raw)
        data=parsed(raw)
        if enabled:
            entries=data.get('items',data)
            if 'setup.legion-taskbar' in entries: return  # Respect an unowned custom entry.
            entry={'icon':'󰍜','label':'Taskbar','description':'Window behavior, Alt+Tab, previews and shortcuts','action':'python3 '+shlex.quote(str(Path(__file__).parent/'taskbar.py'))+' settings','aliases':['taskbar','taskbar-settings']}
            block=START+'  "setup.legion-taskbar": '+json.dumps(entry,ensure_ascii=False)+',\n'+END
            masked=re.sub(r'^\s*//[^\n]*',lambda m:' '*len(m.group()),raw,flags=re.M)
            match=re.search(r'"items"\s*:\s*\{',masked) if isinstance(data.get('items'),dict) else re.search(r'\{',masked)
            pos=match.end()
            raw=raw[:pos]+block+raw[pos:]
        if raw==original:return
        parsed(raw)
        MENU.parent.mkdir(parents=True,exist_ok=True)
        backup=store.STATE/'menu-before-taskbar.jsonc'
        if not backup.exists():backup.write_text(original)
        temp=MENU.with_name(MENU.name+'.taskbar-tmp');temp.write_text(raw);temp.replace(MENU)
