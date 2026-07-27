package scripting;

#if HSCRIPT_ALLOWED
import insanity.Module;
import insanity.Environment;
import insanity.syntax.Expr;
import insanity.types.ScriptedClass;
import insanity.types.IScriptedType;
import insanity.types.TypeCollection;
import psychlua.HScript;
import psychlua.HScript.HScriptInfos;
import scripting.ScriptedStates.ResolveScope;

/**
 * Loads script-declared classes and keeps each mod's alive as its own world.
 *
 * A mod's classes live under a class root, with folders as packages, exactly like a Haxe source
 * tree:
 *
 *     mods/MyMod/scripts/classes/taiko/TaikoNote.hx  ->  package taiko;  class TaikoNote { ... }
 *     mods/MyMod/scripts/classes/taiko/TaikoMode.hx  ->  import taiko.TaikoNote;
 *     mods/MyMod/scripts/classes/states/MyMenu.hx    ->  package states;  (a scripted state)
 *
 * Scripted states are ordinary classes in the `states` package: they get their entry points from
 * `ScriptedStates` and are reloaded on every state entry (so `create()` starts clean), but they
 * share their mod's world, which is what lets a state and a song script pass objects to each other.
 *
 * **One world per mod.** Every module a mod loads joins that mod's `insanity.Environment`, which is
 * what lets its scripts `import` each other: import resolution consults the environment's type
 * collection alongside the engine's compiled types. Keeping worlds separate means two mods can both
 * ship `rhythm.ScoreKeeper` without colliding, and a mod's statics die with the mod rather than
 * leaking into the next one. Modules are cached per file, so a class instantiated once per note is
 * parsed once, not once per instance.
 */
class ScriptRegistry {
	/**
		Source roots for a mod's scripted classes, relative to the mod (or shared assets) folder,
		best match first. Folders under a root are packages, exactly like a Haxe source tree.

		`scripts/classes/` is the home: everything a scripter writes then lives in one place, beside
		the ordinary scripts that use it. A top-level `classes/` is still read, lower priority, for
		mods that keep their class library outside `scripts/`.
	**/
	public static var CLASS_ROOTS:Array<String> = ['scripts/classes/', 'classes/'];

	/** Package a scripted state lives in, under a class root. **/
	public static inline var STATE_PACKAGE:String = 'states';

	/** Package a scripted substate lives in, under a class root. **/
	public static inline var SUBSTATE_PACKAGE:String = 'substates';

	/** Key for the world holding shared (non-mod) classes. **/
	public static inline var SHARED_WORLD:String = '';

	/**
		Every place a dotted class path could be, best first.

		@param path Dotted type path, e.g. `demo.Counter`.
		@return Mod-relative file paths to try in order.
	**/
	public static function classPaths(path:String):Array<String> {
		var relative:String = path.split('.').join('/') + '.hx';
		var out:Array<String> = [];
		for (root in CLASS_ROOTS)
			out.push(root + relative);
		return out;
	}

	/**
		Whether a folder directly under `mods/` is a script root rather than a modpack.

		`mods/scripts/classes/states/FreeplayState.hx` is a GLOBAL override owned by no mod, so the
		first path segment must not be mistaken for a mod named "scripts".
	**/
	public static function isScriptRoot(folder:String):Bool {
		for (root in CLASS_ROOTS)
			if (root.split('/')[0] == folder)
				return true;
		return false;
	}

	/**
		The mod a script file belongs to, or `SHARED_WORLD` for one that belongs to none.

		e.g. `mods/MyMod/scripts/classes/demo/Counter.hx` -> `MyMod`, while a bare-root global
		override at `mods/scripts/classes/states/FreeplayState.hx` -> `''`.
	**/
	public static function modOfFile(file:String):String {
		#if MODS_ALLOWED
		if (file == null)
			return SHARED_WORLD;

		var parts:Array<String> = file.split('/');
		if (parts.length > 3 && parts[0] + '/' == Paths.mods() && !isScriptRoot(parts[1]))
			return parts[1];
		#end
		return SHARED_WORLD;
	}

	/** Every mod's world, keyed by mod folder. **/
	static var worlds:Map<String, ScriptWorld> = new Map();

