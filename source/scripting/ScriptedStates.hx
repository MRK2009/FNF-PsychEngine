package scripting;

#if HSCRIPT_ALLOWED
import flixel.FlxState;
import flixel.FlxSubState;
import backend.MusicBeatState;
import backend.MusicBeatSubstate;
import insanity.Module;
import insanity.Environment;
import insanity.backend.types.Scripted.InsanityScriptedClass;
import insanity.backend.types.Scripted.IInsanityType;
import backend.Mods;
import backend.Mods.StateSourceMode;
import psychlua.HScript;
import psychlua.HScript.HScriptInfos;

// Which folders a scripted state may be resolved from.
enum ResolveScope {
	ANY; // current mod -> global mods -> shared (default, for explicit switchToState)
	LAUNCHED; // the launched mod only (From Mod overrides)
	GLOBALS; // global/scriptpack mods + shared (Global Script overrides)
}
#end

/**
 * Loads and instantiates class-based scripted states/substates written with
 * hscript-insanity.
 *
 * A scripted state lives in `states/<Name>.hx` (inside a mod folder or the
 * shared assets) and must declare a class named exactly `<Name>` that extends
 * `ScriptedMusicBeatState` (or `ScriptedMusicBeatSubstate` for substates):
 *
 *     // states/MyMenu.hx
 *     class MyMenu extends ScriptedMusicBeatState {
 *         override function create() { super.create(); ... }
 *     }
 *
 * Then from Lua/HScript or engine code:
 *
 *     switchToState('MyMenu');          // replaces the current state
 *     openScriptedSubstate('MyPause');  // opens a substate over it
 */
class ScriptedStates {
	#if HSCRIPT_ALLOWED
	// The scriptable bridges are only ever created reflectively (through the
	// insanity scripted-class registry), so nothing references them as types.
	// This forces them to be typed -- which runs their @:autoBuild macro and
	// registers them as extendable scripted classes. Without it the bridges
	// would be invisible to `extends ScriptedMusicBeatState` in scripts.
	@:keep static var __forceTyping:Array<Class<Dynamic>> = [ScriptedMusicBeatState, ScriptedMusicBeatSubstate];

	/**
	 * Builds a live `MusicBeatState` from `states/<name>.hx`.
	 * Returns null (and logs to the debug console) if the script is missing,
	 * fails to parse, or doesn't declare a matching scripted-state class.
	 */
	public static function loadState(name:String, ?args:Array<Dynamic>, scope:ResolveScope = ANY):MusicBeatState {
		var inst:Dynamic = instantiate('states/', name, args, scope);
		if (inst == null)
			return null;
		if (!(inst is MusicBeatState)) {
			HScript.error('Scripted state "$name" must extend ScriptedMusicBeatState', errPos(name));
			return null;
		}
		return cast inst;
	}

	/** Builds a live `MusicBeatSubstate` from `substates/<name>.hx`. */
	public static function loadSubstate(name:String, ?args:Array<Dynamic>):MusicBeatSubstate {
		var inst:Dynamic = instantiate('substates/', name, args);
		if (inst == null)
			return null;
		if (!(inst is MusicBeatSubstate)) {
			HScript.error('Scripted substate "$name" must extend ScriptedMusicBeatSubstate', errPos(name));
			return null;
		}
		return cast inst;
	}

	/** Loads `states/<name>.hx` and switches to it. */
	public static function switchToState(name:String, ?args:Array<Dynamic>, scope:ResolveScope = ANY):Bool {
		var state:MusicBeatState = loadState(name, args, scope);
		if (state == null)
			return false;
		MusicBeatState.switchState(state);
		return true;
	}

	// ── Core-state override system ────────────────────────────────────────────
	// Core engine menus that may NEVER be overridden by a mod, so the user can
	// always reach the mods menu (and from there exit a launched mod).
	static final NON_OVERRIDABLE:Array<String> = ['ModsMenuState'];

