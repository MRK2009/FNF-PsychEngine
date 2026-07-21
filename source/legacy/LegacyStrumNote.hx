package legacy;

import objects.Note;
import backend.animation.PsychAnimationController;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

/**
 * **LEGACY (pre-v2) strum/receptor — deprecated.** The old `objects.StrumNote`, kept for editors,
 * stages and Lua/HScript that reference `StrumNote`, and for the `compatibilityMode` strum mirror. The
 * live runtime uses `objects.notes.Receptor`. Its methods are `@:deprecated`.
**/
class LegacyStrumNote extends FlxSprite {
	public var rgbShader:RGBShaderReference;
	public var resetAnim:Float = 0;

	private var noteData:Int = 0;

	public var direction:Float = 90;
	public var downScroll:Bool = false;
	public var sustainReduce:Bool = true;

	// When true this strum's `angle` also rotates its notes' scroll axis (connected lane
	// rotation). When false `angle` only spins the receptor sprite. See Note.followStrumNote.
	public var rotateNotes:Bool = false;

	public var skinOffsetX:Float = 0;
	public var skinOffsetY:Float = 0;

	public var folderLaneCenter:Bool = false;

	public var folderColorPerAnim:Bool = false;
	public var staticColorable:Bool = false;
	public var pressedColorable:Bool = true;
	public var confirmColorable:Bool = true;

	private var player:Int;

	public var texture(default, set):String = null;

	/**
		Setter for the receptor skin image; assigning a new value reloads the static/pressed/confirm
		animations from it.
		@param value the skin image name (no extension)
		@return the assigned value
	**/
	private function set_texture(value:String):String {
		if (texture != value) {
			texture = value;
			reloadNote();
		}
		return value;
	}

	public var useRGBShader:Bool = true;

