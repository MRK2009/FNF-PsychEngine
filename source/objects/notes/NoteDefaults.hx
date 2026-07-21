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

	public static var defaultNoteSkin(default, never):String = 'noteSkins/NOTE_assets';

	public static var SUSTAIN_SIZE:Int = 44;

	/** Per-column global RGB palettes, lazily built by `initializeGlobalRGBShader`. **/
	public static var globalRgbShaders:Array<RGBPalette> = [];

	/**
		Lazily builds (and caches) the shared per-column RGB palette for `noteData`, seeded from the
		multikey palette or the user's arrow-color prefs.
		@param noteData the 0-based column
		@return the shared `RGBPalette` for that column
	**/
	public static function initializeGlobalRGBShader(noteData:Int):RGBPalette {
		if (globalRgbShaders[noteData] == null) {
			var newRGB:RGBPalette = new RGBPalette();
			// A skin may ship its own palette; the player's colours are the fallback (and win outright
			// when `overrideSkinColors` is on).
			var arr:Array<FlxColor> = backend.NoteSkinConfig.skinNoteColors(noteData);
			if (arr != null) {} else if (Mania.current != Mania.DEFAULT)
				arr = Mania.getColors(Mania.current)[noteData]; // multikey palette
			else
				arr = (!PlayState.isPixelStage) ? ClientPrefs.data.arrowRGB[noteData] : ClientPrefs.data.arrowRGBPixel[noteData];

			if (arr != null && arr.length >= 3) {
				newRGB.r = arr[0];
				newRGB.g = arr[1];
				newRGB.b = arr[2];
			} else {
				newRGB.r = 0xFFFF0000;
				newRGB.g = 0xFF00FF00;
				newRGB.b = 0xFF0000FF;
			}

			globalRgbShaders[noteData] = newRGB;
		}
		return globalRgbShaders[noteData];
	}

	/** The skin postfix derived from the user's note-skin pref (empty for the default skin). **/
	public static function getNoteSkinPostfix():String {
		var skin:String = '';
		if (ClientPrefs.data.noteSkin != ClientPrefs.defaultData.noteSkin)
			skin = '-' + ClientPrefs.data.noteSkin.trim().toLowerCase().replace(' ', '_');
		return skin;
	}
}
