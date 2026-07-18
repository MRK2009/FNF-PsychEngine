package objects.notes;

import flixel.FlxSprite;
import flixel.math.FlxRect;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.notes.NoteDefaults;
import shaders.RGBPalette.RGBShaderReference;

/**
	A sustain (hold) rendered as ONE drawable: a vertically-scaled `body` plus a `tail` end-cap,
	replacing the legacy model of one `Note` per sustain step. Pooled (no-arg ctor + `apply`).

	Geometry -- length (`scale.y`), screen position, and progressive clipping as it's held -- is set by
	the `NoteField` each frame; this class only carries the visual and the clip helper.
**/
final class SustainSprite extends FlxSprite {
	public var data:NoteData;
	public var column:Int = 0;
	public var keyCount:Int = 4;

	/** Per-skin override of `headOverlap` (from `skin.tcfg`); `null` uses the static default. **/
	public var skinHeadOverlap:Null<Float> = null;

	/** `false` when the active skin ships no hold-end (tail) frame; the body then fills the tail's span. **/
	public var hasTail:Bool = true;

	public var tail:FlxSprite;

	public var rgbShader:RGBShaderReference;
	public var tailRGB:RGBShaderReference;

	/**
		Per-note hold graphic override (a sparrow/pixel sheet name). Assigning re-skins this hold's body +
		tail immediately, so a custom note can carry its own trail graphic. `null`/empty leaves the skin.
	**/
	public var texture(default, set):String = null;

	/** Toggles this hold's RGB palette shader (body + tail together). **/
	public var rgbEnabled(get, set):Bool;

	inline function get_rgbEnabled():Bool
		return rgbShader != null && rgbShader.enabled;

	inline function set_rgbEnabled(value:Bool):Bool {
		if (rgbShader != null)
			rgbShader.enabled = value;
		if (tailRGB != null)
			tailRGB.enabled = value;
		return value;
	}

	function set_texture(value:String):String {
		texture = value;
		if (value != null && value.length > 0) {
			NoteSkinService.classic().applySustainTexture(this, tail, column, keyCount, value);
			centerOnStrum = true;
		}
		return value;
	}

	/**
		How far a hold's visible tip is pulled back toward its head from the end-note centre, as a fraction
		of the note half-width. `0` (default) ends the trail exactly at the end-note centre: the cap sits AT
		that point and extends back toward the head, so it can't overlap a note on the next step AND the trail
		consumes cleanly right up to the release (a positive trim shortens the visual trail, which then
		finishes a little before you actually let go). Increase only if a skin wants the cap tucked in further.
	**/
	public static var endTrimRatio:Float = 0;

	/**
		Extra trail left past the receptor when a held hold is clipped, as a fraction of the note width.
		`0` (default) cuts the trail exactly at the receptor centre, so the receptor's near half hides the
		cut edge at any receptor scale. A positive value leaves more trail poking toward/over the receptor,
		but keep it below the receptor's scaled half-width or the trail pokes past a scaled-down receptor
		(what made held holds stick out under/over the strum on `scale: 0.7` skins).
	**/
	public static var holdClipNudge:Float = 0;

	/**
		Extra tuck of an un-held hold's head-side edge PAST the note centre, under the head, as a fraction of
		the note width. `0` (default) connects the trail at the head centre -- the head's near half hides the
		seam at any note scale. A positive value tucks further, but keep it below the head's scaled half-width
		or the trail pokes past a scaled-down head (e.g. `scale: 0.7` skins). Un-held trail only; once hit, the
		held clip (`holdClipNudge`) owns the receptor-side edge.
	**/
	public static var headOverlap:Float = 0;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var centerOnStrum:Bool = true;
	public var multAlpha:Float = 0.6;
	public var multSpeed:Float = 1;
	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;

	/** Extra rotation added on top of the receptor-derived angle while `copyAngle` is on. **/
	public var offsetAngle:Float = 0;
	public var copyAlpha:Bool = true;
	public var pixel:Bool = false;

