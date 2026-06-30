package objects;

import backend.animation.PsychAnimationController;
import shaders.RGBPalette;
import flixel.system.FlxAssets.FlxShader;

typedef RGB = {
	r:Null<Int>,
	g:Null<Int>,
	b:Null<Int>
}

typedef NoteSplashAnim = {
	name:String,
	noteData:Int,
	prefix:String,
	indices:Array<Int>,
	offsets:Array<Float>,
	fps:Array<Int>
}

typedef NoteSplashConfig = {
	animations:Map<String, NoteSplashAnim>,
	scale:Float,
	allowRGB:Bool,
	allowPixel:Bool,
	rgb:Array<Null<RGB>>
}

class NoteSplash extends FlxSprite {
	public var rgbShader:PixelSplashShaderRef;
	public var texture:String;
	public var config(default, set):NoteSplashConfig;
	public var babyArrow:FlxSprite;
	public var noteData:Int = 0;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var inEditor:Bool = false;

	var spawned:Bool = false;
	var noteDataMap:Map<Int, String> = new Map();

	// Cache identity (`NoteSkinConfig.splashSourceKey`) of the folder-native splash currently loaded,
	// or null when a legacy sparrow atlas is loaded instead. Avoids rebuilding the splash every spawn.
	public var folderSkinSource:String = null;

	// True when the loaded folder splash is pixel art (force antialiasing off without shader blocking).
	var folderSplashPixel:Bool = false;

	// True for folder-native splashes: centre on the lane (the same reference the notes/receptor use)
	// instead of the legacy sparrow splash's hand-tuned offset. `splashNudge*` adds the config offset.
	var folderCentered:Bool = false;
	var splashNudgeX:Float = 0;
	var splashNudgeY:Float = 0;

	public static var defaultNoteSplash(default, never):String = "noteSplashes/noteSplashes";
	public static var configs:Map<String, NoteSplashConfig> = new Map();

	// "Note Splashes" option value that defers to the active note skin's `splash`. Default selection.
	public static final FROM_NOTESKIN:String = 'From Noteskin';

	// Display name of the engine-default splash atlas (`noteSplashes/noteSplashes`, no postfix).
	public static final BASE_SKIN:String = 'Psych';

	// Splash anim/colour basis. Splash atlases only carry the 4 cardinal colours,
	// so splashes always map columns via `% 4` -- this is deliberately NOT
	// colArray, which becomes longer (purple/blue/green/red/square/...) under
	// multikey and would break the splash config build (no 'square' splash anim).
	public static var colArray:Array<String> = ['purple', 'blue', 'green', 'red'];

	public function new(?x:Float = 0, ?y:Float = 0, ?splash:String) {
		super(x, y);

		animation = new PsychAnimationController(this);

		rgbShader = new PixelSplashShaderRef();
		shader = rgbShader.shader;

		loadSplash(splash);
	}

	public var maxAnims(default, set):Int = 0;

