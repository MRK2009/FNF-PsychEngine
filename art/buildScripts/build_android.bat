@echo off
rem Build the Android APK on Windows.
rem
rem Portable: no hardcoded SDK/NDK/JDK paths. Relies on your lime Android config
rem (run "haxelib run lime setup android" once, or set ANDROID_SDK / ANDROID_NDK_ROOT /
rem JAVA_HOME in %USERPROFILE%\.lime\config.xml) and on JAVA_HOME in your environment.
rem
rem lime's own Gradle-wrapper invocation is broken on Windows, so this lets lime do the
rem Haxe -> C++ -> arm64 link, then finishes by calling gradlew.bat directly.
rem
rem Usage: build-android.bat [debug^|release]   (default: debug)
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "MODE=%~1"
if "%MODE%"=="" set "MODE=debug"

if /i "%MODE%"=="debug" (
	set "LIME_FLAGS=-debug"
	set "GRADLE_TASK=assembleDebug"
	set "OUT=debug"
	set "EXPORT=export\debug\android\bin"
) else if /i "%MODE%"=="release" (
	set "LIME_FLAGS="
	set "GRADLE_TASK=assembleRelease"
	set "OUT=release"
	set "EXPORT=export\release\android\bin"
) else (
	echo Usage: build-android.bat [debug^|release]
	exit /b 1
)

set "APK_DIR=%EXPORT%\app\build\outputs\apk\%OUT%"

echo ^>^> haxelib run lime build android %LIME_FLAGS%
call haxelib run lime build android %LIME_FLAGS%

if exist "%APK_DIR%\*.apk" (
	echo ^>^> APK built by lime:
	dir /b "%APK_DIR%\*.apk"
	exit /b 0
)

echo ^>^> Finishing with the Gradle wrapper (%GRADLE_TASK%)
pushd "%EXPORT%"
call gradlew.bat %GRADLE_TASK% --no-daemon
set "RC=!ERRORLEVEL!"
popd
if not "!RC!"=="0" exit /b !RC!

echo ^>^> APK:
dir /b "%APK_DIR%\*.apk"
endlocal
