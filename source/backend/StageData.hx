package backend;

import openfl.utils.Assets;
import haxe.Json;
import backend.Song;
import psychlua.ModchartSprite;

typedef StageFile = {
	var directory:String;
	var defaultZoom:Float;
	@:optional var isPixelStage:Null<Bool>;
	var stageUI:String;

	var boyfriend:Array<Dynamic>;
	var girlfriend:Array<Dynamic>;
	var opponent:Array<Dynamic>;
	var hide_girlfriend:Bool;

	var camera_boyfriend:Array<Float>;
	var camera_opponent:Array<Float>;
	var camera_girlfriend:Array<Float>;
	var camera_speed:Null<Float>;

	@:optional var preload:Dynamic;
	@:optional var objects:Array<Dynamic>;
	@:optional var _editorMeta:Dynamic;
}

enum abstract LoadFilters(Int) from Int from UInt to Int to UInt {
	var LOW_QUALITY:Int = (1 << 0);
	var HIGH_QUALITY:Int = (1 << 1);

	var STORY_MODE:Int = (1 << 2);
	var FREEPLAY:Int = (1 << 3);
}

class StageData {
	public static function dummy():StageFile {
		return {
			directory: "",
			defaultZoom: 0.9,
			stageUI: "normal",

			boyfriend: [770, 100],
			girlfriend: [400, 130],
			opponent: [100, 100],
			hide_girlfriend: false,

			camera_boyfriend: [0, 0],
			camera_opponent: [0, 0],
			camera_girlfriend: [0, 0],
			camera_speed: 1,

			_editorMeta: {
				gf: "gf",
				dad: "dad",
				boyfriend: "bf"
			}
		};
	}

	public static var forceNextDirectory:String = null;

