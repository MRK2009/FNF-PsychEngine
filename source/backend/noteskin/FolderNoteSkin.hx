package backend.noteskin;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import shaders.RGBPalette.RGBShaderReference;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;

/**
	Modern folder note skin (`.tcfg`/`.json` via `NoteSkinConfig`). Ports the per-lane resolution that
	used to live inline in `Note.reloadFolderNote` / `StrumNote.reloadFolderStrum`, retargeted onto bare
	sprites. Anything a folder skin can't resolve (missing element/keycount) falls back to the
	`ClassicNoteSkin` so partial skins still render. See `INoteSkin` for the method contracts.
**/
class FolderNoteSkin implements INoteSkin {
	final skinName:String;
	final fallback:ClassicNoteSkin;

	/**
		@param skinName the active folder skin (e.g. `noteSkins/Default`)
		@param fallback the classic provider used for elements this skin can't resolve
	**/
	public function new(skinName:String, fallback:ClassicNoteSkin) {
		this.skinName = skinName;
		this.fallback = fallback;
	}

	public function isPixel():Bool {
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return PlayState.isPixelStage;
		return NoteSkinConfig.pixelRenderFor(cfg);
	}

	/** Updates the global `NoteSkinConfig.pixelRender` for this skin (unless an editor override is set). **/
	inline function syncPixelMode(cfg:NoteSkinData):Void {
		if (NoteSkinConfig.editorOverride == null)
			NoteSkinConfig.pixelRender = NoteSkinConfig.pixelRenderFor(cfg);
	}

	/** Builds the note head; falls back to the classic skin if the lane/element can't be resolved. **/
	public function applyNote(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, animName:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return fallback.applyNote(spr, rgb, column, keyCount, animName);
		syncPixelMode(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var col:Int = column;
		var kc:Int = Mania.clamp(keyCount);
		var scaleBase:Float = NoteSkinConfig.scaleForColumn(cfg, col) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, col);

		var note = NoteSkinConfig.resolveColumn(cfg, cfg.notes, col);
		if (note == null)
			return fallback.applyNote(spr, rgb, column, keyCount, animName);
		var noteFrames:Array<String> = NoteSkinConfig.resolveFrames(base + note.key);
		if (noteFrames == null)
			return fallback.applyNote(spr, rgb, column, keyCount, animName);
		noteFrames = NoteSkinConfig.staticFrame(noteFrames, NoteSkinConfig.animatedFor(cfg, 'notes'));

		// osu!mania column-fit skins measure the element's TRUE width, so don't square-pad first (padding a
		// tall key up to a square would make `fitColumnWidth` render it as a thin sliver). Square-pad only
		// for the normal (native-pixel) skins that rely on it for rotation-safe, uniform centering.
		var square:Bool = !NoteSkinConfig.fitsColumnWidth(cfg);
		var factor:Float = NoteSkinConfig.applyAnims(spr, [
			{name: 'note', keys: noteFrames, fps: laneFps, loop: false, angle: note.angle, square: square}
		]);

		var colorable:Bool = NoteSkinConfig.colorableFor(cfg, 'notes');
		if (!colorable && rgb != null)
			rgb.enabled = false;
		v.colorable = colorable;
		// (Note splashes are built separately by NoteSkinConfig.applySplash / NoteSplash, not here.)

		spr.antialiasing = NoteSkinConfig.pixelRender ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, col, ClientPrefs.data.antialiasing);
		var fit:Float = NoteSkinConfig.fitScaleFor(cfg, spr.frameWidth, kc);
		var scaleFinal:Float = (fit > 0) ? fit : scaleBase * factor;
		spr.scale.set(scaleFinal, scaleFinal);
		spr.centerOffsets();
		spr.centerOrigin();
		spr.updateHitbox();

