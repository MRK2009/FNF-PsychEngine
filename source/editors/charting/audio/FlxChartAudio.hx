package editors.charting.audio;

import backend.Paths;
import flixel.FlxG;
import flixel.sound.FlxSound;
import openfl.media.Sound;

/**
	`IChartAudio` on `FlxSound`: instrumental is the clock; player/opponent vocals follow it
	with a drift resync. Vocal files resolve like the legacy editor: `Voices-Player` /
	`Voices-Opponent`, falling back to plain `Voices` for the player side.
**/
final class FlxChartAudio implements IChartAudio {
	final inst:FlxSound;
	final vocals:FlxSound;
	final oppVocals:FlxSound;

	var hasInst:Bool = false;
	var hasVocals:Bool = false;
	var hasOpp:Bool = false;

	var instVol:Float = 1;
	var mainVol:Float = 1;
	var oppVol:Float = 1;
	var rate:Float = 1;

	/** See `IChartAudio.loaded`. **/
	public var loaded(get, never):Bool;

	/** See `IChartAudio.playing`. **/
	public var playing(get, never):Bool;

	/** See `IChartAudio.time`. **/
	public var time(get, never):Float;

	/** See `IChartAudio.length`. **/
	public var length(get, never):Float;

	inline function get_loaded():Bool {
		return hasInst;
	}

	inline function get_playing():Bool {
		return hasInst && inst.playing;
	}

	inline function get_time():Float {
		return hasInst ? inst.time : 0;
	}

	inline function get_length():Float {
		return hasInst ? inst.length : 0;
	}

	/** See `IChartAudio.instSound`. **/
	public var instSound(get, never):FlxSound;

	inline function get_instSound():FlxSound {
		return hasInst ? inst : null;
	}

	/** See `IChartAudio.waveformSound`. **/
	public function waveformSound(target:Int):FlxSound {
		return switch (target) {
			case 1: hasVocals ? vocals : null;
			case 2: hasOpp ? oppVocals : null;
			default: hasInst ? inst : null;
		}
	}

	/** Creates the three tracks and registers them with the sound list. **/
	public function new() {
		inst = new FlxSound();
		inst.persist = false;
		FlxG.sound.list.add(inst);
		vocals = new FlxSound();
		vocals.persist = false;
		FlxG.sound.list.add(vocals);
		oppVocals = new FlxSound();
		oppVocals.persist = false;
		FlxG.sound.list.add(oppVocals);
	}

	/** See `IChartAudio.load`. **/
	public function load(songName:String, needsVoices:Bool):Void {
		pause();
		hasInst = false;
		hasVocals = false;
		hasOpp = false;
		if (songName == null || songName.length == 0)
			return;

		try {
			var snd:Sound = Paths.inst(songName);
			if (snd != null && snd.length > 0) {
				inst.loadEmbedded(snd);
				hasInst = true;
			}
		} catch (e:Dynamic) {}
		if (!hasInst)
			return;

		if (needsVoices) {
			try {
				var plr:Sound = Paths.voices(songName, 'Player');
				if (plr == null)
					plr = Paths.voices(songName);
				if (plr != null && plr.length > 0) {
					vocals.loadEmbedded(plr);
					hasVocals = true;
				}
			} catch (e:Dynamic) {}
			try {
				var opp:Sound = Paths.voices(songName, 'Opponent');
				if (opp != null && opp.length > 0) {
					oppVocals.loadEmbedded(opp);
					hasOpp = true;
				}
			} catch (e:Dynamic) {}
		}
		applyVolumes();
		applyRate();
	}

	/** See `IChartAudio.play`. **/
	public function play(fromMs:Float):Void {
		if (!hasInst)
			return;
		if (fromMs < 0)
			fromMs = 0;
		if (fromMs >= inst.length)
			return;
		inst.play(true, fromMs);
		if (hasVocals && fromMs < vocals.length)
			vocals.play(true, fromMs);
		if (hasOpp && fromMs < oppVocals.length)
			oppVocals.play(true, fromMs);
		applyVolumes();
		applyRate();
	}

	/** See `IChartAudio.pause`. **/
	public function pause():Void {
		if (!hasInst)
			return;
		inst.pause();
		vocals.pause();
		oppVocals.pause();
	}

	/** See `IChartAudio.seek`. **/
	public function seek(ms:Float):Void {
		if (!hasInst)
			return;
		if (ms < 0)
			ms = 0;
		if (ms > inst.length)
			ms = inst.length;
		var wasPlaying:Bool = inst.playing;
		if (wasPlaying) {
			pause();
			inst.time = ms;
			play(ms);
		} else {
			inst.time = ms;
			if (hasVocals)
				vocals.time = (ms < vocals.length) ? ms : vocals.length;
			if (hasOpp)
				oppVocals.time = (ms < oppVocals.length) ? ms : oppVocals.length;
		}
	}

	/** See `IChartAudio.setRate`. **/
	public function setRate(rate:Float):Void {
		this.rate = (rate > 0) ? rate : 1;
		applyRate();
	}

	/** See `IChartAudio.setVolumes`. **/
	public function setVolumes(inst:Float, mainVox:Float, oppVox:Float):Void {
		instVol = inst;
		mainVol = mainVox;
		oppVol = oppVox;
		applyVolumes();
	}

	function applyVolumes():Void {
		inst.volume = instVol;
		vocals.volume = mainVol;
		oppVocals.volume = oppVol;
	}

	function applyRate():Void {
		#if FLX_PITCH
		inst.pitch = rate;
		vocals.pitch = rate;
		oppVocals.pitch = rate;
		#end
	}

	/** See `IChartAudio.update` (vocal drift resync). **/
	public function update(elapsed:Float):Void {
		if (!playing)
			return;
		var now:Float = inst.time;
		if (hasVocals && vocals.playing && Math.abs(vocals.time - now) > 30)
			vocals.time = now;
		if (hasOpp && oppVocals.playing && Math.abs(oppVocals.time - now) > 30)
			oppVocals.time = now;
	}

	/** See `IChartAudio.destroy`. **/
	public function destroy():Void {
		inst.stop();
		vocals.stop();
		oppVocals.stop();
		FlxG.sound.list.remove(inst, true);
		FlxG.sound.list.remove(vocals, true);
		FlxG.sound.list.remove(oppVocals, true);
		inst.destroy();
		vocals.destroy();
		oppVocals.destroy();
	}
}
