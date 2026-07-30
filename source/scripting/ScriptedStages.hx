package scripting;

#if HSCRIPT_ALLOWED
import backend.BaseStage;
import backend.Mods;
import insanity.types.IScriptedType;
import insanity.types.ScriptedClass;
import psychlua.HScript;
import psychlua.HScript.HScriptInfos;
import scripting.ScriptedStates.ResolveScope;
#end

/**
	Builds a stage from a scripted class, so a modpack can ship the stage logic the engine used to
	compile in.

	A stage lives in the `stages` package under a class root, named after the stage key with its
	first letter capitalised, and extends `BaseStage` like a compiled stage does:

	    // mods/MyPack/scripts/classes/stages/Spooky.hx   ->   stage key "spooky"
	    package stages;

	    class Spooky extends BaseStage {
	        override function create() { ... }
	        override function beatHit() { ... }
	    }

	`BaseStage`'s constructor registers the stage with `PlayState` and calls `create()` itself, so
	building the instance is the whole job. That ordering is safe here: hscript-insanity binds the
	script's fields and methods BEFORE it runs the constructor chain, so the `create()` fired from
	inside `BaseStage.new` already dispatches to the script's override.

	A missing script is the normal case (most stages are pure JSON), so it resolves silently; only a
	script that exists and is wrong reports an error.
**/
class ScriptedStages {
	#if HSCRIPT_ALLOWED
	/**
		Builds the scripted stage for `stage`, or null when the pack ships no class for it.

		@param stage The stage key, e.g. `spooky` (as `PlayState.curStage` holds it).
	**/
	public static function load(stage:String):BaseStage {
		if (stage == null || stage.length < 1)
			return null;

		for (name in candidateNames(stage)) {
			var paths:Array<String> = ScriptRegistry.classPaths(ScriptRegistry.STAGE_PACKAGE + '.' + name);

			// A stage belongs to whichever mod's song is playing, which is exactly what ANY resolves
			// through (`Mods.currentModDirectory` -> globals -> shared). LAUNCHED is the fallback for
			// a launched pack, whose `currentModDirectory` the engine's week helpers repoint at will.
			var scope:ResolveScope = ANY;
			var path:String = ScriptedStates.resolveScript(paths, scope);
			#if MODS_ALLOWED
			if (path == null && Mods.launchedMod != null && Mods.launchedMod.length > 0) {
				scope = LAUNCHED;
				path = ScriptedStates.resolveScript(paths, scope);
			}
			#end
			if (path == null)
				continue;

			var type:IScriptedType = ScriptRegistry.loadEntry(path, name, [ScriptRegistry.STAGE_PACKAGE], scope);
			if (type == null || !(type is ScriptedClass)) {
				HScript.error('Scripted stage "$name" must declare a class named "$name"', errPos(name));
				return null;
			}

			var inst:Dynamic = ScriptRegistry.build(cast type, name);
			if (inst == null)
				return null;

			if (!(inst is BaseStage)) {
				HScript.error('Scripted stage "$name" must extend BaseStage', errPos(name));
				return null;
			}
			return cast inst;
		}
		return null;
	}

	/** Whether a scripted class exists for `stage`, without building it. **/
	public static function exists(stage:String):Bool {
		if (stage == null || stage.length < 1)
			return false;

		for (name in candidateNames(stage)) {
			var paths:Array<String> = ScriptRegistry.classPaths(ScriptRegistry.STAGE_PACKAGE + '.' + name);
			if (ScriptedStates.resolveScript(paths, ANY) != null)
				return true;
			#if MODS_ALLOWED
			if (Mods.launchedMod != null && Mods.launchedMod.length > 0 && ScriptedStates.resolveScript(paths, LAUNCHED) != null)
				return true;
			#end
		}
		return false;
	}

	/**
		Class names to try for a stage key, best first: the Haxe-cased name (`phillyStreets` ->
		`PhillyStreets`), then the key verbatim for packs that named the class in lower case.
	**/
	static function candidateNames(stage:String):Array<String> {
		var capitalised:String = stage.charAt(0).toUpperCase() + stage.substr(1);
		return (capitalised == stage) ? [stage] : [capitalised, stage];
	}

	static inline function errPos(name:String):HScriptInfos
		return cast {fileName: name, showLine: false};
	#else
	public static function load(stage:String):backend.BaseStage
		return null;

	public static function exists(stage:String):Bool
		return false;
	#end
}
