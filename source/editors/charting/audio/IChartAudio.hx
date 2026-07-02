package editors.charting.audio;

/**
	Playback service for the chart editor: instrumental + vocal tracks behind one clock.
	The editor only talks to this interface; `FlxChartAudio` is the FlxSound implementation.
**/
interface IChartAudio {
	/** `true` when an instrumental is loaded and playable. **/
	var loaded(get, never):Bool;

	var playing(get, never):Bool;

	/** Current playback position in ms (the editor clock while playing). **/
	var time(get, never):Float;

	/** Instrumental length in ms (0 when unloaded). **/
	var length(get, never):Float;

	/** The instrumental FlxSound for waveform sampling (`null` when unloaded). **/
	var instSound(get, never):flixel.sound.FlxSound;

	/** Waveform source by target: 0 = inst, 1 = player vocals, 2 = opponent vocals. **/
	function waveformSound(target:Int):flixel.sound.FlxSound;

	/** Loads inst + vocals for a song (safe to call with a song that has no audio). **/
	function load(songName:String, needsVoices:Bool):Void;

	function play(fromMs:Float):Void;

	function pause():Void;

	/** Seeks all tracks (works paused or playing). **/
	function seek(ms:Float):Void;

	/** Playback rate (pitch-preserving is not attempted; legacy pitch behavior). **/
	function setRate(rate:Float):Void;

	function setVolumes(inst:Float, mainVox:Float, oppVox:Float):Void;

	/** Per-frame drift resync while playing. **/
	function update(elapsed:Float):Void;

	function destroy():Void;
}
