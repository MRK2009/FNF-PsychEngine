package legacy;

import backend.animation.PsychAnimationController;
import backend.NoteTypesConfig;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;
import objects.StrumNote;
import objects.notes.NoteDefaults;
import flixel.math.FlxRect;

using StringTools;

// These typedefs now live on the neutral `objects.notes.NoteDefaults`; re-exported here so the long-
// standing `legacy.LegacyNote.EventNote` / `.NoteSplashData` (and `objects.Note.*`) names keep working.
typedef EventNote = objects.notes.NoteDefaults.EventNote;
typedef NoteSplashData = objects.notes.NoteDefaults.NoteSplashData;

/**
 * **LEGACY (pre-v2) note object — deprecated.** This is the old `objects.Note`, kept only so editors,
 * stages and Lua/HScript that reference `Note` keep working, and so a `compatibilityMode` modpack can
 * run on the legacy script API. The live gameplay runtime is `objects.notes.*` (`NoteData` +
 * `NoteSprite`/`SustainSprite`/`Receptor`/`NoteField`). Its gameplay methods are `@:deprecated`; the
 * remaining static forwarders (`swagWidth`/`colArray`/`initializeGlobalRGBShader`/...) are NOT — they
 * just re-export the neutral `objects.notes.NoteDefaults` / `Mania` so `Note.*` reads still resolve.
 *
 * If you want to make a custom note type, you should search for: "function set_noteType"
**/
class LegacyNote extends FlxSprite {
	// Note constants/helpers now live on the neutral `objects.notes.NoteDefaults`; these forwarders keep
	// the historical `Note.*` read/write API for editors, stages and Lua. Inline, so they compile to a
	// direct access on `NoteDefaults` with no call overhead.
	public static var defaultNoteTypes(get, never):Array<String>;

	static inline function get_defaultNoteTypes():Array<String>
		return NoteDefaults.defaultNoteTypes;

	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var strumTime:Float = 0;
	public var noteData:Int = 0;

	public var mustPress:Bool = false;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;

	public var wasGoodHit:Bool = false;
	public var missed:Bool = false;

	public var ignoreNote:Bool = false;
	public var hitByOpponent:Bool = false;
	public var noteWasHit:Bool = false;
	public var prevNote:LegacyNote;
	public var nextNote:LegacyNote;

	public var spawned:Bool = false;

	public var tail:Array<LegacyNote> = []; // for sustains
	public var parent:LegacyNote;

	public var blockHit:Bool = false; // only works for player

	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	public var noteType(default, set):String = null;

	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';

	public var rgbShader:RGBShaderReference;

	public static var globalRgbShaders(get, set):Array<RGBPalette>;

	static inline function get_globalRgbShaders():Array<RGBPalette>
		return NoteDefaults.globalRgbShaders;

	static inline function set_globalRgbShaders(value:Array<RGBPalette>):Array<RGBPalette>
		return NoteDefaults.globalRgbShaders = value;

	// Per-song dedupe set for hitsound precaching. set_noteType used to
	// call Paths.sound(hitsound) for every note that referenced a custom
	// hitsound -- with hundreds of notes per chart that's hundreds of
	// string formats + Map.exists checks + localTrackedAssets pushes
	// for the same handful of unique sounds. PlayState resets this on
	// create() so memory doesn't accumulate across songs.
	public static var precachedHitsounds:Map<String, Bool> = new Map();

	public var inEditor:Bool = false;

	public var animSuffix:String = '';
	public var gfNote:Bool = false;
	public var earlyHitMult:Float = 1;
	public var lateHitMult:Float = 1;
	public var lowPriority:Bool = false;

	public static var SUSTAIN_SIZE(get, never):Int;

	static inline function get_SUSTAIN_SIZE():Int
		return NoteDefaults.SUSTAIN_SIZE;

