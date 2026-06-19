package objects;

import backend.animation.PsychAnimationController;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

class StrumNote extends FlxSprite {
	public var rgbShader:RGBShaderReference;
	public var resetAnim:Float = 0;

	private var noteData:Int = 0;

	public var direction:Float = 90;
	public var downScroll:Bool = false;
	public var sustainReduce:Bool = true;

	public var skinOffsetX:Float = 0;
	public var skinOffsetY:Float = 0;

	public var folderLaneCenter:Bool = false;

	public var folderColorPerAnim:Bool = false;
	public var staticColorable:Bool = false;
	public var pressedColorable:Bool = true;
	public var confirmColorable:Bool = true;

	private var player:Int;

	public var texture(default, set):String = null;

	private function set_texture(value:String):String {
		if (texture != value) {
			texture = value;
			reloadNote();
		}
		return value;
	}

	public var useRGBShader:Bool = true;

	public function new(x:Float, y:Float, leData:Int, player:Int) {
		animation = new PsychAnimationController(this);

		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(leData));
		rgbShader.enabled = false;
		if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB)
			useRGBShader = false;

		var arr:Array<FlxColor>;
		if (Mania.current != Mania.DEFAULT && !PlayState.isPixelStage)
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

	public function reloadNote() {
		var lastAnim:String = null;
		if (animation.curAnim != null)
			lastAnim = animation.curAnim.name;

		folderLaneCenter = false;
		folderColorPerAnim = false;

		var folderSkin:String = NoteSkinConfig.activeSkin();
		if (folderSkin != null && reloadFolderStrum(folderSkin, lastAnim))
			return;

		if (PlayState.isPixelStage) {
			// Cache the pixel atlas reference -- the previous code called
			// Paths.image() twice for the exact same texture key, which
			// triggers a redundant cache lookup and graphic decode.
			final pixelGraphic = Paths.image('pixelUI/' + texture);
			if (pixelGraphic == null) {
				FlxG.log.error('StrumNote: pixel skin missing -- could not load "images/pixelUI/$texture.png"');
				return;
			}
			loadGraphic(pixelGraphic);
			width = width / 4;
			height = height / 5;
			loadGraphic(pixelGraphic, true, Math.floor(width), Math.floor(height));

			antialiasing = false;
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));

			animation.add('green', [6]);
			animation.add('red', [7]);
			animation.add('blue', [5]);
			animation.add('purple', [4]);
			switch (Math.abs(noteData) % 4) {
				case 0:
					animation.add('static', [0]);
					animation.add('pressed', [4, 8], 12, false);
					animation.add('confirm', [12, 16], 24, false);
				case 1:
					animation.add('static', [1]);
					animation.add('pressed', [5, 9], 12, false);
					animation.add('confirm', [13, 17], 24, false);
				case 2:
					animation.add('static', [2]);
					animation.add('pressed', [6, 10], 12, false);
					animation.add('confirm', [14, 18], 12, false);
				case 3:
					animation.add('static', [3]);
					animation.add('pressed', [7, 11], 12, false);
					animation.add('confirm', [15, 19], 24, false);
			}
		} else if (Mania.current != Mania.DEFAULT) {
			// Multikey: keep the 4 arrows from the note skin and merge in the
			// square atlas (which adds the centre "square" note + arrowSQUARE);
			// the per-column anim name comes from the Mania table.
			var atlas:flixel.graphics.frames.FlxAtlasFrames = Paths.getSparrowAtlas(texture);
			atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			frames = atlas;
			antialiasing = ClientPrefs.data.antialiasing;

			var anim:String = Mania.noteAnimations[Mania.current - 1][Std.int(Math.abs(noteData)) % Mania.current];
			animation.addByPrefix('static', 'arrow' + anim.toUpperCase(), 24, false);
			animation.addByPrefix('pressed', anim + ' press', 24, false);
			animation.addByPrefix('confirm', anim + ' confirm', 24, false);

			setGraphicSize(Std.int(width * Mania.noteSizes[Mania.current - 1]));
		} else {
			frames = Paths.getSparrowAtlas(texture);
			animation.addByPrefix('green', 'arrowUP');
			animation.addByPrefix('blue', 'arrowDOWN');
			animation.addByPrefix('purple', 'arrowLEFT');
			animation.addByPrefix('red', 'arrowRIGHT');

			antialiasing = ClientPrefs.data.antialiasing;
			setGraphicSize(Std.int(width * 0.7));

			switch (Math.abs(noteData) % 4) {
				case 0:
					animation.addByPrefix('static', 'arrowLEFT');
					animation.addByPrefix('pressed', 'left press', 24, false);
					animation.addByPrefix('confirm', 'left confirm', 24, false);
				case 1:
					animation.addByPrefix('static', 'arrowDOWN');
					animation.addByPrefix('pressed', 'down press', 24, false);
					animation.addByPrefix('confirm', 'down confirm', 24, false);
				case 2:
					animation.addByPrefix('static', 'arrowUP');
					animation.addByPrefix('pressed', 'up press', 24, false);
					animation.addByPrefix('confirm', 'up confirm', 24, false);
				case 3:
					animation.addByPrefix('static', 'arrowRIGHT');
					animation.addByPrefix('pressed', 'right press', 24, false);
					animation.addByPrefix('confirm', 'right confirm', 24, false);
			}
		}
		updateHitbox();

		if (lastAnim != null) {
			playAnim(lastAnim, true);
		}
	}

	function reloadFolderStrum(skinName:String, lastAnim:String):Bool {
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return false;

		if (NoteSkinConfig.editorOverride == null)
			NoteSkinConfig.pixelMode = (cfg.pixel == true) || (cfg.pixelVariant == true && PlayState.isPixelStage);

		var base:String = NoteSkinConfig.folder(skinName);
		var c:Int = Std.int(Math.abs(noteData));

		var st = NoteSkinConfig.resolveColumn(cfg, cfg.strums, c);
		if (st == null)
			return false;
		var staticF:Array<String> = NoteSkinConfig.frameKeys(NoteSkinConfig.variant(base + st.key));
		if (staticF == null)
			return false;
		var staticA:Float = st.angle;

		var pr = NoteSkinConfig.resolveColumn(cfg, cfg.pressed, c);
		var pressedF:Array<String> = pr == null ? null : NoteSkinConfig.frameKeys(NoteSkinConfig.variant(base + pr.key));
		var pressedA:Float = pr == null ? staticA : pr.angle;
		if (pressedF == null) {
			pressedF = staticF;
			pressedA = staticA;
		}

		var cf = NoteSkinConfig.resolveColumn(cfg, cfg.confirm, c);
		var confirmF:Array<String> = cf == null ? null : NoteSkinConfig.frameKeys(NoteSkinConfig.variant(base + cf.key));
		var confirmA:Float = cf == null ? pressedA : cf.angle;
		if (confirmF == null) {
			confirmF = pressedF;
			confirmA = pressedA;
		}

		var confirmFps:Int = cfg.confirmFPS == null ? 24 : cfg.confirmFPS;
		var factor:Float = NoteSkinConfig.applyAnims(this, [
			{
				name: 'static',
				keys: staticF,
				fps: 24,
				loop: false,
				angle: staticA,
				square: true
			},
			{
				name: 'pressed',
				keys: pressedF,
				fps: 24,
				loop: false,
				angle: pressedA,
				square: true
			},
			{
				name: 'confirm',
				keys: confirmF,
				fps: confirmF.length > 1 ? confirmFps : 24,
				loop: false,
				angle: confirmA,
				square: true
			}
		]);

		folderColorPerAnim = true;
		staticColorable = NoteSkinConfig.colorableFor(cfg, 'strums');
		pressedColorable = NoteSkinConfig.colorableFor(cfg, 'pressed');
		confirmColorable = NoteSkinConfig.colorableFor(cfg, 'confirm');
		antialiasing = (cfg.pixel == true || NoteSkinConfig.pixelMode) ? false : (cfg.antialiasing == null ? ClientPrefs.data.antialiasing : cfg.antialiasing);
		var soff:Array<Float> = NoteSkinConfig.offsetFor(cfg.strumOffsets, c);
		skinOffsetX = soff[0];
		skinOffsetY = soff[1];
		folderLaneCenter = true;
		var kc:Int = Mania.clamp(Mania.current);
		var scaleBase:Float = (cfg.scale == null ? 0.7 : cfg.scale) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		scale.set(scaleBase * factor, scaleBase * factor);
		updateHitbox();

		if (lastAnim != null)
			playAnim(lastAnim, true);
		return true;
	}

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

	public function playAnim(anim:String, ?force:Bool = false) {
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
