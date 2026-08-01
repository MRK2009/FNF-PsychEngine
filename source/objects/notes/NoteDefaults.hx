package objects.notes;

import shaders.RGBPalette;

using StringTools;

/**
	Splash-spawn descriptor (texture + per-channel RGB + alpha). Lives here, not on the legacy note,
	so the v2 drawables can describe a splash without depending on `legacy.LegacyNote`.
**/
typedef NoteSplashData = {
	disabled:Bool,
	texture:String,
	useGlobalShader:Bool, // breaks r/g/b but makes it copy default colors for your custom note
	useRGBShader:Bool,
	antialiasing:Bool,
	r:FlxColor,
	g:FlxColor,
	b:FlxColor,
	a:Float
}

/** A chart event scheduled at `strumTime`. **/
typedef EventNote = {
	strumTime:Float,
	event:String,
	value1:String,
	value2:String
}

/**
	Neutral home for the note constants/helpers shared by the v2 runtime, the skin service and the
	splash. These used to live on `legacy.LegacyNote`; the v2 drawables read them through the
	`objects.Note` alias, which dragged a transitive `legacy` dependency into the hot path. They now
	live here, and `LegacyNote` (hence `objects.Note`) forwards to them so existing `Note.*` script
	and editor calls keep working unchanged.

	Per-keycount globals (`swagWidth` / `colArray`) are NOT duplicated here -- they are owned by
	`Mania`; the v2 drawables read `Mania.*` directly.
**/
class NoteDefaults {
	/**
		Built-in note-type names; also the index map old (0.1-0.3 / Week 7) charts use for integer note
		types. Index 3 is `'Hurt Note'` (restored: the original `Note`->`LegacyNote` rename had mangled it
		to `'Hurt LegacyNote'`, which broke v2's `'Hurt Note'` switch for integer-typed hurt notes;
		`LegacyNote.set_noteType` was fixed in lockstep).
	**/
	public static final defaultNoteTypes:Array<String> = [
		'', // Always leave this one empty pls
		'Alt Animation',
		'Hey!',
		'Hurt Note',
		'GF Sing',
		'No Animation'
	];

	/** The pre-folder-skin sheet path. Nothing ships here any more, but a mod still may. **/
	public static inline var CLASSIC_SHEET:String = 'noteSkins/NOTE_assets';

	/** Where the base game's copy of that sheet moved to when the folder skins took over `noteSkins/`. **/
	public static inline var CLASSIC_SHEET_BASE:String = 'noteSkins/Legacy/NOTE_assets';

	/**
		The classic (pre-folder-skin) note sheet, resolved rather than fixed.

		`noteSkins/` became the folder-skin root and the flat `noteSkins/NOTE_assets` was deleted from
		the base game, so a hardcoded path resolved to nothing and every classic fallback rendered
		Flixel's placeholder graphic. The old path still wins when something provides it -- a mod
		shipping its own `noteSkins/NOTE_assets` is the case `NoteSkinConfig.modProvidesClassicDefault`
		exists for -- and only otherwise does this point at the relocated base sheet.
	**/
	public static var defaultNoteSkin(get, never):String;

	static function get_defaultNoteSkin():String {
		// Probed against the root the caller will actually load from, which for a legacy pack on a
		// pixel stage is `pixelUI/`. Testing both roots together would answer "old path" whenever the
		// pixel sheet exists and leave every non-pixel strum on a missing image.
		var root:String = 'images/' + backend.skins.Pixel.legacyPrefix();
		return Paths.fileExists('$root$CLASSIC_SHEET.png', IMAGE) ? CLASSIC_SHEET : CLASSIC_SHEET_BASE;
	}

	public static var SUSTAIN_SIZE:Int = 44;

	/** Per-column RGB palettes for the ACTIVE keycount, lazily built by `initializeGlobalRGBShader`. **/
	public static var globalRgbShaders:Array<RGBPalette> = [];

	/**
		Palettes for keycounts other than the active one, keyed by count.

		Strumlines carry their own `keyCount`, so a song can hold a 4K line and a 6K line at once. The
		palette a lane wants depends on that count, not just on the column index: keying by column alone
		gave a 6K line the 4K palette for lanes 0-3 and no palette at all for lanes 4-5, since the
		player's arrow-colour prefs only go four wide. Only the active count lives in
		`globalRgbShaders`, which the colour menu edits in place; the rest live here.
	**/
	static var rgbShadersByCount:Map<Int, Array<RGBPalette>> = new Map();

