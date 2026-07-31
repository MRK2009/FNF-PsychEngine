package backend.uiskin;

/**
	Result of an `IUISkin` apply call. The provider loads the graphic onto the passed `FlxSprite`
	directly; everything that is not part of the bare sprite comes back here so the popup code can
	apply it without knowing which kind of skin produced it.

	Mirrors `backend.noteskin.NoteVisual`, minus everything that only means something for a note.
**/
final class UIVisual {
	/** `false` if the skin had no art for this element -- the caller falls back to the next tier. **/
	public var ok:Bool = false;

	/**
		Scale multiplier the graphic needs, from `@2x` art. The popup multiplies its own sizing by this,
		so a hi-res image ends up the same on-screen size as a 1x one.
	**/
	public var factor:Float = 1;

	/** Antialiasing this element wants, or null to leave the caller's choice alone. **/
	public var antialias:Null<Bool> = null;

	/** Pixel-mode look: the skin resolved pixel art, so pixel sizing applies. **/
	public var pixel:Bool = false;

	public function new() {}
}