	public static function loadDirectory(SONG:SwagSong) {
		var stage:String = '';
		if (SONG.stage != null && SONG.stage.length > 0)
			stage = SONG.stage;
		else if (Song.loadedSongName != null)
			stage = vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));
		else
			stage = 'stage';

		var stageFile:StageFile = getStageFile(stage);
		forceNextDirectory = (stageFile != null) ? stageFile.directory : ''; // preventing crashes
	}

	public static function getStageFile(stage:String):StageFile {
		// Previously had `try { ... }` with no catch -- exceptions propagated
		// up instead of falling through to dummy(). Added catch so a malformed
		// stage JSON now returns the dummy instead of crashing.
		try {
			var path:String = Paths.getPath('stages/' + stage + '.json', TEXT, null, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(path))
				return cast CoolUtil.parseJson(File.getContent(path));
			#else
			if (Assets.exists(path))
				return cast CoolUtil.parseJson(Assets.getText(path));
			#end
		} catch (e:Dynamic) {
			trace('StageData: failed to load stage "$stage": $e');
		}
		return dummy();
	}

	public static function vanillaSongStage(songName):String {
		switch (songName) {
			case 'spookeez' | 'south' | 'monster':
				return 'spooky';
			case 'pico' | 'blammed' | 'philly' | 'philly-nice':
				return 'philly';
			case 'milf' | 'satin-panties' | 'high':
				return 'limo';
			case 'cocoa' | 'eggnog':
				return 'mall';
			case 'winter-horrorland':
				return 'mallEvil';
			case 'senpai' | 'roses':
				return 'school';
			case 'thorns':
				return 'schoolEvil';
			case 'ugh' | 'guns' | 'stress':
				return 'tank';
		}
		return 'stage';
	}

	public static var reservedNames:Array<String> = [
		'gf', 'gfGroup', 'dad', 'dadGroup', 'boyfriend', 'boyfriendGroup',
		// The three built-in character anchors. A `character` object may not shadow them, or a
		// strumline asking for `player` would get the stage's object instead of the real one.
		ANCHOR_OPPONENT, ANCHOR_PLAYER, ANCHOR_SPECTATOR
	]; // blocks these names from being used on stage editor's name input text

	/** The anchor a strumline's character stands on when its role is OPPONENT. **/
	public static inline var ANCHOR_OPPONENT:String = 'opponent';

	/** ... PLAYER. **/
	public static inline var ANCHOR_PLAYER:String = 'player';

	/** ... ADDITIONAL, and where a `gf` sing-track lands. **/
	public static inline var ANCHOR_SPECTATOR:String = 'spectator';

	/**
		Named character anchors a stage declares, beyond the three built-in ones.

		An anchor is a `character` entry in the stage's `objects` list:
		`{ "type": "character", "name": "dj_booth", "x": 2750, "y": 1610 }`. It sits in the layer
		stack at its own slot like any other object, which is the reason anchors live in `objects`
		rather than in a positions map -- a character that cannot be layered between stage pieces is
		not much use.

		@param stage the loaded stage file
		@return anchor name -> `[x, y]`, empty when the stage declares none
	**/
	public static function characterAnchors(stage:StageFile):Map<String, Array<Float>> {
		var out:Map<String, Array<Float>> = new Map();
		if (stage == null || stage.objects == null)
			return out;

		for (data in stage.objects) {
			if (data == null || data.type != 'character')
				continue;
			var name:String = data.name;
			if (name == null || name.length < 1)
				continue;
			out.set(name, [(data.x != null) ? data.x : 0.0, (data.y != null) ? data.y : 0.0]);
		}
		return out;
	}

	/**
		Empty positioned groups created for `character` anchors, by anchor name.

		Filled by `addObjectsToState` and read straight after by `PlayState`, which spawns whichever
		strumline character is bound to each anchor into its group. Cleared on every call so a
		restart does not inherit the previous stage's groups.
	**/
	public static var anchorGroups:Map<String, FlxSpriteGroup> = new Map();

	public static function addObjectsToState(objectList:Array<Dynamic>, gf:FlxSprite, dad:FlxSprite, boyfriend:FlxSprite, ?group:Dynamic = null,
			?ignoreFilters:Bool = false) {
		var addedObjects:Map<String, FlxSprite> = [];
		anchorGroups = new Map();
		for (num => data in objectList) {
			// Pick the canonical key the matching branch below would store under.
			// Previously this called `addedObjects.exists(data)` on a Dynamic,
			// so the dedup never matched and entries could be added twice.
			var dedupKey:String = switch (data.type) {
				case 'gf', 'gfGroup': 'gf';
				case 'dad', 'dadGroup': 'dad';
				case 'boyfriend', 'boyfriendGroup': 'boyfriend';
				default: data.name;
			};
			if (dedupKey != null && addedObjects.exists(dedupKey))
				continue;

			switch (data.type) {
				// A character anchor: an empty group at this slot in the layer stack, which PlayState
				// fills with whichever strumline's character is bound to this name. Adding it here
				// rather than positioning a character directly is what gives the character the same
				// layering control every other stage object has.
				case 'character':
					var name:String = data.name;
					if (name == null || name.length < 1)
						continue;

					var anchor:FlxSpriteGroup = new FlxSpriteGroup((data.x != null) ? data.x : 0.0, (data.y != null) ? data.y : 0.0);
					anchor.ID = num;
					if (data.scrollFactor != null)
						anchor.scrollFactor.set(data.scrollFactor[0], data.scrollFactor[1]);
					if (group != null)
						group.add(anchor);
					anchorGroups.set(name, anchor);
					addedObjects.set(name, anchor);

				case 'gf', 'gfGroup':
					if (gf != null) {
						gf.ID = num;
						if (group != null)
							group.add(gf);
						addedObjects.set('gf', gf);
					}
				case 'dad', 'dadGroup':
					if (dad != null) {
						dad.ID = num;
						if (group != null)
							group.add(dad);
						addedObjects.set('dad', dad);
					}
				case 'boyfriend', 'boyfriendGroup':
					if (boyfriend != null) {
						boyfriend.ID = num;
						if (group != null)
							group.add(boyfriend);
						addedObjects.set('boyfriend', boyfriend);
					}

				case 'square', 'sprite', 'animatedSprite':
					if (!ignoreFilters && !validateVisibility(data.filters))
						continue;

					var spr:ModchartSprite = new ModchartSprite(data.x, data.y);
					spr.ID = num;
					if (data.type != 'square') {
						if (data.type == 'sprite')
							spr.loadGraphic(Paths.image(data.image));
						else
							spr.frames = Paths.getAtlas(data.image);

						if (data.type == 'animatedSprite' && data.animations != null) {
							var anims:Array<objects.Character.AnimArray> = cast data.animations;
							for (key => anim in anims) {
								if (anim.indices == null || anim.indices.length < 1)
									spr.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);
								else
									spr.animation.addByIndices(anim.anim, anim.name, anim.indices, '', anim.fps, anim.loop);

								if (anim.offsets != null)
									spr.addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);

								if (spr.animation.curAnim == null || data.firstAnimation == anim.anim)
									spr.playAnim(anim.anim, true);
							}
						}
						for (varName in ['antialiasing', 'flipX', 'flipY']) {
							var dat:Dynamic = Reflect.getProperty(data, varName);
							if (dat != null)
								Reflect.setProperty(spr, varName, dat);
						}
						if (!ClientPrefs.data.antialiasing)
							spr.antialiasing = false;
					} else {
						spr.makeGraphic(1, 1, FlxColor.WHITE);
						spr.antialiasing = false;
					}

					if (data.scale != null && (data.scale[0] != 1.0 || data.scale[1] != 1.0)) {
						spr.scale.set(data.scale[0], data.scale[1]);
						spr.updateHitbox();
					}
					if (data.scroll != null)
						spr.scrollFactor.set(data.scroll[0], data.scroll[1]);
					if (data.color != null)
						spr.color = CoolUtil.colorFromString(data.color);

					for (varName in ['alpha', 'angle']) {
						var dat:Dynamic = Reflect.getProperty(data, varName);
						if (dat != null)
							Reflect.setProperty(spr, varName, dat);
					}

					if (group != null)
						group.add(spr);
					addedObjects.set(data.name, spr);

				default:
					var err = '[Stage .JSON file] Unknown sprite type detected: ${data.type}';
					trace(err);
					FlxG.log.error(err);
			}
		}
		return addedObjects;
	}

	public static function validateVisibility(filters:LoadFilters) {
		// Previously written as a nested if/else chain whose inner branch
		// (`if (PlayState.isStoryMode)` inside the `else` of `if (!PlayState.isStoryMode)`)
		// was unreachable, and pure-FREEPLAY-filtered objects were never hidden in
		// story mode. Split into two independent bitmask checks.
		if ((filters & STORY_MODE) == STORY_MODE && !PlayState.isStoryMode)
			return false;
		if ((filters & FREEPLAY) == FREEPLAY && PlayState.isStoryMode)
			return false;

		return ((ClientPrefs.data.lowQuality && (filters & LOW_QUALITY) == LOW_QUALITY)
			|| (!ClientPrefs.data.lowQuality && (filters & HIGH_QUALITY) == HIGH_QUALITY));
	}
}
