package backend.patterns;

typedef ChartNote = {
	var time:Float;
	var lane:Int;
	var length:Float;
	var type:String;
	@:optional var hitsounds:Array<{file:String, volume:Float}>;
}
