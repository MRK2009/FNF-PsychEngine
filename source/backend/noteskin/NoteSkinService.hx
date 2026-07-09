package backend.noteskin;

import backend.NoteSkinConfig;

/**
	Entry point the drawable layer uses to get its look. Picks the active provider -- a `FolderNoteSkin`
	when a folder skin (`.tcfg`/`.json`) is active, otherwise the `ClassicNoteSkin`. The returned
	`INoteSkin` is the only skin type notes/sustains/receptors ever touch, keeping them decoupled.

	Cached per skin; call `reset` when the active skin can change (e.g. `PlayState.create`), mirroring
	`NoteSkinConfig.reset`.
**/
class NoteSkinService {
	static var classicSkin:ClassicNoteSkin = null;
	static var folderSkin:FolderNoteSkin = null;
	static var folderName:String = null;

	/**
		The shared `ClassicNoteSkin` provider (created on first use), bound to `name` -- the selected
		classic atlas skin, or null for the built-in NOTE_assets/arrowSkin default (also the mode used
		when it serves as a `FolderNoteSkin` fallback).
		@param name the classic skin to render, or null for the default
	**/
	public static function classic(?name:String):ClassicNoteSkin {
		if (classicSkin == null)
			classicSkin = new ClassicNoteSkin();
		classicSkin.activeName = name;
		return classicSkin;
	}

	/**
		@return the provider for the active skin. Identity is by ASSET LAYOUT: an individual-image folder
		skin (`skin.tcfg`/`json`, no atlas) -> `FolderNoteSkin`; anything backed by a sparrow atlas (even
		one that also ships a config) -> the `ClassicNoteSkin` bound to that skin.
	**/
	public static function current():INoteSkin {
		var active:String = NoteSkinConfig.activeSkin();
		if (active != null && NoteSkinConfig.isFolderSkin(active) && !NoteSkinConfig.isClassicSkin(active)) {
			if (folderSkin == null || folderName != active) {
				folderName = active;
				folderSkin = new FolderNoteSkin(active, classic());
			}
			return folderSkin;
		}
		return classic(NoteSkinConfig.activeClassicSkin());
	}

	/** Clears the cached providers so the next `current` call rebuilds for the new active skin. **/
	public static function reset():Void {
		classicSkin = null;
		folderSkin = null;
		folderName = null;
	}
}
