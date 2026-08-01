package backend.skins;

using StringTools;

/**
	The one place pixel behaviour is decided, for BOTH skin systems.

	Note skins and UI skins had grown a pixel implementation each: their own mode booleans, their own
	"which skin is the pixel variant" scan, their own `pixel/` path resolution, and -- on the note
	side -- an ambient render flag written from six files with hand-written save/restore around it.
	Same idea twice, already drifting: note skins had grown a `pixelMode` string that UI skins never
	got. This owns all of it; `NoteSkinConfig` and `UISkinConfig` keep thin forwarders so existing
	call sites (and mod scripts reaching them) are unaffected.

	Three separate things live here, and they are easy to confuse:

	- the skin's DECLARED mode (`modeOf`) -- what the author wrote in the tcfg,
	- whether it renders pixel RIGHT NOW (`activeFor`) -- mode plus the stage,
	- the render switch (`render`) -- what the builders actually consult, which an editor may force
	  for previewing and which the baker deliberately turns off.

	Pixel art itself lives in `<skin>/pixel/` for both systems; `candidates` is the resolution order.
**/
class Pixel {
	/** `pixelMode`: never pixel. **/
	public static inline var NONE:String = 'none';

	/** `pixelMode`: the skin IS pixel art and always renders as such. **/
	public static inline var ALWAYS:String = 'always';

	/** `pixelMode`: HD by default, with pixel art that takes over on a pixel stage. **/
	public static inline var VARIANT:String = 'variant';

	/**
		Whether the skin currently being built renders PIXEL art -- it makes frame resolution prefer a
		`pixel/` variant, drops antialiasing on rotated frames and switches scaling to `pixelScale`.

		A RENDER flag, not a declared mode: it is normally set from the active skin's mode, but an
		editor forces it to preview, and `PixelArtBaker` forces it off so a bake reads the base art
		rather than a previous bake. Those two save and restore it around a block; if you add a
		third caller, make sure every exit from that block restores it.
	**/
	public static var render:Bool = false;

	/**
		A skin's declared pixel mode, normalised.

		Takes the fields rather than the config object so both skin systems can share it without
		reflection or `Dynamic`; the older `pixel` / `pixelVariant` booleans are still honoured so
		skins written before `pixelMode` keep working unchanged.

		@param pixelMode The explicit mode, or null.
		@param pixel The older "always pixel" boolean.
		@param pixelVariant The older "pixel on a pixel stage" boolean.
		@return One of `NONE` / `ALWAYS` / `VARIANT`.
	**/
	public static function modeOf(pixelMode:String, pixel:Null<Bool>, pixelVariant:Null<Bool>):String {
		if (pixelMode != null) {
			var m:String = pixelMode.toLowerCase();
			if (m == ALWAYS || m == VARIANT || m == NONE)
				return m;
		}

		if (pixel == true)
			return ALWAYS;
		if (pixelVariant == true)
			return VARIANT;

		return NONE;
	}

	/**
		Whether a mode renders pixel art right now: `always` unconditionally, `variant` only on a pixel
		stage. The single decision every skin builder should use.

		@param mode A mode from `modeOf`.
		@return Whether to render pixel art.
	**/
	public static function activeFor(mode:String):Bool {
		if (mode == ALWAYS)
			return true;
		if (mode == VARIANT)
			return states.PlayState.isPixelStage;

		return false;
	}

	/** Whether a mode means the skin ships pixel art at all. **/
	public static inline function ships(mode:String):Bool
		return mode != NONE;

	/**
		Every layout a pixel variant of `key` may use, in resolution order:

		1. `<dir>/pixel/<name>` -- a `pixel/` subfolder with plain names
		2. `<dir>/pixel/<name>-pixel` -- a `pixel/` subfolder with suffixed names (per-frame for sequences)
		3. `<name>-pixel` -- suffixed alongside the base art

		@param key The base art key, including its folder.
		@return The candidate keys, in the order they are tried.
	**/
	public static function candidates(key:String):Array<String> {
		if (key == null || key.length < 1)
			return [];

		var out:Array<String> = [];
		var slash:Int = key.lastIndexOf('/');
		if (slash >= 0) {
			var sub:String = key.substr(0, slash) + '/pixel' + key.substr(slash);
			out.push(sub);
			out.push(sub + '-pixel');
		}
		out.push(key + '-pixel');

		return out;
	}

	/**
		The first skin declaring `variant`, preferring `defaultName`. Drives the pixel-stage auto-swap.

		Uncached: both skin systems cache the answer themselves because they invalidate on different
		events. This owns only the scan, which is what had been written twice.

		@param defaultName The skin to prefer.
		@param names Every available skin name.
		@param modeFor A skin name to its declared mode.
		@return The variant skin's name, or null.
	**/
	public static function variantSkin(defaultName:String, names:Array<String>, modeFor:String->String):Null<String> {
		if (defaultName != null && modeFor(defaultName) == VARIANT)
			return defaultName;

		if (names != null)
			for (name in names)
				if (modeFor(name) == VARIANT)
					return name;

		return null;
	}

	/**
		The `pixelUI/` prefix, for LEGACY packs only.

		Before per-skin `pixel/` folders, pixel art was found by prefixing `pixelUI/` to the asset name
		on a pixel stage. The skin systems replaced that, but the prefix was still inlined in five
		native files, so every pixel stage consulted the old folder. It now applies only when the pack
		opts in via `compatibilityMode` / `legacyMode` in pack.json, and resolves from the old location
		exactly as before for packs that do.

		Gated on the LOOKUP rather than on the legacy classes deliberately: `legacy/` code is reachable
		outside compatibility mode (`objects.StrumNote` is a typedef to `legacy.LegacyStrumNote`, which
		the note-splash editor builds), so gating the class would change unrelated editor paths.

		@return `'pixelUI/'` for a legacy pack on a pixel stage, otherwise an empty string.
	**/
	public static function legacyPrefix():String {
		return legacySheets() ? 'pixelUI/' : '';
	}

	/**
		Whether the legacy `pixelUI/` sheets are in play at all.

		Callers that only need the prefix use `legacyPrefix`. This exists for the ones that also take a
		different code path for them -- the classic renderer slices a pixel sheet into a grid and
		applies `daPixelZoom`, which would be wrong applied to the ordinary sparrow sheet. Those sites
		branch on this, so a non-legacy pack on a pixel stage takes the normal classic route rather
		than pixel-framing art that is not pixel art.

		@return Whether a legacy pack is on a pixel stage.
	**/
	public static function legacySheets():Bool {
		#if MODS_ALLOWED
		return states.PlayState.isPixelStage && backend.Mods.noteCompatibilityMode();
		#else
		return false;
		#end
	}
}
