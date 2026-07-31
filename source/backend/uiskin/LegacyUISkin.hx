package backend.uiskin;

import flixel.FlxSprite;
import states.PlayState;

/**
	The base `stageUI` assets: what the engine drew before UI skins existed, and what it still falls
	back to when no skin resolves.

	A stage sets `stageUI` (`"normal"`, `"pixel"`, `"week6"`, ...), which becomes the `uiPrefix` /
	`uiPostfix` pair on `PlayState`; this reads `images/<prefix>UI/<element><postfix>`. That is the
	whole tier -- there is no config and nothing to discover, which is why it is chosen by elimination
	rather than by name.

	Kept as a real provider rather than an `else` branch inside the popup code so the three tiers are
	selected in one place, and so a skin that is missing one element can fall through to it cleanly.
**/
class LegacyUISkin implements IUISkin {
	public function new() {}

	public function applyRating(spr:FlxSprite, name:String):UIVisual
		return load(spr, name);

	public function applyCombo(spr:FlxSprite):UIVisual
		return load(spr, 'combo');

	public function applyDigit(spr:FlxSprite, digit:Int):UIVisual
		return load(spr, 'num' + digit);

	public function applyCountdown(spr:FlxSprite, step:String):UIVisual
		return load(spr, step);

	public function isPixel():Bool
		return PlayState.isPixelStage;

	/** `images/<uiPrefix>UI/<key><uiPostfix>`, the historic path. **/
	function load(spr:FlxSprite, key:String):UIVisual {
		var out:UIVisual = new UIVisual();
		var folder:String = (PlayState.stageUI != "normal") ? PlayState.uiPrefix + "UI/" : "";
		var graphic = Paths.image(folder + key + PlayState.uiPostfix);
		if (graphic == null)
			return out;

		spr.loadGraphic(graphic);
		out.ok = true;
		out.pixel = PlayState.isPixelStage;
		// The base assets follow the stage: pixel stages want it off, everything else the player's pref.
		out.antialias = (PlayState.stageUI != "normal") ? !PlayState.isPixelStage : ClientPrefs.data.antialiasing;
		return out;
	}
}
