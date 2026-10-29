#!/bin/sh
# Build the Linux export (build/linux/redace.x86_64). GODOT and font handling as in build.sh.
exec "$(dirname "$0")/../build.sh" Linux
