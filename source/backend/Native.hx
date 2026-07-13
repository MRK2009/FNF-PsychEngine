package backend;

import lime.app.Application;
import lime.system.Display;
import lime.system.System;
import flixel.util.FlxColor;

#if (cpp && windows)
@:buildXml('
<target id="haxe">
	<lib name="dwmapi.lib" if="windows"/>
	<lib name="gdi32.lib" if="windows"/>
	<lib name="advapi32.lib" if="windows"/>
</target>
')
@:cppFileCode('
#include <windows.h>
#include <dwmapi.h>
#include <winuser.h>
#include <wingdi.h>

#define attributeDarkMode 20
#define attributeDarkModeFallback 19

#define attributeCaptionColor 34
#define attributeTextColor 35
#define attributeBorderColor 36

struct HandleData {
	DWORD pid = 0;
	HWND handle = 0;
};

BOOL CALLBACK findByPID(HWND handle, LPARAM lParam) {
	DWORD targetPID = ((HandleData*)lParam)->pid;
	DWORD curPID = 0;

	GetWindowThreadProcessId(handle, &curPID);
	if (targetPID != curPID || GetWindow(handle, GW_OWNER) != (HWND)0 || !IsWindowVisible(handle)) {
		return TRUE;
	}

	((HandleData*)lParam)->handle = handle;
	return FALSE;
}

HWND curHandle = 0;
void getHandle() {
	if (curHandle == (HWND)0) {
		HandleData data;
		data.pid = GetCurrentProcessId();
		EnumWindows(findByPID, (LPARAM)&data);
		curHandle = data.handle;
	}
}

// -1 = unknown, 0 = light, 1 = dark. Cached so re-applying on focus is a no-op unless the
// user actually changed their Windows color scheme (avoids a title-bar repaint every alt-tab).
int lastTitleBarDark = -1;
void applyTitleBarTheme() {
	getHandle();
	if (curHandle == (HWND)0) return;

	// Settings > Personalization > Colors > "Choose your default Windows mode" (title bars/taskbar).
	// Missing key (older Windows) defaults to light.
	DWORD lightTheme = 1;
	DWORD sz = sizeof(lightTheme);
	RegGetValueA(HKEY_CURRENT_USER, "Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Themes\\\\Personalize",
		"SystemUsesLightTheme", RRF_RT_REG_DWORD, NULL, &lightTheme, &sz);

	int dark = (lightTheme == 0) ? 1 : 0;
	if (dark == lastTitleBarDark) return;
	lastTitleBarDark = dark;

	BOOL useDark = dark ? TRUE : FALSE;
	if (DwmSetWindowAttribute(curHandle, attributeDarkMode, &useDark, sizeof(useDark)) != S_OK)
		DwmSetWindowAttribute(curHandle, attributeDarkModeFallback, &useDark, sizeof(useDark));

	// Caption/border/text colors are intentionally left at their defaults so Windows applies the
	// user\'s "Show accent color on title bars and window borders" preference automatically.
	SetWindowPos(curHandle, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}
')
#end
class Native {
	public static function __init__():Void {
		registerDPIAware();
	}

	public static function registerDPIAware():Void {
		#if (cpp && windows)
		// DPI Scaling fix for windows
		// this shouldn't be needed for other systems
		// Credit to YoshiCrafter29 for finding this function
		untyped __cpp__('
			SetProcessDPIAware();	
			#ifdef DPI_AWARENESS_CONTEXT
			SetProcessDpiAwarenessContext(
				#ifdef DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
				DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
				#else
				DPI_AWARENESS_CONTEXT_SYSTEM_AWARE
				#endif
			);
			#endif
		');
		#end
	}

	private static var fixedScaling:Bool = false;

	public static function fixScaling():Void {
		if (fixedScaling)
			return;
		fixedScaling = true;

		#if (cpp && windows)
		final display:Null<Display> = System.getDisplay(0);
		if (display != null) {
			final dpiScale:Float = display.dpi / 96;
			@:privateAccess Application.current.window.width = Std.int(Main.game.width * dpiScale);
			@:privateAccess Application.current.window.height = Std.int(Main.game.height * dpiScale);

			Application.current.window.x = Std.int((Application.current.window.display.bounds.width - Application.current.window.width) / 2);
			Application.current.window.y = Std.int((Application.current.window.display.bounds.height - Application.current.window.height) / 2);
		}

		untyped __cpp__('
			getHandle();
			if (curHandle != (HWND)0) {
				HDC curHDC = GetDC(curHandle);
				RECT curRect;
				GetClientRect(curHandle, &curRect);
				FillRect(curHDC, &curRect, (HBRUSH)GetStockObject(BLACK_BRUSH));
				ReleaseDC(curHandle, curHDC);
			}
		');
		#end
	}

	/**
		Matches the window title bar to the user's current Windows color scheme (dark/light) and lets
		Windows apply their accent-on-title-bar preference. Safe to call repeatedly -- the native side
		no-ops unless the scheme actually changed, so it can be wired to `focusGained` for live updates.
		No-op on non-Windows (macOS/Linux decorations follow the system automatically).
	**/
	public static function applyWindowTheme():Void {
		#if (cpp && windows)
		untyped __cpp__('applyTitleBarTheme();');
		#end
	}
}
