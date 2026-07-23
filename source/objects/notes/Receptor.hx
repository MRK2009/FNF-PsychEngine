package objects.notes;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.notes.NoteDefaults;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

/**
	A receptor (the "strum"). Clean rewrite of `StrumNote`: it holds no skin-building logic -- it asks
	`NoteSkinService` to build its static/pressed/confirm look and only keeps positioning and the played
	animation. One per column per side.
**/
final class Receptor extends FlxSprite {
	public var column:Int = 0;
	public var keyCount:Int = 4;
	public var player:Int = 0;

	public var direction:Float = 90;

	/**
		Scroll direction. Both the osu key `flip` and the `hitBonus` press point depend on it, but callers set
		it AFTER `build()` (gameplay: ctor then `r.downScroll = ...`; editor: `layout()`), so changing it must
		force `syncFrameCentering` to re-run past its frame-size early-out -- otherwise the flip/hitBonus stay
		at the value computed for the wrong direction until something else re-syncs (a note hit).
	**/
	public var downScroll(default, set):Bool = false;

	function set_downScroll(value:Bool):Bool {
		if (value != downScroll)
			_lastFrameW = -1;
		return downScroll = value;
	}

	public var sustainReduce:Bool = true;
	public var rotateNotes:Bool = false;

	/**
		Cached scroll-axis unit vector and the matching sprite angle (`axisDeg - 90`). Recomputed by
		`refreshAxis` only when the effective axis angle changes, so the per-note `follow` reads these
		instead of paying `cos`/`sin` every frame. `axisDeg` defaults to 90 (vertical scroll): straight up.
	**/
	public var axisX(default, null):Float = 0;

	public var axisY(default, null):Float = 1;
	public var axisAngle(default, null):Float = 0;

	var _axisDeg:Float = Math.NaN;

	public var resetAnim:Float = 0;

	public var skinOffsetX:Float = 0;
	public var skinOffsetY:Float = 0;

	public var rgbShader:RGBShaderReference;
	public var useRGBShader:Bool = true;

	/** When set, the palette shader toggles per played anim; otherwise it's "colored unless static". **/
	public var colorPerAnim:Bool = false;

	/** When set, each anim frame is re-centered on the fixed lane width (folder skins). **/
	public var laneCenter:Bool = false;

	/**
		Hit-position fraction (osu!mania `HitPosition` analog), or `NaN` for the default lane-centre press
		point. Marks WHERE on this receptor's art (0 = top, 1 = bottom) a note should be for a perfect hit;
		the receptor art itself is NOT moved -- instead `hitBonus` shifts the note/hold landing point onto
		that spot. Set from a folder skin's `hitAlign`; the osu skin converter auto-detects it from the art.
	**/
	public var hitAlign:Float = Math.NaN;

	/**
		Extra along-axis distance (px) from the default note landing point (`swagWidth/2` past the strum
		origin) to this receptor's `hitAlign` press point. `0` when no hit position is set. Read by
		`NoteSprite.follow` / `SustainSprite.follow` so notes and holds converge on the receptor's hit zone
		without the receptor art being repositioned. Recomputed in `syncFrameCentering`.
	**/
	public var hitBonus:Float = 0;

	/**
		Vertical-flip mode for the receptor art (osu!mania's per-scroll key flip): `"always"`,
		`"upscroll"`, `"downscroll"`, or `null` for never. Resolved against `downScroll` each frame; when
		it flips, `hitAlign` is auto-inverted so the hit target still lands on the judgement line.
	**/
	public var receptorFlip:String = null;

	public var staticColorable:Bool = false;
	public var pressedColorable:Bool = true;
	public var confirmColorable:Bool = true;

	/**
		@param x screen x of the receptor
		@param y screen y of the receptor
		@param column the 0-based lane this receptor serves
		@param player `0` for the opponent side, `1` for the player side
		@param keyCount the active column count; defaults to `Mania.current`
	**/
	public function new(x:Float, y:Float, column:Int, player:Int, ?keyCount:Int) {
		super(x, y);
		animation = new PsychAnimationController(this);

		this.column = column;
		this.player = player;
		this.keyCount = (keyCount != null) ? keyCount : Mania.current;
		this.ID = column;

		rgbShader = new RGBShaderReference(this, NoteDefaults.initializeGlobalRGBShader(column));
		rgbShader.enabled = false;
		if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB)
			useRGBShader = false;

