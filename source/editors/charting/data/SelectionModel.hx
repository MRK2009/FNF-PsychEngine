package editors.charting.data;

import backend.SongChart.SongNote;

/**
	The set of currently selected notes (identity references into `chart.noteList`).
	`onChanged` fires once per user-level operation, not per element.
**/
final class SelectionModel {
	/** The selected notes (live references; do not mutate directly). **/
	public final notes:Array<SongNote> = [];

	/** Fired after the selection changes. **/
	public var onChanged:Void->Void = null;

	public function new() {}

	/** The number of selected notes. **/
	public var count(get, never):Int;

	inline function get_count():Int {
		return notes.length;
	}

	/**
		Whether a note is selected (identity comparison).
		@param n the note to test
		@return `true` when selected
	**/
	public inline function has(n:SongNote):Bool {
		return notes.indexOf(n) >= 0;
	}

	/**
		Adds a note to the selection (no-op when already selected).
		@param n the note to select
	**/
	public function add(n:SongNote):Void {
		if (notes.indexOf(n) < 0) {
			notes.push(n);
			changed();
		}
	}

	/**
		Removes a note from the selection.
		@param n the note to deselect
	**/
	public function remove(n:SongNote):Void {
		if (notes.remove(n))
			changed();
	}

	/**
		Flips a note's selected state.
		@param n the note to toggle
	**/
	public function toggle(n:SongNote):Void {
		if (!notes.remove(n))
			notes.push(n);
		changed();
	}

	/** Empties the selection. **/
	public function clear():Void {
		if (notes.length == 0)
			return;
		notes.resize(0);
		changed();
	}

	/** Replaces the whole selection in one operation. **/
	public function setAll(list:Array<SongNote>):Void {
		notes.resize(0);
		var i:Int = 0;
		var n:Int = list.length;
		while (i < n) {
			notes.push(list[i]);
			i++;
		}
		changed();
	}

	/** Drops references that no longer exist in the chart (after undo/restore). **/
	public function prune(existing:Array<SongNote>):Void {
		var i:Int = notes.length;
		var removed:Bool = false;
		while (--i >= 0) {
			if (existing.indexOf(notes[i]) < 0) {
				notes.splice(i, 1);
				removed = true;
			}
		}
		if (removed)
			changed();
	}

	inline function changed():Void {
		if (onChanged != null)
			onChanged();
	}
}
