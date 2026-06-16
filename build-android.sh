#!/bin/sh
# Build the Android APK.
#
# Portable: no hardcoded SDK/NDK/JDK paths. It relies on your lime Android config
# (run `haxelib run lime setup android` once, or set ANDROID_SDK / ANDROID_NDK_ROOT /
# JAVA_HOME in ~/.lime/config.xml) and on JAVA_HOME being on your environment.
#
# Why this exists: `lime build android` on Windows currently dies invoking the Gradle
# wrapper ("'gradlew' is not recognized"). This script lets lime do the Haxe -> C++ ->
# arm64 link, then finishes packaging by calling the Gradle wrapper directly. On Linux/
# macOS lime completes everything itself and the wrapper step is skipped.
#
# Usage: ./build-android.sh [debug|release]   (default: debug)
set -e
cd "$(dirname "$0")"

MODE="${1:-debug}"
case "$MODE" in
	debug)   LIME_FLAGS="-debug"; GRADLE_TASK="assembleDebug";   OUT="debug";   EXPORT="export/debug/android/bin" ;;
	release) LIME_FLAGS="";       GRADLE_TASK="assembleRelease"; OUT="release"; EXPORT="export/release/android/bin" ;;
	*) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac

APK_DIR="$EXPORT/app/build/outputs/apk/$OUT"

echo ">> haxelib run lime build android $LIME_FLAGS"
# Don't abort if lime's own gradlew invocation fails (Windows); we finish below.
haxelib run lime build android $LIME_FLAGS || true

# If lime already produced the APK (Linux/macOS), we're done.
if ls "$APK_DIR"/*.apk >/dev/null 2>&1; then
	echo ">> APK built by lime:"
	ls -1 "$APK_DIR"/*.apk
	exit 0
fi

echo ">> Finishing with the Gradle wrapper ($GRADLE_TASK)"
cd "$EXPORT"
# Use the POSIX wrapper -- works on Linux, macOS and git-bash on Windows alike.
# (Native cmd.exe users should run build-android.bat instead.)
chmod +x ./gradlew 2>/dev/null || true
./gradlew "$GRADLE_TASK" --no-daemon

echo ">> APK:"
ls -1 "app/build/outputs/apk/$OUT"/*.apk