	// Keycount-derived globals now live on (and are owned by) `Mania`; these stay as the historical
	// `Note.swagWidth` / `Note.colArray` read API (Lua, editors, legacy) and forward to it. Inline,
	// so reads compile to a direct `Mania.*` field access -- no call overhead in the hot paths.
	public static var swagWidth(get, never):Float;

	static inline function get_swagWidth():Float
		return Mania.swagWidth;

	public static var colArray(get, never):Array<String>;

	static inline function get_colArray():Array<String>
		return Mania.colArray;

	public static var defaultNoteSkin(get, never):String;

	static inline function get_defaultNoteSkin():String
		return NoteDefaults.defaultNoteSkin;

	public var noteSplashData:NoteSplashData = {
		disabled: false,
		texture: null,
		antialiasing: !PlayState.isPixelStage,
		useGlobalShader: false,
		useRGBShader: (PlayState.SONG != null) ? !(PlayState.SONG.disableNoteRGB == true) : true,
		r: -1,
		g: -1,
		b: -1,
		a: ClientPrefs.data.splashAlpha
	};

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var centerOnStrum:Bool = false;
	public var offsetAngle:Float = 0;
	public var multAlpha:Float = 1;
	public var multSpeed(default, set):Float = 1;

	/*
	 * Stretched sustain-body scale at the song's base speed, captured at creation so scripts
	 * (e.g. the osu! SV script) can rescale the hold length without compounding. 0 = not a body.
	 */
	public var sustainBaseScaleY:Float = 0;

	/*
	 * Free per-note cache for scripts (the osu! SV script stores its precomputed scroll
	 * position here at spawn, so its per-frame work stays O(1) with no lookup).
	 */
	public var svScrollPos:Float = 0;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;

	public var hitHealth:Float = 0.02;
	public var missHealth:Float = 0.1;
	public var rating:String = 'unknown';
	public var ratingMod:Float = 0; // 9 = unknown, 0.25 = shit, 0.5 = bad, 0.75 = good, 1 = sick
	public var ratingDisabled:Bool = false;

	public var texture(default, set):String = null;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var hitCausesMiss:Bool = false;
	public var distance:Float = 2000; // plan on doing scroll directions soon -bb

	public var hitsoundDisabled:Bool = false;
	public var hitsoundChartEditor:Bool = true;

	/**
	 * Forces the hitsound to be played even if the user's hitsound volume is set to 0
	**/
	public var hitsoundForce:Bool = false;

	public var hitsoundVolume(get, default):Float = 1.0;

	/**
		Effective hitsound volume: the user's preference when non-zero, else `1` only if this note forces
		its hitsound (`hitsoundForce`), else `0` (muted).
		@return the volume in the `0...1` range
	**/
	function get_hitsoundVolume():Float {
		if (ClientPrefs.data.hitsoundVolume > 0)
			return ClientPrefs.data.hitsoundVolume;
		// @:bypassAccessor avoids re-entering this getter recursively
		return hitsoundForce ? @:bypassAccessor this.hitsoundVolume : 0.0;
	}

	public var hitsound:String = 'hitsound';

	/**
		Setter for the per-note scroll-speed multiplier.
		@param value the new multiplier
		@return the assigned value
	**/
	private function set_multSpeed(value:Float):Float {
		multSpeed = value;
		return value;
	}

	/**
		Scales a sustain body's length by `ratio` (no-op on note heads and tail caps), e.g. for runtime
		scroll-speed changes.
		@param ratio the multiplier to apply to `scale.y`
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function resizeByRatio(ratio:Float) // haha funny twitter shit
	{
		if (isSustainNote && animation.curAnim != null && !animation.curAnim.name.endsWith('end')) {
			scale.y *= ratio;
			updateHitbox();
		}
	}

	/**
		Setter for the note's skin image; assigning a new value reloads the note graphic/animations.
		@param value the skin image name (no extension)
		@return the assigned value
	**/
	private function set_texture(value:String):String {
		if (texture != value)
			reloadNote(value);

		texture = value;
		return value;
	}

