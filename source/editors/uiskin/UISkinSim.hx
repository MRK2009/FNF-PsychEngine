package editors.uiskin;

import backend.UISkinConfig;
import backend.UISkinConfig.UIJudgement;
import backend.UISkinConfig.UIPlacement;
import backend.uiskin.IUISkin;
import backend.uiskin.UISkinService;
import backend.uiskin.UIVisual;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import smidr.flixel.FlxSmidr;
import smidr.input.UIFocus;

using StringTools;

/**
	The live preview: the judgement popup, the countdown, and the draggable placement handles.

	Every graphic is resolved through `backend.uiskin.UISkinService`, not `UISkinConfig.image`, for
	the same reason `editors.noteskin.NoteSkinSim` drives a real `NoteField` -- the provider is what
	gameplay draws through, so a classic or legacy skin previews exactly as it will play and the
	per-element fallback between kinds is visible while authoring. A preview that resolved images its
	own way would drift from the game the moment either side changed.

	Motion, placement and the custom rating tiers still come from `UISkinConfig`, which reads the
	in-edit config live via `editorOverride` + `setConfig`, so there is no Apply step.
**/
class UISkinSim {
	/** Everything the preview draws, for the owner to add to the state. **/
	public final group:FlxSpriteGroup = new FlxSpriteGroup();

	/** The drag handles, kept separate so they layer above the popups. **/
	public final handleGroup:FlxSpriteGroup = new FlxSpriteGroup();

	/** Combo number drawn, so every digit's art can be checked. **/
	public var comboCount:Int = 123;

	/** Which rating the popup shows. **/
	public var ratingName:String = 'sick';

	/** The "combo" word is hidden in gameplay by default; this shows it. **/
	public var showComboWord:Bool = false;

	/** Holds the popups on screen instead of letting them fade. **/
	public var staticHold:Bool = false;

	/** Shows the draggable placement handles. **/
	public var showHandles(default, set):Bool = false;

	function set_showHandles(v:Bool):Bool {
		showHandles = v;
		positionHandles();
		return v;
	}

	/** Fired after a drag writes a new placement, so the owner can refresh its fields. **/
	public var onPlacementChanged:String->Void = null;

	final pool:Array<FlxSprite> = [];
	final handleElems:Array<String> = ['rating', 'combo', 'numbers'];
	final handleSpr:Array<FlxSprite> = [];
	final handleLabels:Array<FlxText> = [];

	var dragIndex:Int = -1;
	var grabX:Float = 0;
	var grabY:Float = 0;

	public function new() {
		buildHandles();
	}

	inline function font()
		return Paths.font('vcr.ttf');

	// ---- popups ----

	inline function acquire():FlxSprite {
		var s:FlxSprite = (pool.length > 0) ? pool.pop() : new FlxSprite();
		s.revive();
		s.alpha = 1;
		s.scale.set(1, 1);
		s.angle = 0;
		s.velocity.set(0, 0);
		s.acceleration.set(0, 0);
		s.moves = true;
		group.add(s);
		return s;
	}

	function release(s:FlxSprite):Void {
		FlxTween.cancelTweensOf(s);
		group.remove(s, true);
		s.kill();
		pool.push(s);
	}

	/** Drops every live popup, for a restart or a skin change. **/
	public function clear():Void {
		var i:Int = group.members.length;
		while (--i >= 0) {
			var m = group.members[i];
			if (m != null)
				release(cast m);
		}
	}

