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

	/** This note's hold trail, if it has one (set by `NoteField` when it spawns). Lets a script reach the
		sustain from the head (e.g. `note.sustain.texture = ...`); `null` for a tap. **/
	public var sustain:SustainSprite = null;

	public var rgbShader:RGBShaderReference;

	/** Toggles this note's head RGB palette shader (the v2 per-note RGB on/off for scripts). **/
	public var rgbEnabled(get, set):Bool;

	inline function get_rgbEnabled():Bool
		return rgbShader != null && rgbShader.enabled;

	inline function set_rgbEnabled(value:Bool):Bool {
		if (rgbShader != null)
			rgbShader.enabled = value;
		return value;
	}

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var centerOnStrum:Bool = false;
	public var multAlpha:Float = 1;
	public var multSpeed:Float = 1;
	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;

	/** Extra rotation added on top of the receptor-derived angle while `copyAngle` is on. **/
	public var offsetAngle:Float = 0;
	public var copyAlpha:Bool = true;
	public var pixel:Bool = false;
	public var scaleFactor:Float = 1;

	/**
		Per-note head graphic override (a sparrow/pixel sheet name). Assigning re-skins this note's head
		immediately with the standard classic build, so a script can give a note its own look at spawn
		(`onSpawnNote`) -- the v2 equivalent of the old `Note.texture`. `null`/empty leaves the active skin.
	**/
	public var texture(default, set):String = null;

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

	/**
		Re-skins the head from an explicit sheet (or leaves the current skin when cleared). Uses the same
		classic build + centered-on-strum layout as an `applyType`/`data.texture` note, so a runtime set
		lands identically to the load-time path.
		@param value the sheet name, or `null`/empty to keep the active skin
		@return the assigned value
	**/
	function set_texture(value:String):String {
		texture = value;
		if (value != null && value.length > 0) {
			NoteSkinService.classic().applyNoteTexture(this, column, keyCount, value);
			offsetX = 0;
			offsetY = 0;
			centerOnStrum = false;
			pixel = PlayState.isPixelStage;
			scaleFactor = scale.x;
		}
		return value;
	}

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
	/**
		Applies this note's visuals, then shrinks them to the strumline's fitted size.

		@param fitScale extra uniform scale from the layout, applied ON TOP of whatever the skin
		               computed -- the skin decides how big a note is for its keycount, and the
		               layout only says how much of that fits on screen. `1` leaves it untouched.
	**/
	public function apply(data:NoteData, keyCount:Int, fitScale:Float = 1):Void {
		this.data = data;
		this.column = data.column;
		this.keyCount = keyCount;

		exists = visible = active = true;
		alpha = 1;
		multAlpha = data.multAlpha; // load-time / compat unspawn override (default 1)
		multSpeed = data.multSpeed;
		copyX = copyY = copyAngle = copyAlpha = true;
		offsetAngle = 0;
		offsetX = offsetY = 0;
		centerOnStrum = false;
		clipRect = null;

		if (rgbShader == null)
			rgbShader = new RGBShaderReference(this, NoteDefaults.initializeGlobalRGBShader(column));
		else
			rgbShader.reset(this, NoteDefaults.initializeGlobalRGBShader(column));
		rgbShader.enabled = !(data.disableRGB || (PlayState.SONG != null && PlayState.SONG.disableNoteRGB));

		fillSplashData(noteSplashData);

		// Force Selected Skin blocks a PLAIN note's texture override (script / chart per-note texture); a
		// note carrying a custom type keeps its type's texture.
		var forceSkip:Bool = ClientPrefs.data.forceNoteSkin && (data.type == null || data.type == '');
		if (!forceSkip && data.texture != null && data.texture.length > 0) {
			// Per-note custom graphic (note type / data.texture): route through the `texture` setter, which
			// does the classic build with the standard centered-on-strum layout -- skipping the active
			// skin's applyNote (otherwise a folder skin's centerOnStrum/offsets would be left on top of a
			// classic sheet and mis-place the note). A script can re-set `head.texture` later the same way.
			texture = data.texture;
		} else {
			@:bypassAccessor texture = null;
			// Force Selected Skin: pin the active skin's asset resolution to its owner so a mod can't shadow it.
			var prevPin:Null<String> = Paths.pinModRoot;
			var pin:Null<String> = backend.NoteSkinConfig.activeSkinPinRoot();
			if (pin != null)
				Paths.pinModRoot = pin;
			var v:NoteVisual = NoteSkinService.current().applyNote(this, rgbShader, column, keyCount, null);
			Paths.pinModRoot = prevPin;
			offsetX = v.offsetX;
			offsetY = v.offsetY;
			centerOnStrum = v.centerOnStrum;
			pixel = v.pixel;
			scaleFactor = v.scaleFactor;
		}

		applyTypeVisual(data.type);

		// Last, so it multiplies the finished size whichever path above built it.
		if (fitScale != 1) {
			scale.x *= fitScale;
			scale.y *= fitScale;
			updateHitbox();
		}
	}

	/**
		Applies a built-in note type's visual half (RGB tint + splash) on top of the skin build, the
		drawable counterpart to `NoteData.applyType`'s gameplay half. Setting the `rgbShader` channels
		clones the shared per-column palette on write, so the tint stays local to this head.
		@param type the note-type name (`''`/`null` for a normal note)
	**/
	inline function applyTypeVisual(type:String):Void {
		if (type == 'Hurt Note') {
			rgbShader.r = 0xFF101010;
			rgbShader.g = 0xFFFF0000;
			rgbShader.b = 0xFF990022;

			noteSplashData.r = 0xFFFF0000;
			noteSplashData.g = 0xFF101010;
			noteSplashData.texture = 'noteSplashes/noteSplashes-electric';
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
			angle = strum.axisAngle + offsetAngle;
		if (copyAlpha)
			alpha = strum.alpha * multAlpha;

		var along:Float = offsetY + distance + height / 2 + strum.hitBonus;
		var perp:Float = offsetX + (centerOnStrum ? strum.laneWidth / 2 : width / 2);
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
		sustain = null;
		clipRect = null;
	}
}
