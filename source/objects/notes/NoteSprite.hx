package objects.notes;

import flixel.FlxSprite;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.Note;
import objects.Note.NoteSplashData;
import shaders.RGBPalette.RGBShaderReference;

/**
	A note head (tap). Pooled: constructed once with no args, then `apply`'d to a `NoteData` whenever
	it's recycled. Purely visual + positionable -- judgement state lives on the `NoteData`, positioning
	is driven by the `NoteField`, and the look comes from `NoteSkinService` (no skin code here).
**/
final class NoteSprite extends FlxSprite {
	public var data:NoteData;
	public var column:Int = 0;
	public var keyCount:Int = 4;

	public var rgbShader:RGBShaderReference;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var centerOnStrum:Bool = false;
	public var multAlpha:Float = 1;
	public var multSpeed:Float = 1;
	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;
	public var pixel:Bool = false;
	public var scaleFactor:Float = 1;

	public var noteSplashData:NoteSplashData;

	/** Convenience pass-through to `data.time` for trivial scripts. **/
	public var strumTime(get, never):Float;

	/** Convenience pass-through to `data.column` for trivial scripts. **/
	public var noteData(get, never):Int;

	/** Always `false`; a head is a tap, the trail is a separate `SustainSprite`. **/
	public var isSustainNote(get, never):Bool;

	inline function get_strumTime():Float
		return data != null ? data.time : 0;

	inline function get_noteData():Int
		return data != null ? data.column : 0;

	inline function get_isSustainNote():Bool
		return false;

	public function new() {
		super();
		animation = new PsychAnimationController(this);
		scrollFactor.set();
		noteSplashData = makeSplashData();
	}

	static function makeSplashData():NoteSplashData {
		return {
			disabled: false,
			texture: (PlayState.SONG != null) ? PlayState.SONG.splashSkin : 'noteSplashes/noteSplashes',
			antialiasing: !PlayState.isPixelStage,
			useGlobalShader: false,
			useRGBShader: (PlayState.SONG != null) ? !(PlayState.SONG.disableNoteRGB == true) : true,
			r: -1,
			g: -1,
			b: -1,
			a: ClientPrefs.data.splashAlpha
		};
	}

	/**
		Binds this pooled head to a note and (re)builds its look from the active skin.
		@param data the note this head represents
		@param keyCount the active column count (for per-keycount skin resolution)
	**/
	public function apply(data:NoteData, keyCount:Int):Void {
		this.data = data;
		this.column = data.column;
		this.keyCount = keyCount;

		exists = visible = active = true;
		alpha = 1;
		multAlpha = 1;
		multSpeed = 1;
		copyX = copyY = copyAngle = copyAlpha = true;
		offsetX = offsetY = 0;
		centerOnStrum = false;
		clipRect = null;

		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(column));
		rgbShader.enabled = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB);

		noteSplashData = makeSplashData();

		var v:NoteVisual = NoteSkinService.current().applyNote(this, rgbShader, column, keyCount, null);
		offsetX = v.offsetX;
		offsetY = v.offsetY;
		centerOnStrum = v.centerOnStrum;
		pixel = v.pixel;
		scaleFactor = v.scaleFactor;
	}

	/**
		Positions this head relative to its receptor for the current song time (ported from
		`followStrumNote`).
		@param strum the receptor for this note's column
		@param songSpeed the active scroll speed (already divided by playback rate)
		@param scrollNow the SV-mapped position of the current song time (`== songPos` when SV is off)
	**/
	public function follow(strum:Receptor, songSpeed:Float, scrollNow:Float):Void {
		if (data == null)
			return;
		var distance:Float = 0.45 * (scrollNow - data.scrollPos) * songSpeed * multSpeed;
		if (!strum.downScroll)
			distance *= -1;

		var uX:Float = strum.axisX;
		var uY:Float = strum.axisY;

		if (copyAngle)
			angle = strum.axisAngle;
		if (copyAlpha)
			alpha = strum.alpha * multAlpha;

		var along:Float = offsetY + distance + height / 2;
		var perp:Float = offsetX + (centerOnStrum ? Note.swagWidth / 2 : width / 2);
		var cx:Float = strum.x + uX * along + uY * perp;
		var cy:Float = strum.y + uY * along - uX * perp;
		if (copyX)
			x = cx - width / 2;
		if (copyY)
			y = cy - height / 2;
	}

	/** Returns this head to the pool. **/
	public function release():Void {
		exists = false;
		visible = false;
		active = false;
		data = null;
		clipRect = null;
	}
}
