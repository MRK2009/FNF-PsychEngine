package backend.replay;

/**
 * Streams a `ReplayData`'s input edges back into gameplay. The PlayState drains due edges each
 * frame (before `keysCheck`): press edges re-enter `keyPressed` with the song position forced to
 * the recorded value, so every judgement sees the bit-identical offset it saw live; the `held`
 * array replaces `Controls.pressed` for sustain sampling, flipping exactly at the recorded edges
 * like real event-driven key state.
 */
final class ReplayPlayer {
	/** The replay being played. */
	public var data(default, null):ReplayData;

	/** The next edge index to fire. */
	public var cursor(default, null):Int = 0;

	/** Live virtual key state per column, driven by the fired edges. */
	public var held(default, null):Array<Bool>;

	/**
	 * @param data the replay to play
	 */
	public function new(data:ReplayData) {
		this.data = data;
		held = [for (_ in 0...(data.keyCount < 1 ? 4 : data.keyCount)) false];
	}

	/** @return true when every edge has fired */
	public inline function finished():Bool
		return cursor >= data.times.length;

	/**
	 * Whether the next edge is due at a song position.
	 * @param songPos the current song position in ms
	 * @return true when an edge should fire now
	 */
	public inline function due(songPos:Float):Bool
		return cursor < data.times.length && data.times[cursor] <= songPos;

	/** @return the next edge's recorded song position */
	public inline function nextTime():Float
		return data.times[cursor];

	/** @return the next edge's column */
	public inline function nextColumn():Int
		return data.columns[cursor] & 0x7F;

	/** @return whether the next edge is a press */
	public inline function nextDown():Bool
		return (data.columns[cursor] & 0x80) != 0;

	/** Marks the current edge as fired and updates the virtual key state. */
	public function advance():Void {
		var col:Int = nextColumn();
		if (col >= 0 && col < held.length)
			held[col] = nextDown();
		cursor++;
	}
}
