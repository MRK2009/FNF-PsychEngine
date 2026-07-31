package backend.uiskin;

import flixel.FlxSprite;

/**
	A UI-skin provider: builds the *look* of the judgement popups and the countdown onto bare
	`FlxSprite`s.

	The gameplay layer never names a UI texture or decides which asset tier to read from -- it holds
	an `IUISkin` (via `UISkinService.current()`) and calls these. Two implementations exist:
	`SkinnedUI` (a skin folder, with or without a config) and `LegacyUISkin` (the base `stageUI`
	assets, which is what the engine drew before skins existed and what a skin falls back to).

	Every call configures `spr` in place and returns the non-sprite details. `ok = false` means this
	skin had no art for the element, and the caller should try the next tier.
**/
interface IUISkin {
	/**
		Builds a judgement rating popup ("sick", "good", or a custom tier's image key).
		@param spr the popup sprite to configure
		@param name the rating/tier image key
	**/
	function applyRating(spr:FlxSprite, name:String):UIVisual;

	/**
		Builds the "combo" word popup.
		@param spr the popup sprite to configure
	**/
	function applyCombo(spr:FlxSprite):UIVisual;

	/**
		Builds one combo digit.
		@param spr the digit sprite to configure
		@param digit the digit 0-9
	**/
	function applyDigit(spr:FlxSprite, digit:Int):UIVisual;

	/**
		Builds one countdown step.
		@param spr the countdown sprite to configure
		@param step `ready`, `set` or `go`
	**/
	function applyCountdown(spr:FlxSprite, step:String):UIVisual;

	/**
		@return `true` when this skin renders in pixel mode for the current stage
	**/
	function isPixel():Bool;
}
