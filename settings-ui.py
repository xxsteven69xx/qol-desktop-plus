#!/usr/bin/env python3
"""Settings-panel bridge. Structured data only; never evaluates commands."""
import copy
import fcntl
import json
from pathlib import Path
import sys
import settings as store

ROOT = Path(__file__).parent

def read():
    config = store.load_settings()
    return {'config':config, 'error':store.ERROR, 'path':str(store.CONFIG),
            'schema':json.loads((ROOT/'settings.schema.json').read_text()),
            'meta':json.loads((ROOT/'settings-ui.json').read_text())}

def apply(request):
    store.load_settings()
    with (store.STATE/'settings.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        current = store.validate(json.loads(store.CONFIG.read_text()))
        result = copy.deepcopy(current)
        for path, change in request.items():
            section,key = path.split('.')
            if section not in current or key not in current[section]:
                raise ValueError('Unknown setting: '+path)
            if current[section][key] != change['before'] and current[section][key] != change['after']:
                raise ValueError(path+' changed outside this panel. Reopen settings to load the current value.')
            result[section][key] = change['after']
        result = store.validate(result)
        store.atomic_write(store.CONFIG,result)
        store.atomic_write(store.STATE/'settings-last-good.json',result)
        return {'config':result}

if __name__ == '__main__':
    try:
        if sys.argv[1] == 'read': result=read()
        elif sys.argv[1] == 'apply': result=apply(json.loads(sys.argv[2]))
        else: raise ValueError('Unknown settings operation')
        print(json.dumps(result))
    except (OSError,ValueError,KeyError,TypeError) as error:
        print(json.dumps({'error':str(error)}))
        sys.exit(1)
