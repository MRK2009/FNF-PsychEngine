package backend.noteskin;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import shaders.RGBPalette.RGBShaderReference;
import objects.Note;

using StringTools;

/**
	The classic (pre-folder) note skin: NOTE_assets sparrow sheets, `pixelUI/` pixel sheets, and the
	multikey square-atlas merge. A faithful port of the old `Note`/`StrumNote` building (and
	`legacy.LegacyNoteSkin`) retargeted onto bare `FlxSprite`s with standardized anim names
	(`note`/`hold`/`end` and `static`/`pressed`/`confirm`). Used by the new drawables when no folder
	skin is active, and as `FolderNoteSkin`'s fallback for elements a folder skin can't resolve. See
	`INoteSkin` for the method contracts.
**/
class ClassicNoteSkin implements INoteSkin {
	public function new() {}

	public function isPixel():Bool
		return PlayState.isPixelStage;

	/**
		Resolves the base classic skin image name: the chart's `arrowSkin` (else the default) plus the
		user's noteSkin postfix when that variant exists.
		@return the resolved skin image base name
	**/
	function resolveSkin():String {
		var skin:String = (PlayState.SONG != null && PlayState.SONG.arrowSkin != null
			&& PlayState.SONG.arrowSkin.length > 1) ? PlayState.SONG.arrowSkin : Note.defaultNoteSkin;
		var postfix:String = Note.getNoteSkinPostfix();
		var custom:String = skin + postfix;
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';
		if (Paths.fileExists('images/' + path + custom + '.png', IMAGE))
			skin = custom;
		return skin;
	}

	/** Builds the note head from the classic sparrow sheet, or the `pixelUI/` sheet on a pixel stage. **/
	public function applyNote(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, animName:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var skin:String = resolveSkin();
		var nd:Int = column % Note.colArray.length;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			var graphic = Paths.image('pixelUI/' + skin);
			if (graphic == null)
				return v;
			spr.loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			spr.animation.add('note', [nd + 4], 24, false);
			spr.setGraphicSize(Std.int(spr.width * PlayState.daPixelZoom));
			spr.antialiasing = false;
			v.pixel = true;
		} else {
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			if (Mania.current != Mania.DEFAULT)
				atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			spr.frames = atlas;
			spr.antialiasing = ClientPrefs.data.antialiasing;
			spr.animation.addByPrefix('note', Note.colArray[nd] + '0');
			spr.setGraphicSize(Std.int(spr.width * Mania.noteSizes[kc - 1]));
		}