	public function loadSplash(?splash:String) {
		config = null;
		maxAnims = 0;
		folderSkinSource = null; // a legacy sparrow atlas is being loaded; drop any folder-splash state
		folderSplashPixel = false;
		folderCentered = false;

		if (splash == null) {
			if (PlayState.SONG != null && PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0)
				splash = PlayState.SONG.splashSkin;
			else
				splash = preferredSplashTexture();
		}

		texture = splash;
		frames = Paths.getSparrowAtlas(texture);
		if (frames == null) {
			texture = defaultNoteSplash + getSplashSkinPostfix();
			frames = Paths.getSparrowAtlas(texture);
			if (frames == null) {
				texture = defaultNoteSplash;
				frames = Paths.getSparrowAtlas(texture);
			}
		}

		var path:String = 'images/$texture';
		if (configs.exists(path)) {
			this.config = configs.get(path);
			for (anim in this.config.animations) {
				if (anim.noteData % 4 == 0)
					maxAnims++;
			}
			return;
		} else if (Paths.fileExists('$path.json', TEXT)) {
			var config:Dynamic = haxe.Json.parse(Paths.getTextFromFile('$path.json'));
			if (config != null) {
				var tempConfig:NoteSplashConfig = {
					animations: new Map(),
					scale: config.scale,
					allowRGB: config.allowRGB,
					allowPixel: config.allowPixel,
					rgb: config.rgb
				}

				if (config.animations != null) {
					for (i in Reflect.fields(config.animations)) {
						var anim:NoteSplashAnim = Reflect.field(config.animations, i);
						if (anim == null) continue;
						tempConfig.animations.set(i, anim);
						if (anim.noteData % 4 == 0)
							maxAnims++;
					}
				}

				this.config = tempConfig;
				configs.set(path, this.config);
				return;
			}
		}

		// Splashes with no json
		var tempConfig:NoteSplashConfig = createConfig();
		var anim:String = 'note splash';
		var fps:Array<Null<Int>> = [22, 26];
		var offsets:Array<Array<Float>> = [[0, 0]];
		if (Paths.fileExists('$path.txt', TEXT)) // Backwards compatibility with 0.7 splash txts
		{
			var configFile:Array<String> = CoolUtil.listFromString(Paths.getTextFromFile('$path.txt'));
			if (configFile.length > 0) {
				anim = configFile[0];
				if (configFile.length > 1) {
					var framerates:Array<String> = configFile[1].split(' ');
					fps = [Std.parseInt(framerates[0]), Std.parseInt(framerates[1])];
					if (fps[0] == null)
						fps[0] = 22;
					if (fps[1] == null)
						fps[1] = 26;

					if (configFile.length > 2) {
						offsets = [];
						for (i in 2...configFile.length) {
							if (configFile[i].trim() != '') {
								var animOffs:Array<String> = configFile[i].split(' ');
								var x:Float = Std.parseFloat(animOffs[0]);
								var y:Float = Std.parseFloat(animOffs[1]);
								if (Math.isNaN(x))
									x = 0;
								if (Math.isNaN(y))
									y = 0;
								offsets.push([x, y]);
							}
						}
						// If every offset row was blank, fall back to default
						// instead of leaving an empty array; the wrap math
						// below would otherwise return offsets[0] == null and
						// crash later in spawnSplashNote.
						if (offsets.length == 0)
							offsets = [[0, 0]];
					}
				}
			}
		}

		var failedToFind:Bool = false;
		while (true) {
			for (v in colArray) {
				if (!checkForAnim('$anim $v ${maxAnims + 1}')) {
					failedToFind = true;
					break;
				}
			}
			if (failedToFind)
				break;
			maxAnims++;
		}

		for (animNum in 0...maxAnims) {
			for (i => col in colArray) {
				var data:Int = i % colArray.length + (animNum * colArray.length);
				var name:String = animNum > 0 ? '$col' + (animNum + 1) : col;
				var offset:Array<Float> = offsets[FlxMath.wrap(data, 0, Std.int(offsets.length - 1))];
				addAnimationToConfig(tempConfig, 1, name, '$anim $col ${animNum + 1}', fps, offset, [], data);
			}
		}

		this.config = tempConfig;
		configs.set(path, this.config);
	}

	/**
		Loads the active note skin's folder-native splash (built from individual images / sequences via
		`NoteSkinConfig.applySplash`, with `@2x` and `pixel/` variants), reusing the cached build when the
		skin/keycount/pixel state is unchanged.
		@return `true` if a folder splash was loaded; `false` if the skin provides none (use the legacy path)
	**/
	public function tryFolderSplash():Bool {
		var source:String = backend.NoteSkinConfig.splashSourceKey();
		if (source == null)
			return false;
		if (folderSkinSource == source && config != null && frames != null)
			return true; // already built for this skin/keycount/pixel state

		@:privateAccess animation.clearAnimations();
		noteDataMap.clear();

		var info:backend.NoteSkinConfig.SplashInfo = backend.NoteSkinConfig.applySplash(this);
		if (info == null) {
			folderSkinSource = null;
			return false;
		}

		var cfg:NoteSplashConfig = createConfig();
		cfg.scale = info.scale;
		cfg.allowRGB = info.allowRGB;
		cfg.allowPixel = info.allowPixel;
		cfg.rgb = null; // recolour from the arrow palette, like the default white splash
		for (col in 0...info.names.length) {
			var nm:String = info.names[col];
			cfg.animations.set(nm, {name: nm, noteData: col, prefix: '', indices: [], offsets: info.offsets[col], fps: info.fps});
			noteDataMap.set(col, nm);
		}

		// The anims are already on the sprite (applySplash -> applyAnims); bypass set_config so it
		// doesn't wipe and try to rebuild them from prefixes.
		@:bypassAccessor this.config = cfg;
		@:bypassAccessor this.maxAnims = 1;
		scale.set(info.scale, info.scale);
		texture = null;
		folderSkinSource = info.source;
		folderSplashPixel = info.pixel;
		folderCentered = true;
		return true;
	}

