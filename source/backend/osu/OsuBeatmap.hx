package backend.osu;

typedef OsuTimingPoint = {
	var time:Float;
	var beatLength:Float;
	var meter:Int;
	var uninherited:Bool;
}

typedef OsuHitObject = {
	var posX:Int;
	var posY:Int;
	var time:Int;
	var type:Int;
	var endTime:Int;
	var pixelLength:Float;
	var repeats:Int;
}

class OsuBeatmap {
	public static inline var MODE_STD:Int = 0;
	public static inline var MODE_MANIA:Int = 3;

	public static inline var TYPE_CIRCLE:Int = 1;
	public static inline var TYPE_SLIDER:Int = 2;
	public static inline var TYPE_SPINNER:Int = 8;
	public static inline var TYPE_HOLD:Int = 128;

	public var audioFilename:String = null;
	public var mode:Int = 0;

	public var title:String = 'Unknown';
	public var artist:String = '';
	public var creator:String = '';
	public var version:String = 'Normal';
	public var beatmapSetId:Int = -1;

	public var circleSize:Float = 4;
	public var overallDifficulty:Float = 5;
	public var hpDrainRate:Float = 5;
	public var approachRate:Float = 5;
	public var sliderMultiplier:Float = 1.4;

	public var timingPoints:Array<OsuTimingPoint> = [];
	public var hitObjects:Array<OsuHitObject> = [];

	public var background:String = null;
	public var video:String = null;
	public var videoOffset:Int = 0;
	public var storyboardLines:Array<String> = [];

	public function new() {}

	/** Number of mania columns, derived from `circleSize` (osu! stores key count there). */
	public var keyCount(get, never):Int;

	function get_keyCount():Int {
		var keys:Int = Math.round(circleSize);
		if (keys < 1)
			keys = 1;
		return keys;
	}

	public function isMania():Bool
		return mode == MODE_MANIA;

	public function isStd():Bool
		return mode == MODE_STD;

	/** Time (ms) of the latest note edge in the map, counting hold-note release times. */
	public function lastObjectTime():Float {
		var last:Float = 0;
		for (obj in hitObjects) {
			var time:Float = obj.endTime > obj.time ? obj.endTime : obj.time;
			if (time > last)
				last = time;
		}
		return last;
	}
}
