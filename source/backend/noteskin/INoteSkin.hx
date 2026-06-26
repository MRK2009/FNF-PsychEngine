package backend.noteskin;

import flixel.FlxSprite;
import shaders.RGBPalette.RGBShaderReference;

/**
	A note-skin provider: builds the *look* of notes, sustains and receptors onto bare `FlxSprite`s.

	The gameplay/drawable layer never references textures, atlases or `NoteSkinConfig` -- it only holds
	an `INoteSkin` (via `NoteSkinService.current()`) and calls these. Two implementations exist:
	`FolderNoteSkin` (modern `.tcfg`/`.json` skins) and `ClassicNoteSkin` (legacy atlas/pixel/multikey).
**/
interface INoteSkin {
	/**
		Builds a tap/note-head onto `spr`.
		@param spr the head sprite to configure
		@param rgb the head's palette shader reference
		@param column the note's 0-based lane
		@param keyCount the active column count
		@param animName an anim to restore after the rebuild, or `null`
		@return the non-sprite look details (offsets, colorability, splash override)
	**/
	function applyNote(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, animName:String):NoteVisual;

	/**
		Builds a sustain onto a body sprite and its tail sprite. The body plays the looping hold anim and
		the tail the end cap; the vertical length (`scale.y`) is the field's job, the skin only sets the
		frames, `scale.x` and antialiasing.
		@param body the hold-body sprite
		@param bodyRGB the body's palette shader reference
		@param tail the end-cap sprite
		@param tailRGB the tail's palette shader reference
		@param column the note's 0-based lane
		@param keyCount the active column count
		@return the non-sprite look details (offsets, colorability)
	**/
	function applySustain(body:FlxSprite, bodyRGB:RGBShaderReference, tail:FlxSprite, tailRGB:RGBShaderReference, column:Int,
		keyCount:Int):NoteVisual;

	/**
		Builds a receptor's static/pressed/confirm look onto `spr`.
		@param spr the receptor sprite to configure
		@param rgb the receptor's palette shader reference
		@param column the receptor's 0-based lane
		@param keyCount the active column count
		@param lastAnim an anim to restore after the rebuild, or `null`
		@return the non-sprite look details (per-anim colorability, lane centering, offsets)
	**/
	function applyReceptor(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, lastAnim:String):NoteVisual;

	/**
		@return `true` when this skin renders in pixel mode for the current stage
	**/
	function isPixel():Bool;
}
