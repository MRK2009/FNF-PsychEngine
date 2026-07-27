package scripting;

import flixel.FlxG;
import flixel.util.FlxColor;

/**
	The one place a script failure is reported.

	Before this, three paths existed and disagreed. `FunkinLua.luaTrace` only reached the screen
	when the script itself had set `luaDebugMode`, so a Lua runtime error was invisible by default
	and never reached the log file at all; `HScript.error` traced and fed the crash handler;
	`trace` reached the console and nothing else. Every one of them also assumed `PlayState.instance`
	existed, which stops being true as soon as scripts run in menus.
**/
class ScriptError {
	/** A failure. Always reported, whatever the script's debug settings say. **/
	public static inline function error(source:String, message:String):Void
		report(source, 'ERROR', message, FlxColor.RED);

	/** Something suspicious but survivable. **/
	public static inline function warn(source:String, message:String):Void
		report(source, 'WARNING', message, FlxColor.YELLOW);

	/**
		Reports a script failure to the debug console, the log file, the crash handler and the
		on-screen overlay.

		@param source Which language or subsystem produced it, for the console line.
		@param level `ERROR`, `WARNING`, `FATAL`. Errors and fatals are kept as crash context.
		@param message The already-formatted message, position included.
		@param color Overlay colour.
	**/
	public static function report(source:String, level:String, message:String, color:FlxColor):Void {
		trace('$level: $message');

		#if CRASH_HANDLER
		if (level == 'ERROR' || level == 'FATAL')
			backend.CrashHandler.reportScriptError(source, message);
		#end

		show('$level: $message', color);
	}

	/**
		Puts a line on the in-game debug overlay, if there is one.

		Whatever state is active, not just `PlayState` -- every `MusicBeatState` has the overlay,
		and scripts reach menus now. A state that is neither leaves the console line as the record.
	**/
	public static function show(message:String, color:FlxColor = FlxColor.WHITE):Void {
		var state:flixel.FlxState = FlxG.state;
		if (state != null && (state is backend.MusicBeatState)) {
			cast(state, backend.MusicBeatState).addTextToDebug(message, color);
			return;
		}

		if (states.PlayState.instance != null)
			states.PlayState.instance.addTextToDebug(message, color);
	}
}
