package debug.bench;

typedef BenchScriptDef = {
	var fileName:String;
	var lua:Bool;
	var source:String;
	var copies:Int;
}

typedef BenchScenario = {
	var name:String;
	var desc:String;
	var durationSec:Float;
	var bpm:Float;
	var keyCount:Int;
	var scrollSpeed:Float;
	var playerNps:Float;
	var opponentNps:Float;
	var sustainChance:Float;
	var eventsPerBeat:Float;
	var hitchEveryMs:Float;
	var hitchLenMs:Float;
	var song:String;
	var stage:String;
	var scripts:Array<BenchScriptDef>;
}
