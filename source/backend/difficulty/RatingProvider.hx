package backend.difficulty;

import backend.patterns.ChartNote;

/**
 * A difficulty-rating system (osu!mania star, Etterna MSD, ...). Each provider is a
 * pure function of a flattened, time-sorted note list, the column count and a rate
 * multiplier, returning a `RatingResult`.
 *
 * `id` is a stable cache key (never change it for an existing system). `algoVersion`
 * is bumped whenever the maths changes so `DifficultyCache` recomputes stale entries
 * without throwing the whole cache away. Implementations must be deterministic and
 * side-effect free so results can be cached by chart MD5.
 */
interface RatingProvider {
	public function id():String;
	public function displayName():String;
	public function algoVersion():Int;
	public function compute(notes:Array<ChartNote>, keyCount:Int, rate:Float):RatingResult;
}
