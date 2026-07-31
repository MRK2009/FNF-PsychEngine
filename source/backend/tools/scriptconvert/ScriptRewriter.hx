package backend.tools.scriptconvert;

import backend.tools.scriptconvert.ScriptRule;

using StringTools;

/** Result of rewriting one script: the new text and how many substitutions were applied. **/
typedef RewriteResult = {
	text:String,
	changes:Int
}

/**
	How much the converter is allowed to change.

	The split is by KIND of edit, not by confidence: a rename swaps one name for another and leaves the
	shape of the code alone, so it can be checked by eye in a diff. Anything that changes the shape --
	a field read becoming a call, a statement becoming several -- can be right about the API and still
	wrong about the surrounding code, so it is opt-in.
**/
enum abstract RewriteMode(Int) from Int to Int {
	/** Renames and moved type paths only. Nothing that changes the shape of a line. **/
	var RENAMES_ONLY;

	/** The renames plus the structural rewrites in `STRUCTURAL`. **/
	var FULL;

	/** The dropdown entry for this mode. **/
	public function label():String {
		return switch (cast this : RewriteMode) {
			case RENAMES_ONLY: 'Renames and paths only';
			case FULL: 'Renames plus code rewrites';
		}
	}

	/** One line for the report header, saying what the run was allowed to touch. **/
	public function describe():String {
		return switch (cast this : RewriteMode) {
			case RENAMES_ONLY: 'renames and moved type paths only -- nothing that changes the shape of a line';
			case FULL: 'renames, moved type paths, and structural rewrites';
		}
	}
}

/**
	The auto-fix half of the Script Converter: unlike the detect-only annotate pass, this REWRITES the
	mechanical migrations in place. What it is allowed to touch depends on the `RewriteMode`:

	- `RENAMES_ONLY` (the default): the old->new Lua callback renames, the note-field renames, and the
	  moved type paths. Every one of these is old name in, new name out.
	- `FULL`: also the `STRUCTURAL` rewrites, which change the shape of the code rather than just a name.

	Whatever a run leaves behind -- the modes it wasn't allowed to touch, plus the idioms that can't be
	swapped blindly (`unspawnNotes` restructuring, removed APIs) -- the annotate pass flags in place.

	Every rename is anchored: Lua callbacks on whole-identifier boundaries, note fields only after a `.`,
	`'` or `"` (a field/table access) so unrelated locals aren't touched.
**/
class ScriptRewriter {
	/** Whole-identifier Lua callback renames (mirror `scripting.lua.api.DeprecatedFunctions` / `ScriptRules`). **/
	static final LUA_RENAMES:Array<Array<String>> = [
		['addAnimationByIndicesLoop', 'addAnimationByIndices'],
		['objectPlayAnimation', 'playAnim'],
		['characterPlayAnim', 'playAnim'],
		['luaSpriteMakeGraphic', 'makeGraphic'],
		['luaSpriteAddAnimationByPrefix', 'addAnimationByPrefix'],
		['luaSpriteAddAnimationByIndices', 'addAnimationByIndices'],
		['luaSpritePlayAnimation', 'playAnim'],
		['setLuaSpriteCamera', 'setObjectCamera'],
		['setLuaSpriteScrollFactor', 'setScrollFactor'],
		['scaleLuaSprite', 'scaleObject'],
		['getPropertyLuaSprite', 'getProperty'],
		['setPropertyLuaSprite', 'setProperty'],
		['musicFadeIn', 'soundFadeIn'],
		['musicFadeOut', 'soundFadeOut'],
		['updateHitboxFromGroup', 'updateHitbox']
	];

	/** Note-field renames on the v2 `NoteData`; matched only after a `.`/`'`/`"` so locals are safe. **/
	static final FIELD_RENAMES:Array<Array<String>> = [
		['strumTime', 'time'],
		['noteData', 'column'],
		['wasGoodHit', 'hit'],
		['sustainLength', 'length'],
		['ignoreNote', 'ignore']
	];