	public function spawnSplashNote(?x:Float = 0, ?y:Float = 0, ?noteData:Int = 0, ?note:Note, ?randomize:Bool = true) {
		if (note != null && note.noteSplashData.disabled)
			return;

		aliveTime = 0;

		if (!inEditor) {
			// Resolution priority: a note-type's explicit splash override > the chart's `splashSkin`
			// (songs override the player's option) > the player's "Note Splashes" choice (which is
			// "From Noteskin" by default). "From Noteskin" prefers the active skin's folder-native
			// splash and only falls back to the legacy sparrow path when the skin provides one.
			var legacyTexture:String = null;
			if (note != null && note.noteSplashData.texture != null && note.noteSplashData.texture.length > 0)
				legacyTexture = note.noteSplashData.texture;
			else if (PlayState.SONG != null && PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0)
				legacyTexture = PlayState.SONG.splashSkin;
			else if (ClientPrefs.data.splashSkin != FROM_NOTESKIN)
				legacyTexture = defaultNoteSplash + getSplashSkinPostfix();

			if (legacyTexture != null) {
				if (folderSkinSource != null || texture != legacyTexture)
					loadSplash(legacyTexture);
			} else if (!tryFolderSplash()) {
				// "From Noteskin" but the skin has no folder splash: its named sparrow atlas, or the base.
				var sparrow:String = backend.NoteSkinConfig.currentSplash();
				var baseTexture:String = (sparrow != null) ? sparrow : defaultNoteSplash;
				if (folderSkinSource != null || texture != baseTexture)
					loadSplash(baseTexture);
			}
		}

		setPosition(x, y);

		if (note != null)
			noteData = note.noteData;

		var paletteCol:Int = noteData;

		// Always map the column to one of the 4 cardinal splash colours (`% 4`); pick a random variant
		// only when the atlas ships more than one. (Plain `% 4` also keeps multikey columns in range.)
		var variant:Int = (randomize && maxAnims > 1) ? FlxG.random.int(0, maxAnims - 1) : 0;
		noteData = noteData % colArray.length + variant * colArray.length;

		this.noteData = noteData;
		var anim:String = playDefaultAnim();

		var tempShader:RGBPalette = null;
		if (config.allowRGB && ClientPrefs.data.linkSplashColor) {
			Note.initializeGlobalRGBShader(noteData % colArray.length);
			if (inEditor
				|| (note == null || note.noteSplashData.useRGBShader)
				&& (PlayState.SONG == null || !PlayState.SONG.disableNoteRGB)) {
				tempShader = new RGBPalette();
				// If Note RGB is enabled:
				if ((note == null || !note.noteSplashData.useGlobalShader) || inEditor) {
					var colors = config.rgb;
					if (colors != null) {
						for (i in 0...colors.length) {
							if (i > 2)
								break;

							var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[noteData % colArray.length];
							if (PlayState.isPixelStage)
								arr = ClientPrefs.data.arrowRGBPixel[noteData % colArray.length];

							var rgb = colors[i];
							if (rgb == null) {
								if (i == 0)
									tempShader.r = arr[0];
								else if (i == 1)
									tempShader.g = arr[1];
								else if (i == 2)
									tempShader.b = arr[2];
								continue;
							}

							var r:Null<Int> = rgb.r;
							var g:Null<Int> = rgb.g;
							var b:Null<Int> = rgb.b;

							if (r == null || Math.isNaN(r) || r < 0)
								r = arr[0];
							if (g == null || Math.isNaN(g) || g < 0)
								g = arr[1];
							if (b == null || Math.isNaN(b) || b < 0)
								b = arr[2];

							var color:FlxColor = FlxColor.fromRGB(r, g, b);
							if (i == 0)
								tempShader.r = color;
							else if (i == 1)
								tempShader.g = color;
							else if (i == 2)
								tempShader.b = color;
						}
					} else
						tempShader.copyValues(Note.globalRgbShaders[noteData % colArray.length]);

					if (note != null) {
						if (note.noteSplashData.r != -1)
							tempShader.r = note.noteSplashData.r;
						if (note.noteSplashData.g != -1)
							tempShader.g = note.noteSplashData.g;
						if (note.noteSplashData.b != -1)
							tempShader.b = note.noteSplashData.b;
					}
				} else
					tempShader.copyValues(Note.globalRgbShaders[noteData % colArray.length]);
			}
		}

		if (tempShader != null && note == null && !inEditor && Mania.current != Mania.DEFAULT) {
			var mc:Array<Array<FlxColor>> = Mania.getColors(Mania.current);
			if (paletteCol >= 0 && paletteCol < mc.length && mc[paletteCol] != null && mc[paletteCol].length >= 3) {
				tempShader.r = mc[paletteCol][0];
				tempShader.g = mc[paletteCol][1];
				tempShader.b = mc[paletteCol][2];
			}
		}
		rgbShader.copyValues(tempShader);
		if (!config.allowPixel)
			rgbShader.pixelAmount = 1;
		else if (PlayState.isPixelStage)
			rgbShader.pixelAmount = PlayState.daPixelZoom;

		var conf:NoteSplashAnim = config.animations.get(anim);
		var offsets:Array<Float> = (conf != null && conf.offsets != null) ? conf.offsets : [0, 0];
		// All splashes are centred on the receptor in followArrow(); the config offsets nudge that centre
		// via the position (not `offset`, which would fight the centring math).
		offset.set(0, 0);
		splashNudgeX = offsets[0];
		splashNudgeY = offsets[1];

		animation.finishCallback = function(name:String) {
			kill();
			spawned = false;
		}

		alpha = ClientPrefs.data.splashAlpha;
		if (note != null)
			alpha = note.noteSplashData.a;

		antialiasing = ClientPrefs.data.antialiasing;
		if (note != null)
			antialiasing = note.noteSplashData.antialiasing;
		if (PlayState.isPixelStage && config.allowPixel)
			antialiasing = false;
		if (folderSplashPixel) // folder pixel splash: crisp art, but no extra shader blocking
			antialiasing = false;

		var minFps:Int = 22;
		var maxFps:Int = 26;
		if (conf != null) {
			minFps = conf.fps[0];
			if (minFps < 0)
				minFps = 0;

			maxFps = conf.fps[1];
			if (maxFps < 0)
				maxFps = 0;
		}

		if (animation.curAnim != null)
			animation.curAnim.frameRate = FlxG.random.int(minFps, maxFps);

		// Multikey: scale the splash down to match the smaller notes. 4K keeps the config scale untouched;
		// followArrow() re-centres on the receptor afterwards, so no per-keycount offset nudge is needed.
		if (!inEditor && Mania.current != Mania.DEFAULT) {
			var ratio:Float = Mania.noteSizes[Mania.current - 1] / 0.7;
			scale.set(config.scale * ratio, config.scale * ratio);
		}

		followArrow();
		spawned = true;
	}

