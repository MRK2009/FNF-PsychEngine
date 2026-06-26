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
		@return the shared `ClassicNoteSkin` provider (created on first use)
	**/
	public static function classic():ClassicNoteSkin {
		if (classicSkin == null)
			classicSkin = new ClassicNoteSkin();
		return classicSkin;
	}

	/**
		@return the provider for the active skin: a `FolderNoteSkin` when a folder skin is active,
		otherwise the `ClassicNoteSkin`
	**/
	public static function current():INoteSkin {
		var active:String = NoteSkinConfig.activeSkin();
		if (active != null) {
			if (folderSkin == null || folderName != active) {
				folderName = active;
				folderSkin = new FolderNoteSkin(active, classic());
			}
			return folderSkin;
		}
		return classic();
	}

	/** Clears the cached providers so the next `current` call rebuilds for the new active skin. **/
	public static function reset():Void {
		classicSkin = null;
		folderSkin = null;
		folderName = null;
	}
}
