package backend;

#if CRASH_HANDLER
import haxe.CallStack;
import haxe.io.Path;
import openfl.events.UncaughtErrorEvent;
import openfl.Lib;
import lime.app.Application;
import states.CrashState;

/**
	Central uncaught-error handler.

	Rewrites the old inline `Main.onCrash` (originally from Izzy Engine by sqirra-rng) into a
	richer, more graceful system:

	- Captures far more context than a raw stack dump: engine version, platform, the live
	  state, the current mod/song, and process memory.
	- Prefers a soft recovery ("jump over" the error) by dropping the player back onto an
	  in-engine crash screen instead of hard-killing the process, so a single bad frame no
	  longer loses the whole session. See `CrashState`.
	- Guards against crash loops: if errors keep firing faster than the player can react, it
	  stops trying to recover and falls back to the old native-alert + exit path.
	- Installs a native signal / SEH handler so *hard* crashes (a bad shader, a null handed to
	  OpenFL's C++ render path, a segfault in a native lib) that never reach OpenFL's
	  `UncaughtErrorEvent` still get a written report instead of the game vanishing silently.
	  Script activity leading up to the fault is captured because `scriptErrors` lives in static
	  memory. See `installNativeHandler`.
	- Always writes a full report to `./crash/` regardless of which path is taken.

	The presentation (buttons, "send issue" stub, recover / quit) lives in `states.CrashState`;
	this class owns detection, reporting, and the recover-vs-fatal decision.

**/
#if (cpp && windows)
@:buildXml('<target id="haxe"><lib name="advapi32.lib" if="windows"/></target>')
@:cppFileCode('
#include <windows.h>
#include <cstdio>

static ::String __crash_windows_version() {
	char buf[256]; buf[0] = 0;
	typedef LONG (WINAPI *RtlGetVersionPtr)(OSVERSIONINFOW*);
	OSVERSIONINFOW vi; ZeroMemory(&vi, sizeof(vi)); vi.dwOSVersionInfoSize = sizeof(vi);
	unsigned long major = 0, minor = 0, build = 0;
	HMODULE nt = GetModuleHandleW(L"ntdll.dll");
	if (nt) {
		RtlGetVersionPtr p = (RtlGetVersionPtr)GetProcAddress(nt, "RtlGetVersion");
		if (p && p(&vi) == 0) { major = vi.dwMajorVersion; minor = vi.dwMinorVersion; build = vi.dwBuildNumber; }
	}
	unsigned long ubr = 0, sz = sizeof(ubr);
	RegGetValueA(HKEY_LOCAL_MACHINE, "SOFTWARE\\\\Microsoft\\\\Windows NT\\\\CurrentVersion", "UBR", RRF_RT_REG_DWORD, NULL, &ubr, &sz);
	char disp[64]; disp[0] = 0; unsigned long dsz = sizeof(disp);
	RegGetValueA(HKEY_LOCAL_MACHINE, "SOFTWARE\\\\Microsoft\\\\Windows NT\\\\CurrentVersion", "DisplayVersion", RRF_RT_REG_SZ, NULL, disp, &dsz);
	int rel = (build >= 22000) ? 11 : 10;
	if (disp[0])
		snprintf(buf, sizeof(buf), "Windows %d %s (NT %lu.%lu.%lu.%lu)", rel, disp, major, minor, build, ubr);
	else
		snprintf(buf, sizeof(buf), "Windows %d (NT %lu.%lu.%lu.%lu)", rel, major, minor, build, ubr);
	return ::String(buf);
}

static char __crash_env[2048];
static char __crash_scripts[4096];
static char __crash_dir[512];

static void __crash_copy(char *dst, int cap, const char *src) {
	if (!src) { dst[0] = 0; return; }
	int i = 0;
	for (; src[i] && i < cap - 1; i++) dst[i] = src[i];
	dst[i] = 0;
}

void __crash_set_env(const char *s) { __crash_copy(__crash_env, sizeof(__crash_env), s); }
void __crash_set_scripts(const char *s) { __crash_copy(__crash_scripts, sizeof(__crash_scripts), s); }
void __crash_set_dir(const char *s) { __crash_copy(__crash_dir, sizeof(__crash_dir), s); }

static void __crash_emergency_write(unsigned long code, const char *name) {
	const char *dir = __crash_dir[0] ? __crash_dir : "./crash/";
	CreateDirectoryA(dir, NULL);

	SYSTEMTIME st; GetLocalTime(&st);
	char path[640];
	snprintf(path, sizeof(path), "%sPsychEngine_NATIVE_%04d-%02d-%02d_%02d\'%02d\'%02d.txt",
		dir, st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

	FILE *f = fopen(path, "wb");
	if (!f) return;
	fputs("Psych Engine Crash Report\\n=========================\\n\\n", f);
	char line[128];
	snprintf(line, sizeof(line), "Native Crash: Windows exception 0x%08lX (%s)\\n\\n", code, name);
	fputs(line, f);
	fputs("Emergency handler: the stack was exhausted, so this report was written without the\\n"
	      "Haxe runtime. No call stack is available -- the script history below is the best lead,\\n"
	      "and unbounded recursion in a mod script is by far the most common cause.\\n\\n", f);
	if (__crash_env[0]) { fputs(__crash_env, f); fputs("\\n", f); }
	if (__crash_scripts[0]) {
		fputs("Recent script errors (newest last):\\n", f);
		fputs(__crash_scripts, f);
		fputs("\\n", f);
	}
	fclose(f);
}

static LONG WINAPI __crash_seh_filter(EXCEPTION_POINTERS* info) {
	unsigned long code = (info && info->ExceptionRecord) ? info->ExceptionRecord->ExceptionCode : 0;
	if (code == EXCEPTION_STACK_OVERFLOW) {
		__crash_emergency_write(code, "STACK_OVERFLOW");
		return EXCEPTION_EXECUTE_HANDLER;
	}
	// Every other fault still has a usable stack, so take the full Haxe reporting path.
	::backend::CrashHandler_obj::onNativeWindowsCrash((int)code);
	return EXCEPTION_EXECUTE_HANDLER;
}

void __crash_install_native() {
	// Without this the filter has no stack left to run in after a stack overflow, and the process
	// dies completely silently. Reserves a slice for the handler on THIS thread.
	ULONG guarantee = 256 * 1024;
	SetThreadStackGuarantee(&guarantee);
	SetUnhandledExceptionFilter(__crash_seh_filter);
}
')
#end
#if (cpp && !windows)
@:cppFileCode('
#include <csignal>

static void __crash_signal_handler(int sig) {
	std::signal(sig, SIG_DFL);
	::backend::CrashHandler_obj::onNativeSignal(sig);
}

void __crash_install_native() {
	std::signal(SIGSEGV, __crash_signal_handler);
	std::signal(SIGABRT, __crash_signal_handler);
	std::signal(SIGFPE, __crash_signal_handler);
	std::signal(SIGILL, __crash_signal_handler);
	std::signal(SIGBUS, __crash_signal_handler);
}
')
#end
class CrashHandler {
	/** Where crash reports are written, relative to the working directory. **/
	public static inline var CRASH_DIR:String = "./crash/";

	/** Report an issue here. Change this if you fork the engine. **/
	public static inline var ISSUES_URL:String = "https://github.com/MeguminBOT/FNF-PsychEngine/issues";

	/**
		If this many recoveries happen inside `LOOP_WINDOW` seconds we assume the game is
		wedged in a crash loop and stop trying to recover, going straight to the fatal path.
	**/
	static inline var LOOP_LIMIT:Int = 3;

	static inline var LOOP_WINDOW:Float = 6.0;

	/** True once we are inside `onUncaughtError`, so a crash while handling a crash goes fatal. **/
	static var handling:Bool = false;

	/** True once a native fault has been caught, so a second fault while reporting dies immediately. **/
	static var nativeCrashed:Bool = false;

	static var nativeInstalled:Bool = false;

	/** Absolute path of the report written by the most recent crash (for the crash screen). **/
	public static var lastReportPath:String = "";

	/** Full text of the most recent crash report (for clipboard / send-issue). **/
	public static var lastReport:String = "";

	static var recentCrashes:Int = 0;
	static var lastCrashTime:Float = -1000;

	/**
		Environment block (OS + build, architecture, form factor, CPU count, display, locale),
		gathered once at startup while the app is healthy and cached so the crash path,
		native faults included, only has to embed a string. 
		Every value here is machine-generic and holds nothing that identifies the user.
	**/
	static var systemInfo:String = "";

	/**
		Ring buffer of recent non-fatal script errors (HScript / hscript-insanity and LuaProxy),
		newest last. These are caught and don't kill the game on their own, but a bad script
		frequently corrupts state that hard-crashes later,
		so we fold the recent history into every crash report as context. 
		Fed by `reportScriptError`.
	**/
	static final scriptErrors:Array<String> = [];

	static inline var MAX_SCRIPT_ERRORS:Int = 12;

	/** Wire the handler into OpenFL. Call once from `Main`. **/
	public static function init():Void {
		collectSystemInfo();
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#if cpp
		installNativeHandler();
		#end
	}

	/** Gather the machine-generic environment block once, at healthy startup. **/
	static function collectSystemInfo():Void {
		final buf:StringBuf = new StringBuf();

		buf.add("OS:        " + osLabel() + "\n");
		buf.add("Arch:      " + archLabel() + "\n");
		buf.add("Form:      " + formFactor() + "\n");
		buf.add("CPUs:      " + safe(() -> {
			final n:String = Sys.getEnv("NUMBER_OF_PROCESSORS");
			return (n != null && n.length > 0) ? n : "(n/a)";
		}) + "\n");
		buf.add("Display:   " + displayLabel() + "\n");
		buf.add("Language:  " + safe(() -> {
			final l:String = ClientPrefs.data.language;
			return (l != null && l.length > 0) ? l : "(default)";
		}) + "\n");

		systemInfo = buf.toString();
		pushNativeEnv();
	}

	/**
		Mirror the cached context into the C-side emergency buffers. Those are the only thing the
		stack-overflow path can use, since it must not re-enter the Haxe runtime.
	**/
	static inline function pushNativeEnv():Void {
		#if (cpp && windows)
		untyped __cpp__('__crash_set_env({0}.utf8_str())', systemInfo);
		untyped __cpp__('__crash_set_dir({0}.utf8_str())', (CRASH_DIR : String));
		#end
	}

	static inline function pushNativeScripts():Void {
		#if (cpp && windows)
		untyped __cpp__('__crash_set_scripts({0}.utf8_str())', scriptErrors.join("\n"));
		#end
	}

	static function osLabel():String {
		return safe(() -> {
			#if (cpp && windows)
			final w:String = windowsVersion();
			if (w != null && w.length > 0)
				return w;
			#end
			var name:String = lime.system.System.platformName;
			if (name == null || name.length == 0)
				name = Sys.systemName();
			final ver:String = lime.system.System.platformVersion;
			return (ver != null && ver.length > 0) ? (name + " " + ver) : name;
		});
	}

	#if (cpp && windows)
	static function windowsVersion():String {
		var s:String = "";
		try
			s = untyped __cpp__('__crash_windows_version()')
		catch (_:Dynamic)
			s = "";
		return s;
	}
	#end

	static inline function archLabel():String {
		return #if HXCPP_ARM64
			"arm64"
		#elseif HXCPP_ARMV7
			"armv7"
		#elseif hxcpp_arm64
			"arm64"
		#elseif HXCPP_M64
			"x86_64"
		#elseif HXCPP_X86_64
			"x86_64"
		#elseif cpp
			"x86"
		#else
			"(managed)"
		#end;
	}

	static inline function formFactor():String {
		return #if mobile "Mobile" #elseif desktop "Desktop" #else "Unknown" #end;
	}

	static function displayLabel():String {
		return safe(() -> {
			final count:Int = lime.system.System.numDisplays;
			final d:lime.system.Display = lime.system.System.getDisplay(0);
			if (d == null || d.currentMode == null)
				return count > 0 ? (count + " display(s)") : "(unknown)";
			final m:lime.system.DisplayMode = d.currentMode;
			final res:String = m.width + "x" + m.height + (m.refreshRate > 0 ? " @ " + m.refreshRate + "Hz" : "");
			return res + (count > 1 ? " (" + count + " displays)" : "");
		});
	}

	#if cpp
	/**
		Install a native crash handler so segfaults / access violations that never surface as a
		Haxe exception (so OpenFL's `UncaughtErrorEvent` never fires) still produce a report.

		Windows uses a top-level SEH filter; POSIX (Linux/macOS/Android/iOS) traps the fatal
		signals. A native fault means memory is already suspect, so these paths only WRITE a
		report and terminate, they never try the in-engine recovery screen. Report building
		still runs (best-effort) because the process is going down regardless, and the recent
		script-error history it prints is usually the actual culprit.
	**/
	static function installNativeHandler():Void {
		if (nativeInstalled)
			return;
		nativeInstalled = true;

		try
			untyped __cpp__('__crash_install_native()')
		catch (_:Dynamic) {}
	}

	#if windows
	/**
		Entry point called by the C++ SEH filter. `@:keep` is required: nothing in Haxe calls
		this, so DCE would otherwise strip it and the generated C++ would not link.
	**/
	@:keep public static function onNativeWindowsCrash(code:Int):Void {
		onNativeCrash('Windows exception 0x' + StringTools.hex(code, 8) + winExceptionName(code));
	}

	static function winExceptionName(code:Int):String {
		return switch (code) {
			case 0xC0000005: " (ACCESS_VIOLATION)";
			case 0xC00000FD: " (STACK_OVERFLOW)";
			case 0xC000001D: " (ILLEGAL_INSTRUCTION)";
			case 0xC0000094: " (INTEGER_DIVIDE_BY_ZERO)";
			case 0xC0000090: " (FLOAT_INVALID_OPERATION)";
			default: "";
		}
	}
	#else

	/**
		Entry point called by the C++ signal trap (which has already reset the signal to its
		default). `@:keep` is required: nothing in Haxe calls this, so DCE would otherwise strip
		it and the generated C++ would not link.
	**/
	@:keep public static function onNativeSignal(sig:Int):Void {
		onNativeCrash('Fatal signal ' + sig + posixSignalName(sig));
	}

	static function posixSignalName(sig:Int):String {
		return switch (sig) {
			case 11: " (SIGSEGV)";
			case 6: " (SIGABRT)";
			case 8: " (SIGFPE)";
			case 4: " (SIGILL)";
			case 7, 10: " (SIGBUS)";
			default: "";
		}
	}
	#end

	static function onNativeCrash(reason:String):Void {
		// A fault while we're already reporting one: bail out hard, no more Haxe work.
		if (nativeCrashed || handling) {
			try
				Sys.stderr().writeString("Double fault during crash reporting: " + reason + "\n")
			catch (_:Dynamic) {}
			Sys.exit(1);
			return;
		}
		nativeCrashed = true;
		handling = true;

		final text:String = try buildReport("Native Crash", reason, safeCallStack()) catch (_:Dynamic) ("Native Crash: " + reason);
		lastReport = text;
		saveReport(text);
		try
			Sys.println(text)
		catch (_:Dynamic) {}

		fatal(text);
	}

	static function safeCallStack():Array<StackItem> {
		try {
			return CallStack.callStack();
		} catch (_:Dynamic) {
			return [];
		}
	}
	#end

	/**
		Record a non-fatal script error so it appears in the next crash report. 
		Safe to call from anywhere (scripting hot paths included)
		it only trims a small ring buffer and never switches state or blocks.

		@param source short origin tag, e.g. "HScript" or "LuaProxy"
		@param message the already-formatted error text
	**/
	public static function reportScriptError(source:String, message:String):Void {
		final stamp:String = try DateTools.format(Date.now(), "%H:%M:%S") catch (_:Dynamic) "";
		scriptErrors.push((stamp.length > 0 ? stamp + " " : "") + "[" + source + "] " + message);
		while (scriptErrors.length > MAX_SCRIPT_ERRORS)
			scriptErrors.shift();
		pushNativeScripts();
	}

	static function onUncaughtError(e:UncaughtErrorEvent):Void {
		if (handling) {
			fatal(lastReport.length > 0 ? lastReport : Std.string(e.error));
			return;
		}
		handling = true;

		// Stop OpenFL from rethrowing (which would kill the process before we can recover).
		try
			e.preventDefault()
		catch (_:Dynamic) {}

		final report:String = buildReport("Uncaught Error", e.error);
		lastReport = report;
		saveReport(report);

		Sys.println(report);
		if (lastReportPath.length > 0)
			Sys.println("Crash report saved to " + lastReportPath);

		#if DISCORD_ALLOWED
		try
			DiscordClient.shutdown()
		catch (_:Dynamic) {}
		#end

		final now:Float = haxe.Timer.stamp();
		if (now - lastCrashTime < LOOP_WINDOW)
			recentCrashes++;
		else
			recentCrashes = 1;
		lastCrashTime = now;

		final loopedOut:Bool = recentCrashes >= LOOP_LIMIT;

		if (!loopedOut && tryShowCrashScreen(report, e.error)) {
			handling = false;
			return;
		}

		fatal(report);
	}

	/**
		Attempt to swap to the in-engine `CrashState`. Returns false if the runtime is too far
		gone to safely switch states, in which case the caller falls back to `fatal`.
	**/
	static function tryShowCrashScreen(report:String, error:Dynamic):Bool {
		#if mobile
		#if android
		try
			extension.androidtools.widget.Toast.makeText('Crashed -- report saved to crash/', extension.androidtools.widget.Toast.LENGTH_LONG)
		catch (_:Dynamic) {}
		#end
		#end

		if (FlxG.game == null)
			return false;

		try {
			// Skip the fade transition; the state that would run it may be the one that just died.
			flixel.addons.transition.FlxTransitionableState.skipNextTransIn = true;
			flixel.addons.transition.FlxTransitionableState.skipNextTransOut = true;
			FlxG.switchState(new CrashState(report, Std.string(error)));
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	/** Classic path: show a blocking native alert (desktop) and terminate. **/
	public static function fatal(report:String):Void {
		#if !mobile
		try
			Application.current.window.alert(report, "Fatal Error")
		catch (_:Dynamic) {}
		#end
		Sys.exit(1);
	}

	/** Send the current crash report to the issue tracker. STUB: not wired up yet. **/
	public static function sendIssue():Bool {
		// TODO: real implementation
		// gather `lastReport`, POST to a collector or open a
		// prefilled GitHub issue, respecting user consent. For now this only points people
		// at the tracker so the UI has something to hang off of.
		return false;
	}

	/** Open the crash folder in the platform file browser. Desktop only; best-effort. **/
	public static function openCrashFolder():Void {
		#if desktop
		final dir:String = Path.normalize(Sys.getCwd() + "/" + CRASH_DIR);
		try {
			#if windows
			Sys.command("explorer", [dir]);
			#elseif mac
			Sys.command("open", [dir]);
			#elseif linux
			Sys.command("xdg-open", [dir]);
			#end
		} catch (_:Dynamic) {}
		#end
	}

	static function saveReport(report:String):Void {
		var dateNow:String = Date.now().toString();
		dateNow = dateNow.replace(" ", "_");
		dateNow = dateNow.replace(":", "'");

		var path:String = CRASH_DIR + "PsychEngine_" + dateNow + ".txt";
		try {
			if (!FileSystem.exists(CRASH_DIR))
				FileSystem.createDirectory(CRASH_DIR);

			// The stamp only resolves to the second, and a crash cascade (the teardown of a
			// half-built state faulting again) writes several reports inside that second. Without
			// a uniquifier the follow-up ones overwrite the FIRST report, which is the only one
			// that names the original fault.
			var dupe:Int = 1;
			while (FileSystem.exists(path) && dupe < 100) {
				dupe++;
				path = CRASH_DIR + "PsychEngine_" + dateNow + "_" + dupe + ".txt";
			}

			File.saveContent(path, report + "\n");
			lastReportPath = Path.normalize(path);
		} catch (_:Dynamic) {
			lastReportPath = "";
		}
	}

	/**
		Build the full crash report. Every context lookup is wrapped so that a failure gathering
		diagnostics can never mask (or crash on top of) the original error.
	**/
	static function buildReport(label:String, error:Dynamic, ?stack:Array<StackItem>):String {
		final buf:StringBuf = new StringBuf();

		buf.add("Psych Engine Crash Report\n");
		buf.add("=========================\n\n");

		buf.add("Time:      " + Date.now().toString() + "\n");
		buf.add("Engine:    " + safe(() -> "v" + states.MainMenuState.psychEngineVersion) + "\n");
		buf.add(systemInfo.length > 0 ? systemInfo : ("OS:        " + platformLabel() + "\n"));
		buf.add("State:     " + safe(() -> FlxG.state == null ? "(none)" : Type.getClassName(Type.getClass(FlxG.state))) + "\n");
		buf.add("Mod:       " + safe(() -> {
			final m:String = backend.Mods.currentModDirectory;
			return (m == null || m.length == 0) ? "(none)" : m;
		}) + "\n");
		buf.add("Song:      " + currentSong() + "\n");
		buf.add("Memory:    " + memoryLabel() + "\n\n");

		buf.add(label + ": " + Std.string(error) + "\n");

		final exMsg:String = safe(() -> {
			final ex:Dynamic = (error is haxe.Exception) ? cast(error, haxe.Exception) : null;
			return ex == null ? "" : (ex.message == null ? "" : Std.string(ex.message));
		});
		if (exMsg.length > 0 && exMsg != Std.string(error))
			buf.add("Message: " + exMsg + "\n");

		if (scriptErrors.length > 0) {
			buf.add("\nRecent script errors (newest last):\n");
			for (line in scriptErrors)
				buf.add("  " + line + "\n");
		}

		buf.add("\nCall Stack:\n");
		buf.add(formatStack(stack != null ? stack : CallStack.exceptionStack(true)));

		buf.add("\nPlease report this error to the GitHub page: " + ISSUES_URL + "\n");
		buf.add("\n> Crash handler based on work by sqirra-rng (Izzy Engine)\n");

		return buf.toString();
	}

	static function formatStack(stack:Array<StackItem>):String {
		if (stack == null || stack.length == 0)
			return "  (no stack available)\n";

		final buf:StringBuf = new StringBuf();
		for (item in stack) {
			switch (item) {
				case FilePos(_, file, line, _):
					buf.add("  " + file + " (line " + line + ")\n");
				case Method(className, method):
					buf.add("  " + className + "." + method + "\n");
				case Module(m):
					buf.add("  module " + m + "\n");
				case LocalFunction(v):
					buf.add("  local function #" + v + "\n");
				case CFunction:
					buf.add("  (native function)\n");
			}
		}
		return buf.toString();
	}

	static inline function platformLabel():String {
		return #if windows "Windows" #elseif mac "macOS" #elseif linux "Linux" #elseif android "Android" #elseif ios "iOS" #else "Unknown" #end;
	}

	static function currentSong():String {
		return safe(() -> {
			if (!(FlxG.state is states.PlayState))
				return "(not in gameplay)";
			final song:Dynamic = states.PlayState.SONG;
			if (song == null || song.song == null)
				return "(unknown)";
			return Std.string(song.song) + " [" + backend.Difficulty.getString() + "]";
		});
	}

	static function memoryLabel():String {
		return safe(() -> {
			final bytes:Float = openfl.system.System.totalMemory;
			return Std.string(Math.round(bytes / 1024 / 1024)) + " MB";
		});
	}

	/** Run a diagnostic getter, swallowing any failure so report building never crashes. **/
	static inline function safe(fn:Void->String):String {
		var out:String;
		try
			out = fn()
		catch (_:Dynamic)
			out = "(unavailable)";
		return out;
	}
}
#end
