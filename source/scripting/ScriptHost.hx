package scripting;

#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
import backend.Mods;
import backend.Paths;
import flixel.FlxG;
import psychlua.LuaUtils;
#if LUA_ALLOWED
import psychlua.FunkinLua;
#end
#if HSCRIPT_ALLOWED
import psychlua.HScript;
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end
using StringTools;

/**
	Owns the scripts belonging to one state: the two script arrays, the load-order scan, hook
	dispatch, variable broadcast and teardown.

	All of this lived on `PlayState`, which is why nothing but gameplay could run a script -- a mod
	that wanted anything in a menu had to write a whole scripted state. A host belongs to any
	`MusicBeatState`, so `scripts/global/` runs everywhere while `scripts/` stays gameplay-only.

	`current` is what a `FunkinLua` or `HScript` registers itself into when it is constructed,
	replacing the hard reference to `PlayState.instance` those constructors used to make.
**/
class ScriptHost {
	/** The host of the state being created or updated right now. **/
	public static var current(default, null):ScriptHost = null;

	/** The state these scripts belong to. **/
	public var owner:flixel.FlxState;

	/**
		Whether the owning state drives the lifecycle hooks itself.

		`PlayState` dispatches `onCreate`/`onUpdate`/`onDestroy` at exact points in its own frame,
		so it turns this off; a menu lets `MusicBeatState` do it.
	**/
	public var autoDispatch:Bool = true;

	#if LUA_ALLOWED
	public var luaArray:Array<FunkinLua> = [];

	/**
		Names this host's scripts registered through `createGlobalCallback`.

		`FunkinLua.customFunctions` is one global registry shared by every host, and teardown used to
		`clear()` it outright -- so a host dying took every OTHER live host's global callbacks with
		it. Now that `scripts/global/` gives every state a host, that is a real collision.
	**/
	var ownedGlobalCallbacks:Array<String> = [];

	/** Publishes a global callback and remembers it, so teardown removes only what this host added. **/
	public function registerGlobalCallback(name:String, func:Dynamic):Void {
		if (!ownedGlobalCallbacks.contains(name))
			ownedGlobalCallbacks.push(name);

		FunkinLua.customFunctions.set(name, func);
	}
	#end
	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	public function new(owner:flixel.FlxState) {
		this.owner = owner;
		current = this;
	}

	/**
		Whether this host has anything to dispatch to.

		Lets a per-frame caller skip the hook entirely rather than walking two empty arrays, which is
		the common case: every state has a host now, and almost none of them have scripts.
	**/
	public inline function hasScripts():Bool {
		#if LUA_ALLOWED
		if (luaArray != null && luaArray.length > 0)
			return true;
		#end
		#if HSCRIPT_ALLOWED
		if (hscriptArray != null && hscriptArray.length > 0)
			return true;
		#end
		return false;
	}

	/**
		Loads every script in `folder` from every mod that has one, in load order.

		@param folder Path relative to a mod root, ending in `/` (`scripts/`, `scripts/global/`).
	**/
	public function loadFolder(folder:String):Void {
		#if sys
		for (dir in Mods.directoriesWithFile(Paths.getSharedPath(), folder))
			for (file in getScriptLoadOrder(dir)) {
				var lower:String = file.toLowerCase();
				#if LUA_ALLOWED
				if (lower.endsWith('.lua'))
					new FunkinLua(dir + file);
				#end
				#if HSCRIPT_ALLOWED
				if (lower.endsWith('.hx'))
					initHScript(dir + file);
				#end
			}
		#end
	}

