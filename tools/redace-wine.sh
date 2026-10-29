#!/bin/bash
# Launch Red Ace Windows builds under the Flatpak Wine (org.winehq.Wine).
#
#   tools/redace-wine.sh                  original game in a 640x480 Wine desktop window
#   tools/redace-wine.sh original 1024x768   original in a bigger desktop (match the in-game video mode)
#   tools/redace-wine.sh original full    original without a virtual desktop (takes over the screen)
#   tools/redace-wine.sh remake           Godot Windows export (build/windows/redace.exe)
#   tools/redace-wine.sh kill             stop every process of the Wine Flatpak
#
# Expected layout (made while comparing the remake with the original):
#   prefix   ~/.var/app/org.winehq.Wine/data/wine
#   C:\RedAce  -> ~/.var/app/org.winehq.Wine/data/redace/RedAce (installed game, CD check patched)
#   D:       -> ~/.var/app/org.winehq.Wine/data/redace/cd       (files from REDACE.BIN)
# Wine output goes to $LOG (default /tmp/redace-wine.log).

set -euo pipefail

APP=org.winehq.Wine
BRANCH=${WINE_BRANCH:-stable-26.08}
DATA=$HOME/.var/app/$APP/data
GAME=$DATA/redace/RedAce
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOG=${LOG:-/tmp/redace-wine.log}

wine() {
	flatpak run --user "$APP//$BRANCH" "$@" >>"$LOG" 2>&1
}

need() {
	if ! flatpak info --user "$APP//$BRANCH" >/dev/null 2>&1; then
		echo "Flatpak $APP//$BRANCH not installed:" >&2
		echo "  flatpak install --user flathub $APP//$BRANCH" >&2
		exit 1
	fi
}

mode=${1:-original}
: >"$LOG"

case $mode in
original)
	need
	if [ ! -f "$GAME/RedAce.exe" ] || [ ! -e "$DATA/wine/dosdevices/d:" ]; then
		echo "Game not set up in the Wine prefix (need $GAME/RedAce.exe and drive D:)." >&2
		exit 1
	fi
	size=${2:-640x480}
	echo "Starting original ($size), log: $LOG"
	if [ "$size" = full ]; then
		wine cmd /c "cd /d C:\\RedAce && RedAce.exe"
	else
		wine explorer "/desktop=RedAce,$size" cmd /c "cd /d C:\\RedAce && RedAce.exe"
	fi
	;;
remake)
	need
	exe=$ROOT/build/windows/redace.exe
	if [ ! -f "$exe" ]; then
		echo "No Windows export at $exe; export it with Godot first." >&2
		exit 1
	fi
	echo "Starting remake, log: $LOG"
	# Z: maps to /, so the export runs in place; extra arguments go to the game (e.g. -- --mission=3)
	wine "Z:${exe//\//\\}" "${@:2}"
	;;
kill)
	flatpak kill "$APP" 2>/dev/null || true
	;;
*)
	sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
	;;
esac
