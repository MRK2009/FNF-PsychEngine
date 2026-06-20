package backend.osu;

typedef OsuTimingPoint = {
	var time:Float;
	var beatLength:Float;
	var meter:Int;
	var uninherited:Bool;
}

typedef OsuHitObject = {
	var posX:Int; // osu! playfield x (0..512), used to derive the mania column
	var time:Int;
	var type:Int;
	var endTime:Int; // -1 for a tap note, otherwise the hold/long-note release time
}

class OsuBeatmap {
	public var audioFilename:String = null;
	public var mode:Int = 0; // 3 == osu!mania

	public var title:String = 'Unknown';
	public var artist:String = '';
	public var creator:String = '';
	public var version:String = 'Normal';
	public var beatmapSetId:Int = -1;

	public var circleSize:Float = 4;
	public var overallDifficulty:Float = 5;

	public var timingPoints:Array<OsuTimingPoint> = [];
	public var hitObjects:Array<OsuHitObject> = [];

	public var background:String = null;
	public var video:String = null;
	public var videoOffset:Int = 0;
	public var storyboardLines:Array<String> = [];

	public function new() {}

	public var keyCount(get, never):Int;

	function get_keyCount():Int {
		var keys:Int = Math.round(circleSize);
		if (keys < 1)
			keys = 1;
		return keys;
	}

	public function isMania():Bool
		return mode == 3;

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
