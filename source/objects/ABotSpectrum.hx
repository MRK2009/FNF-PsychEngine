package objects;

import flixel.sound.FlxSound;
#if funkin.vis
import funkin.vis.dsp.SpectralAnalyzer;
#end

/**
	Per-band audio levels for a playing `FlxSound`, as a plain `Array<Float>`.

	The one piece of a spectrum visualiser (the A-Bot speaker, a modder's own EQ bars) a script
	cannot do for itself: the analysis needs `funkin.vis` running against the OpenAL audio source
	behind the sound, which is both a haxelib type and private OpenFL state. Everything above it --
	sprites, animation, how a level maps to a frame -- belongs in the script.

	    var spectrum = new ABotSpectrum(7);
	    spectrum.bind(FlxG.sound.music);
	    // per frame:
	    var levels = spectrum.levels();
	    for (i in 0...levels.length) bars[i].animation.curAnim.curFrame = Math.round(levels[i] * 5);

	Levels come back normalised (0 = silence, 1 = full), one per band, and the returned array is
	reused between calls so a per-frame read allocates nothing. Without the `funkin.vis` haxelib
	every level reads 0 and `ready` is false, so a script built on this still runs.
**/
class ABotSpectrum {
	/** Number of frequency bands this analyses. **/
	public var bands(default, null):Int;

	/** Whether a sound is bound and the analyser is live. **/
	public var ready(get, never):Bool;

	var _out:Array<Float>;
	var _snd:FlxSound;

	#if funkin.vis
	var _analyzer:SpectralAnalyzer;
	var _bars:Array<Bar>;
	#end

	final _smoothing:Float;
	final _peakHold:Int;

	/**
		Defaults match the A-Bot speaker's own analyser settings.

		@param bands     Frequency bands to split the signal into (the A-Bot uses 7).
		@param smoothing Smoothing time constant: lower reacts faster, higher glides.
		@param peakHold  Frames a band holds its peak before falling back.
	**/
	public function new(bands:Int = 7, smoothing:Float = 0.1, peakHold:Int = 40) {
		this.bands = bands;
		_smoothing = smoothing;
		_peakHold = peakHold;
		_out = [for (_ in 0...bands) 0.0];
	}

	/**
		Points the analyser at `snd`. Call again whenever the sound is replaced or restarted: the
		analyser is tied to the audio source that was live at bind time.
	**/
	public function bind(snd:FlxSound):Void {
		_snd = snd;
		#if funkin.vis
		_analyzer = null;
		if (snd == null)
			return;

		@:privateAccess
		var source:Dynamic = (snd._channel != null) ? snd._channel.__audioSource : null;
		if (source == null)
			return;

		_analyzer = new SpectralAnalyzer(source, bands, _smoothing, _peakHold);
		#if desktop
		// Desktop runs a plain FFT rather than the browser's optimised path, so it needs a smaller
		// window to keep up.
		_analyzer.fftN = 256;
		#end
		#end
	}

	/** Drops the analyser and unbinds the sound. **/
	public function dispose():Void {
		_snd = null;
		#if funkin.vis
		_analyzer = null;
		_bars = null;
		#end
		for (i in 0..._out.length)
			_out[i] = 0;
	}

	/**
		Current level per band, 0 to 1, newest first read of this frame.

		The array is owned by this object and overwritten on every call, so copy it if it has to
		outlive the frame.
	**/
	public function levels():Array<Float> {
		#if funkin.vis
		if (_analyzer == null)
			return _out;

		_bars = _analyzer.getLevels(_bars);
		var count:Int = (_bars.length < _out.length) ? _bars.length : _out.length;
		for (i in 0...count) {
			var v:Float = _bars[i].value;
			_out[i] = (v < 0) ? 0 : ((v > 1) ? 1 : v);
		}
		for (i in count..._out.length)
			_out[i] = 0;
		#end
		return _out;
	}

	/** Level of the loudest band this frame, 0 to 1. **/
	public function peak():Float {
		var vals:Array<Float> = levels();
		var max:Float = 0;
		for (i in 0...vals.length)
			if (vals[i] > max)
				max = vals[i];
		return max;
	}

	inline function get_ready():Bool {
		#if funkin.vis
		return _analyzer != null;
		#else
		return false;
		#end
	}
}
