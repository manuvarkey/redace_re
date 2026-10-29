#!/bin/sh
# Build the Windows export (build/windows/redace.exe). GODOT and font handling as in build.sh.
exec "$(dirname "$0")/../build.sh" Windows
