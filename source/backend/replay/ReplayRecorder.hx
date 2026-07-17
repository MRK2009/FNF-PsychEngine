package backend.replay;

/**
 * Records the player's input edges during gameplay with zero measurable cost: each press/release
 * is two array pushes into the growing `ReplayData`. Press edges are logged with the exact
 * music-resynced song position `keyPressed` judges with, release edges with the frame's song
 * position -- everything playback needs for a 1:1 reproduction.
 */
final class ReplayRecorder {
	/** The replay being built. */
	public var data(default, null):ReplayData;

	/** Whether edges are being collected. */
	public var active:Bool = false;

	public function new() {
		data = new ReplayData();
	}

	/**
	 * Snapshots the run context into the replay header and arms the recorder.
	 * @param songKey the score-DB song key
	 * @param songName the song's display name
	 * @param folder the owning mod directory
	 * @param diff the difficulty index
	 * @param keyCount the column count
	 * @param playbackRate the music rate multiplier
	 * @param systemId the active scoring system id
	 */
	public function begin(songKey:String, songName:String, folder:String, diff:Int, keyCount:Int, playbackRate:Float, systemId:String):Void {
		data = new ReplayData();
		data.songKey = songKey;
		data.songName = songName;
		data.folder = folder;
		data.diff = diff;
		data.keyCount = keyCount;
		data.playbackRate = playbackRate;
		data.systemId = systemId;
		data.etternaJudge = ClientPrefs.data.etternaJudge;
		data.osuOD = ClientPrefs.data.osuOD;
		data.ratingOffset = ClientPrefs.data.ratingOffset;
		data.noteOffset = ClientPrefs.data.noteOffset;
		data.safeFrames = ClientPrefs.data.safeFrames;
		data.sickWindow = ClientPrefs.data.sickWindow;
		data.goodWindow = ClientPrefs.data.goodWindow;
		data.badWindow = ClientPrefs.data.badWindow;
		data.ghostTapping = ClientPrefs.data.ghostTapping;
		data.guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;
		data.dateSec = Date.now().getTime() / 1000;
		active = true;
	}

	/**
	 * Logs a press edge.
	 * @param column the strum column
	 * @param judgedTimeMs the resynced song position the press judges with
	 */
	public inline function notePress(column:Int, judgedTimeMs:Float):Void {
		if (active)
			data.push(column, true, judgedTimeMs);
	}

	/**
	 * Logs a release edge.
	 * @param column the strum column
	 * @param timeMs the song position at release
	 */
	public inline function noteRelease(column:Int, timeMs:Float):Void {
		if (active)
			data.push(column, false, timeMs);
	}
}
