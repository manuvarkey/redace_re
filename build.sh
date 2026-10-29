#!/bin/sh
# Build the Red Ace remake: fetch the Microsoft core fonts if missing, import, export.
# Usage: ./build.sh [Web|Linux|Windows|Android ...]   (default: Web, Linux, Windows)
# Per-platform shortcuts: scripts/build_linux.sh, build_windows.sh, build_web.sh, build_android.sh.
# GODOT: Godot 4.7.2 executable with export templates installed.
# Android: Godot's editor settings must name the Android SDK and JDK 17+ (export/android/android_sdk_path,
# java_sdk_path), plus the android_*.apk export templates; the APK is signed with a debug keystore,
# made in build/ on first use (keytool from JAVA_HOME or PATH).
set -eu

cd "$(dirname "$0")"
GODOT=${GODOT:-$HOME/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64}
FONTS=redace/fonts
SYS_FONTS=/usr/share/fonts/truetype/msttcorefonts
CORE_URL=https://downloads.sourceforge.net/corefonts

# Font file in redace/fonts, corefonts cabinet, file name inside the cabinet.
FONT_LIST="
Arial.ttf                arial32  arial.ttf
Arial_Bold.ttf           arial32  arialbd.ttf
Courier_New.ttf          courie32 cour.ttf
Courier_New_Bold.ttf     courie32 courbd.ttf
Times_New_Roman.ttf      times32  times.ttf
Times_New_Roman_Bold.ttf times32  timesbd.ttf
Verdana.ttf              verdan32 verdana.ttf
Verdana_Bold.ttf         verdan32 verdanab.ttf
"

# The Microsoft core fonts are not redistributable, so they are not in the repository.
# Copy them from the system (ttf-mscorefonts-installer) or download the original cabinets.
fetch_fonts() {
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	echo "$FONT_LIST" | while read -r name cab file; do
		[ -n "$name" ] || continue
		[ -f "$FONTS/$name" ] && continue
		if [ -f "$SYS_FONTS/$name" ]; then
			cp "$SYS_FONTS/$name" "$FONTS/$name"
			continue
		fi
		command -v cabextract >/dev/null || { echo "cabextract is needed to unpack $cab.exe" >&2; exit 1; }
		[ -f "$tmp/$cab.exe" ] || curl -fsSL -o "$tmp/$cab.exe" "$CORE_URL/$cab.exe"
		cabextract -q -L -F "$file" -d "$tmp" "$tmp/$cab.exe"
		mv "$tmp/$file" "$FONTS/$name"
		echo "fetched $name"
	done
}

[ $# -gt 0 ] || set -- Web Linux Windows
for preset in "$@"; do
	case $preset in
		Web|Linux|Windows|Android) ;;
		*) echo "unknown preset '$preset' (use Web, Linux, Windows or Android)" >&2; exit 1 ;;
	esac
done

# Debug signing for the APK (no release keystore): Godot reads it from these variables.
debug_keystore() {
	export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$PWD/build/debug.keystore
	export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
	export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
	[ -f build/debug.keystore ] && return
	mkdir -p build
	keytool=${JAVA_HOME:+$JAVA_HOME/bin/}keytool
	"$keytool" -genkeypair -keystore build/debug.keystore -storepass android -alias androiddebugkey \
		-keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" -noprompt
}

fetch_fonts
"$GODOT" --headless --path redace --import

for preset in "$@"; do
	case $preset in
		Web) mkdir -p build/web ;;
		Linux) mkdir -p build/linux ;;
		Windows) mkdir -p build/windows ;;
		Android) mkdir -p build/android && debug_keystore ;;
	esac
	if [ "$preset" = Android ]; then
		"$GODOT" --headless --path redace --export-debug Android
		continue
	fi
	"$GODOT" --headless --path redace --export-release "$preset"
	if [ "$preset" = Web ]; then
		# The help pages are served as files next to index.html.
		mkdir -p build/web/help && unzip -oq redace/game_data/help.zip -d build/web/help
	fi
done