	// Keeps the spawned splash glued to its receptor. Folder splashes centre on the lane -- the same
	// `swagWidth`-square reference the notes/receptor use -- so the burst sits exactly on the strum;
	// legacy sparrow splashes keep their historical hand-tuned offset. Called on spawn and every frame.
	function followArrow():Void {
		if (babyArrow == null)
			return;
		// Centre the splash graphic on the receptor's on-screen graphic centre, accounting for the
		// receptor's own offset + scale, so the burst sits exactly on the strum for every skin/keycount.
		var recCx:Float = babyArrow.x - babyArrow.offset.x + babyArrow.frameWidth * babyArrow.scale.x / 2;
		var recCy:Float = babyArrow.y - babyArrow.offset.y + babyArrow.frameHeight * babyArrow.scale.y / 2;
		if (copyX)
			x = recCx - frameWidth * scale.x / 2 + splashNudgeX;
		if (copyY)
			y = recCy - frameHeight * scale.y / 2 + splashNudgeY;
	}

	public function playDefaultAnim() {
		var anim:String = noteDataMap.get(noteData);
		if (anim != null && animation.exists(anim))
			animation.play(anim, true);

		return anim;
	}

	function checkForAnim(anim:String) {
		var animFrames = [];
		@:privateAccess
		animation.findByPrefix(animFrames, anim); // adds valid frames to animFrames

		return animFrames.length > 0;
	}

	var aliveTime:Float = 0;

	static var buggedKillTime:Float = 0.5; // automatically kills note splashes if they break to prevent it from flooding your HUD

	override function update(elapsed:Float) {
		if (spawned) {
			aliveTime += elapsed;
			if (animation.curAnim == null && aliveTime >= buggedKillTime) {
				kill();
				spawned = false;
			}
		}

		followArrow();
		super.update(elapsed);
	}

	public static function getSplashSkinPostfix() {
		var sel:String = ClientPrefs.data.splashSkin;
		// Both "From Noteskin" (skin-provided) and the base "Psych" atlas use no filename postfix.
		if (sel == FROM_NOTESKIN || sel == BASE_SKIN)
			return '';
		return '-' + sel.trim().toLowerCase().replace(' ', '-');
	}