	/** Drops every cached palette, active and per-keycount alike. **/
	public static function resetPalettes():Void {
		globalRgbShaders = [];
		rgbShadersByCount.clear();
	}

	/**
		Lazily builds (and caches) the shared RGB palette for a lane, seeded from the skin's palette, the
		multikey palette for `keyCount`, or the user's arrow-colour prefs.
		@param noteData the 0-based column
		@param keyCount the column count of the strumline this lane belongs to; defaults to the active one
		@return the shared `RGBPalette` for that lane
	**/
	public static function initializeGlobalRGBShader(noteData:Int, ?keyCount:Int):RGBPalette {
		var count:Int = (keyCount != null) ? Mania.clamp(keyCount) : Mania.current;
		var store:Array<RGBPalette> = globalRgbShaders;
		if (count != Mania.current) {
			store = rgbShadersByCount.get(count);
			if (store == null) {
				store = [];
				rgbShadersByCount.set(count, store);
			}
		}

		if (store[noteData] == null) {
			var newRGB:RGBPalette = new RGBPalette();
			var arr:Array<FlxColor> = laneColors(noteData, count);
			if (arr != null && arr.length >= 3) {
				newRGB.r = arr[0];
				newRGB.g = arr[1];
				newRGB.b = arr[2];
			} else {
				newRGB.r = 0xFFFF0000;
				newRGB.g = 0xFF00FF00;
				newRGB.b = 0xFF0000FF;
			}

			store[noteData] = newRGB;
		}
		return store[noteData];
	}

	/**
		The `[main, border, shadow]` triple a lane draws with: the skin's shipped palette first (unless
		the player overrides skin colours), then the keycount palette, then the pixel/normal arrow-colour
		prefs. The prefs are only four lanes wide, so anything past 4K takes the keycount palette.
		@param column the 0-based lane
		@param count the strumline's column count
	**/
	static function laneColors(column:Int, count:Int):Array<FlxColor> {
		var arr:Array<FlxColor> = backend.NoteSkinConfig.skinNoteColors(column);
		if (arr != null)
			return arr;

		if (count != Mania.DEFAULT) {
			var palette:Array<Array<FlxColor>> = Mania.getColors(count);
			return (palette != null && column >= 0 && column < palette.length) ? palette[column] : null;
		}

		var prefs:Array<Array<FlxColor>> = (!PlayState.isPixelStage) ? ClientPrefs.data.arrowRGB : ClientPrefs.data.arrowRGBPixel;
		return (prefs != null && column >= 0 && column < prefs.length) ? prefs[column] : null;
	}

	/**
		The resolved `[main, border, shadow]` RGB triple for a lane, matching exactly what receptors and
		notes render: the active skin's shipped palette first (unless the player is overriding skin colours),
		then the multikey/player palette, then the pixel/normal arrow-colour prefs. Unlike
		`initializeGlobalRGBShader` this touches no shared cache, so menus and overlays (e.g. the mobile
		Hitbox) can read a lane's colour with no gameplay side effects.
		@param column the 0-based lane
		@param keyCount the strumline's column count; defaults to the active one
	**/
	public static function resolveLaneColors(column:Int, ?keyCount:Int):Array<FlxColor>
		return laneColors(column, (keyCount != null) ? Mania.clamp(keyCount) : Mania.current);

	/** The primary (Main channel) colour of a lane, i.e. the arrow's dominant tint. **/
	public static function resolveLaneColor(column:Int, ?keyCount:Int):FlxColor {
		var arr:Array<FlxColor> = resolveLaneColors(column, keyCount);
		return (arr != null && arr.length > 0) ? arr[0] : 0xFFFFFFFF;
	}

	/** The skin postfix derived from the user's note-skin pref (empty for the default skin). **/
	public static function getNoteSkinPostfix():String {
		var skin:String = '';
		if (ClientPrefs.data.noteSkin != ClientPrefs.defaultData.noteSkin)
			skin = '-' + ClientPrefs.data.noteSkin.trim().toLowerCase().replace(' ', '_');
		return skin;
	}
}