	/**
		Replays the real judgement popup (rating + combo word + digits) with the in-edit config.
		@param diffMs the hit offset to judge, which selects the custom visual tier
	**/
	public function firePopup(diffMs:Float = 0):Void {
		var skin:IUISkin = UISkinService.current();
		var twR:Dynamic = UISkinConfig.tweenFor('rating');
		var twC:Dynamic = UISkinConfig.tweenFor('combo');
		var twN:Dynamic = UISkinConfig.tweenFor('numbers');
		var vis:UIJudgement = UISkinConfig.pickVisual(diffMs, ratingName);
		var pl:UIPlacement = UISkinConfig.placement();
		var placement:Float = FlxG.width * pl.anchorX;

		var rating:FlxSprite = acquire();
		var ratingLook:UIVisual = skin.applyRating(rating, vis.image);
		rating.screenCenter();
		rating.x = placement + pl.rating[0];
		rating.y += pl.rating[1];
		rating.acceleration.y = UISkinConfig.tRange(twR, 'accelY', 550, 550);
		rating.velocity.y -= UISkinConfig.tRange(twR, 'velocityY', 140, 175);
		rating.velocity.x -= UISkinConfig.tRange(twR, 'velocityX', 0, 10);
		rating.setGraphicSize(Std.int(rating.width
			* UISkinConfig.tFloat(twR, 'scale', 0.7)
			* (vis.scale != null ? vis.scale : 1)
			* ratingLook.factor));
		rating.updateHitbox();
		fade(rating, UISkinConfig.tFloat(twR, 'duration', 0.2), UISkinConfig.tEase(twR),
			UISkinConfig.tStartDelay(twR, Conductor.crochet * 0.001));

		var combo:FlxSprite = null;
		if (showComboWord) {
			combo = acquire();
			var comboLook:UIVisual = skin.applyCombo(combo);
			combo.screenCenter();
			combo.acceleration.y = UISkinConfig.tRange(twC, 'accelY', 200, 300);
			combo.velocity.y -= UISkinConfig.tRange(twC, 'velocityY', 140, 160);
			combo.velocity.x += UISkinConfig.tRange(twC, 'velocityX', 1, 10);
			combo.setGraphicSize(Std.int(combo.width * UISkinConfig.tFloat(twC, 'scale', 0.7) * comboLook.factor));
			combo.updateHitbox();
			combo.y += pl.combo[1];
		}

		var sep:String = Std.string(comboCount).lpad('0', 3);
		var xThing:Float = 0;
		for (i in 0...sep.length) {
			var num:FlxSprite = acquire();
			var numLook:UIVisual = skin.applyDigit(num, Std.parseInt(sep.charAt(i)));
			num.screenCenter();
			num.x = placement + (pl.numSpacing * i) + pl.numbers[0];
			num.y += pl.numbers[1];
			num.setGraphicSize(Std.int(num.width * UISkinConfig.tFloat(twN, 'scale', 0.5) * numLook.factor));
			num.updateHitbox();
			num.acceleration.y = UISkinConfig.tRange(twN, 'accelY', 200, 300);
			num.velocity.y -= UISkinConfig.tRange(twN, 'velocityY', 140, 160);
			num.velocity.x = UISkinConfig.tRange(twN, 'velocityX', -5, 5);
			fade(num, UISkinConfig.tFloat(twN, 'duration', 0.2), UISkinConfig.tEase(twN),
				UISkinConfig.tStartDelay(twN, Conductor.crochet * 0.002));
			if (num.x > xThing)
				xThing = num.x;
		}

		if (combo != null) {
			combo.x = xThing + pl.combo[0];
			fade(combo, UISkinConfig.tFloat(twC, 'duration', 0.2), UISkinConfig.tEase(twC),
				UISkinConfig.tStartDelay(twC, Conductor.crochet * 0.002));
		}
	}

	/**
		Fades a popup out, or freezes it in place when Static is on. Static holds motion too, so the
		sprite can be inspected where it was placed rather than mid-arc.
	**/
	function fade(spr:FlxSprite, duration:Float, ease:Float->Float, startDelay:Float):Void {
		if (staticHold) {
			spr.velocity.set(0, 0);
			spr.acceleration.set(0, 0);
			return;
		}
		FlxTween.tween(spr, {alpha: 0}, duration, {
			ease: ease,
			startDelay: startDelay,
			onComplete: function(_) release(spr)
		});
	}

	/** Plays the ready/set/go countdown once, at the current tempo. **/
	public function fireCountdown():Void {
		var names:Array<String> = ['ready', 'set', 'go'];
		var step:Int = 0;
		new FlxTimer().start(Conductor.crochet / 1000, function(tmr:FlxTimer) {
			if (step < names.length)
				spawnCountdown(names[step]);
			step++;
		}, names.length);
	}