	/**
		Type paths that moved when the scripting runtime became one package.

		`psychlua`, `llua` and `scripting` were the same subsystem under three names; it is now all
		`scripting.*`, and the thin `llua` aliases resolve to the `hxluajit` types they always were.
		A script naming one of these by path
		-- `import psychlua.LuaUtils;` in HScript, `import('psychlua.LuaUtils')` in LuaProxy Lua --
		is rewritten in place. The bare names scripts see through `ScriptGlobals.TYPE_IMPORTS`
		(`CustomSubstate` and the rest) never changed, so nothing else has to.

		Longest path first: `psychlua.LuaProxy` must not be matched by a shorter prefix rule.
	**/
	static final TYPE_RENAMES:Array<Array<String>> = [
		['psychlua.ReflectionFunctions', 'scripting.lua.api.ReflectionFunctions'],
		['psychlua.FlxAnimateFunctions', 'scripting.lua.api.FlxAnimateFunctions'],
		['psychlua.DeprecatedFunctions', 'scripting.lua.api.DeprecatedFunctions'],
		['psychlua.ModchartAnimateSprite', 'scripting.lua.ModchartAnimateSprite'],
		['psychlua.ShaderFunctions', 'scripting.lua.api.ShaderFunctions'],
		['psychlua.ExtraFunctions', 'scripting.lua.api.ExtraFunctions'],
		['psychlua.TextFunctions', 'scripting.lua.api.TextFunctions'],
		['psychlua.CallbackHandler', 'scripting.lua.CallbackHandler'],
		['psychlua.ModchartSprite', 'scripting.lua.ModchartSprite'],
		['psychlua.CustomSubstate', 'scripting.lua.CustomSubstate'],
		['psychlua.DebugLuaText', 'scripting.lua.DebugLuaText'],
		['psychlua.PropertyPath', 'scripting.lua.PropertyPath'],
		['psychlua.PsychInterp', 'scripting.hscript.PsychInterp'],
		['psychlua.FunkinLua', 'scripting.lua.FunkinLua'],
		['psychlua.LuaProxy', 'scripting.lua.LuaProxy'],
		['psychlua.LuaUtils', 'scripting.lua.LuaUtils'],
		['psychlua.HScript', 'scripting.hscript.HScript'],
		['llua.Lua_helper', 'scripting.lua.Lua_helper'],
		['llua.Convert', 'scripting.lua.Convert'],
		['llua.LuaL', 'hxluajit.LuaL'],
		['llua.Lua', 'hxluajit.Lua']
	];

	/**
		Rewrites that change the SHAPE of a line, not just a name -- gated behind `RewriteMode.FULL`.

		`isSustainNote` was a field and `isSustain()` is a method, so the read has to become a call. That
		is correct for a plain `note.isSustainNote` read and wrong the moment the name is being assigned
		to, passed as a property string, or reached through anything the pattern can't see. A rename
		can't be wrong that way; this can, which is why it is opt-in.

		A Lua string property (`'isSustainNote'`) is left alone in both modes -- a string can't carry a
		call -- and so is an assignment target, since `note.isSustain() = true` is not valid in either
		language. Both are flagged by the annotate pass instead. The `(?!=)` inside the lookahead keeps
		`== ` a read: only a single `=` means assignment.
	**/
	static final STRUCTURAL:Array<Array<String>> = [['\\.isSustainNote\\b(?!\\s*=(?!=))', '.isSustain()']];

	/**
		Applies the mechanical renames to a script's source.
		@param src the raw script text
		@param kind the source language (`LUA` or `HSCRIPT`)
		@param mode how much to change; renames and paths only unless told otherwise
		@return the rewritten text and the number of substitutions made
	**/
	public static function rewrite(src:String, kind:ScriptKind, mode:RewriteMode = RENAMES_ONLY):RewriteResult {
		var text:String = src;
		var changes:Int = 0;

		// Both languages: an `import` naming a moved type, whether it is HScript's `import a.B;` or
		// LuaProxy's `import('a.B')`. Matched on the path itself so either form is covered.
		for (r in TYPE_RENAMES) {
			var re:EReg = new EReg('\\b' + r[0].split('.').join('\\.') + '\\b', 'g');
			changes += count(text, re);
			text = re.replace(text, r[1]);
		}

		if (kind == LUA)
			for (r in LUA_RENAMES) {
				var re:EReg = new EReg('\\b' + r[0] + '\\b', 'g');
				changes += count(text, re);
				text = re.replace(text, r[1]);
			}

		// Note-field renames apply to both Lua string props ('strumTime') and HScript field access
		// (.strumTime). The leading `.`/`'`/`"` is captured and kept so only the identifier changes.
		for (r in FIELD_RENAMES) {
			var re:EReg = new EReg("([.'\"])" + r[0] + "\\b", 'g');
			changes += count(text, re);
			text = re.replace(text, '$1' + r[1]);
		}

		if (mode == FULL)
			for (r in STRUCTURAL) {
				var re:EReg = new EReg(r[0], 'g');
				changes += count(text, re);
				text = re.replace(text, r[1]);
			}

		return {text: text, changes: changes};
	}

	/** Non-overlapping match count of `re` in `text` (EReg.replace gives no count). **/
	static function count(text:String, re:EReg):Int {
		var n:Int = 0;
		var pos:Int = 0;
		while (re.matchSub(text, pos)) {
			var p = re.matchedPos();
			n++;
			pos = p.pos + (p.len > 0 ? p.len : 1);
			if (pos > text.length)
				break;
		}
		return n;
	}
}
