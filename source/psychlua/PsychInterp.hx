package psychlua;

#if HSCRIPT_ALLOWED
import insanity.runtime.Interp;
import insanity.runtime.Error;

/**
 * insanity interpreter with one Psych-specific addition: bare-identifier
 * resolution against a "parent instance" (the state that created the script).
 *
 * This restores the old hscript-iris `CustomInterp` behaviour so existing mod
 * scripts that reference a `PlayState` field directly -- e.g. `playerStrums`
 * instead of `game.playerStrums` -- keep working.
 *
 * Installed globally via `HScript.setupConfig()` (`Config.interpClass`).
 */
@:access(insanity.runtime.Interp)
class PsychInterp extends Interp {
	public var parentInstance(default, set):Dynamic = null;

	/**
	 * The parent instance's field names, as a set.
	 *
	 * A `Map`, not the `Array` `Type.getInstanceFields` hands back: this is consulted for every
	 * identifier the script does not otherwise resolve, and for the base of every member access
	 * (`isResolvable`). `parentInstance` is usually `PlayState`, whose field list runs to several
	 * hundred entries, so a linear `indexOf` put a few hundred string comparisons on a path that
	 * runs many times per frame.
	 */
	var _instanceFields:Map<String, Bool> = new Map();

	function set_parentInstance(inst:Dynamic):Dynamic {
		parentInstance = inst;
		_instanceFields = new Map();
		if (inst != null) {
			var cls:Class<Dynamic> = Type.getClass(inst);
			if (cls != null)
				for (field in Type.getInstanceFields(cls))
					_instanceFields.set(field, true);
		}
		return inst;
	}

	public function new(?environment:insanity.Environment, ?parent:Dynamic) {
		super(environment, parent);
	}

	// The base `resolveField` (member access `a.b`) gates the base identifier
	// behind `isResolvable()` and errors WITHOUT calling `resolve()` when it
	// returns false -- which would bypass the parentInstance fallback below.
	// Teach it about parent-instance fields so `camHUD.zoom` works the same as
	// the bare identifier `camHUD` (EIdent goes straight through `resolve`).
	// Purely additive: when parentInstance is null (e.g. scripted states that
	// never set it) this short-circuits to the base behaviour.
	override public function isResolvable(id:String):Bool {
		return super.isResolvable(id) || (parentInstance != null && _instanceFields.exists(id));
	}

	// Write-back counterpart to `resolve`: assigning to a creating-state field by
	// bare identifier (e.g. `camZooming = false`) targets the instance field, the
	// same way reads of it do. Only fires for a genuine instance field that isn't
	// shadowed by an import or script variable; everything else (Mirror
	// properties, the strict undeclared-variable error for non-fields like a
	// typo'd local) defers to insanity unchanged.
	override function setVar(name:String, v:Dynamic):Dynamic {
		if (!imports.exists(name) && !variables.exists(name) && parentInstance != null && _instanceFields.exists(name)) {
			Reflect.setProperty(parentInstance, name, v);
			return v;
		}
		return super.setVar(name, v);
	}

	override public function resolve(id:String):Dynamic {
		if (imports.exists(id)) {
			var v:Dynamic = imports.get(id);
			if (v == null)
				error(ECustom('Module $id does not define type $id'));
			return resolveMirror(v);
		}

		if (variables.exists(id))
			return resolveMirror(variables.get(id));

		// Back-compat: resolve a field of the creating state as a bare identifier.
		if (parentInstance != null && _instanceFields.exists(id))
			return Reflect.getProperty(parentInstance, id);

		error(EUnknownVariable(id));
		return null;
	}
}
#end
