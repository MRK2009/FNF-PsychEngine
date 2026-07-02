package editors.charting.data;

/**
	The grid snap selection: divisions of a 4/4 measure (`1/16` = one step). Pure state -
	`ChartEditorModel.snapTime` does the actual quantizing.
**/
final class SnapGrid {
	/** The available snap divisions, coarsest to finest. **/
	public static final SNAPS:Array<Int> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];

	/** The current index into `SNAPS`. **/
	public var index(default, null):Int = 3;

	/** The current division (e.g. 16 for `1/16`). **/
	public var value(get, never):Int;

	inline function get_value():Int {
		return SNAPS[index];
	}

	public function new() {}

	/**
		The current selection as display text.
		@return e.g. `1/16`
	**/
	public function label():String {
		return '1/${SNAPS[index]}';
	}

	/** Steps the snap selection by `dir` (clamped). **/
	public function cycle(dir:Int):Void {
		var next:Int = index + dir;
		if (next < 0)
			next = 0;
		if (next >= SNAPS.length)
			next = SNAPS.length - 1;
		index = next;
	}

	/** Selects the closest snap entry to a persisted index. **/
	public function select(idx:Int):Void {
		index = (idx < 0) ? 0 : (idx >= SNAPS.length ? SNAPS.length - 1 : idx);
	}
}
