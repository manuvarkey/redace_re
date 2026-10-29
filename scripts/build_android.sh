#!/bin/sh
# Build the Android APK (build/android/redace.apk, debug-signed). GODOT, ANDROID_HOME and JAVA_HOME as in build.sh.
exec "$(dirname "$0")/../build.sh" Android