	/** The world for `mod`, created on first use. **/
	public static function worldFor(?mod:String):ScriptWorld {
		var key:String = (mod != null) ? mod : SHARED_WORLD;

		var found:ScriptWorld = worlds.get(key);
		if (found == null) {
			found = new ScriptWorld(key);
			worlds.set(key, found);
		}
		return found;
	}

	/** Drops one mod's classes, so re-entering it re-reads from disk. **/
	public static function disposeMod(?mod:String):Void {
		var key:String = (mod != null) ? mod : SHARED_WORLD;

		var found:ScriptWorld = worlds.get(key);
		if (found == null)
			return;

		found.dispose();
		worlds.remove(key);
	}

	/** Drops every world. **/
	public static function dispose():Void {
		for (world in worlds)
			world.dispose();
		worlds.clear();
	}

	/** True if any parsed file in any world has changed on disk since it was loaded. */
	public static function stale():Bool {
		for (world in worlds)
			if (world.stale())
				return true;

		return false;
	}

	/**
	 * Resolves a scripted class by dotted path (`taiko.TaikoNote`), loading it and anything
	 * it imports if it isn't in the world yet. Returns null and logs to the debug console
	 * when the file is missing or fails to initialize.
	 *
	 * @param mod Which mod's world to resolve in. Defaults to the shared world.
	 */
	public static function resolveClass(path:String, ?mod:String, ?scope:ResolveScope):ScriptedClass {
		var world:ScriptWorld = worldFor(mod);

		var type:IScriptedType = resolveType(world, path, (scope != null) ? scope : world.scope);
		if (type == null)
			return null;

		if (!(type is ScriptedClass)) {
			HScript.error('Scripted type "$path" is not a class', errPos(path));
			return null;
		}
		return cast type;
	}

	/** Builds an instance of a scripted class by dotted path. */
	public static function instantiate(path:String, ?args:Array<Dynamic>, ?mod:String, ?scope:ResolveScope):Dynamic {
		var cls:ScriptedClass = resolveClass(path, mod, scope);
		if (cls == null)
			return null;

		return build(cls, path, args);
	}

	/**
	 * Constructs an already-resolved scripted class, routing runtime errors in its methods
	 * to the debug console instead of letting them take the game down.
	 */
	public static function build(cls:ScriptedClass, name:String, ?args:Array<Dynamic>):Dynamic {
		if (cls.failed || !cls.initialized) {
			HScript.error('Scripted class "$name" failed to initialize', errPos(name));
			return null;
		}

		makeSafe(cls);

		try {
			return cls.typeCreateInstance(args != null ? args : []);
		} catch (e:haxe.Exception) {
			HScript.error('Failed to instantiate "$name": ${e.message}', errPos(name));
			return null;
		}
	}

	/** Whether `path` names a scripted class extending (directly or not) the given native base. */
	public static function isSubclassOf(path:String, base:Class<Dynamic>, ?mod:String, ?scope:ResolveScope):Bool {
		var cls:ScriptedClass = resolveClass(path, mod, scope);
		if (cls == null)
			return false;

		var native:Dynamic = cls.instanceClass;
		while (native != null) {
			if (native == base)
				return true;
			native = Type.getSuperClass(native);
		}
		return false;
	}