	/**
		The splash atlas the player's "Note Splashes" option resolves to, ignoring per-note and
		per-chart overrides. "From Noteskin" -> the active note skin's `splash` (or the base atlas when
		the skin provides none); any other value -> the base atlas plus that skin's filename postfix.
	**/
	public static function preferredSplashTexture():String {
		if (ClientPrefs.data.splashSkin == FROM_NOTESKIN) {
			var fromSkin:String = backend.NoteSkinConfig.currentSplash();
			if (fromSkin != null && fromSkin.length > 0)
				return fromSkin;
		}
		return defaultNoteSplash + getSplashSkinPostfix();
	}

	public static function createConfig():NoteSplashConfig {
		return {
			animations: new Map(),
			scale: 1,
			allowRGB: true,
			allowPixel: true,
			rgb: null
		}
	}

	public static function addAnimationToConfig(config:NoteSplashConfig, scale:Float, name:String, prefix:String, fps:Array<Int>, offsets:Array<Float>,
			indices:Array<Int>, noteData:Int):NoteSplashConfig {
		if (config == null)
			config = createConfig();

		config.animations.set(name, {
			name: name,
			noteData: noteData,
			prefix: prefix,
			indices: indices,
			offsets: offsets,
			fps: fps
		});
		config.scale = scale;
		return config;
	}

	function set_config(value:NoteSplashConfig):NoteSplashConfig {
		if (value == null)
			value = createConfig();

		@:privateAccess
		animation.clearAnimations();
		noteDataMap.clear();

		for (i in value.animations) {
			var key:String = i.name;
			if (i.prefix.length > 0 && key != null && key.length > 0) {
				if (i.indices != null && i.indices.length > 0)
					animation.addByIndices(key, i.prefix, i.indices, "", i.fps[1], false);
				else
					animation.addByPrefix(key, i.prefix, i.fps[1], false);

				noteDataMap.set(i.noteData, key);
			}
		}

		scale.set(value.scale, value.scale);
		return config = value;
	}

	function set_maxAnims(value:Int) {
		if (value > 0)
			noteData = Std.int(FlxMath.wrap(noteData, 0, (value * colArray.length) - 1));
		else
			noteData = 0;

		return maxAnims = value;
	}
}

class PixelSplashShaderRef {
	public var shader:PixelSplashShader = new PixelSplashShader();
	public var enabled(default, set):Bool = true;
	public var pixelAmount(default, set):Float = 1;

	public function copyValues(tempShader:RGBPalette) {
		if (tempShader != null) {
			for (i in 0...3) {
				shader.r.value[i] = tempShader.shader.r.value[i];
				shader.g.value[i] = tempShader.shader.g.value[i];
				shader.b.value[i] = tempShader.shader.b.value[i];
			}
			shader.mult.value[0] = tempShader.shader.mult.value[0];
		} else
			enabled = false;
	}

	public function set_enabled(value:Bool) {
		enabled = value;
		shader.mult.value = [value ? 1 : 0];
		return value;
	}

	public function set_pixelAmount(value:Float) {
		pixelAmount = value;
		shader.uBlocksize.value = [value, value];
		return value;
	}

	public function reset() {
		shader.r.value = [0, 0, 0];
		shader.g.value = [0, 0, 0];
		shader.b.value = [0, 0, 0];
	}

	public function new() {
		reset();
		enabled = true;

		if (!PlayState.isPixelStage)
			pixelAmount = 1;
		else
			pixelAmount = PlayState.daPixelZoom;
		// trace('Created shader ' + Conductor.songPosition);
	}
}

class PixelSplashShader extends FlxShader {
	@:glFragmentHeader('
		#pragma header

		uniform vec3 r;
		uniform vec3 g;
		uniform vec3 b;
		uniform float mult;
		uniform vec2 uBlocksize;

		vec4 flixel_texture2DCustom(sampler2D bitmap, vec2 coord) {
			vec2 blocks = openfl_TextureSize / uBlocksize;
			vec4 color = flixel_texture2D(bitmap, floor(coord * blocks) / blocks);
			if (!hasTransform) {
				return color;
			}

			if (color.a == 0.0 || mult == 0.0) {
				return color * openfl_Alphav;
			}

			vec4 newColor = color;
			newColor.rgb = min(color.r * r + color.g * g + color.b * b, vec3(1.0));
			newColor.a = color.a;

			color = mix(color, newColor, mult);

			if (color.a > 0.0) {
				return vec4(color.rgb, color.a);
			}
			return vec4(0.0, 0.0, 0.0, 0.0);
		}')
	@:glFragmentSource('
		#pragma header

		void main() {
			gl_FragColor = flixel_texture2DCustom(bitmap, openfl_TextureCoordv);
		}')
	public function new() {
		super();
	}
}