		// Skin-shipped palette first, then the keycount/player colours (see NoteSkinConfig.skinNoteColors).
		var arr:Array<FlxColor> = backend.NoteSkinConfig.skinNoteColors(column);
		if (arr == null) {
			if (Mania.current != Mania.DEFAULT)
				arr = Mania.getColors(Mania.current)[column];
			else {
				arr = ClientPrefs.data.arrowRGB[column];
				if (PlayState.isPixelStage)
					arr = ClientPrefs.data.arrowRGBPixel[column];
			}
		}
		if (arr != null && arr.length >= 3) {
			@:bypassAccessor {
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}

		scrollFactor.set();
		build();
		playAnim('static');
	}

	/** (Re)builds the receptor's static/pressed/confirm look from the active skin. **/
	public function build():Void {
		var lastAnim:String = (animation.curAnim != null) ? animation.curAnim.name : null;
		laneCenter = false;
		hitAlign = Math.NaN;
		hitBonus = 0;
		receptorFlip = null;
		colorPerAnim = false;

		// Pin asset resolution to the active skin's owner so a folder skin in any mod (or a forced skin)
		// builds its strums from its own images -- matches NoteSprite/SustainSprite.apply.
		var prevPin:Null<String> = Paths.pinModRoot;
		var pin:Null<String> = backend.NoteSkinConfig.activeSkinPinRoot();
		if (pin != null)
			Paths.pinModRoot = pin;
		var v:NoteVisual = NoteSkinService.current().applyReceptor(this, rgbShader, column, keyCount, lastAnim);
		Paths.pinModRoot = prevPin;
		laneCenter = v.laneCenter;
		hitAlign = v.hitAlign;
		receptorFlip = v.receptorFlip;
		colorPerAnim = v.colorPerAnim;
		staticColorable = v.staticColorable;
		pressedColorable = v.pressedColorable;
		confirmColorable = v.confirmColorable;
		skinOffsetX = v.offsetX;
		skinOffsetY = v.offsetY;

		// Re-center NOW (offsets + hitBonus), not just next frame: applyReceptor already set the static
		// frame + scale, and the notes read `hitBonus` in their own `follow` which runs BEFORE the receptor's
		// update() each frame. Deferring the recompute left notes reading a stale hitBonus after a live edit
		// (a rebuild) until something else forced a re-sync -- e.g. a note hit calling playAnim. Force it here
		// so an edit takes effect immediately. `-1` makes the (frame-size-gated) recompute actually run.
		_lastFrameW = _lastFrameH = -1;
		syncFrameCentering();
	}

	/** Applies the initial on-screen placement for this column/side (matches the legacy strum layout). **/
	public function playerPosition():Void {
		final kc:Int = Mania.current;
		// A skin may widen/narrow the lane spacing; additive, and 4K gets it too (it has no base gap).
		final skinGap:Float = backend.NoteSkinConfig.columnGap();
		if (kc == Mania.DEFAULT) {
			x += (Mania.swagWidth + skinGap) * column;
			x += 50;
			x += ((FlxG.width / 2) * player);
			x += skinOffsetX;
			y += skinOffsetY;
			return;
		}

		final step:Float = Mania.swagWidth + Mania.STRUM_GAP + skinGap;
		final center4K:Float = 160 * Mania.noteSizes[Mania.DEFAULT - 1] * (Mania.DEFAULT - 1) / 2;

		x += step * column;
		x += 50;
		x += ((FlxG.width / 2) * player);
		x -= (step * (kc - 1) / 2 - center4K);
		y += Mania.noteOffsetsY[kc - 1];
		x += skinOffsetX;
		y += skinOffsetY;
	}

	/**
		Recomputes the cached scroll-axis vector when the effective axis angle (`direction` plus the
		sprite `angle` when `rotateNotes`) changed. Cheap to call per frame: it only runs `cos`/`sin`
		on an actual angle change, so a script rotating the receptor stays correct. Call once per frame
		before the drawables read `axisX`/`axisY`/`axisAngle`.
	**/
	public inline function refreshAxis():Void {
		final deg:Float = direction + (rotateNotes ? angle : 0);
		if (deg != _axisDeg) {
			_axisDeg = deg;
			axisAngle = deg - 90;
			if (deg == 90) {
				axisX = 0;
				axisY = 1;
			} else {
				final rad:Float = deg * Math.PI / 180;
				axisX = Math.cos(rad);
				axisY = Math.sin(rad);
			}
		}
	}

	var _lastFrameW:Int = -1;
	var _lastFrameH:Int = -1;