	/**
		Reseeds this note's RGB palette (and, for multikey, its splash tint) from the active multikey or
		arrow-colour prefs for its column.
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function defaultRGB() {
		var arr:Array<FlxColor>;
		if (Mania.current != Mania.DEFAULT)
			arr = Mania.getColors(Mania.current)[noteData]; // multikey palette
		else {
			arr = ClientPrefs.data.arrowRGB[noteData];
			if (PlayState.isPixelStage)
				arr = ClientPrefs.data.arrowRGBPixel[noteData];
		}

		// `arr` is the per-direction RGB triple ([r,g,b], length 3); guarding
		// `noteData < arr.length` rejected noteData == 3 (right arrow) and
		// caused the right arrow to render with the fallback palette. Bound
		// against the outer arrowRGB length and require the triple to be full.
		if (arr != null && noteData > -1 && arr.length >= 3) {
			rgbShader.r = arr[0];
			rgbShader.g = arr[1];
			rgbShader.b = arr[2];

			// Multikey: the splash atlas only has 4 colours, so the splash anim is
			// chosen by column % 4 -- tint it with this note's actual palette so a
			// 6th/7th-column splash isn't recoloured to the wrong cardinal hue.
			if (Mania.current != Mania.DEFAULT) {
				noteSplashData.r = arr[0];
				noteSplashData.g = arr[1];
				noteSplashData.b = arr[2];
			}
		} else {
			rgbShader.r = 0xFFFF0000;
			rgbShader.g = 0xFF00FF00;
			rgbShader.b = 0xFF0000FF;
		}
	}

	/**
		Setter for the note's type; applies the built-in type effects (Hurt Note tint/health, Alt
		Animation, GF Sing, …) and any `NoteTypesConfig` data, precaching a custom hitsound once.
		@param value the note-type name (`''` for a normal note)
		@return the assigned value
	**/
	private function set_noteType(value:String):String {
		noteSplashData.texture = PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes/noteSplashes';
		defaultRGB();

		if (noteData > -1 && noteType != value) {
			switch (value) {
				case 'Hurt Note':
					ignoreNote = mustPress;
					// reloadNote('HURTNOTE_assets');
					// this used to change the note texture to HURTNOTE_assets.png,
					// but i've changed it to something more optimized with the implementation of RGBPalette:

					// note colors
					rgbShader.r = 0xFF101010;
					rgbShader.g = 0xFFFF0000;
					rgbShader.b = 0xFF990022;

					// splash data and colors
					noteSplashData.r = 0xFFFF0000;
					noteSplashData.g = 0xFF101010;
					noteSplashData.texture = 'noteSplashes/noteSplashes-electric';

					// gameplay data
					lowPriority = true;
					missHealth = isSustainNote ? 0.25 : 0.1;
					hitCausesMiss = true;
					hitsound = 'cancelMenu';
					hitsoundChartEditor = false;
				case 'Alt Animation':
					animSuffix = '-alt';
				case 'No Animation':
					noAnimation = true;
					noMissAnimation = true;
				case 'GF Sing':
					gfNote = true;
			}
			if (value != null && value.length > 1)
				NoteTypesConfig.applyNoteTypeData(this, value);
			if (hitsound != 'hitsound' && hitsoundVolume > 0 && !precachedHitsounds.exists(hitsound)) {
				precachedHitsounds.set(hitsound, true);
				Paths.sound(hitsound); // precache new sound for being idiot-proof
			}
			noteType = value;
		}
		return value;
	}