	/**
	 * Registers an entry module (a state or substate) in its mod's world, replacing any previous
	 * version so it re-runs from scratch. Returns its main type.
	 *
	 * The world comes from the FILE, not from whatever mod happens to be current: a state and the
	 * song scripts of the same mod must land in one world or they cannot see each other's classes.
	 */
	public static function loadEntry(file:String, name:String, ?pack:Array<String>, ?scope:ResolveScope):IScriptedType {
		if (pack == null)
			pack = [];

		// The same trust gate the mod's own classes go through. Without it a state script from an
		// untrusted mod would run while every class it imports was blocked -- which both executes
		// code the player never approved and fails in a way that reads like a broken script.
		if (blocked(file)) {
			HScript.error('Scripted state "$name" is blocked: mod not trusted', errPos(name));
			return null;
		}

		var world:ScriptWorld = worldFor(modOfFile(file));

		// The entry was resolved in this scope, so its classes have to resolve in it too.
		world.scope = (scope != null) ? scope : ANY;

		var failed:Bool = false;
		var module:Module = new Module(File.getContent(file), name, pack, file);
		module.onParsingError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(name)); };
		module.onProgramError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(name)); };
		module.onTypeError = function(e:haxe.Exception, t:IScriptedType) { failed = true; HScript.error('${e.message}', errPos(name)); };

		if (failed)
			return null;

		var env:Environment = world.environment();
		env.addModule(module);
		world.stamps.set(file, modified(file));

		var added:Array<Module> = [module];
		for (dependency in scriptedImports(world, module))
			load(world, dependency, world.scope, added);

		startAll(world, added);

		if (failed)
			return null;

		return env.resolve(insanity.tools.Tools.pathToString(name, pack));
	}

	static function resolveType(world:ScriptWorld, path:String, scope:ResolveScope):IScriptedType {
		var env:Environment = world.environment();

		var existing:IScriptedType = env.resolve(path);
		if (existing != null)
			return existing;

		if (world.failedPaths.contains(path))
			return null;

		var added:Array<Module> = [];
		if (!load(world, path, scope, added)) {
			world.failedPaths.push(path);
			return null;
		}

		startAll(world, added);
		return env.resolve(path);
	}

	/**
	 * Parses `path` (and, depth-first, every scripted type it imports) into the world without
	 * starting anything yet -- cross-references only resolve once all of them are registered.
	 */
	static function load(world:ScriptWorld, path:String, scope:ResolveScope, added:Array<Module>):Bool {
		if (world.loaded.exists(path))
			return true;

		var candidates:Array<String> = classPaths(path);
		var file:String = null;

		// Every root in the requested scope first, then every root in the wider search. LAUNCHED
		// and GLOBALS deliberately never fall back to shared on their own, but a class library
		// that lives outside the launched mod should still be reachable.
		file = ScriptedStates.resolveScript(candidates, scope);
		if (file == null && scope != ANY)
			file = ScriptedStates.resolveScript(candidates, ANY);

		// `scriptedImports` only hands over paths that are NOT compiled types, so failing to find
		// one on disk is a real error. Reporting it here is what turns "must declare a class named
		// X" -- raised much later, when the type that needed the import fails to initialize -- into
		// the actual missing file.
		if (file == null) {
			HScript.error('Unresolved import "$path": no compiled type, and no ${candidates.join(" or ")} in this mod', errPos(path));
			return false;
		}

		if (blocked(file)) {
			HScript.error('Unresolved import "$path": the mod it belongs to is not trusted', errPos(path));
			return false;
		}

		var parts:Array<String> = path.split('.');
		var name:String = parts.pop();

		var failed:Bool = false;
		var module:Module = new Module(File.getContent(file), name, parts, file);
		module.onParsingError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(path)); };
		module.onProgramError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(path)); };
		module.onTypeError = function(e:haxe.Exception, t:IScriptedType) { failed = true; HScript.error('${e.message}', errPos(path)); };

		if (failed)
			return false;

		world.loaded.set(path, module);
		world.stamps.set(file, modified(file));
		world.environment().addModule(module);
		added.push(module);

		for (dependency in scriptedImports(world, module))
			load(world, dependency, scope, added);

		return true;
	}

	/**
	 * Dotted paths this module imports that aren't compiled types -- i.e. the ones that have
	 * to come off disk. A path already in the engine's type collection is a native import
	 * and needs nothing from us.
	 */
	static function scriptedImports(world:ScriptWorld, module:Module):Array<String> {
		var paths:Array<String> = [];

		for (decl in module.decls) {
			switch (decl.d) {
				case DImport(path, _):
					// `import pack.Type.staticField` -- the type is the last uppercase segment.
					var parts:Array<String> = path.copy();
					while (parts.length > 0 && !isTypeName(parts[parts.length - 1]))
						parts.pop();

					if (parts.length == 0)
						continue;

					var full:String = parts.join('.');
					if (TypeCollection.main.fromPath(full) != null || world.loaded.exists(full))
						continue;

					if (!paths.contains(full))
						paths.push(full);

				default:
			}
		}

		return paths;
	}

	static inline function isTypeName(s:String):Bool
		return s.length > 0 && s.charAt(0) == s.charAt(0).toUpperCase();

	/** Runs module-level code and initializes the types of newly added modules. */
	static function startAll(world:ScriptWorld, modules:Array<Module>):Void {
		var env:Environment = world.environment();

		for (module in modules)
			module.init(env);

		for (module in modules)
			module.start(env);

		for (module in modules)
			module.startTypes(env);

		// Every scripted class runs in "safe" mode: a runtime error in one of its methods
		// is caught and logged to the debug console instead of crashing the game -- the same
		// treatment scripted states already get. This matters for classes a script builds
		// itself with `new` (e.g. a scripted PlayState subclass), which never pass through
		// `build()`, so without this their errors would be uncaught.
		for (module in modules)
			for (type in module.types)
				if (type is ScriptedClass)
					makeSafe(cast type);
	}

	/** Puts a class into safe mode and funnels its instance errors to the debug console. */
	static function makeSafe(cls:ScriptedClass):Void {
		cls.safe = true;
		cls.onInstanceError = function(e:Dynamic, fun:String, ?inst:Dynamic) {
			HScript.error('${cls.path}.$fun(): $e', errPos(cls.path));
		};
	}

	static function blocked(file:String):Bool {
		#if MODS_ALLOWED
		var parts:Array<String> = file.split('/');
		if (parts[0] + '/' == Paths.mods()
			&& (Mods.currentModDirectory == parts[1] || Mods.getGlobalMods().contains(parts[1]))
			&& backend.ModSecurity.isBlocked(parts[1])) {
			trace('ScriptRegistry: blocked $file -- mod "${parts[1]}" not trusted');
			return true;
		}
		#end
		return false;
	}

	static function modified(file:String):Float {
		#if sys
		try {
			return FileSystem.stat(file).mtime.getTime();
		} catch (e:Dynamic) {}
		#end
		return 0;
	}

	static inline function errPos(name:String):HScriptInfos
		return cast {fileName: name, showLine: false};
}

