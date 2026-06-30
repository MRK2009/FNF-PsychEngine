package objects.notes;

import flixel.FlxSprite;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.notes.NoteDefaults;
import objects.notes.NoteDefaults.NoteSplashData;
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

	/** LEGACY-API name: convenience pass-through to `data.time` (the v2 field) for old scripts. **/
	public var strumTime(get, never):Float;

	/** LEGACY-API name: convenience pass-through to `data.column` (the v2 field) for old scripts. **/
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
		var d:NoteSplashData = {
			disabled: false,
			texture: 'noteSplashes/noteSplashes',
			antialiasing: true,
			useGlobalShader: false,
			useRGBShader: true,
			r: -1,
			g: -1,
			b: -1,
			a: 1
		};
		fillSplashData(d);
		return d;
	}

	/** Refreshes the splash-data fields in place (reused across recycles instead of reallocating). **/
	static function fillSplashData(d:NoteSplashData):Void {
		d.disabled = false;
		d.texture = (PlayState.SONG != null) ? PlayState.SONG.splashSkin : 'noteSplashes/noteSplashes';
		d.antialiasing = !PlayState.isPixelStage;
		d.useGlobalShader = false;
		d.useRGBShader = (PlayState.SONG != null) ? !(PlayState.SONG.disableNoteRGB == true) : true;
		d.r = -1;
		d.g = -1;
		d.b = -1;
		d.a = ClientPrefs.data.splashAlpha;
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

		if (rgbShader == null)
			rgbShader = new RGBShaderReference(this, NoteDefaults.initializeGlobalRGBShader(column));
		else
			rgbShader.reset(this, NoteDefaults.initializeGlobalRGBShader(column));
		rgbShader.enabled = !(PlayState.SONG != null && PlayState.SONG.disableNoteRGB);

		fillSplashData(noteSplashData);

		if (data.texture != null && data.texture.length > 0) {
			// Per-note custom graphic (note type or compat script): build straight from the classic skin
			// path with the standard classic layout, skipping the active skin's applyNote. Otherwise a
			// folder skin's centerOnStrum / offsets would stay applied on top of a classic custom sheet
			// and mis-place the note. Mirrors the legacy path (custom textures always used the classic build).
			NoteSkinService.classic().applyNoteTexture(this, column, keyCount, data.texture);
			offsetX = 0;
			offsetY = 0;
			centerOnStrum = false;
			pixel = PlayState.isPixelStage;
			scaleFactor = scale.x;
		} else {
			var v:NoteVisual = NoteSkinService.current().applyNote(this, rgbShader, column, keyCount, null);
			offsetX = v.offsetX;
			offsetY = v.offsetY;
			centerOnStrum = v.centerOnStrum;
			pixel = v.pixel;
			scaleFactor = v.scaleFactor;
		}
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
		var perp:Float = offsetX + (centerOnStrum ? Mania.swagWidth / 2 : width / 2);
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
