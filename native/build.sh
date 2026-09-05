#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
output=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/taskbar/native/manual/minimize.so}
mkdir -p -- "$(dirname -- "$output")"
read -r -a flags <<< "$(pkg-config --cflags hyprland aquamarine hyprlang pixman-1 libdrm)"
g++ -std=c++26 -O2 -shared -fPIC -fno-gnu-unique "${flags[@]}" minimize.cpp -o "$output.new"
python3 - "$output" <<'HELPER'
from pathlib import Path
import sys
(Path(sys.argv[1]).parent / 'helper-path').write_text(str(Path('../taskbar.py').resolve()))
HELPER
mv -- "$output.new" "$output"