	/** LEGACY-API name: convenience pass-through to `data.time` (the v2 field) for old scripts. **/
	public var strumTime(get, never):Float;

	/** LEGACY-API name: convenience pass-through to `data.column` (the v2 field) for old scripts. **/
	public var noteData(get, never):Int;

	/** Always `true`; this drawable is the hold trail. **/
	public var isSustainNote(get, never):Bool;

	inline function get_strumTime():Float
		return data != null ? data.time : 0;

	inline function get_noteData():Int
		return data != null ? data.column : 0;

	inline function get_isSustainNote():Bool
		return true;

	public function new() {
		super();
		animation = new PsychAnimationController(this);
		scrollFactor.set();
		tail = new FlxSprite();
		tail.animation = new PsychAnimationController(tail);
		tail.scrollFactor.set();
	}

	/**
		Binds this pooled hold to a note and (re)builds its body + tail from the active skin.
		@param data the sustain this drawable represents
		@param keyCount the active column count (for per-keycount skin resolution)
	**/
	public function apply(data:NoteData, keyCount:Int):Void {
		this.data = data;
		this.column = data.column;
		this.keyCount = keyCount;
		skinHeadOverlap = backend.NoteSkinConfig.headOverlap();

		exists = visible = active = true;
		tail.exists = tail.visible = true;
		copyX = copyY = copyAngle = copyAlpha = true;
		offsetAngle = 0;
		clipRect = null;
		tail.clipRect = null;

		var rgbOff:Bool = data.disableRGB || (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
		if (rgbShader == null)
			rgbShader = new RGBShaderReference(this, NoteDefaults.initializeGlobalRGBShader(column));
		else
			rgbShader.reset(this, NoteDefaults.initializeGlobalRGBShader(column));
		if (tailRGB == null)
			tailRGB = new RGBShaderReference(tail, NoteDefaults.initializeGlobalRGBShader(column));
		else
			tailRGB.reset(tail, NoteDefaults.initializeGlobalRGBShader(column));

		// Force Selected Skin blocks a PLAIN note's hold-texture override; a custom-type note keeps it.
		var forceSkip:Bool = ClientPrefs.data.forceNoteSkin && (data.type == null || data.type == '');
		if (!forceSkip && data.texture != null && data.texture.length > 0) {
			// Per-note custom hold graphic (matches the head's data.texture); route through the setter.
			@:bypassAccessor texture = null;
			texture = data.texture;
			offsetX = 0;
			offsetY = 0;
			pixel = PlayState.isPixelStage;
		} else {
			@:bypassAccessor texture = null;
			// Force Selected Skin: pin the active skin's asset resolution to its owner (mods can't shadow it).
			var prevPin:Null<String> = Paths.pinModRoot;
			var pin:Null<String> = backend.NoteSkinConfig.activeSkinPinRoot();
			if (pin != null)
				Paths.pinModRoot = pin;
			var v:NoteVisual = NoteSkinService.current().applySustain(this, rgbShader, tail, tailRGB, column, keyCount);
			Paths.pinModRoot = prevPin;
			offsetX = v.offsetX;
			offsetY = v.offsetY;
			centerOnStrum = v.centerOnStrum;
			pixel = v.pixel;
		}
		if (rgbOff) {
			rgbShader.enabled = false;
			tailRGB.enabled = false;
		}

		if (data.type == 'Hurt Note') {
			rgbShader.r = tailRGB.r = 0xFF101010;
			rgbShader.g = tailRGB.g = 0xFFFF0000;
			rgbShader.b = tailRGB.b = 0xFF990022;
		}

		// No hold-end frame in the skin -> the body extends over the tail's span instead of stopping short.
		var endAnim = tail.animation.getByName('end');
		hasTail = (endAnim != null && endAnim.numFrames > 0);
		tail.visible = hasTail;

		// Holds default to a dimmer 0.6; a load-time/compat script override on the note replaces it.
		multAlpha = (data.multAlpha != 1) ? data.multAlpha : 0.6;
		multSpeed = data.multSpeed;
		alpha = multAlpha;
		tail.alpha = alpha;
	}

	/** Returns this hold (body + tail) to the pool. **/
	public function release():Void {
		exists = visible = active = false;
		tail.exists = tail.visible = false;
		data = null;
		clipRect = null;
		tail.clipRect = null;
	}

	/**
		Positions the stretched body and its tail cap relative to the receptor for the current song
		time. One body spans the whole hold; `scale.y` = (span length - tail height) / frame height so
		the tail cap occupies the final segment instead of adding to it. The sustain is `flipY`'d for
		downscroll (matching the legacy per-piece flip) and uses the same `0.45 * (songPos - t) * rate`
		scroll multiplier as the head (negated for upscroll).

		This is the most behaviourally sensitive piece of the rewrite; offsets/clip want a runtime pass.
		@param strum the receptor for this hold's column
		@param songSpeed the active scroll speed (already divided by playback rate)
		@param scrollNow the SV-mapped position of the current song time (`== songPos` when SV is off)
	**/
	public function follow(strum:Receptor, songSpeed:Float, scrollNow:Float):Void {
		if (data == null)
			return;
		flipY = strum.downScroll;
		tail.flipY = strum.downScroll;

		// `neg` matches the note head's distance negation, so head and trail share one convention in
		// BOTH scroll directions (the old code only got downscroll right).
		var neg:Float = strum.downScroll ? 1 : -1;
		var rate:Float = songSpeed * multSpeed;
		var half:Float = Mania.swagWidth * 0.5;

		var uX:Float = strum.axisX;
		var uY:Float = strum.axisY;

		if (copyAngle)
			angle = strum.axisAngle + offsetAngle;
		if (copyAlpha) {
			alpha = strum.alpha * multAlpha;
			tail.alpha = alpha;
		}

		// Note-centre position along the scroll axis for the head and the hold end, using the SAME
		// mapping as the note head (a note's centre sits half a note-width past its raw scroll point).
		var headCenter:Float = offsetY + neg * (0.45 * (scrollNow - data.scrollPos) * rate) + half;
		var endCenter:Float = offsetY + neg * (0.45 * (scrollNow - data.endScrollPos) * rate) + half;

		// Direction from the head toward the end along the axis (mirror-safe for up/down scroll).
		var dir:Float = (endCenter >= headCenter) ? 1 : -1;

		// Visible tip at the end-note centre (endTrimRatio 0). The cap extends from here back toward the head,
		// so it never reaches past the end into a note on the next step, and the trail consumes fully to the
		// release. Applied whether held or not so the length never jumps when you press. The cap is also HIDDEN
		// near the receptor at completion (below) so it can't poke past it in the final frames.
		var endTrim:Float = half * endTrimRatio;
		var tipAlong:Float = endCenter - dir * endTrim;

		// Head-side edge sits at the head note's CENTRE, so the head's near half always hides the seam at any
		// note scale (a scaled-down head doesn't cover a full-note-width over-tuck, which used to make the
		// trail poke past the head -- most visibly on upscroll). A skin/`headOverlap` can still tuck further.
		var startAlong:Float = headCenter;
		if (!data.hit) {
			var ho:Float = (skinHeadOverlap != null) ? skinHeadOverlap : headOverlap;
			if (ho != 0)
				startAlong -= dir * (Mania.swagWidth * ho);
		}

		// Missing hold-end: no tail length is reserved, so the body reaches where the tail would have ended.
		var tailLen:Float = hasTail ? tail.height : 0;
		var fullLen:Float = Math.abs(tipAlong - startAlong);
		var bodyLen:Float = fullLen - tailLen;
		if (bodyLen < 0)
			bodyLen = 0;

		// bodyLen is constant while scrolling, so scale.y only really moves on spawn/speed change and
		// while a held note clips. Only pay updateHitbox when it actually changed (legacy's 0.1px gate).
		if (frameHeight > 0) {
			var newScaleY:Float = bodyLen / frameHeight;
			if (Math.abs((newScaleY - scale.y) * frameHeight) > 0.1) {
				scale.y = newScaleY;
				updateHitbox();
			}
		}

		var perp:Float = offsetX + (centerOnStrum ? half : width / 2);
		// Body occupies [startAlong .. tip - tail]; the tail cap occupies the final tailLen up to the tip.
		var bodyCenter:Float = (startAlong + (tipAlong - dir * tailLen)) * 0.5;
		var bcx:Float = strum.x + uX * bodyCenter + uY * perp;
		var bcy:Float = strum.y + uY * bodyCenter - uX * perp;
		if (copyX)
			x = bcx - width / 2;
		if (copyY)
			y = bcy - (frameHeight * scale.y) / 2;

		var tperp:Float = offsetX + (centerOnStrum ? half : tail.width / 2);
		var tailCenter:Float = tipAlong - dir * (tailLen * 0.5);
		var tcx:Float = strum.x + uX * tailCenter + uY * tperp;
		var tcy:Float = strum.y + uY * tailCenter - uX * tperp;
		tail.angle = copyAngle ? strum.axisAngle + offsetAngle : tail.angle;
		tail.x = tcx - tail.width / 2;
		tail.y = tcy - tail.height / 2;

		// Held: hide the tail cap once its receptor-facing edge reaches the receptor centre, so the cap can't
		// scroll past/under the receptor in the last frames before the note is reclaimed (the receptor covers
		// the flat end). `receptorAlong` is where the head sat when it was hit.
		tail.visible = hasTail;
		if (data.hit && hasTail) {
			var receptorAlong:Float = offsetY + half;
			var receptorFacingEdge:Float = tipAlong - dir * tailLen;
			if ((receptorFacingEdge - receptorAlong) * dir < 0)
				tail.visible = false;
		}

		// Held: hide the portion already scrolled past the receptor (raw scroll progress, dir-independent).
		clip(0.45 * (scrollNow - data.scrollPos) * rate - Mania.swagWidth * holdClipNudge, bodyLen);
	}

	/**
		Clips away the consumed portion of the body once the head has been hit, anchored to the receptor
		so the cut edge stays put instead of drifting past it as the hold shrinks. The hidden fraction is
		measured against the ACTUAL body sprite (`consumed / bodyLen`), NOT the full hold span -- the span
		includes the tail cap and the end-trim, so dividing by it under-clips and the near edge creeps past
		the receptor. Because the body is `flipY`'d for downscroll, hiding the first `frac` of the frame
		removes the receptor-side region in both scroll directions.
		@param consumed how far the head has scrolled past the receptor, in screen px (negative = not yet)
		@param bodyLen the body's on-screen length, in screen px
	**/
	public function clip(consumed:Float, bodyLen:Float):Void {
		if (data == null || !data.hit || data.length <= 0 || bodyLen <= 0 || consumed <= 0) {
			// Only touch clipRect when it's actually set -- assigning it (even null) fires the overridden
			// set_clipRect, which re-derives `frame` every frame for every un-held hold otherwise.
			if (clipRect != null)
				clipRect = null;
			return;
		}
		var frac:Float = consumed / bodyLen;
		if (frac > 1)
			frac = 1;

		var r:FlxRect = (clipRect != null) ? clipRect : new FlxRect();
		r.x = 0;
		r.width = frameWidth;
		r.y = frameHeight * frac;
		r.height = frameHeight * (1 - frac);
		clipRect = r;
	}

	override function draw():Void {
		super.draw();
		if (tail != null && tail.exists && tail.visible) {
			tail.cameras = cameras;
			tail.draw();
		}
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);
		if (tail != null && tail.exists)
			tail.update(elapsed);
	}

	@:noCompletion override function set_clipRect(rect:FlxRect):FlxRect {
		@:bypassAccessor clipRect = rect;
		if (frames != null && animation.frameIndex >= 0 && animation.frameIndex < frames.frames.length)
			frame = frames.frames[animation.frameIndex];
		return rect;
	}
}