		spr.updateHitbox();
		spr.centerOffsets();
		spr.centerOrigin();
		spr.animation.play('note', true);
		v.scaleFactor = spr.scale.x;
		v.colorable = true;
		v.ok = true;
		return v;
	}

	/**
		Builds the hold body + tail. On a pixel stage both come from the `<skin>ENDS` sheet (4 columns x
		2 rows: top row = hold piece, bottom row = end cap, indexed by direction); otherwise from the
		classic sparrow `hold piece` / `hold end` prefixes.
	**/
	public function applySustain(body:FlxSprite, bodyRGB:RGBShaderReference, tail:FlxSprite, tailRGB:RGBShaderReference, column:Int,
			keyCount:Int):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var skin:String = resolveSkin();
		var nd:Int = column % Note.colArray.length;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			var ends = Paths.image('pixelUI/' + skin + 'ENDS');
			if (ends == null)
				return v;
			body.loadGraphic(ends, true, Math.floor(ends.width / 4), Math.floor(ends.height / 2));
			tail.loadGraphic(ends, true, Math.floor(ends.width / 4), Math.floor(ends.height / 2));
			body.animation.add('hold', [nd], 24, true);
			tail.animation.add('end', [nd + 4], 24, true);
			var zoom:Float = PlayState.daPixelZoom;
			body.setGraphicSize(Std.int(body.width * zoom));
			tail.setGraphicSize(Std.int(tail.width * zoom));
			body.antialiasing = tail.antialiasing = false;
			v.pixel = true;
		} else {
			var bodyAtlas:FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			var tailAtlas:FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			if (Mania.current != Mania.DEFAULT) {
				bodyAtlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
				tailAtlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			}
			body.frames = bodyAtlas;
			tail.frames = tailAtlas;
			body.animation.addByPrefix('hold', Note.colArray[nd] + ' hold piece', 24, true);
			tail.animation.addByPrefix('end', Note.colArray[nd] + ' hold end', 24, true);
			body.antialiasing = tail.antialiasing = ClientPrefs.data.antialiasing;
			var sz:Float = Mania.noteSizes[kc - 1];
			body.setGraphicSize(Std.int(body.width * sz));
			tail.setGraphicSize(Std.int(tail.width * sz));
		}

		body.animation.play('hold', true);
		tail.animation.play('end', true);
		body.updateHitbox();
		tail.updateHitbox();
		v.scaleFactor = body.scale.x;
		v.colorable = true;
		v.ok = true;
		return v;
	}

	/** Builds the receptor static/pressed/confirm look (pixel, multikey, or classic 4K branch). **/
	public function applyReceptor(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, lastAnim:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var nd:Int = column;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			var graphic = Paths.image('pixelUI/' + resolveSkin());
			if (graphic == null)
				return v;
			spr.loadGraphic(graphic);
			spr.width = spr.width / 4;
			spr.height = spr.height / 5;
			spr.loadGraphic(graphic, true, Math.floor(spr.width), Math.floor(spr.height));
			spr.antialiasing = false;
			spr.setGraphicSize(Std.int(spr.width * PlayState.daPixelZoom));
			switch (Std.int(Math.abs(nd)) % 4) {
				case 0:
					spr.animation.add('static', [0]);
					spr.animation.add('pressed', [4, 8], 12, false);
					spr.animation.add('confirm', [12, 16], 24, false);
				case 1:
					spr.animation.add('static', [1]);
					spr.animation.add('pressed', [5, 9], 12, false);
					spr.animation.add('confirm', [13, 17], 24, false);
				case 2:
					spr.animation.add('static', [2]);
					spr.animation.add('pressed', [6, 10], 12, false);
					spr.animation.add('confirm', [14, 18], 12, false);
				case 3:
					spr.animation.add('static', [3]);
					spr.animation.add('pressed', [7, 11], 12, false);
					spr.animation.add('confirm', [15, 19], 24, false);
			}
			v.pixel = true;
		} else if (Mania.current != Mania.DEFAULT) {
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(Note.defaultNoteSkin);
			atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			spr.frames = atlas;
			spr.antialiasing = ClientPrefs.data.antialiasing;
			var anim:String = Mania.noteAnimations[Mania.current - 1][Std.int(Math.abs(nd)) % Mania.current];
			spr.animation.addByPrefix('static', 'arrow' + anim.toUpperCase(), 24, false);
			spr.animation.addByPrefix('pressed', anim + ' press', 24, false);
			spr.animation.addByPrefix('confirm', anim + ' confirm', 24, false);
			spr.setGraphicSize(Std.int(spr.width * Mania.noteSizes[kc - 1]));
		} else {
			spr.frames = Paths.getSparrowAtlas(Note.defaultNoteSkin);
			spr.antialiasing = ClientPrefs.data.antialiasing;
			spr.setGraphicSize(Std.int(spr.width * 0.7));
			switch (Std.int(Math.abs(nd)) % 4) {
				case 0:
					spr.animation.addByPrefix('static', 'arrowLEFT');
					spr.animation.addByPrefix('pressed', 'left press', 24, false);
					spr.animation.addByPrefix('confirm', 'left confirm', 24, false);
				case 1:
					spr.animation.addByPrefix('static', 'arrowDOWN');
					spr.animation.addByPrefix('pressed', 'down press', 24, false);
					spr.animation.addByPrefix('confirm', 'down confirm', 24, false);
				case 2:
					spr.animation.addByPrefix('static', 'arrowUP');
					spr.animation.addByPrefix('pressed', 'up press', 24, false);
					spr.animation.addByPrefix('confirm', 'up confirm', 24, false);
				case 3:
					spr.animation.addByPrefix('static', 'arrowRIGHT');
					spr.animation.addByPrefix('pressed', 'right press', 24, false);
					spr.animation.addByPrefix('confirm', 'right confirm', 24, false);
			}
		}

		spr.updateHitbox();
		if (lastAnim != null && spr.animation.getByName(lastAnim) != null)
			spr.animation.play(lastAnim, true);
		else
			spr.animation.play('static', true);
		v.colorable = true;
		v.ok = true;
		return v;
	}
}
