package backend.scoring;

/**
 * Registry mapping the `ClientPrefs.data.scoreSystem` value (id or display label) to a fresh
 * `ScoreSystem` instance. Every song constructs a new instance, so systems never share state
 * across runs or threads.
 */
final class ScoreSystems {
	/** Display labels for the options menu, index-aligned with `IDS`. */
	public static final LABELS:Array<String> = ['Psych', 'Wife3', 'osu!mania', 'V-Slice'];

	/** Stable system ids, index-aligned with `LABELS`. */
	public static final IDS:Array<String> = ['psych', 'wife3', 'osu_mania', 'vslice'];

	/**
	 * Builds a fresh instance of the requested system.
	 * @param idOrLabel the system id ('psych') or its display label ('Psych')
	 * @return the new system; unknown values fall back to Psych
	 */
	public static function byId(idOrLabel:String):ScoreSystem {
		return switch (normalize(idOrLabel)) {
			case 'wife3': new Wife3Scoring();
			case 'osu_mania': new OsuManiaScoring();
			case 'vslice': new VSliceScoring();
			default: new PsychScoring();
		}
	}

	/**
	 * Normalizes a pref value to a stable id.
	 * @param idOrLabel the raw pref string
	 * @return the matching id, 'psych' when unrecognized
	 */
	public static function normalize(idOrLabel:String):String {
		if (idOrLabel == null)
			return 'psych';
		var i:Int = LABELS.indexOf(idOrLabel);
		if (i >= 0)
			return IDS[i];
		return IDS.indexOf(idOrLabel) >= 0 ? idOrLabel : 'psych';
	}
}