	function spawnCountdown(logical:String):Void {
		var spr:FlxSprite = acquire();
		var look:UIVisual = UISkinService.current().applyCountdown(spr, logical);
		spr.updateHitbox();
		if (look.factor != 1)
			spr.setGraphicSize(Std.int(spr.width * look.factor));
		spr.screenCenter();
		fade(spr, Conductor.crochet / 1000, FlxEase.cubeInOut, 0);
	}

	// ---- placement handles ----

	function buildHandles():Void {
		var sizes:Array<Array<Int>> = [[150, 64], [120, 50], [140, 50]];
		var cols:Array<Int> = [0x5500FF00, 0x5500CCFF, 0x55FFCC00];
		for (i in 0...handleElems.length) {
			var spr:FlxSprite = new FlxSprite().makeGraphic(sizes[i][0], sizes[i][1], cols[i]);
			spr.scrollFactor.set();
			handleGroup.add(spr);
			handleSpr.push(spr);

			var lbl:FlxText = new FlxText(0, 0, sizes[i][0], handleElems[i], 12);
			lbl.setFormat(font(), 12, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
			lbl.scrollFactor.set();
			handleGroup.add(lbl);
			handleLabels.push(lbl);
		}
		positionHandles();
	}

	// Reference frame the placement [x,y] is measured from: the anchor column X and the screen centre Y.
	inline function refX():Float
		return FlxG.width * UISkinConfig.placement().anchorX;

	inline function refY():Float
		return FlxG.height / 2;

	inline function placeOf(elem:String):Array<Float> {
		var pl:UIPlacement = UISkinConfig.placement();
		return switch (elem) {
			case 'combo': pl.combo;
			case 'numbers': pl.numbers;
			default: pl.rating;
		}
	}

	/** Re-seats the handles on the config's current placement. **/
	public function positionHandles():Void {
		handleGroup.visible = showHandles;
		var rx:Float = refX();
		var ry:Float = refY();
		for (i in 0...handleSpr.length) {
			var p:Array<Float> = placeOf(handleElems[i]);
			handleSpr[i].x = rx + p[0];
			handleSpr[i].y = ry + p[1];
			handleLabels[i].x = handleSpr[i].x;
			handleLabels[i].y = handleSpr[i].y + handleSpr[i].height / 2 - 8;
			// The "combo" word is hidden by default, so its handle only shows when the word is enabled.
			var vis:Bool = showHandles && (handleElems[i] != 'combo' || showComboWord);
			handleSpr[i].visible = vis;
			handleLabels[i].visible = vis;
		}
	}

	/**
		Drag handling. Call once per frame from the owner's `update`.
		@param config the draft config that placement is written into
		@return the element that moved this frame, or null
	**/
	public function updateHandles(config:Dynamic):Null<String> {
		if (!showHandles || UIFocus.focused != null) {
			dragIndex = -1;
			return null;
		}
		var overUI:Bool = FlxSmidr.mouseBlocked;
		if (dragIndex < 0 && FlxG.mouse.justPressed && !overUI) {
			for (i in 0...handleSpr.length) {
				if (!handleSpr[i].visible)
					continue;
				if (FlxG.mouse.overlaps(handleSpr[i])) {
					dragIndex = i;
					grabX = FlxG.mouse.x - handleSpr[i].x;
					grabY = FlxG.mouse.y - handleSpr[i].y;
					break;
				}
			}
		}
		if (dragIndex < 0)
			return null;

		handleSpr[dragIndex].x = FlxG.mouse.x - grabX;
		handleSpr[dragIndex].y = FlxG.mouse.y - grabY;
		handleLabels[dragIndex].x = handleSpr[dragIndex].x;
		handleLabels[dragIndex].y = handleSpr[dragIndex].y + handleSpr[dragIndex].height / 2 - 8;

		var elem:String = handleElems[dragIndex];
		if (Reflect.field(config, 'placement') == null)
			Reflect.setField(config, 'placement', {});
		Reflect.setField(Reflect.field(config, 'placement'), elem, [
			Math.round(handleSpr[dragIndex].x - refX()),
			Math.round(handleSpr[dragIndex].y - refY())
		]);

		if (onPlacementChanged != null)
			onPlacementChanged(elem);
		if (FlxG.mouse.justReleased)
			dragIndex = -1;
		return elem;
	}

	public function destroy():Void {
		clear();
		pool.resize(0);
	}
}
