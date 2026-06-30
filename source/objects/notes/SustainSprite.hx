package objects.notes;

import flixel.FlxSprite;
import flixel.math.FlxRect;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.Note;
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

	public var tail:FlxSprite;

	public var rgbShader:RGBShaderReference;
	public var tailRGB:RGBShaderReference;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var centerOnStrum:Bool = true;
	public var multAlpha:Float = 0.6;
	public var multSpeed:Float = 1;
	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;
	public var pixel:Bool = false;

	/** Convenience pass-through to `data.time` for trivial scripts. **/
	public var strumTime(get, never):Float;

	/** Convenience pass-through to `data.column` for trivial scripts. **/
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

		exists = visible = active = true;
		tail.exists = tail.visible = true;
		copyX = copyY = copyAngle = copyAlpha = true;
		clipRect = null;
		tail.clipRect = null;

		var rgbOff:Bool = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
		if (rgbShader == null)
			rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(column));
		else
			rgbShader.reset(this, Note.initializeGlobalRGBShader(column));
		if (tailRGB == null)
			tailRGB = new RGBShaderReference(tail, Note.initializeGlobalRGBShader(column));
		else
			tailRGB.reset(tail, Note.initializeGlobalRGBShader(column));

		var v:NoteVisual = NoteSkinService.current().applySustain(this, rgbShader, tail, tailRGB, column, keyCount);
		offsetX = v.offsetX;
		offsetY = v.offsetY;
		centerOnStrum = v.centerOnStrum;
		pixel = v.pixel;
		if (rgbOff) {
			rgbShader.enabled = false;
			tailRGB.enabled = false;
		}

		alpha = multAlpha = 0.6;
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

		var sign:Float = strum.downScroll ? 1 : -1;
		var rate:Float = songSpeed * multSpeed;

		var uX:Float = strum.axisX;
		var uY:Float = strum.axisY;

		if (copyAngle)
			angle = strum.axisAngle;
		if (copyAlpha) {
			alpha = strum.alpha * multAlpha;
			tail.alpha = alpha;
		}

		var headDist:Float = sign * (0.45 * (scrollNow - data.scrollPos) * rate);
		var endDist:Float = sign * (0.45 * (scrollNow - data.endScrollPos) * rate);
		var nearA:Float = offsetY + headDist;
		var farA:Float = offsetY + endDist;

		var tailLen:Float = tail.height;
		var totalLen:Float = Math.abs(headDist - endDist);
		var bodyLen:Float = totalLen - tailLen;
		if (bodyLen < 0)
			bodyLen = 0;
		if (frameHeight > 0)
			scale.y = bodyLen / frameHeight;
		updateHitbox();

		var perp:Float = offsetX + (centerOnStrum ? Note.swagWidth / 2 : width / 2);
		var bodyA:Float = (nearA + farA + sign * tailLen) / 2;
		var bcx:Float = strum.x + uX * bodyA + uY * perp;
		var bcy:Float = strum.y + uY * bodyA - uX * perp;
		if (copyX)
			x = bcx - width / 2;
		if (copyY)
			y = bcy - (frameHeight * scale.y) / 2;

		var tperp:Float = offsetX + (centerOnStrum ? Note.swagWidth / 2 : tail.width / 2);
		var tailA:Float = farA + sign * (tailLen / 2);
		var tcx:Float = strum.x + uX * tailA + uY * tperp;
		var tcy:Float = strum.y + uY * tailA - uX * tperp;
		tail.angle = copyAngle ? strum.axisAngle : tail.angle;
		tail.x = tcx - tail.width / 2;
		tail.y = tcy - tail.height / 2;

		clip(strum, scrollNow);
	}

	/**
		Clips away the consumed portion of the body once the head has been hit. Because the body is
		`flipY`'d for downscroll, the receptor-side region maps to the same frame slice either way:
		hide the first `frac` of the frame and keep the rest. `frac` is measured in scroll position so
		it stays correct through SV (equals the raw time fraction when SV is off).
		@param strum the receptor this hold scrolls toward (its `downScroll` selects the clip side)
		@param scrollNow the SV-mapped position of the current song time
	**/
	public function clip(strum:Receptor, scrollNow:Float):Void {
		if (data == null || !data.hit || data.length <= 0) {
			clipRect = null;
			return;
		}
		var span:Float = data.endScrollPos - data.scrollPos;
		if (span == 0) {
			clipRect = null;
			return;
		}
		var frac:Float = (scrollNow - data.scrollPos) / span;
		if (frac <= 0) {
			clipRect = null;
			return;
		}
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