		v.centerOnStrum = true;
		var off:Array<Float> = NoteSkinConfig.offsetFor(cfg.noteOffsets, col);
		v.offsetX = off[0];
		v.offsetY = off[1];
		v.scaleFactor = scaleFinal;
		v.pixel = NoteSkinConfig.pixelRender;
		spr.animation.play('note', true);
		v.ok = true;
		return v;
	}

	/** Builds the hold body + tail; falls back to the classic skin if the lane/element can't be resolved. **/
	public function applySustain(body:FlxSprite, bodyRGB:RGBShaderReference, tail:FlxSprite, tailRGB:RGBShaderReference, column:Int,
			keyCount:Int):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return fallback.applySustain(body, bodyRGB, tail, tailRGB, column, keyCount);
		syncPixelMode(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var col:Int = column;
		var kc:Int = Mania.clamp(keyCount);
		var scaleBase:Float = NoteSkinConfig.scaleForColumn(cfg, col) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, col);

		var holdKey:String = NoteSkinConfig.columnKey(cfg.holds, col);
		var endKey:String = NoteSkinConfig.columnKey(cfg.ends, col);
		if (holdKey == null || endKey == null)
			return fallback.applySustain(body, bodyRGB, tail, tailRGB, column, keyCount);
		var holdFrames:Array<String> = NoteSkinConfig.resolveFrames(base + holdKey);
		var endFrames:Array<String> = NoteSkinConfig.resolveFrames(base + endKey);
		if (holdFrames == null || endFrames == null)
			return fallback.applySustain(body, bodyRGB, tail, tailRGB, column, keyCount);
		holdFrames = NoteSkinConfig.staticFrame(holdFrames, NoteSkinConfig.animatedFor(cfg, 'holds'));
		endFrames = NoteSkinConfig.staticFrame(endFrames, NoteSkinConfig.animatedFor(cfg, 'ends'));

		var fBody:Float = NoteSkinConfig.applyAnims(body, [{name: 'hold', keys: holdFrames, fps: laneFps, loop: true}]);
		var fTail:Float = NoteSkinConfig.applyAnims(tail, [{name: 'end', keys: endFrames, fps: laneFps, loop: true}]);

		var holdsSupported:Bool = NoteSkinConfig.colorableFor(cfg, 'holds');
		var endsSupported:Bool = NoteSkinConfig.colorableFor(cfg, 'ends');
		var linked:Bool = ClientPrefs.data.linkSustainColor;
		tintElement(bodyRGB, 'holds', holdsSupported, linked, col, kc);
		tintElement(tailRGB, 'ends', endsSupported, linked, col, kc);

		var aa:Bool = NoteSkinConfig.pixelRender ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, col, ClientPrefs.data.antialiasing);
		if (cfg.holdAntialiasing != null)
			aa = cfg.holdAntialiasing;
		body.antialiasing = tail.antialiasing = aa;
		var fitBody:Float = NoteSkinConfig.fitScaleFor(cfg, body.frameWidth, kc);
		var fitTail:Float = NoteSkinConfig.fitScaleFor(cfg, tail.frameWidth, kc);
		var bodyScale:Float = (fitBody > 0) ? fitBody : scaleBase * fBody;
		var tailScale:Float = (fitTail > 0) ? fitTail : scaleBase * fTail;
		body.scale.set(bodyScale, bodyScale);
		tail.scale.set(tailScale, tailScale);
		body.updateHitbox();
		tail.updateHitbox();

		v.centerOnStrum = true;
		var off:Array<Float> = NoteSkinConfig.offsetFor(cfg.holdOffsets, col);
		v.offsetX = off[0];
		v.offsetY = off[1];
		// Tail cap: its own `endOffsets` when the skin ships them, else the body's `holdOffsets` (no nudge).
		var eoff:Array<Float> = (cfg.endOffsets != null) ? NoteSkinConfig.offsetFor(cfg.endOffsets, col) : off;
		v.endOffsetX = eoff[0];
		v.endOffsetY = eoff[1];
		v.scaleFactor = bodyScale;
		v.pixel = NoteSkinConfig.pixelRender;
		v.colorable = holdsSupported;
		v.holdAlpha = NoteSkinConfig.numForColumn(cfg.holdAlpha, col, 0.6);
		v.ok = true;
		return v;
	}

	/**
		Enables/tints an element's RGB shader: disabled when the skin can't colour it; otherwise the note
		colour when its link is ON, or the asset's own independent colour (per-keycount aware) when OFF.
	**/
	inline function tintElement(ref:RGBShaderReference, element:String, supported:Bool, linked:Bool, column:Int, keyCount:Int):Void {
		if (ref == null)
			return;
		if (!supported) {
			ref.enabled = false;
			return;
		}
		ref.enabled = true;
		if (linked)
			return;
		var cols:Array<FlxColor> = tintFor(element, column, keyCount);
		if (cols != null) {
			ref.r = cols[0];
			ref.g = cols[1];
			ref.b = cols[2];
		}
	}

	/** The [r,g,b] triple an asset resolves to at a lane, or null when out of range. **/
	inline function tintFor(element:String, column:Int, keyCount:Int):Array<FlxColor> {
		var all:Array<Array<FlxColor>> = Mania.getAssetColors(element, keyCount);
		return (column >= 0 && column < all.length && all[column] != null && all[column].length >= 3) ? all[column] : null;
	}

	/** Builds the receptor static/pressed/confirm look; falls back to the classic skin if unresolved. **/
	public function applyReceptor(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, lastAnim:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return fallback.applyReceptor(spr, rgb, column, keyCount, lastAnim);
		syncPixelMode(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var c:Int = column;
		var kc:Int = Mania.clamp(keyCount);

		var st = NoteSkinConfig.resolveColumn(cfg, cfg.strums, c);
		if (st == null)
			return fallback.applyReceptor(spr, rgb, column, keyCount, lastAnim);
		var staticF:Array<String> = NoteSkinConfig.resolveFrames(base + st.key);
		if (staticF == null)
			return fallback.applyReceptor(spr, rgb, column, keyCount, lastAnim);
		staticF = NoteSkinConfig.staticFrame(staticF, NoteSkinConfig.animatedFor(cfg, 'strums'));
		var staticA:Float = st.angle;

		var pr = NoteSkinConfig.resolveColumn(cfg, cfg.pressed, c);
		var pressedF:Array<String> = pr == null ? null : NoteSkinConfig.resolveFrames(base + pr.key);
		var pressedA:Float = pr == null ? staticA : pr.angle;
		if (pressedF == null) {
			pressedF = staticF;
			pressedA = staticA;
		} else
			pressedF = NoteSkinConfig.staticFrame(pressedF, NoteSkinConfig.animatedFor(cfg, 'pressed'));

		var cf = NoteSkinConfig.resolveColumn(cfg, cfg.confirm, c);
		var confirmF:Array<String> = cf == null ? null : NoteSkinConfig.resolveFrames(base + cf.key);
		var confirmA:Float = cf == null ? pressedA : cf.angle;
		if (confirmF == null) {
			confirmF = pressedF;
			confirmA = pressedA;
		} else
			confirmF = NoteSkinConfig.staticFrame(confirmF, NoteSkinConfig.animatedFor(cfg, 'confirm'));

		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, c);
		// See applyNote: osu!mania column-fit skins keep their native (unpadded) frame so a tall key fills
		// the lane width instead of being squeezed into a square and rendering as a sliver.
		var square:Bool = !NoteSkinConfig.fitsColumnWidth(cfg);
		var factor:Float = NoteSkinConfig.applyAnims(spr, [
			{name: 'static', keys: staticF, fps: laneFps, loop: false, angle: staticA, square: square},
			{name: 'pressed', keys: pressedF, fps: laneFps, loop: false, angle: pressedA, square: square},
			{name: 'confirm', keys: confirmF, fps: confirmF.length > 1 ? laneFps : 24, loop: false, angle: confirmA, square: square}
		]);

		v.colorPerAnim = true;
		// Skin support only; the per-anim link/custom colour is resolved in Receptor.playAnim.
		v.staticColorable = NoteSkinConfig.colorableFor(cfg, 'strums');
		v.pressedColorable = NoteSkinConfig.colorableFor(cfg, 'pressed');
		v.confirmColorable = NoteSkinConfig.colorableFor(cfg, 'confirm');
		spr.antialiasing = NoteSkinConfig.pixelRender ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, c, ClientPrefs.data.antialiasing);

		var soff:Array<Float> = NoteSkinConfig.offsetFor(cfg.strumOffsets, c);
		v.offsetX = soff[0];
		v.offsetY = soff[1];
		v.laneCenter = true;
		v.hitAlign = NoteSkinConfig.hitAlignFor(cfg, c);
		v.receptorFlip = NoteSkinConfig.receptorFlipMode(cfg);

		var scaleBase:Float = NoteSkinConfig.scaleForColumn(cfg, c) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		var fit:Float = NoteSkinConfig.fitScaleFor(cfg, spr.frameWidth, kc);
		var scaleX:Float = (fit > 0) ? fit : scaleBase * factor;
		var scaleY:Float = scaleX;
		if (fit > 0) {
			// osu!mania keys fill the column WIDTH but keep their native texture HEIGHT (the key sprite is
			// `RelativeSizeAxes.X` only -- height is NOT aspect-locked to width). Reproduce that: scale height
			// off the source column width instead of the frame width, so a narrow-but-tall column key isn't
			// stretched vertically the way a uniform width-fit does. `x1.6` is osu's POSITION_SCALE_FACTOR
			// (its skin.ini ColumnWidth is in osu!px; the note art it fills is in that px space x1.6).
			var colW:Float = NoteSkinConfig.receptorColumnWidth(cfg, c);
			if (!Math.isNaN(colW) && colW > 0)
				scaleY = (160 * Mania.noteSizes[kc - 1] / (colW * 1.6)) * factor;
		}
		spr.scale.set(scaleX, scaleY);
		spr.updateHitbox();
		v.scaleFactor = scaleX;
		v.pixel = NoteSkinConfig.pixelRender;

		if (lastAnim != null && spr.animation.getByName(lastAnim) != null)
			spr.animation.play(lastAnim, true);
		else
			spr.animation.play('static', true);
		v.ok = true;
		return v;
	}
}
