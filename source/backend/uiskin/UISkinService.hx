package backend.uiskin;

/**
	Entry point the popup layer uses to get its look.

	A UI skin is a folder; there is no second kind. The chain is the selected skin, then the engine's
	own `Default` skin, then the base `stageUI` assets -- each tier the fallback of the one above, so
	fallback is per ELEMENT: a skin shipping only a `sick.png` still gets its combo word and countdown
	drawn rather than rendering nothing.

	Cached; call `reset` wherever the active skin can change -- `PlayState.create` already resets
	`UISkinConfig` in the same place.
**/
class UISkinService {
	static var legacySkin:LegacyUISkin = null;
	static var current_:IUISkin = null;
	static var currentName:String = null;
	static var currentResolved:Bool = false;

	/** The shared legacy provider, which never varies by skin name. **/
	public static function legacy():LegacyUISkin {
		if (legacySkin == null)
			legacySkin = new LegacyUISkin();
		return legacySkin;
	}

	/** @return the provider for the active skin, rebuilt when the active skin changes. **/
	public static function current():IUISkin {
		var active:String = UISkinConfig.activeSkin();
		if (currentResolved && currentName == active && current_ != null)
			return current_;

		currentName = active;
		currentResolved = true;

		if (active == null) {
			current_ = legacy();
			return current_;
		}

		current_ = new SkinnedUI(active, baseline(active));

		return current_;
	}

	/**
		What an incomplete skin falls back to: the engine's own Default skin, then the base `stageUI`
		assets.

		The Default skin holds the engine's art -- including its pixel set under `Default/pixel/` -- so
		it is what a skin missing an element should borrow from. Ending the chain at `stageUI` alone
		would mean a partial skin on a pixel stage had nothing to fall back to once that art moved into
		the skin folder.
	**/
	static function baseline(active:String):IUISkin {
		if (active == UISkinConfig.DEFAULT)
			return legacy();
		return new SkinnedUI(UISkinConfig.DEFAULT, legacy());
	}

	/** Clears the cached provider so the next `current` call rebuilds for the new active skin. **/
	public static function reset():Void {
		current_ = null;
		currentName = null;
		currentResolved = false;
		legacySkin = null;
	}
}