	/**
		Builds a legacy note (head or one sustain piece): applies the user note offset, seeds the RGB
		palette, loads the skin and (for sustains) links to the previous piece, flips/sizes the tail for
		the scroll direction and folder-skin hold alpha.
		@param strumTime the note's hit time in ms (before the user note-offset is applied)
		@param noteData the lane/direction (`-1` for an event placeholder)
		@param prevNote the previous note in the sustain chain (or `null`)
		@param sustainNote `true` if this is a sustain piece rather than a head
		@param inEditor `true` when built for an editor preview (skips the user note-offset)
		@param createdFrom the owning state (defaults to `PlayState.instance`)
	**/
	public function new(strumTime:Float, noteData:Int, ?prevNote:LegacyNote, ?sustainNote:Bool = false, ?inEditor:Bool = false, ?createdFrom:Dynamic = null) {
		super();

		animation = new PsychAnimationController(this);

		antialiasing = ClientPrefs.data.antialiasing;
		if (createdFrom == null)
			createdFrom = PlayState.instance;

		if (prevNote == null)
			prevNote = this;

		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.inEditor = inEditor;
		this.moves = false;

		x += (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;
		this.strumTime = strumTime;
		if (!inEditor)
			this.strumTime += ClientPrefs.data.noteOffset;

		this.noteData = noteData;

		if (noteData > -1) {
			rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(noteData));
			if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB)
				rgbShader.enabled = false;
			texture = '';

			x += swagWidth * (noteData);
			if (!isSustainNote && noteData < colArray.length) { // Doing this 'if' check to fix the warnings on Senpai songs
				var animToPlay:String = '';
				animToPlay = colArray[noteData % colArray.length];
				animation.play(animToPlay + 'Scroll');
			}
		}

		// trace(prevNote);

		if (prevNote != null)
			prevNote.nextNote = this;

		if (isSustainNote && prevNote != null) {
			alpha = 0.6;
			multAlpha = 0.6;
			var aCfg:NoteSkinData = null;
			var aSkin:String = NoteSkinConfig.activeSkin();
			if (aSkin != null) {
				aCfg = NoteSkinConfig.forCurrentKeys(aSkin);
				if (aCfg != null && aCfg.holdAlpha != null) {
					var ha:Float = NoteSkinConfig.numForColumn(aCfg.holdAlpha, noteData, 0.6);
					alpha = ha;
					multAlpha = ha;
				}
			}
			var rgbOff:Bool = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
			hitsoundDisabled = true;
			if (ClientPrefs.data.downScroll)
				flipY = true;

			offsetX += width / 2;
			copyAngle = false;

			animation.play(colArray[noteData % colArray.length] + 'holdend');
			if (aCfg != null && rgbShader != null)
				rgbShader.enabled = !rgbOff && NoteSkinConfig.colorableFor(aCfg, 'ends');

			updateHitbox();

			offsetX -= width / 2;

			if (PlayState.isPixelStage)
				offsetX += 30;

			if (prevNote.isSustainNote) {
				prevNote.animation.play(colArray[prevNote.noteData % colArray.length] + 'hold');
				if (aCfg != null && prevNote.rgbShader != null)
					prevNote.rgbShader.enabled = !rgbOff && NoteSkinConfig.colorableFor(aCfg, 'holds');

				var delta:Float = this.strumTime - prevNote.strumTime;
				var speed:Float = (createdFrom != null && createdFrom.songSpeed != null) ? createdFrom.songSpeed : 1;
				var rate:Float = (createdFrom != null && createdFrom.playbackRate != null) ? createdFrom.playbackRate : 1;
				if (PlayState.isPixelStage && NoteSkinConfig.activeSkin() == null) {
					prevNote.scale.y *= (delta / 100) * speed;
					prevNote.scale.y *= 1.19;
					prevNote.scale.y *= (6 / height);
				} else {
					prevNote.scale.y = (delta * 0.45 * speed / rate) / prevNote.frameHeight;
				}
				prevNote.sustainBaseScaleY = prevNote.scale.y;
				prevNote.updateHitbox();
			}

			if (PlayState.isPixelStage) {
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
			earlyHitMult = 0;
		} else if (!isSustainNote) {
			centerOffsets();
			centerOrigin();
		}
		x += offsetX;
	}

