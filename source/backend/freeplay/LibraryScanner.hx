package backend.freeplay;

import backend.difficulty.DifficultyRating.ChartRatings;
#if sys
import sys.thread.Deque;
import sys.thread.Thread;
#end

/** One "rate this chart file" request handed to a scan worker. `path` is resolved on the main thread. */
class ScanRequest {
	public var entry:SongEntry;
	public var diffName:String;
	public var path:String;

	/**
	 * @param entry the song the chart belongs to
	 * @param diffName the difficulty being rated
	 * @param path the absolute chart-file path
	 */
	public function new(entry:SongEntry, diffName:String, path:String) {
		this.entry = entry;
		this.diffName = diffName;
		this.path = path;
	}
}

/** A finished compute: the ratings for `entry`'s `diffName` (or null if the chart couldn't be read). */
class ScanResult {
	public var entry:SongEntry;
	public var diffName:String;
	public var path:String;
	public var ratings:Null<ChartRatings>;

	/**
	 * @param entry the song the chart belongs to
	 * @param diffName the difficulty that was rated
	 * @param path the absolute chart-file path
	 * @param ratings the computed ratings, or null when the chart couldn't be read
	 */
	public function new(entry:SongEntry, diffName:String, path:String, ratings:Null<ChartRatings>) {
		this.entry = entry;
		this.diffName = diffName;
		this.path = path;
		this.ratings = ratings;
	}
}

/**
 * Background chart-rating scanner for the Freeplay library.
 *
 * A small pool of worker threads pulls `ScanRequest`s off a queue, reads the chart file with direct
 * `sys.io.File`, and runs the pure `ChartStats.ratingsFromRaw` (which never touches `FlxG.save`,
 * `Paths`, or the static `Song.parseJSON` pipeline — the only way this is thread-safe). Finished
 * `ScanResult`s go on a second queue the main thread drains each frame (`SongLibrary.poll`), where the
 * results are folded into the `SongEntry`s and persisted via `ChartScanCache` on the main thread.
 *
 * On non-`sys` targets (no threads) `drain` computes a few requests synchronously per call instead, so
 * the same producer interface keeps compiling and streaming — just cooperatively rather than in
 * parallel.
 */
class LibraryScanner {
	static inline final DEFAULT_WORKERS:Int = 3;

	/** Total requests enqueued (cold computes only — cached hits never reach the scanner). */
	public var queued(default, null):Int = 0;

	/** Requests whose result has been drained by the main thread. */
	public var completed(default, null):Int = 0;

	#if sys
	var work:Deque<ScanRequest>;
	var done:Deque<ScanResult>;
	var workerCount:Int = 0;
	var running:Bool = false;
	#else
	var pending:Array<ScanRequest> = [];
	#end

	public function new() {}

	/**
	 * Spins up the worker pool. No-op when already running or on non-`sys` targets.
	 * @param workers the pool size, defaulting to `DEFAULT_WORKERS` when null or non-positive
	 */
	public function start(?workers:Int):Void {
		#if sys
		if (running)
			return;
		running = true;
		workerCount = (workers != null && workers > 0) ? workers : DEFAULT_WORKERS;
		work = new Deque<ScanRequest>();
		done = new Deque<ScanResult>();
		// Capture the queues in locals so a worker never re-reads a (possibly nulled) field.
		var w:Deque<ScanRequest> = work;
		var d:Deque<ScanResult> = done;
		for (i in 0...workerCount)
			Thread.create(() -> workerLoop(w, d));
		#end
	}

	#if sys
	/**
	 * A worker thread's life: block on the work queue, rate charts, push results until the null sentinel.
	 * @param work the shared request queue
	 * @param done the shared result queue
	 */
	static function workerLoop(work:Deque<ScanRequest>, done:Deque<ScanResult>):Void {
		while (true) {
			var req:ScanRequest = work.pop(true);
			if (req == null)
				break; // sentinel -> exit
			var ratings:Null<ChartRatings> = null;
			try {
				if (req.path != null && sys.FileSystem.exists(req.path)) {
					var raw:String = sys.io.File.getContent(req.path);
					ratings = ChartStats.ratingsFromRaw(raw);
				}
			} catch (e:Dynamic) {
				ratings = null;
			}
			done.add(new ScanResult(req.entry, req.diffName, req.path, ratings));
		}
	}
	#end

	/**
	 * Enqueues a compute for the workers.
	 * @param req the chart to rate
	 * @param priority true pushes to the front of the queue, so an on-demand selection jumps the cold backlog
	 */
	public function enqueue(req:ScanRequest, priority:Bool = false):Void {
		queued++;
		#if sys
		if (priority)
			work.push(req);
		else
			work.add(req);
		#else
		if (priority)
			pending.unshift(req);
		else
			pending.push(req);
		#end
	}

	/**
	 * Main-thread drain of finished results. On `sys` these come off the worker queue without
	 * blocking; on non-`sys` they are computed synchronously here, a few per call, so the stream
	 * keeps flowing without a thread.
	 * @param max the most results to return in one call
	 * @return the drained results, possibly empty
	 */
	public function drain(max:Int):Array<ScanResult> {
		var out:Array<ScanResult> = [];
		#if sys
		if (done == null)
			return out;
		while (out.length < max) {
			var r:ScanResult = done.pop(false);
			if (r == null)
				break;
			completed++;
			out.push(r);
		}
		#else
		while (out.length < max && pending.length > 0) {
			var req:ScanRequest = pending.shift();
			var ratings:Null<ChartRatings> = null;
			try {
				var raw:String = openfl.utils.Assets.getText(req.path);
				if (raw != null)
					ratings = ChartStats.ratingsFromRaw(raw);
			} catch (e:Dynamic) {
				ratings = null;
			}
			completed++;
			out.push(new ScanResult(req.entry, req.diffName, req.path, ratings));
		}
		#end
		return out;
	}

	/**
	 * Whether cold computes are still outstanding.
	 * @return true while enqueued requests have not all been drained
	 */
	public inline function busy():Bool
		return completed < queued;

	/** Stops the workers (one sentinel each) and drops the queues. Safe to call once. */
	public function stop():Void {
		#if sys
		if (!running)
			return;
		running = false;
		if (work != null)
			for (i in 0...workerCount)
				work.push(null); // sentinel per worker; loops break and threads exit
		work = null;
		done = null;
		#else
		pending = [];
		#end
	}
}