	/**
	 * Called from `MusicBeatState.switchState` for every state transition.
	 * If the active state-source provides a scripted replacement for the given
	 * built-in state, returns it; otherwise null (caller keeps the built-in).
	 * A missing override is the common case and is handled silently.
	 */
	public static function coreOverride(builtin:FlxState):MusicBeatState {
		if (Mods.stateSourceMode == NONE || builtin == null)
			return null;
		if (builtin is ScriptedMusicBeatState)
			return null; // already a scripted override -- don't recurse

		var clsName:String = Type.getClassName(Type.getClass(builtin));
		if (clsName == null)
			return null;
		var name:String = clsName.split('.').pop();
		if (NON_OVERRIDABLE.contains(name))
			return null;

		var scope:ResolveScope = (Mods.stateSourceMode == MOD) ? LAUNCHED : GLOBALS;
		if (resolvePath('states/' + name + '.hx', scope) == null)
			return null; // no override file -> stay built-in, no error
		return loadState(name, null, scope);
	}

	/**
	 * Enters a mod's scripted states: makes it the active source and switches to
	 * its entry state (pack.json "entryState", default MainMenuState). One mod at
	 * a time, so different mods never boot their own menus simultaneously.
	 */
	public static function launchMod(folder:String):Bool {
		#if MODS_ALLOWED
		if (!Mods.isLaunchable(folder))
			return false;
		Mods.currentModDirectory = folder;
		Mods.launchedMod = folder;
		Mods.stateSourceMode = MOD;
		Mods.pushGlobalMods();
		return switchToState(Mods.getEntryState(folder), null, LAUNCHED);
		#else
		return false;
		#end
	}

	/**
	 * Leaves a launched mod and returns to the engine's mods menu. Forces the
	 * built-in states for the rest of the session (a full restart re-applies the
	 * stateSource pref). Intended as the BACK target for a mod's top menu.
	 */
	public static function exitToEngine():Void {
		Mods.launchedMod = null;
		Mods.stateSourceMode = NONE;
		Mods.loadTopMod();
		MusicBeatState.switchState(new states.ModsMenuState());
	}

	/** Loads `substates/<name>.hx` and opens it over the current state. */
	public static function openSubstate(name:String, ?args:Array<Dynamic>):Bool {
		var sub:MusicBeatSubstate = loadSubstate(name, args);
		if (sub == null)
			return false;
		FlxG.state.openSubState(sub);
		return true;
	}

