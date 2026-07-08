package backend.tools.scriptconvert;

import backend.tools.scriptconvert.ScriptRule;

using StringTools;

/** Result of rewriting one script: the new text and how many substitutions were applied. **/
typedef RewriteResult = {
	text:String,
	changes:Int
}

/**
	The auto-fix half of the Script Converter: unlike the detect-only annotate pass, this REWRITES the
	safe, mechanical migrations in place -- the old->new Lua callback renames, the note-field renames, and
	`isSustainNote` -> `isSustain()`. The residual idioms that can't be swapped blindly (`unspawnNotes`
	restructuring, removed APIs) are left for the annotate pass to flag.

	Every rename is anchored: Lua callbacks on whole-identifier boundaries, note fields only after a `.`,
	`'` or `"` (a field/table access) so unrelated locals aren't touched.
**/
class ScriptRewriter {
	/** Whole-identifier Lua callback renames (mirror `psychlua.DeprecatedFunctions` / `ScriptRules`). **/
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
		Applies the mechanical renames to a script's source.
		@param src the raw script text
		@param kind the source language (`LUA` or `HSCRIPT`)
		@return the rewritten text and the number of substitutions made
	**/
	public static function rewrite(src:String, kind:ScriptKind):RewriteResult {
		var text:String = src;
		var changes:Int = 0;

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

		// isSustainNote (a v2-removed field) -> the isSustain() method. `.isSustainNote` becomes
		// `.isSustain()`; a Lua string prop `'isSustainNote'` can't be a method call, so it's left for the
		// annotate pass. HScript `note.isSustainNote` reads become `note.isSustain()` cleanly.
		var susRe:EReg = new EReg('\\.isSustainNote\\b', 'g');
		changes += count(text, susRe);
		text = susRe.replace(text, '.isSustain()');

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
