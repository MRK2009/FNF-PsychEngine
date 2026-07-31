package backend.uiskin;

import flixel.FlxSprite;
import backend.NoteSkinConfig.SkinImage;

/**
	A UI skin: a folder under `uiSkins/` holding element images, with an optional `skin.tcfg`.

	There is only one kind of UI skin. A skin without a config takes every setting's default, which is
	why dropping a folder of art in is enough -- a config adds key remapping, motion, placement and
	custom tiers, it does not change what the skin IS.

	Resolution lives in `UISkinConfig` (key remapping, `@2x`, the `pixel/` subfolder), so this is a
	thin adapter over `imageFor` rather than a second copy of that logic.

	An element the skin does not ship resolves to `null`, which comes back as `ok = false` so the
	service's fallback draws it instead. That is what makes a partial skin work.
**/
class SkinnedUI implements IUISkin {
	/** The skin this reads from, named explicitly so it can serve as another skin's fallback. **/
	public final skinName:String;

	/** The tier to fall back to per-element, so a partial skin still renders a full popup. **/
	final fallback:IUISkin;

	public function new(skinName:String, ?fallback:IUISkin) {
		this.skinName = skinName;
		this.fallback = fallback;
	}

	public function applyRating(spr:FlxSprite, name:String):UIVisual
		return load(spr, name, function() return fallback != null ? fallback.applyRating(spr, name) : null);

	public function applyCombo(spr:FlxSprite):UIVisual
		return load(spr, 'combo', function() return fallback != null ? fallback.applyCombo(spr) : null);

	public function applyDigit(spr:FlxSprite, digit:Int):UIVisual
		return load(spr, 'num' + digit, function() return fallback != null ? fallback.applyDigit(spr, digit) : null);

	public function applyCountdown(spr:FlxSprite, step:String):UIVisual
		return load(spr, step, function() return fallback != null ? fallback.applyCountdown(spr, step) : null);

	public function isPixel():Bool
		return PlayState.isPixelStage;

	function load(spr:FlxSprite, key:String, onMissing:Void->UIVisual):UIVisual {
		var img:SkinImage = UISkinConfig.imageFor(skinName, key);
		if (img == null) {
			var alt:UIVisual = onMissing();
			return (alt != null) ? alt : new UIVisual();
		}

		spr.loadGraphic(img.graphic);
		var out:UIVisual = new UIVisual();
		out.ok = true;
		out.factor = img.factor;
		out.pixel = PlayState.isPixelStage;
		return out;
	}
}