/**
 * One mod's scripted-class world: its interpreter environment, what it has loaded, and where it
 * resolves further classes from.
 *
 * Separate worlds are what keep two mods' identically-named classes apart and stop a mod's statics
 * outliving it. The environment is built lazily so a mod that never touches `classes/` costs
 * nothing.
 */
class ScriptWorld {
	/** Mod folder this world belongs to, or `''` for the shared one. **/
	public var mod:String;

	/**
	 * Where this world resolves classes from.
	 *
	 * A launched mod's state is resolved with LAUNCHED scope (see `ScriptedStates.sourceScope`),
	 * because `Mods.currentModDirectory` -- which the plain ANY scope reads -- gets repointed by
	 * engine helpers like `WeekData.setDirectoryFromWeek`. The classes it imports have to come from
	 * the SAME source, or the state loads and its own library does not.
	 */
	public var scope:ResolveScope = ANY;

	/** Dotted type path -> its module, for everything loaded from a class root. **/
	public var loaded:Map<String, Module> = new Map();

	/** File path -> modification time when it was parsed. **/
	public var stamps:Map<String, Float> = new Map();

	/** Paths already known to be unresolvable, so a miss is reported once and not retried. **/
	public var failedPaths:Array<String> = [];

	var env:Environment = null;

	public function new(mod:String) {
		this.mod = mod;
	}

	/** This world's interpreter environment, built (and given its globals) on first use. **/
	public function environment():Environment {
		if (env == null) {
			env = new Environment();
			ScriptGlobals.inject(env.variables, mod);
		}
		return env;
	}

	/** True if any parsed file has changed on disk since it was loaded. **/
	public function stale():Bool {
		for (file => stamp in stamps) {
			#if sys
			try {
				if (FileSystem.stat(file).mtime.getTime() != stamp)
					return true;
			} catch (e:Dynamic) {
				return true;
			}
			#end
		}
		return false;
	}

	public function dispose():Void {
		if (env != null)
			env.snapshot();

		env = null;
		loaded.clear();
		stamps.clear();
		failedPaths.resize(0);
	}
}
#end
