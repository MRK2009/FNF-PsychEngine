package editors.charting.script;

import editors.ChartingState;
#if HSCRIPT_ALLOWED
import scripting.hscript.HScript;
#end

/**
	Loads and dispatches chart-editor scripts from `scripts/charteditor/*.lua|*.hx` (mods +
	shared). Lua runs in raw LuaProxy mode ONLY (see `EditorLuaScript`); `.hx` uses the
	standard `scripting.hscript.HScript` host. Both receive the `editor` (ChartingState) and `api`
	(`EditorScriptAPI`) globals.

	Hooks (fired at mutation points, never per-frame unless opted in):
	- `onEditorCreate()` - editor booted, scripts loaded
	- `onChartLoaded(songName)` - chart adopted (boot, New, Open, autosave)
	- `onNotePlaced(time, column, strumLine)` / `onNoteDeleted(time, column, strumLine)`
	- `onNoteMoved(time, column, strumLine)`
	- `onEventPlaced(time, name)` / `onEventDeleted(time)`
	- `onSectionChanged(section)`
	- `onSelectionChanged(count)`
	- `onPlaybackToggled(playing)`
	- `onSave(path)`
	- `onEditorUpdate(elapsed)` - ONLY after `api.enableUpdateHook()`
	- `onEditorDestroy()`

	`call` is a zero-cost no-op while no scripts are loaded - guard argument-array
	construction at call sites with `hasScripts`.
**/
final class EditorScriptHost {
	#if LUA_ALLOWED
	final luaScripts:Array<EditorLuaScript> = [];
	#end
	#if HSCRIPT_ALLOWED
	final hxScripts:Array<HScript> = [];
	#end

	/** `true` once any script loaded - the cheap guard for hook call sites. **/
	public var hasScripts(default, null):Bool = false;

	/** Set via `api.enableUpdateHook()`; gates `onEditorUpdate`. **/
	public var updateHookEnabled:Bool = false;

	/** The stable facade handed to every script as the `api` global. **/
	public final api:EditorScriptAPI;

	final editor:ChartingState;

	/**
		@param editor the owning editor state (exposed to scripts as `editor`)
	**/
	public function new(editor:ChartingState) {
		this.editor = editor;
		api = new EditorScriptAPI(editor, this);
	}

	/** Enumerates and boots every `scripts/charteditor/` script. **/
	public function loadAll():Void {
		#if (MODS_ALLOWED && sys)
		for (directory in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/charteditor/')) {
			if (!sys.FileSystem.exists(directory))
				continue;
			for (file in sys.FileSystem.readDirectory(directory)) {
				var path:String = haxe.io.Path.join([directory, file.trim()]);
				if (sys.FileSystem.isDirectory(path))
					continue;
				#if LUA_ALLOWED
				if (file.endsWith('.lua')) {
					var script:EditorLuaScript = new EditorLuaScript(path, [{name: 'editor', value: editor}, {name: 'api', value: api}]);
					if (!script.closed)
						luaScripts.push(script);
					continue;
				}
				#end
				#if HSCRIPT_ALLOWED
				if (file.endsWith('.hx'))
					loadHScript(path);
				#end
			}
		}
		#end
		hasScripts = false;
		#if LUA_ALLOWED
		hasScripts = luaScripts.length > 0;
		#end
		#if HSCRIPT_ALLOWED
		if (hxScripts.length > 0)
			hasScripts = true;
		#end
	}

	#if HSCRIPT_ALLOWED
	function loadHScript(path:String):Void {
		#if MODS_ALLOWED
		var myFolder:Array<String> = path.split('/');
		if (myFolder[0] + '/' == Paths.mods()
			&& (Mods.currentModDirectory == myFolder[1] || Mods.getGlobalMods().contains(myFolder[1]))
			&& backend.ModSecurity.isBlocked(myFolder[1])) {
			trace('EditorScriptHost: blocked $path -- mod not trusted');
			return;
		}
		#end
		try {
			var script:HScript = new HScript(null, path, {editor: editor, api: api});
			hxScripts.push(script);
			trace('editor hscript loaded: $path');
		} catch (e:Dynamic)
			trace('EditorScriptHost: error loading $path: $e');
	}
	#end

	/** Fires a hook on every loaded script (no-op while scriptless). **/
	public function call(name:String, args:Array<Dynamic>):Void {
		if (!hasScripts)
			return;
		#if LUA_ALLOWED
		var i:Int = 0;
		while (i < luaScripts.length) {
			luaScripts[i].call(name, args);
			i++;
		}
		#end
		#if HSCRIPT_ALLOWED
		var j:Int = 0;
		while (j < hxScripts.length) {
			var hs:HScript = hxScripts[j];
			if (hs.exists(name))
				hs.call(name, args);
			j++;
		}
		#end
	}

	/** Per-frame hook, gated on the opt-in flag. **/
	public inline function callUpdate(elapsed:Float):Void {
		if (updateHookEnabled && hasScripts)
			call('onEditorUpdate', [elapsed]);
	}

	/** Fires `onEditorDestroy` then stops and drops every script. **/
	public function destroy():Void {
		call('onEditorDestroy', []);
		#if LUA_ALLOWED
		var i:Int = luaScripts.length;
		while (--i >= 0)
			luaScripts[i].stop();
		luaScripts.resize(0);
		#end
		#if HSCRIPT_ALLOWED
		var j:Int = hxScripts.length;
		while (--j >= 0)
			hxScripts[j].destroy();
		hxScripts.resize(0);
		#end
		hasScripts = false;
	}
}
