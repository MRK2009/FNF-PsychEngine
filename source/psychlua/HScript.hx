package psychlua;

import flixel.FlxBasic;
import objects.Character;
import psychlua.LuaUtils;
import psychlua.CustomSubstate;
#if LUA_ALLOWED
import psychlua.FunkinLua;
#end
#if HSCRIPT_ALLOWED
import insanity.Script;
import insanity.runtime.Interp;
import insanity.Config.ConfigBlacklistKind;
import insanity.syntax.Expr.ImportMode;

typedef HScriptInfos = {
	> haxe.PosInfos,
	var ?funcName:String;
	var ?showLine:Null<Bool>;
	#if LUA_ALLOWED
	var ?isLua:Null<Bool>;
	#end
}

// Result of calling a function inside an HScript.
// Mirrors the old crowplexus IrisCall shape so call sites are unchanged.
typedef HScriptCall = {
	var funName:String;
	var signature:Dynamic;
	var returnValue:Dynamic;
}

// Wraps an insanity.Script (formerly extended crowplexus.iris.Iris).
// The public surface (preset() globals, call/set/exists, the runHaxeCode
// Lua bridge, the `instances` registry and the static error/warn loggers)
// is kept identical so the rest of the engine doesn't need to know which
// interpreter backs it.
class HScript {
	public var script:Script;

	public var interp(get, never):Interp;
	inline function get_interp():Interp
		return (script != null ? script.interp : null);

	public var name:String; // registry key (script path or parent Lua name)
	public var filePath:String;
	public var modFolder:String;
	public var returnValue:Dynamic;
	public var scriptCode:String;

	public var origin:String;
	public var blocked:Bool = false;
	public var failed:Bool = false;

	/**
		Hook name -> whether this script defines a function by that name.

		Dispatch asks every script for every hook, and almost every answer is "not defined" -- each
		of which cost a variable lookup plus a `Reflect.isFunction` type check, per script, per
		hook, per frame. `onUpdate` and `onUpdatePost` alone made that `2 x scripts x 60` a second.
		The Lua side has had this (`FunkinLua.hookCache`); HScript went without.

		A `false` is only trusted until the script defines the function later -- see `defineHook`,
		which is what a runtime definition needs to call.
	**/
	var hookCache:Map<String, Bool> = new Map();

	// Replaces crowplexus Iris.instances -- lets PlayState/LoadingState/FunkinLua
	// check whether a script path is already running and fetch it by name.
	public static var instances:Map<String, HScript> = new Map();

	/**
	 * One-time setup of insanity's global scripting config. Mirrors
	 * ModSecurity.BLOCKED_CLASSES into insanity's type blacklist so that scripts
	 * resolving them through the Type/Reflect/Std proxies get null back -- the
	 * defense-in-depth equivalent of the old PatchIris macro. The primary gate
	 * (per-mod trust + source pattern scanning) still lives in ModSecurity and
	 * is interpreter-agnostic, so it is unaffected by the Iris -> insanity swap.
	 *
	 * Call once at boot (see Main.setupGame).
	 */
	public static function setupConfig():Void {
		// Use our interpreter so scripts can reference the creating state's
		// fields as bare identifiers (hscript-iris CustomInterp back-compat).
		insanity.Config.interpClass = PsychInterp;

		// Auto-import every extendable base so scripts can write `class MyThing extends
		// FlxSprite` without an explicit import. insanity makes a class scriptable by
		// registering its BASE class (backend.MusicBeatState -> the generated
		// ScriptedMusicBeatState bridge), so scripts extend the real base, not the
		// bridge. Bare names resolve through imports and these are all packaged, so
		// each has to be imported explicitly -- a package IAll import skips them.
		for (base in scripting.bridges.Bridges.bases)
			insanity.Config.globalImports.set(base, INormal);

		// One shared list of engine types every script resolves unqualified. Everything
		// else is reachable by explicit `import`, resolved against the compiled type set.
		scripting.ScriptGlobals.register();

		// Script-declared `private` members are enforced (native fields carry no access
		// information at runtime and are unaffected).
		insanity.Config.strictAccess = true;

		// Emulate methods flixel/openfl leave without a runtime form (inline extern), e.g.
		// FlxG.sound.playMusic, so scripts can call them like normal Haxe.
		scripting.ScriptShims.register();

		#if MODS_ALLOWED
		var byType:Array<String> = insanity.Config.blacklist.get(ByType);
		if (byType == null) {
			byType = [];
			insanity.Config.blacklist.set(ByType, byType);
		}
		for (name => _ in backend.ModSecurity.BLOCKED_CLASSES)
			if (name.indexOf('.') >= 0 && !byType.contains(name)) // fully-qualified names only
				byType.push(name);

		/**
			`import` is a wider surface than resolution by name: it goes through insanity's own type
			collection, so `ModSecurity.safeResolveClass` never sees it. The packages that are
			dangerous wholesale are mirrored here so both surfaces agree.

			`insanity` itself must NOT be listed. `Std`, `Type` and `Reflect` inside a script resolve
			to `insanity.proxy.*` and scripted abstracts run on `insanity.types.*`, so blocking the
			package blacklists the interpreter's own machinery: every script using `Std` dies with
			"Unknown identifier: Std". `insanity.Config` is in `BLOCKED_CLASSES` by name instead.
		**/
		var byPackage:Array<String> = insanity.Config.blacklist.get(ByPackage(true));
		if (byPackage == null) {
			byPackage = [];
			insanity.Config.blacklist.set(ByPackage(true), byPackage);
		}
		for (pack in backend.ModSecurity.BLOCKED_PACKAGES) {
			var name:String = pack.substr(0, pack.length - 1); // "sys." -> "sys"
			if (!byPackage.contains(name))
				byPackage.push(name);
		}
		#end
	}