	/**
		Returns the files in a `scripts/` folder in load order.

		If the folder contains an order file -- `_order.txt` (checked first) or
		`_loadorder.txt` -- the script filenames listed in it load FIRST, in that
		exact order; every other file follows in the normal filesystem order. Blank
		lines and lines starting with `#` or `//` are ignored, matching is
		case-insensitive, and listed names that don't exist are skipped with a warning.

		With no order file present, the filesystem order is returned unchanged, so
		existing mods are unaffected.
	**/
	public static function getScriptLoadOrder(folder:String):Array<String> {
		#if sys
		var files:Array<String> = FileSystem.readDirectory(folder);

		var orderPath:String = folder + '_order.txt';
		if (!FileSystem.exists(orderPath)) {
			orderPath = folder + '_loadorder.txt';
			if (!FileSystem.exists(orderPath))
				return files; // no override -> keep filesystem order
		}

		// lowercase filename -> actual filename, for case-insensitive matching
		var lookup:Map<String, String> = new Map();
		for (file in files)
			lookup.set(file.toLowerCase(), file);

		var ordered:Array<String> = [];
		var used:Map<String, Bool> = new Map();
		for (rawLine in File.getContent(orderPath).split('\n')) {
			var line:String = rawLine.trim();
			if (line.length == 0 || line.startsWith('#') || line.startsWith('//'))
				continue;

			var actual:String = lookup.get(line.toLowerCase());
			if (actual == null) {
				FlxG.log.warn('Script load order: "$line" listed in $orderPath was not found in $folder');
				continue;
			}
			if (!used.exists(actual)) {
				ordered.push(actual);
				used.set(actual, true);
			}
		}

		// everything not explicitly ordered keeps its filesystem position
		for (file in files)
			if (!used.exists(file))
				ordered.push(file);

		return ordered;
		#else
		return [];
		#end
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String):Bool {
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if (!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if (FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if (openfl.utils.Assets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if (script.scriptName == luaToLoad)
					return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String):Bool {
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if (!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		#if sys
		if (FileSystem.exists(scriptToLoad)) {
			if (HScript.instances.exists(scriptToLoad))
				return false;

			initHScript(scriptToLoad);
			return true;
		}
		#end
		return false;
	}

	public function initHScript(file:String):Void {
		// insanity.Script reports parse/exec errors through HScript's static
		// loggers instead of throwing, so we check `failed` rather than catch.
		var newScript:HScript = new HScript(null, file);
		if (newScript.failed) {
			newScript.destroy();
			return;
		}
		if (!newScript.blocked) {
			newScript.call(ScriptHooks.CREATE);
			trace('initialized hscript interp successfully: $file');
		}
		hscriptArray.push(newScript);
	}
	#end

	/**
		Whether `value` should be ignored as a hook result.

		`Function_Continue` is always ignored, whatever the caller passed: it means "nothing to say",
		and letting a caller's own `excludeValues` list omit it used to be worked around by pushing
		it onto that caller's array, mutating something documented as immutable.
	**/
	static inline function isExcluded(value:Dynamic, control:Int, excludeValues:Array<Dynamic>):Bool {
		return value == null
			|| control == LuaUtils.CONTROL_CONTINUE
			|| (excludeValues.length > 0 && excludeValues.contains(value));
	}

	// Read-only sentinels so per-call default arguments don't allocate.
	// Anything assigned EMPTY_EXCLUSIONS / DEFAULT_EXCLUDE_VALUES must NOT be mutated.
	public static final EMPTY_EXCLUSIONS:Array<String> = [];
	public static final DEFAULT_EXCLUDE_VALUES:Array<Dynamic> = [LuaUtils.Function_Continue];

	/**
		Dispatches a hook to every script, Lua and HScript alike.

		Both languages always run. Lua returning a value used to skip the HScript pass entirely,
		so a single Lua script returning something meant no HScript in the mod ever saw the event.
		Stopping is now per-language: `Function_StopLua` ends the Lua pass, `Function_StopHScript`
		the HScript pass, `Function_StopAll` both, and `Function_Stop` cancels the engine's action
		and skips the other language. The last non-excluded value still wins.
	**/
	public function call(funcToCall:String, args:Array<Dynamic> = null, ignoreStops:Bool = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		// `args` stays null rather than becoming `[]`. Most hooks take no arguments and most scripts
		// implement none of them, so materialising an empty array here allocated once per hook per
		// frame for dispatches that then found nothing to call. Both language passes take null.
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		if (excludeValues == null)
			excludeValues = DEFAULT_EXCLUDE_VALUES;

		var luaValue:Dynamic = callLua(funcToCall, args, ignoreStops, exclusions, excludeValues);
		var control:Int = LuaUtils.controlOf(luaValue);

		if (!ignoreStops
			&& (control == LuaUtils.CONTROL_STOP || control == LuaUtils.CONTROL_STOP_ALL)
			&& !isExcluded(luaValue, control, excludeValues))
			return luaValue;

		var hscriptValue:Dynamic = callHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if (!isExcluded(hscriptValue, LuaUtils.controlOf(hscriptValue), excludeValues))
			return hscriptValue;

		return luaValue;
	}

	public function callLua(funcToCall:String, args:Array<Dynamic> = null, ignoreStops:Bool = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		if (excludeValues == null)
			excludeValues = DEFAULT_EXCLUDE_VALUES;

		var arr:Array<FunkinLua> = null;
		for (script in luaArray) {
			if (script.closed) {
				if (arr == null)
					arr = [];
				arr.push(script);
				continue;
			}

			if (exclusions.length > 0 && exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			var control:Int = LuaUtils.controlOf(myValue);
			var counts:Bool = !isExcluded(myValue, control, excludeValues);

			if (counts)
				returnVal = myValue;

			if (script.closed) {
				if (arr == null)
					arr = [];
				arr.push(script);
			}

			if (counts && !ignoreStops && (control == LuaUtils.CONTROL_STOP_LUA || control == LuaUtils.CONTROL_STOP_ALL))
				break;
		}

		if (arr != null)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callHScript(funcToCall:String, args:Array<Dynamic> = null, ignoreStops:Bool = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;

		#if HSCRIPT_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		if (excludeValues == null)
			excludeValues = DEFAULT_EXCLUDE_VALUES;

		if (hscriptArray.length < 1)
			return returnVal;

		for (script in hscriptArray) {
			if (script == null || (exclusions.length > 0 && exclusions.contains(script.origin)))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			var control:Int = LuaUtils.controlOf(myValue);
			if (isExcluded(myValue, control, excludeValues))
				continue;

			returnVal = myValue;

			if (!ignoreStops && (control == LuaUtils.CONTROL_STOP_HSCRIPT || control == LuaUtils.CONTROL_STOP_ALL))
				break;
		}
		#end

		return returnVal;
	}

	public function set(variable:String, arg:Dynamic, exclusions:Array<String> = null):Void {
		setLua(variable, arg, exclusions);
		setHScript(variable, arg, exclusions);
	}

	public function setLua(variable:String, arg:Dynamic, exclusions:Array<String> = null):Void {
		#if LUA_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		for (script in luaArray) {
			if (exclusions.length > 0 && exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null):Void {
		#if HSCRIPT_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		for (script in hscriptArray) {
			if (exclusions.length > 0 && exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	/** Runs `onDestroy` everywhere, then tears every script down. **/
	public function destroy():Void {
		#if LUA_ALLOWED
		if (luaArray != null) {
			for (lua in luaArray) {
				lua.call(ScriptHooks.DESTROY);
				lua.stop();
			}
			luaArray = null;
		}
		for (name in ownedGlobalCallbacks)
			FunkinLua.customFunctions.remove(name);
		ownedGlobalCallbacks.resize(0);
		#end

		#if HSCRIPT_ALLOWED
		if (hscriptArray != null) {
			for (script in hscriptArray)
				if (script != null) {
					script.call(ScriptHooks.DESTROY);
					script.destroy();
				}
			hscriptArray = null;
		}
		#end

		if (current == this)
			current = null;
		owner = null;
	}
}
#end