	// Shared load/parse/instantiate pipeline for states and substates.
	static function instantiate(subfolder:String, name:String, ?args:Array<Dynamic>, scope:ResolveScope = ANY):Dynamic {
		var path:String = resolvePath(subfolder + name + '.hx', scope);
		if (path == null) {
			HScript.error('Scripted state not found: ${subfolder}${name}.hx', errPos(name));
			return null;
		}

		#if MODS_ALLOWED
		// Reuse the mod trust gate that standalone HScripts use.
		var modFolder:Array<String> = path.split('/');
		if (modFolder[0] + '/' == Paths.mods()
			&& (Mods.currentModDirectory == modFolder[1] || Mods.getGlobalMods().contains(modFolder[1]))
			&& backend.ModSecurity.isBlocked(modFolder[1])) {
			trace('ScriptedStates: blocked $path -- mod "${modFolder[1]}" not trusted');
			return null;
		}
		#end

		var failed:Bool = false;
		var module:Module = new Module(File.getContent(path), name, [], path);
		module.onParsingError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(name)); };
		module.onProgramError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(name)); };
		module.onTypeError = function(e:haxe.Exception, t:IInsanityType) { failed = true; HScript.error('${e.message}', errPos(name)); };

		var environment:Environment = new Environment([module]);
		injectGlobals(environment.variables);
		environment.start();
		if (failed)
			return null;

		var type:IInsanityType = environment.resolve(name);
		if (type == null || !(type is InsanityScriptedClass)) {
			HScript.error('Scripted state "$name" must declare a class named "$name"', errPos(name));
			return null;
		}

		var cls:InsanityScriptedClass = cast type;
		module.startType(environment, cls);
		if (cls.failed || !cls.initialized) {
			HScript.error('Scripted state "$name" failed to initialize', errPos(name));
			return null;
		}

		// Run the scripted class's methods in "safe" mode so a runtime error in
		// create/update/beatHit/etc. is caught and logged to the debug console
		// instead of crashing the game. Must be set after init() (which resets it
		// from the class metadata) and before the instance is constructed.
		cls.safe = true;
		cls.onInstanceError = function(e:Dynamic, fun:String, ?inst:Dynamic) {
			HScript.error('$name.$fun(): $e', errPos(name));
		};

		try {
			return cls.typeCreateInstance(args != null ? args : []);
		} catch (e:haxe.Exception) {
			HScript.error('Failed to instantiate scripted state "$name": ${e.message}', errPos(name));
			return null;
		}
	}

	static inline function errPos(name:String):HScriptInfos
		return cast {fileName: name, showLine: false};

	// Resolves a script path within the requested scope:
	//   ANY      - current mod -> global mods -> shared (Paths.modFolders order)
	//   LAUNCHED - the launched mod folder only (no shared fallback)
	//   GLOBALS  - global/scriptpack mods (in order) -> shared
	static function resolvePath(relative:String, scope:ResolveScope = ANY):String {
		#if MODS_ALLOWED
		switch (scope) {
			case LAUNCHED:
				if (Mods.launchedMod != null && Mods.launchedMod.length > 0) {
					var p:String = Paths.mods(Mods.launchedMod + '/' + relative);
					if (FileSystem.exists(p))
						return p;
				}
				return null; // launched-mod scope: never fall back to shared
			case GLOBALS:
				for (mod in Mods.getGlobalMods()) {
					var p:String = Paths.mods(mod + '/' + relative);
					if (FileSystem.exists(p))
						return p;
				}
			// falls through to shared below
			case ANY:
				var modPath:String = Paths.modFolders(relative);
				if (FileSystem.exists(modPath))
					return modPath;
		}
		#end
		var sharedPath:String = Paths.getSharedPath(relative);
		if (FileSystem.exists(sharedPath))
			return sharedPath;
		return null;
	}

	// Engine globals available inside scripted states. The instance interpreter
	// inherits these (Environment -> Module -> class -> instance), so scripts
	// can use them without importing. `this` (the state instance) and inherited
	// members (add, openSubState, ...) are wired automatically by the macro.
	static function injectGlobals(vars:Map<String, Dynamic>):Void {
		inline function s(name:String, value:Dynamic)
			vars.set(name, value);

		#if sys
		s('File', File);
		s('FileSystem', FileSystem);
		#end
		s('FlxG', flixel.FlxG);
		s('FlxMath', flixel.math.FlxMath);
		s('FlxSprite', flixel.FlxSprite);
		s('FlxText', flixel.text.FlxText);
		s('FlxCamera', flixel.FlxCamera);
		s('FlxTimer', flixel.util.FlxTimer);
		s('FlxTween', flixel.tweens.FlxTween);
		s('FlxEase', flixel.tweens.FlxEase);
		s('FlxColor', psychlua.HScript.CustomFlxColor);
		s('FlxSound', flixel.sound.FlxSound);
		s('PsychCamera', backend.PsychCamera);
		s('MusicBeatState', MusicBeatState);
		s('MusicBeatSubstate', MusicBeatSubstate);
		s('PlayState', PlayState);
		s('Paths', Paths);
		s('Conductor', Conductor);
		s('ClientPrefs', ClientPrefs);
		s('Alphabet', Alphabet);
		s('FlxSpriteGroup', flixel.group.FlxSpriteGroup);

		s('controls', Controls.instance);
		s('getVar', function(name:String):Dynamic {
			return MusicBeatState.getVariables().exists(name) ? MusicBeatState.getVariables().get(name) : null;
		});
		s('setVar', function(name:String, value:Dynamic):Dynamic {
			MusicBeatState.getVariables().set(name, value);
			return value;
		});
		s('removeVar', function(name:String):Bool {
			if (MusicBeatState.getVariables().exists(name)) {
				MusicBeatState.getVariables().remove(name);
				return true;
			}
			return false;
		});

		// Navigation between scripted states from within a scripted state.
		s('switchToState', function(name:String, ?args:Array<Dynamic>):Bool return switchToState(name, args));
		s('openScriptedSubstate', function(name:String, ?args:Array<Dynamic>):Bool return openSubstate(name, args));
		s('switchState', function(state:FlxState) MusicBeatState.switchState(state));
		// Mod launch/exit (for a mod's scripted menus to implement BACK etc.).
		s('exitToEngine', function() exitToEngine());
		s('launchMod', function(folder:String):Bool return launchMod(folder));
	}
	#end
}
