package backend.noteskin;

/**
	Result of an `INoteSkin` apply call. The provider sets the sprite's frames/anims/scale/antialiasing
	directly on the passed `FlxSprite`; everything that is *not* part of the bare sprite (lane offsets,
	per-role colorability, splash overrides, etc.) comes back here so the drawable can apply it without
	the skin code knowing the drawable's concrete type. This is what keeps notes decoupled from skins.
**/
final class NoteVisual {
	/** `false` if the skin couldn't build this element (the caller should fall back). **/
	public var ok:Bool = false;

	/** Pixel-mode look: antialiasing forced off, pixel-art proportions. **/
	public var pixel:Bool = false;

	/** In-lane x offset to add when positioning, in px. **/
	public var offsetX:Float = 0;

	/** In-lane y offset to add when positioning, in px. **/
	public var offsetY:Float = 0;

	/** Center the element on the fixed lane width rather than on its own frame width. **/
	public var centerOnStrum:Bool = false;

	/** Final scale multiplier the provider applied (for scripts / sustain length math). **/
	public var scaleFactor:Float = 1;

	/** Whether this note role's palette shader should stay enabled (note head / sustain). **/
	public var colorable:Bool = true;

	/** Receptor recolors per played anim (static/pressed/confirm) instead of via a single flag. **/
	public var colorPerAnim:Bool = false;

	public var staticColorable:Bool = false;
	public var pressedColorable:Bool = true;
	public var confirmColorable:Bool = true;

	/** Receptor centers each anim frame on the fixed lane (folder skins with varying frame sizes). **/
	public var laneCenter:Bool = false;

	public function new() {}
}
