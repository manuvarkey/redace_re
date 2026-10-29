#!/bin/sh
# Build the Web export (build/web/index.html). GODOT and font handling as in build.sh.
exec "$(dirname "$0")/../build.sh" Web
