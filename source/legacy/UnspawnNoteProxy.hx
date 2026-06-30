package legacy;

import objects.notes.NoteData;
import objects.Note; // = legacy.LegacyNote

/**
	A `compatibilityMode` stand-in for one un-spawned chart note, placed in `game.unspawnNotes` so old
	load-time scripts -- e.g. `setPropertyFromGroup('unspawnNotes', i, 'texture', 'X_assets')` in
	`onCreatePost` -- keep working against the v2 runtime (which otherwise has no up-front note list).

	It wraps the real `NoteData` the field will spawn; `flush` copies the props a script set on the proxy
	back onto that `NoteData` *before* `buildNoteFields` builds the drawables, so the change takes effect
	when the note actually spawns. Never drawn (`visible = active = false`).
**/
class UnspawnNoteProxy extends Note {
	public var dataRef:NoteData;

	/**
		@param d the chart note this proxy mirrors (and writes back to on `flush`)
	**/
	public function new(d:NoteData) {
		super(d.time, d.column, null, d.isSustain(), false);
		dataRef = d;
		visible = false;
		active = false;
		moves = false;
		strumTime = d.time; // the base ctor re-adds noteOffset; d.time already carries it
		@:bypassAccessor noteType = d.type;
		mustPress = d.mustPress;
		sustainLength = d.length;
		missHealth = d.missHealth;
		hitHealth = d.hitHealth;
		ignoreNote = d.ignore;
		@:bypassAccessor texture = d.texture;
	}

	// Store the script-set texture without the heavy reloadNote -- this proxy is never drawn, and the
	// real graphic is loaded by the v2 NoteSprite from `dataRef.texture` after flush.
	override function set_texture(value:String):String {
		@:bypassAccessor this.texture = value;
		return value;
	}

	/** Copies the props a script mutated on this proxy back onto the `NoteData` the field will spawn. **/
	public function flush():Void {
		if (dataRef == null)
			return;
		if (texture != null && texture.length > 0)
			dataRef.texture = texture;
		dataRef.missHealth = missHealth;
		dataRef.hitHealth = hitHealth;
		dataRef.ignore = ignoreNote;
	}
}
