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
		// Build as a HEAD (sustainNote = false): in the pre-v2 model a hold is a head with
		// `isSustainNote == false`, `sustainLength > 0` and a non-empty `tail`; only the per-step pieces
		// had `isSustainNote == true`. A v2 hold is a single `NoteData`, so the proxy stands in for the
		// head and exposes a one-entry `tail`, which keeps old `if (!isSustainNote) ... tail.length`
		// object-counting / hold-detection working.
		super(d.time, d.column, null, false, false);
		dataRef = d;
		visible = false;
		active = false;
		moves = false;
		strumTime = d.time; // the base ctor re-adds noteOffset; d.time already carries it
		@:bypassAccessor noteType = d.type;
		mustPress = d.mustPress;
		sustainLength = d.length;
		if (d.isSustain())
			tail = [this];
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

	/**
		Writes every prop a load-time script may have changed on this proxy back onto its `NoteData` (the
		typed chart the field spawns) and returns it. This is what makes pre-spawn chart transforms -- e.g.
		the double-chart script flipping `mustPress` per section -- take effect: the rebuild collects each
		proxy's `flush()` in `game.unspawnNotes` order.
		@return the updated `NoteData`
	**/
	public function flush():NoteData {
		var d:NoteData = dataRef;
		if (d == null)
			return null;
		d.time = strumTime;
		d.column = noteData;
		d.mustPress = mustPress;
		d.length = sustainLength;
		d.type = noteType;
		d.animSuffix = animSuffix;
		d.gfNote = gfNote;
		d.noAnimation = noAnimation;
		d.noMissAnimation = noMissAnimation;
		d.ignore = ignoreNote;
		d.hitHealth = hitHealth;
		d.missHealth = missHealth;
		if (texture != null && texture.length > 0)
			d.texture = texture;
		if (extraData != null)
			for (k => v in extraData)
				d.extraData.set(k, v);
		return d;
	}
}