	/**
		Forwards to `objects.notes.NoteDefaults.initializeGlobalRGBShader`, kept so legacy `Note.*` callers
		still resolve.
		@param noteData the 0-based column
		@return the shared per-column `RGBPalette`
	**/
	public static inline function initializeGlobalRGBShader(noteData:Int):RGBPalette
		return NoteDefaults.initializeGlobalRGBShader(noteData);

	var _lastNoteOffX:Float = 0;

	static var _lastValidChecked:String; // optimization

	public var originalHeight:Float = 6;
	public var correctionOffset:Float = 0; // dont mess with this

	/**
		(Re)loads this note's graphic + animations: uses the active folder skin when one resolves (and no
		explicit `texture` override is given), otherwise the classic sparrow/pixel/multikey build. An
		explicit `texture` disables the RGB shader (the override supplies its own colours).
		@param texture an explicit per-note texture override, or `''` for the chart/default skin
		@param postfix an optional skin postfix appended to the resolved skin name
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function reloadNote(texture:String = '', postfix:String = '') {
		if (texture == null)
			texture = '';
		if (postfix == null)
			postfix = '';

		var skin:String = texture + postfix;
		if (texture.length < 1) {
			skin = PlayState.SONG != null ? PlayState.SONG.arrowSkin : null;
			if (skin == null || skin.length < 1)
				skin = defaultNoteSkin + postfix;
		} else
			rgbShader.enabled = false;

		var animName:String = null;
		if (animation.curAnim != null) {
			animName = animation.curAnim.name;
		}

		if (texture == null || texture.length < 1) {
			var folderSkin:String = NoteSkinConfig.activeSkin();
			if (folderSkin != null && reloadFolderNote(folderSkin, animName))
				return;
		}

		// No folder skin: classic (pre-NoteSkinConfig) sparrow/pixel/multikey build.
		legacy.LegacyNoteSkin.reloadNote(this, skin, texture, animName);
	}

	/**
		Builds this note's head (or hold/end) look from a folder skin's config for its column, applying the
		per-column frames, colorability, antialiasing, scale and offsets.
		@param skinName the active folder skin
		@param animName the animation to restore afterwards (may be `null`)
		@return `true` if the folder skin supplied this note (so the classic fallback is skipped)
	**/
	function reloadFolderNote(skinName:String, animName:String):Bool {
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return false;

		if (NoteSkinConfig.editorOverride == null)
			NoteSkinConfig.pixelMode = (cfg.pixel == true) || (cfg.pixelVariant == true && PlayState.isPixelStage);

		var base:String = NoteSkinConfig.folder(skinName);
		var col:Int = noteData;
		var name:String = colArray[col % colArray.length];
		var kc:Int = Mania.clamp(Mania.current);
		var scaleBase:Float = NoteSkinConfig.numForColumn(cfg.scale, col, 0.7) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, col);
		var prevScaleY:Float = scale.y;

		var note = NoteSkinConfig.resolveColumn(cfg, cfg.notes, col);
		if (note == null)
			return false;

		var factor:Float;
		if (isSustainNote) {
			var holdKey:String = NoteSkinConfig.columnKey(cfg.holds, col);
			var endKey:String = NoteSkinConfig.columnKey(cfg.ends, col);
			if (holdKey == null || endKey == null)
				return false;
			var holdFrames:Array<String> = NoteSkinConfig.resolveFrames(base + holdKey);
			var endFrames:Array<String> = NoteSkinConfig.resolveFrames(base + endKey);
			if (holdFrames == null || endFrames == null)
				return false;
			holdFrames = NoteSkinConfig.staticFrame(holdFrames, NoteSkinConfig.animatedFor(cfg, 'holds'));
			endFrames = NoteSkinConfig.staticFrame(endFrames, NoteSkinConfig.animatedFor(cfg, 'ends'));
			factor = NoteSkinConfig.applyAnims(this, [
				{
					name: name + 'hold',
					keys: holdFrames,
					fps: laneFps,
					loop: true
				},
				{
					name: name + 'holdend',
					keys: endFrames,
					fps: laneFps,
					loop: true
				}
			]);
		} else {
			var noteFrames:Array<String> = NoteSkinConfig.resolveFrames(base + note.key);
			if (noteFrames == null)
				return false;
			noteFrames = NoteSkinConfig.staticFrame(noteFrames, NoteSkinConfig.animatedFor(cfg, 'notes'));
			factor = NoteSkinConfig.applyAnims(this, [
				{
					name: name + 'Scroll',
					keys: noteFrames,
					fps: laneFps,
					loop: false,
					angle: note.angle,
					square: true
				}
			]);
		}