	/**
		Re-applies the centering when the CURRENT FRAME's size changes.

		`playAnim` centers once, but a folder skin's frames are packed at their own individual sizes, so
		frames WITHIN one animation can differ in size (a confirm burst is usually wider than its first
		frame). The offset computed at play time then goes stale as the animation advances and the
		receptor visibly drifts -- a few px, most obvious on pixel skins where every source pixel is
		multiplied by `pixelScale`. Cheap: it only recomputes on an actual frame-size change.
	**/
	inline function syncFrameCentering():Void {
		if (frameWidth == _lastFrameW && frameHeight == _lastFrameH)
			return;
		_lastFrameW = frameWidth;
		_lastFrameH = frameHeight;
		centerOffsets();
		centerOrigin();
		if (laneCenter)
			offset.x = (frameWidth - Mania.swagWidth) / 2;

		// osu!mania flips its key art vertically depending on scroll direction; mirror that here (its art is
		// drawn for downscroll, so the converter asks to flip on upscroll).
		var flip:Bool = switch (receptorFlip) {
			case 'always': true;
			case 'upscroll': !downScroll;
			case 'downscroll': downScroll;
			default: false;
		};
		if (flipY != flip)
			flipY = flip;

		// Hit position: WITHOUT moving the receptor art, report how far the note's press point should sit
		// past the default landing point (`swagWidth/2` along the axis -- a note centre sits half a lane
		// past its raw scroll point). `hitAlign` is the fraction of the receptor art (0 top .. 1 bottom;
		// mirrored when flipped) that marks the perfect-hit zone; `NoteSprite`/`SustainSprite` add this
		// `hitBonus` so notes converge on that spot of the art instead of the lane centre.
		if (!Math.isNaN(hitAlign)) {
			var a:Float = flip ? (1 - hitAlign) : hitAlign;
			hitBonus = a * frameHeight * scale.y - Mania.swagWidth * 0.5;
		} else
			hitBonus = 0;
	}

	override function update(elapsed:Float) {
		if (resetAnim > 0) {
			resetAnim -= elapsed;
			if (resetAnim <= 0) {
				playAnim('static');
				resetAnim = 0;
			}
		}
		super.update(elapsed);
		syncFrameCentering();
	}

	/**
		Plays a receptor animation and re-applies lane centering + per-anim colorability.
		@param anim one of `static` / `pressed` / `confirm`
		@param force restart the animation even if it's already playing
	**/
	public function playAnim(anim:String, ?force:Bool = false):Void {
		if (animation.curAnim != null && animation.curAnim.name == anim && animation.curAnim.numFrames <= 1)
			return;

		animation.play(anim, force);
		if (animation.curAnim != null) {
			_lastFrameW = _lastFrameH = -1; // force a re-center for the new anim's first frame
			syncFrameCentering();
		}

		if (colorPerAnim) {
			var supported:Bool = false;
			if (useRGBShader && animation.curAnim != null) {
				supported = switch (animation.curAnim.name) {
					case 'static': staticColorable;
					case 'pressed': pressedColorable;
					case 'confirm': confirmColorable;
					default: false;
				}
			}
			rgbShader.enabled = supported;
			if (supported)
				tintAnim(animation.curAnim.name);
		} else if (useRGBShader)
			rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
	}

	/**
		Tints the current receptor anim: the note colour when that element's "Link ..." option is on, or
		its own independent colour (per-keycount aware, falling back to the note colour) when off.
	**/
	function tintAnim(anim:String):Void {
		var element:String = switch (anim) {
			case 'static': 'strums';
			case 'pressed': 'pressed';
			case 'confirm': 'confirm';
			default: null;
		}
		if (element == null)
			return;
		var linked:Bool = switch (element) {
			case 'strums': ClientPrefs.data.linkStrumColor;
			case 'pressed': ClientPrefs.data.linkPressedColor;
			case 'confirm': ClientPrefs.data.linkConfirmColor;
			default: true;
		}
		var c:Array<FlxColor>;
		if (linked) {
			var np:RGBPalette = NoteDefaults.initializeGlobalRGBShader(column);
			c = [np.r, np.g, np.b];
		} else {
			var all:Array<Array<FlxColor>> = Mania.getAssetColors(element, keyCount);
			if (column < 0 || column >= all.length)
				return;
			c = all[column];
		}
		if (c != null && c.length >= 3) {
			rgbShader.r = c[0];
			rgbShader.g = c[1];
			rgbShader.b = c[2];
		}
	}
}
