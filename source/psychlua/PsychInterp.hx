package psychlua;

#if HSCRIPT_ALLOWED
import insanity.backend.Interp;
import insanity.backend.Exception.Error;

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
@:access(insanity.backend.Interp)
class PsychInterp extends Interp {
	public var parentInstance(default, set):Dynamic = null;

	var _instanceFields:Array<String> = [];

	function set_parentInstance(inst:Dynamic):Dynamic {
		parentInstance = inst;
		_instanceFields = (inst != null) ? Type.getInstanceFields(Type.getClass(inst)) : [];
		return inst;
	}

	public function new(?environment:insanity.Environment, ?parent:Dynamic) {
		super(environment, parent);
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
		if (parentInstance != null && _instanceFields.indexOf(id) >= 0)
			return Reflect.getProperty(parentInstance, id);

		error(EUnknownVariable(id));
		return null;
	}
}
#end