	/**
		Builds a legacy receptor for one lane: seeds its RGB palette from the multikey/arrow-colour prefs,
		resolves the chart's `arrowSkin` (or the default) plus the user's note-skin postfix, loads it, and
		plays the `static` animation.
		@param x screen x
		@param y screen y
		@param leData the 0-based lane this receptor serves
		@param player `0` for the opponent side, `1` for the player side
	**/
	public function new(x:Float, y:Float, leData:Int, player:Int) {
		animation = new PsychAnimationController(this);

		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(leData));
		rgbShader.enabled = false;
		if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB)
			useRGBShader = false;

		var arr:Array<FlxColor>;
		if (Mania.current != Mania.DEFAULT)
			arr = Mania.getColors(Mania.current)[leData]; // multikey palette
		else {
			arr = ClientPrefs.data.arrowRGB[leData];
			if (PlayState.isPixelStage)
				arr = ClientPrefs.data.arrowRGBPixel[leData];
		}

		// `arr` is the per-direction RGB triple ([r,g,b], length 3); the
		// previous `leData < arr.length` guard rejected leData == 3 (right
		// strum) and silently disabled its RGB shader. Validate the triple
		// itself instead of comparing direction index against colour count.
		if (arr != null && arr.length >= 3) {
			@:bypassAccessor
			{
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}

		noteData = leData;
		this.player = player;
		this.noteData = leData;
		this.ID = noteData;
		super(x, y);

		var skin:String = null;
		if (PlayState.SONG != null && PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1)
			skin = PlayState.SONG.arrowSkin;
		else
			skin = Note.defaultNoteSkin;

		var customSkin:String = skin + Note.getNoteSkinPostfix();
		if (Paths.fileExists('images/$customSkin.png', IMAGE))
			skin = customSkin;

		texture = skin; // Load texture and anims
		scrollFactor.set();
		playAnim('static');
	}

	/**
		(Re)builds the receptor's look: uses the active folder skin (`.tcfg`/`.json`) when one resolves,
		otherwise falls back to the classic sparrow/pixel/multikey build via `LegacyNoteSkin`.
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function reloadNote() {
		var lastAnim:String = null;
		if (animation.curAnim != null)
			lastAnim = animation.curAnim.name;

		folderLaneCenter = false;
		folderColorPerAnim = false;

		var folderSkin:String = NoteSkinConfig.activeSkin();
		if (folderSkin != null && reloadFolderStrum(folderSkin, lastAnim))
			return;

		// No folder skin: classic (pre-NoteSkinConfig) sparrow/pixel/multikey build.
		legacy.LegacyNoteSkin.reloadStrum(this, lastAnim);
	}

	/**
		Builds the static/pressed/confirm look from a folder skin's config for this lane, applying its
		per-column frames, colorability, antialiasing, offsets and scale.
		@param skinName the active folder skin
		@param lastAnim the animation to restore afterwards (may be `null`)
		@return `true` if the folder skin supplied this lane (so the classic fallback is skipped)
	**/
	function reloadFolderStrum(skinName:String, lastAnim:String):Bool {
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return false;

		if (NoteSkinConfig.editorOverride == null)
			NoteSkinConfig.pixelRender = NoteSkinConfig.pixelRenderFor(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var c:Int = Std.int(Math.abs(noteData));

		var st = NoteSkinConfig.resolveColumn(cfg, cfg.strums, c);
		if (st == null)
			return false;
		var staticF:Array<String> = NoteSkinConfig.resolveFrames(base + st.key);
		if (staticF == null)
			return false;
		staticF = NoteSkinConfig.staticFrame(staticF, NoteSkinConfig.animatedFor(cfg, 'strums'));
		var staticA:Float = st.angle;

		var pr = NoteSkinConfig.resolveColumn(cfg, cfg.pressed, c);
		var pressedF:Array<String> = pr == null ? null : NoteSkinConfig.resolveFrames(base + pr.key);
		var pressedA:Float = pr == null ? staticA : pr.angle;
		if (pressedF == null) {
			pressedF = staticF;
			pressedA = staticA;
		} else
			pressedF = NoteSkinConfig.staticFrame(pressedF, NoteSkinConfig.animatedFor(cfg, 'pressed'));

		var cf = NoteSkinConfig.resolveColumn(cfg, cfg.confirm, c);
		var confirmF:Array<String> = cf == null ? null : NoteSkinConfig.resolveFrames(base + cf.key);
		var confirmA:Float = cf == null ? pressedA : cf.angle;
		if (confirmF == null) {
			confirmF = pressedF;
			confirmA = pressedA;
		} else
			confirmF = NoteSkinConfig.staticFrame(confirmF, NoteSkinConfig.animatedFor(cfg, 'confirm'));

		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, c);
		var factor:Float = NoteSkinConfig.applyAnims(this, [
			{
				name: 'static',
				keys: staticF,
				fps: laneFps,
				loop: false,
				angle: staticA,
				square: true
			},
			{
				name: 'pressed',
				keys: pressedF,
				fps: laneFps,
				loop: false,
				angle: pressedA,
				square: true
			},
			{
				name: 'confirm',
				keys: confirmF,
				fps: confirmF.length > 1 ? laneFps : 24,
				loop: false,
				angle: confirmA,
				square: true
			}
		]);

		folderColorPerAnim = true;
		staticColorable = NoteSkinConfig.colorableFor(cfg, 'strums');
		pressedColorable = NoteSkinConfig.colorableFor(cfg, 'pressed');
		confirmColorable = NoteSkinConfig.colorableFor(cfg, 'confirm');
		antialiasing = NoteSkinConfig.pixelRender ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, c,
			ClientPrefs.data.antialiasing);
		var soff:Array<Float> = NoteSkinConfig.offsetFor(cfg.strumOffsets, c);
		skinOffsetX = soff[0];
		skinOffsetY = soff[1];
		folderLaneCenter = true;
		var kc:Int = Mania.clamp(Mania.current);
		var scaleBase:Float = NoteSkinConfig.numForColumn(cfg.scale, c, 0.7) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		scale.set(scaleBase * factor, scaleBase * factor);
		updateHitbox();

		if (lastAnim != null)
			playAnim(lastAnim, true);
		return true;
	}

	/**
		Applies this receptor's on-screen placement for its lane/side: classic 4K spacing on the default
		key count, otherwise the multikey layout (per-lane step + gap, re-centred so the row stays aligned
		with where the 4K row centres).
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function playerPosition() {
		final kc:Int = Mania.current;
		if (kc == Mania.DEFAULT) {
			// Classic 4K spacing, untouched.
			x += Note.swagWidth * noteData;
			x += 50;
			x += ((FlxG.width / 2) * player);
			x += skinOffsetX;
			y += skinOffsetY;
			return;
		}

		// Multikey: step each column by the note width plus a fixed gap so the
		// lanes aren't cramped, then shift the whole row left/right so it stays
		// centered on the exact point the 4K row centers on. Keeping the same
		// center means normal- and middle-scroll placement match 4K and don't
		// drift as the key count changes. Note.swagWidth already tracks the
		// current key count's scale (160 * noteSizes[kc-1]).
		final step:Float = Note.swagWidth + Mania.STRUM_GAP;
		// Half-span of the 4K row, i.e. how far its center sits from column 0.
		final center4K:Float = 160 * Mania.noteSizes[Mania.DEFAULT - 1] * (Mania.DEFAULT - 1) / 2;

		x += step * noteData;
		x += 50;
		x += ((FlxG.width / 2) * player);
		x -= (step * (kc - 1) / 2 - center4K); // re-center the wider/narrower row
		y += Mania.noteOffsetsY[kc - 1];
		x += skinOffsetX;
		y += skinOffsetY;
	}

	/**
		Per-frame update: counts down `resetAnim` and drops the receptor back to `static` when it elapses.
		@param elapsed seconds since the last frame
	**/
	override function update(elapsed:Float) {
		if (resetAnim > 0) {
			resetAnim -= elapsed;
			if (resetAnim <= 0) {
				playAnim('static');
				resetAnim = 0;
			}
		}
		super.update(elapsed);
	}

	/**
		Plays a receptor animation and re-applies lane centering + per-anim colorability.
		@param anim one of `static` / `pressed` / `confirm`
		@param force restart the animation even if it's already playing
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function playAnim(anim:String, ?force:Bool = false) {
		if (animation.curAnim != null && animation.curAnim.name == anim && animation.curAnim.numFrames <= 1)
			return;

		animation.play(anim, force);
		if (animation.curAnim != null) {
			centerOffsets();
			centerOrigin();
			if (folderLaneCenter)
				offset.x = (frameWidth - Note.swagWidth) / 2;
		}
		if (folderColorPerAnim) {
			var on:Bool = false;
			if (useRGBShader && animation.curAnim != null) {
				on = switch (animation.curAnim.name) {
					case 'static': staticColorable;
					case 'pressed': pressedColorable;
					case 'confirm': confirmColorable;
					default: false;
				}
			}
			rgbShader.enabled = on;
		} else if (useRGBShader)
			rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
	}
}
