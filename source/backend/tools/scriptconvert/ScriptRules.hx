package backend.tools.scriptconvert;

import backend.tools.scriptconvert.ScriptRule;

/**
	The Script Converter's detection catalog: every outdated Lua/HScript idiom the engine knows
	about, paired with the guidance to show. Each row is seeded from a real source -- the Lua
	renames mirror `psychlua.DeprecatedFunctions`, the note-field mappings mirror
	`objects.notes.NoteData`, and the `compatibilityMode` notes mirror the `legacy/` layer
	(`NoteCompatLayer`, `UnspawnNoteProxy`). Adding a new deprecation is a one-line append.

	Order is stable and roughly severity-first within each group; the scanner reports hits in the
	order they appear on each line, so keep the more specific rules above the broader ones.
**/
class ScriptRules {
	/** The full rule set. `ScriptScanner` filters this per file by `appliesTo`. **/
	public static final RULES:Array<ScriptRule> = [
		// ---- Renamed Lua callbacks (mirror psychlua.DeprecatedFunctions) --------------------
		{re: ~/\baddAnimationByIndicesLoop\b/, kind: RENAMED, appliesTo: LUA, message: 'addAnimationByIndicesLoop was replaced.', suggestion: 'Use addAnimationByIndices.', replace: 'addAnimationByIndices'},
		{re: ~/\bobjectPlayAnimation\b/, kind: RENAMED, appliesTo: LUA, message: 'objectPlayAnimation was replaced.', suggestion: 'Use playAnim.', replace: 'playAnim'},
		{re: ~/\bcharacterPlayAnim\b/, kind: RENAMED, appliesTo: LUA, message: 'characterPlayAnim was replaced.', suggestion: 'Use playAnim.', replace: 'playAnim'},
		{re: ~/\bluaSpriteMakeGraphic\b/, kind: RENAMED, appliesTo: LUA, message: 'luaSpriteMakeGraphic was replaced.', suggestion: 'Use makeGraphic.', replace: 'makeGraphic'},
		{re: ~/\bluaSpriteAddAnimationByPrefix\b/, kind: RENAMED, appliesTo: LUA, message: 'luaSpriteAddAnimationByPrefix was replaced.', suggestion: 'Use addAnimationByPrefix.', replace: 'addAnimationByPrefix'},
		{re: ~/\bluaSpriteAddAnimationByIndices\b/, kind: RENAMED, appliesTo: LUA, message: 'luaSpriteAddAnimationByIndices was replaced.', suggestion: 'Use addAnimationByIndices.', replace: 'addAnimationByIndices'},
		{re: ~/\bluaSpritePlayAnimation\b/, kind: RENAMED, appliesTo: LUA, message: 'luaSpritePlayAnimation was replaced.', suggestion: 'Use playAnim.', replace: 'playAnim'},
		{re: ~/\bsetLuaSpriteCamera\b/, kind: RENAMED, appliesTo: LUA, message: 'setLuaSpriteCamera was replaced.', suggestion: 'Use setObjectCamera.', replace: 'setObjectCamera'},
		{re: ~/\bsetLuaSpriteScrollFactor\b/, kind: RENAMED, appliesTo: LUA, message: 'setLuaSpriteScrollFactor was replaced.', suggestion: 'Use setScrollFactor.', replace: 'setScrollFactor'},
		{re: ~/\bscaleLuaSprite\b/, kind: RENAMED, appliesTo: LUA, message: 'scaleLuaSprite was replaced.', suggestion: 'Use scaleObject.', replace: 'scaleObject'},
		{re: ~/\bgetPropertyLuaSprite\b/, kind: RENAMED, appliesTo: LUA, message: 'getPropertyLuaSprite was replaced.', suggestion: 'Use getProperty.', replace: 'getProperty'},
		{re: ~/\bsetPropertyLuaSprite\b/, kind: RENAMED, appliesTo: LUA, message: 'setPropertyLuaSprite was replaced.', suggestion: 'Use setProperty.', replace: 'setProperty'},
		{re: ~/\bmusicFadeIn\b/, kind: RENAMED, appliesTo: LUA, message: 'musicFadeIn was replaced.', suggestion: 'Use soundFadeIn.', replace: 'soundFadeIn'},
		{re: ~/\bmusicFadeOut\b/, kind: RENAMED, appliesTo: LUA, message: 'musicFadeOut was replaced.', suggestion: 'Use soundFadeOut.', replace: 'soundFadeOut'},
		{re: ~/\bupdateHitboxFromGroup\b/, kind: RENAMED, appliesTo: LUA, message: 'updateHitboxFromGroup was replaced.', suggestion: 'Use updateHitbox.', replace: 'updateHitbox'},

		// ---- HScript patterns ---------------------------------------------------------------
		{re: ~/\baddHaxeLibrary\b/, kind: DEPRECATED, appliesTo: HSCRIPT, message: 'addHaxeLibrary is deprecated.', suggestion: 'Import classes with a normal "import" statement at the top of the script.'},

		// ---- Note field renames (mirror objects.notes.NoteData; match .field and Lua "field") -
		{re: ~/[.'"]strumTime\b/, kind: RENAMED, appliesTo: BOTH, message: 'The note field strumTime was renamed on the v2 NoteData.', suggestion: 'Use time.', replace: 'time'},
		{re: ~/[.'"]noteData\b/, kind: RENAMED, appliesTo: BOTH, message: 'The note column field noteData was renamed on the v2 NoteData.', suggestion: 'Use column.', replace: 'column'},
		{re: ~/[.'"]wasGoodHit\b/, kind: RENAMED, appliesTo: BOTH, message: 'The note hit flag wasGoodHit was renamed on the v2 NoteData.', suggestion: 'Use hit.', replace: 'hit'},
		{re: ~/[.'"]sustainLength\b/, kind: RENAMED, appliesTo: BOTH, message: 'The sustain length field sustainLength was renamed on the v2 NoteData.', suggestion: 'Use length.', replace: 'length'},
		{re: ~/[.'"]ignoreNote\b/, kind: RENAMED, appliesTo: BOTH, message: 'The note ignore flag ignoreNote was renamed on the v2 NoteData.', suggestion: 'Use ignore.', replace: 'ignore'},

		// ---- Note structure removed in v2 ---------------------------------------------------
		{re: ~/[.'"]isSustainNote\b/, kind: REMOVED, appliesTo: BOTH, message: 'isSustainNote no longer exists: a v2 sustain is a single NoteData with length > 0.', suggestion: 'Use isSustain() (or check length > 0).'},
		{re: ~/[.'"]prevNote\b/, kind: REMOVED, appliesTo: BOTH, message: 'prevNote no longer exists: v2 sustains are one NoteData, not a head + stacked-tail chain.', suggestion: 'Read the single NoteData (length > 0) instead of walking a prevNote chain.'},

		// ---- unspawnNotes (compat-only via legacy/UnspawnNoteProxy) --------------------------
		// Not auto-rewritten: turning an up-front unspawnNotes loop into per-note callbacks is a
		// structural change, so the converter guides the port instead of swapping tokens.
		{
			re: ~/\bunspawnNotes\b/, kind: COMPAT_ONLY, appliesTo: BOTH,
			message: 'unspawnNotes (the whole pre-spawned chart) only exists under compatibilityMode via a legacy proxy, and per-note edits through it are unreliable in v2.',
			suggestion: 'Port the loop BODY into onSpawnNote, which fires once per note as it spawns -- move whatever you set on each unspawned note (texture / type / x / y / alpha / ignore) onto the spawning note there. '
				+ 'Target it with the callback id: setPropertyFromGroup(\'game.<side>Field.notes\', id, \'<field>\', value) (Lua), or read the callback noteData directly (HScript). '
				+ 'For up-front reads that just count/measure the chart, iterate the chart data once in onCreatePost instead of unspawnNotes.'
		},

		// ---- Common per-note callback bug: `i` is not defined inside note callbacks ---------
		{re: ~/PropertyFromGroup\s*\(\s*['"][^'"]*['"]\s*,\s*i\s*,/, kind: DEPRECATED, appliesTo: LUA, message: 'This indexes a note group with `i`, which is nil inside note callbacks (Lua coerces it to 0), so it always hits the wrong note.', suggestion: 'Use the callback\'s `id` argument: in v2 it is the note\'s index in its field\'s active list (valid inside the callback).'},

		// ---- Write-through mirrors under compatibilityMode ----------------------------------
		{re: ~/\bnotes\.members\s*\[/, kind: REMOVED, appliesTo: BOTH, message: 'Indexing game.notes.members by the callback id no longer works: v2 hit/miss callbacks pass id = -1 (there is no member index anymore).', suggestion: 'Read game.lastJudgedNote in hit/miss callbacks; in onSpawnNote, id indexes the field, so use setPropertyFromGroup(\'game.<side>Field.notes\', id, ...).'},
		{re: ~/\bnotes\.members\b/, kind: COMPAT_ONLY, appliesTo: BOTH, message: 'game.notes is a compatibilityMode mirror; visual writes (x/y/alpha/angle with copyX etc. off, offsetX/offsetY/multAlpha/multSpeed) now propagate to the real v2 drawables, but structural add/remove does not.', suggestion: 'Prefer the v2 fields / note types; native v2 targets game.playerField / opponentField (.notes) with the onSpawnNote id.'},
		{re: ~/\bplayerStrums\b|\bopponentStrums\b|\bstrumLineNotes\b/, kind: COMPAT_ONLY, appliesTo: BOTH, message: 'The strum groups are compatibilityMode mirrors; x/y/alpha/angle writes now move the real receptors, but other props stay read-only.', suggestion: 'Native v2: move/scale the real strums via playerReceptors / opponentReceptors.'},

		// ---- Note-skin pointers (still work; nudge toward the folder note-skin system) -------
		{re: ~/\barrowSkin\b/, kind: DEPRECATED, appliesTo: BOTH, message: 'arrowSkin is the classic single-sheet skin field.', suggestion: 'Consider the folder note-skin system (backend.NoteSkinConfig / backend.noteskin.FolderNoteSkin).'},
		{re: ~/\bdefaultNoteSkin\b|noteSkins\/NOTE_assets/, kind: DEPRECATED, appliesTo: BOTH, message: 'This references the classic noteSkins/NOTE_assets sheet.', suggestion: 'The folder note-skin system supersedes it (backend.NoteSkinConfig).'}
	];

	/**
		The rules that apply to a given file language.
		@param kind the file's language (`LUA` or `HSCRIPT`)
		@return the matching subset (rules tagged `BOTH` always included)
	**/
	public static function forKind(kind:ScriptKind):Array<ScriptRule> {
		var out:Array<ScriptRule> = [];
		for (rule in RULES)
			if (rule.appliesTo == BOTH || rule.appliesTo == kind)
				out.push(rule);
		return out;
	}
}