	#if LUA_ALLOWED
	public var parentLua:FunkinLua;

	public static function initHaxeModule(parent:FunkinLua) {
		if (parent.hscript == null) {
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent);
		}
	}

	public static function initHaxeModuleCode(parent:FunkinLua, code:String, ?varsToBring:Any = null) {
		var hs:HScript = try parent.hscript catch (e) null;
		if (hs == null) {
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent, code, varsToBring);
		} else {
			hs.scriptCode = code;
			hs.varsToBring = varsToBring;
			hs.script.parse(code);
			hs.run();
		}
	}
	#end

	public function new(?parent:Dynamic, ?file:String, ?varsToBring:Any = null, ?manualRun:Bool = false) {
		if (file == null)
			file = '';

		filePath = file;
		if (filePath != null && filePath.length > 0) {
			this.origin = filePath;
			#if MODS_ALLOWED
			var myFolder:Array<String> = filePath.split('/');
			if (myFolder[0] + '/' == Paths.mods()
				&& (Mods.currentModDirectory == myFolder[1] || Mods.getGlobalMods().contains(myFolder[1]))) // is inside mods folder
				this.modFolder = myFolder[1];
			#end
		}

		#if MODS_ALLOWED
		// Security gate: standalone HScripts loaded from a blocked mod are not run.
		// HScripts spawned by a Lua parent inherit the parent's already-vetted trust state.
		if (parent == null && this.modFolder != null && backend.ModSecurity.isBlocked(this.modFolder)) {
			this.blocked = true;
			trace('HScript: blocked $file -- mod "${this.modFolder}" not trusted');
			return;
		}
		#end

		var scriptThing:String = file;
		var scriptName:String = null;
		if (parent == null && file != null) {
			var f:String = file.replace('\\', '/');
			if (f.contains('/') && !f.contains('\n')) {
				scriptThing = File.getContent(f);
				scriptName = f;
			}
		}
		#if LUA_ALLOWED
		if (scriptName == null && parent != null)
			scriptName = parent.scriptName;
		#end

		this.scriptCode = scriptThing;
		this.name = (scriptName != null ? scriptName : (origin != null ? origin : 'hscript'));

		script = new Script(scriptThing, this.name);
		hookErrors();
		// Bare-identifier access to the creating state's fields (back-compat).
		if (interp != null && (interp is PsychInterp))
			cast(interp, PsychInterp).parentInstance = FlxG.state;
		// insanity.Script parses in its constructor with the default (trace)
		// handler; re-parse so parse errors reach our debug-console logger.
		if (script.program == null)
			script.parse(scriptThing);

		#if LUA_ALLOWED
		parentLua = parent;
		if (parent != null) {
			this.origin = parent.scriptName;
			this.modFolder = parent.modFolder;
		}
		#end

		instances.set(this.name, this);

		this.varsToBring = varsToBring;

		if (!manualRun)
			run();
	}

	var _presetDone:Bool = false;

	/**
	 * Executes the parsed program. We deliberately bypass `insanity.Script.start()`
	 * because it calls `interp.setDefaults()` which WIPES the variables map -- that
	 * would erase every global we inject in `preset()`.
	 *
	 * setDefaults()/preset() run ONCE, on the first execution. Re-runs (e.g.
	 * `runHaxeCode` re-using a Lua parent's HScript) must NOT wipe, otherwise
	 * variables set between runs -- like classes added via `addHaxeLibrary` -- are
	 * lost before the new code executes.
	 */
	public function run():Dynamic {
		returnValue = null;
		if (script == null || script.program == null)
			return null;

		if (!_presetDone) {
			script.setDefaults(); // wipes variables + restores this/script/interp + Config globals
			preset(); // inject engine globals AFTER the wipe
			_presetDone = true;
		}
		applyVarsToBring();

		try {
			returnValue = interp.execute(script.program);
			scripting.ScriptHooks.bindHScript(script.variables);
			// Executing is what DEFINES the hooks, and a re-run (runHaxeCode against a Lua parent's
			// interpreter) can replace them wholesale, so nothing learned before it still holds.
			hookCache.clear();
		} catch (e:haxe.Exception) {
			failed = true;
			returnValue = null;
			HScript.error('${e.message}', errorPos());
		}
		return returnValue;
	}

	function applyVarsToBring():Void {
		if (varsToBring == null)
			return;
		for (key in Reflect.fields(varsToBring)) {
			var k:String = key.trim();
			set(k, Reflect.field(varsToBring, k));
		}
	}

	function hookErrors() {
		script.onParsingError = function(e:haxe.Exception) {
			failed = true;
			HScript.error('${e.message}', errorPos());
		};
		script.onProgramError = function(e:haxe.Exception) {
			failed = true;
			HScript.error('${e.message}', errorPos());
		};
	}

	function errorPos(?funcName:String):HScriptInfos {
		var pos:HScriptInfos = (interp != null) ? cast interp.posInfos() : cast {fileName: this.name, showLine: false};
		if (funcName != null)
			pos.funcName = funcName;
		#if LUA_ALLOWED
		if (parentLua != null) {
			pos.isLua = true;
			if (parentLua.lastCalledFunction != '')
				pos.funcName = parentLua.lastCalledFunction;
		}
		#end
		return pos;
	}

	public var varsToBring:Any = null;

	public function set(name:String, value:Dynamic):Void {
		if (script != null)
			script.variables.set(name, value);
		hookCache.remove(name);
	}

	/**
		Forgets what is cached about `func`, so the next dispatch looks it up again.

		Only needed by a script that defines a hook from inside another function, long after load;
		one declared normally is already there the first time it is looked for. Mirrors
		`FunkinLua.defineHook`.
	**/
	public function defineHook(func:String):Void {
		hookCache.remove(func);
	}

	public function get(name:String):Dynamic
		return (script != null) ? script.variables.get(name) : null;

	public function exists(name:String):Bool
		return (script != null && script.variables.exists(name));

	function preset() {
		scripting.ScriptGlobals.shared(function(name:String, value:Dynamic) set(name, value), this.modFolder);

		// Some very commonly used classes
		set('FlxG', flixel.FlxG);
		set('FlxMath', flixel.math.FlxMath);
		set('FlxSprite', flixel.FlxSprite);
		set('FlxText', flixel.text.FlxText);
		set('FlxCamera', flixel.FlxCamera);
		set('PsychCamera', backend.PsychCamera);
		set('FlxTimer', flixel.util.FlxTimer);
		set('FlxTween', flixel.tweens.FlxTween);
		set('FlxEase', flixel.tweens.FlxEase);
		set('Countdown', backend.BaseStage.Countdown);
		set('PlayState', PlayState);
		set('Paths', Paths);
		set('Conductor', Conductor);
		set('ClientPrefs', ClientPrefs);
		#if ACHIEVEMENTS_ALLOWED
		set('Achievements', Achievements);
		#end
		set('Character', Character);
		set('Alphabet', Alphabet);
		set('Note', objects.Note);
		set('CustomSubstate', CustomSubstate);
		#if (!flash && sys)
		set('FlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
		set('ErrorHandledRuntimeShader', shaders.ErrorHandledShader.ErrorHandledRuntimeShader);
		#end
		set('ShaderFilter', openfl.filters.ShaderFilter);
		#if flixel_animate
		set('FlxAnimate', FlxAnimate);
		#end

		// For adding your own callbacks
		// not very tested but should work
		#if LUA_ALLOWED
		set('createGlobalCallback', function(name:String, func:Dynamic) {
			var host:scripting.ScriptHost = scripting.ScriptHost.current;
			if (host != null && host.luaArray != null)
				for (script in host.luaArray)
					if (script != null && script.lua != null && !script.closed)
						Lua_helper.add_callback(script.lua, name, func);

			// Through the host, so its teardown removes this name and leaves other hosts' alone.
			if (host != null)
				host.registerGlobalCallback(name, func);
			else
				FunkinLua.customFunctions.set(name, func);
		});

		// this one was tested
		set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null) {
			if (funk == null)
				funk = parentLua;

			if (funk != null)
				funk.addLocalCallback(name, func);
			else
				HScript.error('createCallback ($name): 3rd argument is null', errorPos());
		});
		#end

		set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			try {
				var str:String = '';
				if (libPackage.length > 0)
					str = libPackage + '.';

				set(libName, #if MODS_ALLOWED backend.ModSecurity.safeResolveClass(str + libName) #else Type.resolveClass(str + libName) #end);
			} catch (e:haxe.Exception) {
				HScript.error('${e.message}', errorPos());
			}
		});
		#if LUA_ALLOWED
		set('parentLua', parentLua);
		#else
		set('parentLua', null);
		#end
		set('this', this);
		set('game', FlxG.state);

		set('customSubstate', CustomSubstate.instance);
		set('customSubstateName', CustomSubstate.name);
	}

	#if LUA_ALLOWED
	public static function implement(funk:FunkinLua) {
		funk.addLocalCallback("runHaxeCode",
			function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
				initHaxeModuleCode(funk, codeToRun, varsToBring);
				if (funk.hscript != null) {
					final retVal:HScriptCall = funk.hscript.callDetailed(funcToRun, funcArgs);
					if (retVal != null) {
						return (LuaUtils.isLuaSupported(retVal.returnValue)) ? retVal.returnValue : null;
					} else if (funk.hscript.returnValue != null) {
						return funk.hscript.returnValue;
					}
				}
				return null;
			});

		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			if (funk.hscript != null) {
				final retVal:HScriptCall = funk.hscript.callDetailed(funcToRun, funcArgs);
				if (retVal != null) {
					return (LuaUtils.isLuaSupported(retVal.returnValue)) ? retVal.returnValue : null;
				}
			} else {
				var pos:HScriptInfos = cast {fileName: funk.scriptName, showLine: false};
				if (funk.lastCalledFunction != '')
					pos.funcName = funk.lastCalledFunction;
				HScript.error("runHaxeFunction: HScript has not been initialized yet! Use \"runHaxeCode\" to initialize it", pos);
			}
			return null;
		});
		// This function is unnecessary because import already exists in HScript as a native feature
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			var str:String = '';
			if (libPackage.length > 0)
				str = libPackage + '.';
			else if (libName == null)
				libName = '';

			var c:Dynamic = #if MODS_ALLOWED backend.ModSecurity.safeResolveClass(str + libName) #else Type.resolveClass(str + libName) #end;
			if (c == null)
				c = Type.resolveEnum(str + libName);

			if (funk.hscript == null)
				initHaxeModule(funk);

			// initHaxeModule may fail to assign funk.hscript (e.g. constructor
			// throws); without this guard the next line NPEs.
			if (funk.hscript == null)
				return;

			var pos:HScriptInfos = funk.hscript.errorPos();
			pos.showLine = false;
			if (funk.lastCalledFunction != '')
				pos.funcName = funk.lastCalledFunction;

			try {
				if (c != null)
					funk.hscript.set(libName, c);
			} catch (e:haxe.Exception) {
				HScript.error('${e.message}', pos);
			}
			FunkinLua.lastCalledScript = funk;
			if (FunkinLua.getBool('luaDebugMode') && FunkinLua.getBool('luaDeprecatedWarnings'))
				HScript.warn("addHaxeLibrary is deprecated! Import classes through \"import\" in HScript!", pos);
		});
	}
	#end

	/**
		Runs `funcToRun` if this script defines it, and returns whatever it returned.

		Quiet about a hook the script simply does not implement -- that is the normal case for
		dispatch, where most scripts implement a handful of the engine's hooks. Real runtime
		failures inside the function are still reported. Returns `null` for "did not run", which
		dispatch treats the same as a function returning nothing.
	**/
	public function call(funcToRun:String, ?args:Array<Dynamic>):Dynamic {
		if (funcToRun == null || script == null)
			return null;

		var known:Null<Bool> = hookCache.get(funcToRun);
		if (known != null && !known)
			return null;

		var func:Dynamic = script.variables.get(funcToRun);
		if (func == null || !Reflect.isFunction(func)) {
			hookCache.set(funcToRun, false);
			return null;
		}
		if (known == null)
			hookCache.set(funcToRun, true);

		try {
			return Reflect.callMethod(null, func, args ?? []);
		} catch (e:haxe.Exception) {
			HScript.error('${e.message}', errorPos(funcToRun));
		}
		return null;
	}

	/**
		`call`, plus the resolved function and its name, for callers that want them.

		Unlike `call` this reports a missing function, because its callers (the `runHaxeFunction`
		Lua bridge) name one explicitly rather than probing for an optional hook.
	**/
	public function callDetailed(funcToRun:String, ?args:Array<Dynamic>):HScriptCall {
		if (funcToRun == null || script == null)
			return null;

		var func:Dynamic = script.variables.get(funcToRun);
		if (func == null || !Reflect.isFunction(func)) {
			HScript.error('No function named: $funcToRun', errorPos());
			return null;
		}

		try {
			final ret:Dynamic = Reflect.callMethod(null, func, args ?? []);
			return {funName: funcToRun, signature: func, returnValue: ret};
		} catch (e:haxe.Exception) {
			HScript.error('${e.message}', errorPos(funcToRun));
		}
		return null;
	}

	public function destroy():Void {
		if (this.name != null && instances.get(this.name) == this)
			instances.remove(this.name);
		origin = null;
		#if LUA_ALLOWED parentLua = null; #end
		script = null;
	}

	// ___________________________ Debug-console logging ___________________________
	// Replaces the crowplexus Iris.error / Iris.warn / Iris.fatal hooks that
	// Main.hx used to wire up. Formats a position-aware message and mirrors it
	// to the in-game debug overlay.
	public static function error(x:String, ?pos:HScriptInfos):Void
		logToDebug('ERROR', x, pos, FlxColor.RED);

	public static function warn(x:String, ?pos:HScriptInfos):Void
		logToDebug('WARNING', x, pos, FlxColor.YELLOW);

	public static function fatal(x:String, ?pos:HScriptInfos):Void
		logToDebug('FATAL', x, pos, 0xFFBB0000);

	static function logToDebug(level:String, x:String, ?pos:HScriptInfos, color:FlxColor):Void {
		var newPos:HScriptInfos = (pos != null) ? pos : cast {fileName: 'hscript', showLine: false};
		if (newPos.showLine == null)
			newPos.showLine = true;
		var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
		#if LUA_ALLOWED
		if (newPos.isLua == true) {
			msgInfo += 'HScript:';
			newPos.showLine = true;
		}
		#end
		if (newPos.showLine == true)
			msgInfo += '${newPos.lineNumber}:';
		msgInfo += ' $x';
		scripting.ScriptError.report('HScript', level, msgInfo, color);
	}
}

#else
class HScript {
	#if LUA_ALLOWED
	public static function implement(funk:FunkinLua) {
		funk.addLocalCallback("runHaxeCode",
			function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
				PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
				return null;
			});
		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
	}
	#end
}
#end
