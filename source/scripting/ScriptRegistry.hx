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
 * Loads script-declared classes and keeps them alive as one shared world.
 *
 * A mod's own classes live under `classes/`, with folders as packages, exactly like a Haxe
 * source tree:
 *
 *     mods/MyMod/classes/taiko/TaikoNote.hx     ->  package taiko;  class TaikoNote { ... }
 *     mods/MyMod/classes/taiko/TaikoMode.hx     ->  import taiko.TaikoNote;
 *
 * Every module loaded in a session joins ONE `insanity.Environment`, which is what lets a
 * script `import` another script's class: import resolution consults the environment's type
 * collection alongside the engine's compiled types. Modules are cached per file, so a class
 * instantiated once per note is parsed once, not once per instance.
 *
 * `states/` and `substates/` keep their own entry points in `ScriptedStates`; those modules
 * are reloaded on every state entry (so `create()` starts from a clean slate) but are added
 * to the same world, so a scripted state can import the mod's classes.
 */
class ScriptRegistry {
	/** Source root for a mod's own classes, relative to the mod (or shared assets) folder. */
	public static inline var CLASS_ROOT:String = 'classes/';

	static var environment:Environment = null;

	/** Dotted type path -> its module, for everything loaded under `CLASS_ROOT`. */
	static var loaded:Map<String, Module> = new Map();

	/** Absolute-ish file path -> modification time when it was parsed. */
	static var stamps:Map<String, Float> = new Map();

	static var failedPaths:Array<String> = [];

	/**
	 * Where this session's `classes/` resolve from.
	 *
	 * A launched mod's state is resolved with LAUNCHED scope (see `ScriptedStates.sourceScope`),
	 * because `Mods.currentModDirectory` -- which the plain ANY scope reads -- gets repointed by
	 * engine helpers like `WeekData.setDirectoryFromWeek`. The classes a state imports have to
	 * come from the SAME source, or the state loads and its own library does not. `loadEntry`
	 * records the scope it was given so everything that follows agrees with it.
	 */
	static var sessionScope:ResolveScope = ANY;

	public static function world():Environment {
		if (environment == null) {
			environment = new Environment();
			ScriptGlobals.inject(environment.variables);
		}
		return environment;
	}

	/**
	 * Drops every loaded class and the shared environment. Called when leaving a mod, so
	 * the next launch re-reads from disk instead of reusing another mod's classes.
	 */
	public static function dispose():Void {
		if (environment != null)
			environment.snapshot();

		environment = null;
		sessionScope = ANY;
		loaded.clear();
		stamps.clear();
		failedPaths.resize(0);
	}

	/** True if any parsed file has changed on disk since it was loaded. */
	public static function stale():Bool {
		for (file => stamp in stamps)
			if (modified(file) != stamp)
				return true;

		return false;
	}

	/**
	 * Resolves a scripted class by dotted path (`taiko.TaikoNote`), loading it and anything
	 * it imports if it isn't in the world yet. Returns null and logs to the debug console
	 * when the file is missing or fails to initialize.
	 */
	public static function resolveClass(path:String, ?scope:ResolveScope):ScriptedClass {
		var type:IScriptedType = resolveType(path, (scope != null) ? scope : sessionScope);
		if (type == null)
			return null;

		if (!(type is ScriptedClass)) {
			HScript.error('Scripted type "$path" is not a class', errPos(path));
			return null;
		}
		return cast type;
	}

	/** Builds an instance of a scripted class by dotted path. */
	public static function instantiate(path:String, ?args:Array<Dynamic>, ?scope:ResolveScope):Dynamic {
		var cls:ScriptedClass = resolveClass(path, scope);
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
	public static function isSubclassOf(path:String, base:Class<Dynamic>, ?scope:ResolveScope):Bool {
		var cls:ScriptedClass = resolveClass(path, scope);
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

	static function resolveType(path:String, scope:ResolveScope):IScriptedType {
		var env:Environment = world();

		var existing:IScriptedType = env.resolve(path);
		if (existing != null)
			return existing;

		if (failedPaths.contains(path))
			return null;

		var added:Array<Module> = [];
		if (!load(path, scope, added)) {
			failedPaths.push(path);
			return null;
		}

		startAll(added);
		return env.resolve(path);
	}

	/**
	 * Parses `path` (and, depth-first, every scripted type it imports) into the shared
	 * environment without starting anything yet -- cross-references only resolve once all
	 * of them are registered.
	 */
	static function load(path:String, scope:ResolveScope, added:Array<Module>):Bool {
		if (loaded.exists(path))
			return true;

		var relative:String = CLASS_ROOT + path.split('.').join('/') + '.hx';
		var file:String = ScriptedStates.resolvePath(relative, scope);

		// A mod's own source first, then the wider search. LAUNCHED and GLOBALS deliberately never
		// fall back to shared on their own, but a class library that lives outside the launched mod
		// should still be reachable.
		if (file == null && scope != ANY)
			file = ScriptedStates.resolvePath(relative, ANY);

		// `scriptedImports` only hands over paths that are NOT compiled types, so failing to find
		// one on disk is a real error. Reporting it here is what turns "must declare a class named
		// X" -- raised much later, when the type that needed the import fails to initialize -- into
		// the actual missing file.
		if (file == null) {
			HScript.error('Unresolved import "$path": no compiled type, and no $relative in this mod', errPos(path));
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

		loaded.set(path, module);
		stamps.set(file, modified(file));
		world().addModule(module);
		added.push(module);

		for (dependency in scriptedImports(module))
			load(dependency, scope, added);

		return true;
	}

	/**
	 * Dotted paths this module imports that aren't compiled types -- i.e. the ones that have
	 * to come off disk. A path already in the engine's type collection is a native import
	 * and needs nothing from us.
	 */
	static function scriptedImports(module:Module):Array<String> {
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
					if (TypeCollection.main.fromPath(full) != null || loaded.exists(full))
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
	static function startAll(modules:Array<Module>):Void {
		for (module in modules)
			module.init(environment);

		for (module in modules)
			module.start(environment);

		for (module in modules)
			module.startTypes(environment);

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

	/**
	 * Registers an entry module (a state or substate) in the shared world, replacing any
	 * previous version so it re-runs from scratch. Returns its main type.
	 */
	public static function loadEntry(file:String, name:String, ?pack:Array<String>, ?scope:ResolveScope):IScriptedType {
		if (pack == null)
			pack = [];

		// The entry was resolved in this scope, so its classes have to resolve in it too.
		sessionScope = (scope != null) ? scope : ANY;

		// The same trust gate the mod's own classes go through. Without it a state script from an
		// untrusted mod would run while every class it imports was blocked -- which both executes
		// code the player never approved and fails in a way that reads like a broken script.
		if (blocked(file)) {
			HScript.error('Scripted state "$name" is blocked: mod not trusted', errPos(name));
			return null;
		}

		var failed:Bool = false;
		var module:Module = new Module(File.getContent(file), name, pack, file);
		module.onParsingError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(name)); };
		module.onProgramError = function(e:haxe.Exception) { failed = true; HScript.error('${e.message}', errPos(name)); };
		module.onTypeError = function(e:haxe.Exception, t:IScriptedType) { failed = true; HScript.error('${e.message}', errPos(name)); };

		if (failed)
			return null;

		var env:Environment = world();
		env.addModule(module);
		stamps.set(file, modified(file));

		var added:Array<Module> = [module];
		for (dependency in scriptedImports(module))
			load(dependency, sessionScope, added);

		startAll(added);

		if (failed)
			return null;

		return env.resolve(insanity.tools.Tools.pathToString(name, pack));
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
#end