		if (isSustainNote) {
			if (animName != null) {
				var rgbOff:Bool = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
				var role:String = animName.endsWith('holdend') ? 'ends' : 'holds';
				rgbShader.enabled = !rgbOff && NoteSkinConfig.colorableFor(cfg, role);
			}
		} else {
			var colorable:Bool = NoteSkinConfig.colorableFor(cfg, 'notes');
			if (!colorable)
				rgbShader.enabled = false;
			if (cfg.splash != null)
				noteSplashData.useRGBShader = colorable;
		}
		antialiasing = (cfg.pixel == true || NoteSkinConfig.pixelMode) ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, col,
			ClientPrefs.data.antialiasing);
		if (isSustainNote && cfg.holdAntialiasing != null)
			antialiasing = cfg.holdAntialiasing;
		if (cfg.splash != null)
			noteSplashData.texture = base + cfg.splash;

		if (isSustainNote) {
			scale.x = scaleBase * factor;
			// Preserve a body's computed height across mid-song skin swaps; tails reset to base.
			scale.y = (animName != null && animName.endsWith('hold')) ? prevScaleY : scaleBase * factor;
		} else {
			scale.set(scaleBase * factor, scaleBase * factor);
			centerOffsets();
			centerOrigin();
		}
		updateHitbox();

		centerOnStrum = true;
		// Sustains use holdOffsets; endOffsets (if provided) overrides for sustain pieces.
		var offField:Dynamic = isSustainNote ? (cfg.endOffsets != null ? cfg.endOffsets : cfg.holdOffsets) : cfg.noteOffsets;
		var off:Array<Float> = NoteSkinConfig.offsetFor(offField, col);
		offsetX = off[0];
		offsetY = off[1];

		if (animName != null && animation.getByName(animName) != null)
			animation.play(animName, true);
		else if (!isSustainNote)
			animation.play(name + 'Scroll', true);
		return true;
	}

	/**
		Forwards to `objects.notes.NoteDefaults.getNoteSkinPostfix`, kept so legacy `Note.*` callers still
		resolve.
		@return the skin postfix for the user's note-skin pref (empty for the default)
	**/
	public static inline function getNoteSkinPostfix():String
		return NoteDefaults.getNoteSkinPostfix();

	/**
		Orders hittable notes for input: lower-priority notes last, then by earliest strum time.
		@param a the first note to compare
		@param b the second note to compare
		@return a negative/zero/positive sort value
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public static function sortHitNotes(a:LegacyNote, b:LegacyNote):Int {
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;
		return flixel.util.FlxSort.byValues(flixel.util.FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	/** Adds the classic sparrow head (`<color>Scroll`) or hold/end animations for this note's column and
		sizes it for the active key count. **/
	function loadNoteAnims() {
		if (colArray[noteData] == null)
			return;

		if (isSustainNote) {
			attemptToAddAnimationByPrefix('purpleholdend', 'pruple end hold', 24, true); // this fixes some retarded typo from the original note .FLA
			animation.addByPrefix(colArray[noteData] + 'holdend', colArray[noteData] + ' hold end', 24, true);
			animation.addByPrefix(colArray[noteData] + 'hold', colArray[noteData] + ' hold piece', 24, true);
		} else
			animation.addByPrefix(colArray[noteData] + 'Scroll', colArray[noteData] + '0');

		// 4K resolves to 0.7 (the classic size); multikey notes shrink per the table.
		setGraphicSize(Std.int(width * Mania.noteSizes[Mania.current - 1]));
		updateHitbox();
	}

	/** Adds the pixel-sheet head or hold/end animations for this note's column (frame indices, not
		prefixes, since pixel sheets are grids). **/
	function loadPixelNoteAnims() {
		if (colArray[noteData] == null)
			return;

		if (isSustainNote) {
			animation.add(colArray[noteData] + 'holdend', [noteData + 4], 24, true);
			animation.add(colArray[noteData] + 'hold', [noteData], 24, true);
		} else
			animation.add(colArray[noteData] + 'Scroll', [noteData + 4], 24, true);
	}

	/**
		Adds an animation by frame prefix only when that prefix actually resolves to frames, avoiding
		"no frames" warnings for sheets missing an optional animation.
		@param name the animation name to register
		@param prefix the frame-name prefix to match
		@param framerate the animation framerate
		@param doLoop whether the animation loops
	**/
	function attemptToAddAnimationByPrefix(name:String, prefix:String, framerate:Float = 24, doLoop:Bool = true) {
		var animFrames = [];
		@:privateAccess
		animation.findByPrefix(animFrames, prefix); // adds valid frames to animFrames
		if (animFrames.length < 1)
			return;

		animation.addByPrefix(name, prefix, framerate, doLoop);
	}

	/**
		Per-frame judgement-window bookkeeping: updates `canBeHit`/`tooLate` for player notes, auto-marks
		opponent (and chained sustain) notes hit at their strum time, and dims notes that scrolled past.
		@param elapsed seconds since the last frame
	**/
	override function update(elapsed:Float) {
		super.update(elapsed);

		if (mustPress) {
			canBeHit = (strumTime > Conductor.songPosition - (Conductor.safeZoneOffset * lateHitMult)
				&& strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * earlyHitMult));

			if (strumTime < Conductor.songPosition - Conductor.safeZoneOffset && !wasGoodHit)
				tooLate = true;
		} else {
			canBeHit = false;

			if (!wasGoodHit && strumTime <= Conductor.songPosition) {
				if (!isSustainNote || (prevNote.wasGoodHit && !ignoreNote))
					wasGoodHit = true;
			}
		}

		if (tooLate && !inEditor) {
			if (alpha > 0.3)
				alpha = 0.3;
		}
	}

	/** Frees this note and clears the cached skin-existence check. **/
	override public function destroy() {
		super.destroy();
		_lastValidChecked = '';
	}

	/**
		Positions this note relative to its receptor for the current song time: derives the scroll
		distance, rotates onto the strum's scroll axis, recomputes a sustain body's length, and copies
		angle/alpha/x/y per the `copy*` flags.
		@param myStrum the receptor for this note's column
		@param fakeCrochet the section crochet used for sustain length (legacy parameter)
		@param songSpeed the active scroll speed
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function followStrumNote(myStrum:StrumNote, fakeCrochet:Float, songSpeed:Float = 1) {
		var strumX:Float = myStrum.x;
		var strumY:Float = myStrum.y;
		var strumAngle:Float = myStrum.angle;
		var strumAlpha:Float = myStrum.alpha;
		var strumDirection:Float = myStrum.direction;

		distance = (0.45 * (Conductor.songPosition - strumTime) * songSpeed * multSpeed);

		if (isSustainNote
			&& nextNote != null
			&& frameHeight > 0
			&& animation.curAnim != null
			&& !animation.curAnim.name.endsWith('end')) {
			var nextDist:Float = 0.45 * (Conductor.songPosition - nextNote.strumTime) * songSpeed * nextNote.multSpeed;
			var target:Float = Math.abs(nextDist - distance) / frameHeight;
			if (Math.abs((target - scale.y) * frameHeight) > 0.1) {
				scale.y = target;
				updateHitbox();
			}
		}

		if (!myStrum.downScroll)
			distance *= -1;

		var rot:Float = (isSustainNote && parent != null) ? parent.offsetAngle : offsetAngle;
		var axisDeg:Float = strumDirection + (myStrum.rotateNotes ? strumAngle : 0) + rot;
		var angleDir:Float = axisDeg * Math.PI / 180;
		var uX:Float = Math.cos(angleDir);
		var uY:Float = Math.sin(angleDir);

		if (copyAngle)
			angle = axisDeg - 90;

		if (copyAlpha)
			alpha = strumAlpha * multAlpha;

		var v:Float = 0;
		if (myStrum.downScroll && isSustainNote) {
			v = (frameHeight * scale.y) - (swagWidth / 2);
			if (PlayState.isPixelStage)
				v += PlayState.daPixelZoom * 9.5;
		}
		var along:Float = offsetY + correctionOffset + distance + height / 2 - v;
		var perp:Float = offsetX + (centerOnStrum ? swagWidth / 2 : width / 2);
		var cx:Float = strumX + uX * along + uY * perp;
		var cy:Float = strumY + uY * along - uX * perp;

		if (copyX)
			x = cx - width / 2;
		if (copyY)
			y = cy - height / 2;
	}

	/**
		Clips the consumed portion of a held sustain against its receptor so the trail shortens as it's
		held, projecting the note onto the strum's scroll axis and trimming the `clipRect` accordingly
		(handles up/down scroll).
		@param myStrum the receptor this note scrolls toward
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public function clipToStrumNote(myStrum:StrumNote) {
		if ((mustPress || !ignoreNote) && (wasGoodHit || (prevNote.wasGoodHit && !canBeHit))) {
			var rot:Float = (isSustainNote && parent != null) ? parent.offsetAngle : offsetAngle;
			var axisDeg:Float = myStrum.direction + (myStrum.rotateNotes ? myStrum.angle : 0) + rot;
			var angleDir:Float = axisDeg * Math.PI / 180;
			var uX:Float = Math.cos(angleDir);
			var uY:Float = Math.sin(angleDir);
			var perp:Float = offsetX + (centerOnStrum ? (LegacyNote.swagWidth - width) / 2 : 0);
			var rX:Float = myStrum.x + uY * perp + uX * (offsetY + LegacyNote.swagWidth / 2);
			var rY:Float = myStrum.y - uX * perp + uY * (offsetY + LegacyNote.swagWidth / 2);
			var proj:Float = (rX - x) * uX + (rY - y) * uY;

			var swagRect:FlxRect = clipRect;
			if (swagRect == null)
				swagRect = new FlxRect(0, 0, frameWidth, frameHeight);

			if (myStrum.downScroll) {
				if (proj <= height - offset.y * scale.y) {
					swagRect.width = frameWidth;
					swagRect.height = proj / scale.y;
					swagRect.y = frameHeight - swagRect.height;
				}
			} else if (proj >= offset.y * scale.y) {
				swagRect.y = proj / scale.y;
				swagRect.width = width / scale.x;
				swagRect.height = (height / scale.y) - swagRect.y;
			}
			clipRect = swagRect;
		}
	}

	/**
		Setter for `clipRect` that re-resolves the current frame so the clip applies immediately (the base
		`FlxSprite` setter doesn't refresh the frame).
		@param rect the clip rectangle (or `null` to clear)
		@return the assigned rectangle
	**/
	@:noCompletion
	override function set_clipRect(rect:FlxRect):FlxRect {
		// @:bypassAccessor avoids recursing into this setter through the
		// (default, set) property declared on FlxSprite. Without it, hxcpp
		// re-enters set_clipRect for every assignment to clipRect.
		@:bypassAccessor clipRect = rect;

		if (frames != null && animation.frameIndex >= 0 && animation.frameIndex < frames.frames.length)
			frame = frames.frames[animation.frameIndex];

		return rect;
	}
}
