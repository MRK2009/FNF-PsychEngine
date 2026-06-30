package editors.charting;

import objects.Note;
import backend.NoteSkinConfig;
import shaders.RGBPalette;
import flixel.util.FlxDestroyUtil;

/**
	Pooled chart-editor note/event drawable.

	One of these renders a single `ChartNote` while it is inside the visible sections; the editor keeps
	a small recycled pool (see `ChartingState.realizeNote`) instead of one sprite per note. This mirrors
	the gameplay note-runtime-v2 split: the persistent identity/data lives on `ChartNote`, this is the
	throwaway visual bound to it via `bind`. A single drawable renders either a note or an event,
	chosen from `data.isEvent`, so the pool is uniform.

	The inherited `Note` fields `strumTime`/`sustainLength`/`noteData`/`mustPress`/`noteType` are kept as
	mirrors of the bound data (copied in `bind`, synced by the data's mutators) so the editor's loops
	over rendered drawables can read them directly.
**/
class MetaNote extends Note {
	public static var noteTypeTexts:Map<Int, FlxText> = [];

	/** The data this drawable currently renders; `null` while pooled/dead. **/
	public var data:ChartNote = null;

	public var sustainSprite:FlxSprite;
	public var eventText:FlxText;

	var _noteTypeText:FlxText;

	public var lastPass:Int = -1;
	public var inCurGroup:Bool = false;

	public function new(?time:Float = 0, ?data:Int = 0) {
		super(time, data, null, false, true);
		scrollFactor.x = 0;
		active = false;
	}

	// Read-through accessors to the bound data, so the editor's loops over rendered drawables can read
	// these the same way they read the (inherited-`Note`) mirror fields. Non-`Note` fields only.
	public var songData(get, never):Array<Dynamic>;

	inline function get_songData():Array<Dynamic>
		return data != null ? data.songData : null;

	public var isEvent(get, never):Bool;

	inline function get_isEvent():Bool
		return data != null && data.isEvent;

	public var chartNoteData(get, never):Int;

	inline function get_chartNoteData():Int
		return data != null ? data.chartNoteData : 0;

	public var chartY(get, never):Float;

	inline function get_chartY():Float
		return data != null ? data.chartY : 0;

	public var chartKeyCount(get, never):Int;

	inline function get_chartKeyCount():Int
		return data != null ? data.chartKeyCount : ChartingState.GRID_COLUMNS_PER_PLAYER;

	public var events(get, never):Array<Array<String>>;

	inline function get_events():Array<Array<String>>
		return data != null ? data.events : null;

	// Forwarders so a data mutation triggered from a rendered drawable (swap/mirror/duet buttons) routes
	// through the authoritative `ChartNote`, which then refreshes this drawable.
	public function changeNoteData(v:Int):Void
		if (data != null)
			data.changeNoteData(v);

	public function setStrumTime(v:Float):Void
		if (data != null)
			data.setStrumTime(v);

	public function updateEventText():Void
		if (data != null)
			data.updateEventText();

	/**
		Binds this drawable to a `ChartNote` and rebuilds its graphics for that entry (note column or
		event icon). Position/alpha are applied by the caller, since they depend on the section.
		@param data the entry to render
	**/
	public function bind(data:ChartNote):Void {
		this.data = data;
		data.sprite = this;
		if (!exists || !alive)
			revive();
		visible = true;
		active = false;
		colorTransform.redMultiplier = colorTransform.greenMultiplier = colorTransform.blueMultiplier = 1;

		strumTime = data.strumTime;
		sustainLength = data.sustainLength;
		gfNote = data.gfNote;

		if (data.isEvent)
			bindEvent(data);
		else
			bindNote(data);
	}

	function bindNote(data:ChartNote):Void {
		if (eventText != null)
			eventText.visible = false;

		refreshNoteData(data);
		noteType = data.noteType;
		rebuildColor(data);
		data.rebuildSpriteSustain();
		if (sustainSprite != null)
			sustainSprite.visible = (sustainLength > 0);
	}

	function bindEvent(data:ChartNote):Void {
		if (sustainSprite != null)
			sustainSprite.visible = false;
		_noteTypeText = null;
		if (rgbShader != null)
			rgbShader.enabled = false;

		// loadGraphic replaces any note frames, so the note frame-cache is now invalid -- force the next
		// note bind on this pooled drawable to rebuild.
		_frameCol = -999;
		loadGraphic(Paths.image('editors/eventIcon'));
		setGraphicSize(ChartingState.GRID_SIZE);
		updateHitbox();

		if (eventText == null) {
			eventText = new FlxText(0, 0, 400, '', 12);
			eventText.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, RIGHT);
			eventText.scrollFactor.x = 0;
		}
		eventText.visible = true;
		refreshEventText();
	}

	// Identity of the frames `reloadNote` last built onto this drawable: the column plus everything
	// `reloadNote`/`reloadFolderNote` reads (active skin, pixel stage, texture override, keycount).
	// `_frameCol == -999` means it currently holds non-note frames (an event icon) and must rebuild.
	var _frameCol:Int = -999;
	var _frameSkin:String = null;
	var _framePix:Bool = false;
	var _frameTex:String = null;
	var _frameKey:Int = -1;

	public function refreshNoteData(data:ChartNote):Void {
		noteData = data.noteData;
		mustPress = data.mustPress;

		// reloadNote rebuilds the per-(column, skin, pixel, texture, keycount) atlas frames. A pooled
		// drawable often already holds exactly those, so skip the rebuild when the identity is unchanged;
		// the column animation + hitbox below are re-applied cheaply regardless, and the '<col>Scroll'
		// animation still exists from the prior same-identity build.
		var skin:String = NoteSkinConfig.activeSkin();
		var pix:Bool = PlayState.isPixelStage;
		var tex:String = (PlayState.SONG != null) ? PlayState.SONG.arrowSkin : null;
		var kc:Int = Mania.current;
		if (noteData != _frameCol || skin != _frameSkin || pix != _framePix || tex != _frameTex || kc != _frameKey) {
			reloadNote();
			_frameCol = noteData;
			_frameSkin = skin;
			_framePix = pix;
			_frameTex = tex;
			_frameKey = kc;
		}

		if (Note.globalRgbShaders.contains(rgbShader.parent))
			rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(noteData));

		var col:Int = noteData % Note.colArray.length;
		if (col < 0)
			col += Note.colArray.length;
		animation.play(Note.colArray[col] + 'Scroll');
		updateHitbox();
		if (width > height)
			setGraphicSize(ChartingState.GRID_SIZE);
		else
			setGraphicSize(0, ChartingState.GRID_SIZE);
		updateHitbox();
		rebuildColor(data);
	}

	inline function rebuildColor(data:ChartNote):Void {
		if (data.quantColor != null)
			applyQuantColor(data.quantColor);
		else
			restoreDirectionColor();
	}

	/** (Re)builds the white sustain-body sprite for the note's current length/zoom. **/
	public function refreshSustain(data:ChartNote, stepCrochet:Float, zoom:Float = 1):Void {
		sustainLength = data.sustainLength;
		if (data.isEvent)
			return;

		if (sustainLength > 0) {
			if (sustainSprite == null) {
				sustainSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
				sustainSprite.scrollFactor.x = 0;
			}
			sustainSprite.setGraphicSize(8,
				Math.max(ChartingState.GRID_SIZE / 4,
					(Math.round((sustainLength * ChartingState.GRID_SIZE + ChartingState.GRID_SIZE) / stepCrochet) * zoom) - ChartingState.GRID_SIZE / 2));
			sustainSprite.updateHitbox();
			sustainSprite.color = (data.quantColor != null) ? data.quantColor : FlxColor.WHITE;
			sustainSprite.visible = true;
		} else if (sustainSprite != null)
			sustainSprite.visible = false;
	}

	// Quantized (StepMania-style) coloring. The RGB palette shader maps the arrow texture's red/green/
	// blue channels to three colours (main / highlight / shadow). To recolour a note to a single hue
	// the same way the note-color option does, set r = hue, g = white highlight, b = a darkened hue --
	// NOT a flat r=g=b (which oversaturates).
	public function applyQuantColor(color:FlxColor):Void {
		if (rgbShader == null)
			return;
		rgbShader.enabled = true;
		rgbShader.r = color;
		rgbShader.g = FlxColor.WHITE;
		rgbShader.b = color.getDarkened(0.6);
		if (sustainSprite != null)
			sustainSprite.color = color;
	}

	public function restoreDirectionColor():Void {
		if (rgbShader == null)
			return;
		defaultRGB();
		rgbShader.enabled = (PlayState.SONG == null || !PlayState.SONG.disableNoteRGB);
		if (sustainSprite != null)
			sustainSprite.color = FlxColor.WHITE;
	}

	public function refreshEventText():Void {
		if (data == null || !data.isEvent || eventText == null || data.events == null)
			return;
		var evs:Array<Array<String>> = data.events;
		var myTime:Float = Math.floor(data.strumTime);
		if (evs.length == 1) {
			var event:Array<String> = evs[0];
			eventText.text = 'Event: ${event[0]} ($myTime ms)\nValue 1: ${event[1]}\nValue 2: ${event[2]}';
		} else if (evs.length > 1) {
			var eventNames:Array<String> = [for (event in evs) event[0]];
			eventText.text = '${evs.length} Events ($myTime ms):\n${eventNames.join(', ')}';
		} else
			eventText.text = 'ERROR FAILSAFE';
	}

	public function findNoteTypeText(num:Int):FlxText {
		var txt:FlxText = null;
		if (num != 0) {
			if (!noteTypeTexts.exists(num)) {
				txt = new FlxText(0, 0, ChartingState.GRID_SIZE, (num > 0) ? Std.string(num) : '?', 16);
				txt.autoSize = false;
				txt.alignment = CENTER;
				txt.borderStyle = SHADOW;
				txt.shadowOffset.set(2, 2);
				txt.borderColor = FlxColor.BLACK;
				txt.scrollFactor.x = 0;
				noteTypeTexts.set(num, txt);
			} else
				txt = noteTypeTexts.get(num);
		}
		return (_noteTypeText = txt);
	}

	/** Detaches from the data and returns the drawable to the pool (killed, ready for `recycle`). **/
	/**
		The editor's per-group free-list this drawable returns to on `unbind`, so `realizeNote` can pop a
		dead sprite in O(1) instead of scanning the group. Set when the sprite is created.
	**/
	public var freeList:Array<MetaNote> = null;

	public function unbind():Void {
		if (data != null) {
			if (data.sprite == this)
				data.sprite = null;
			data = null;
			if (freeList != null)
				freeList.push(this);
		}
		if (eventText != null)
			eventText.visible = false;
		if (sustainSprite != null)
			sustainSprite.visible = false;
		_noteTypeText = null;
		kill();
	}

	override function draw() {
		var isEvent:Bool = (data != null && data.isEvent);

		if (!isEvent && sustainSprite != null && sustainSprite.exists && sustainSprite.visible && sustainLength > 0) {
			sustainSprite.x = this.x + this.width / 2 - sustainSprite.width / 2;
			// Downscroll: the sustain tail extends upward (toward later time) from the head.
			sustainSprite.y = ChartingState.downScroll ? (this.y + this.height / 2 - sustainSprite.height) : (this.y + this.height / 2);
			sustainSprite.alpha = this.alpha;
			sustainSprite.draw();
		}

		super.draw();

		if (isEvent) {
			if (eventText != null && eventText.exists && eventText.visible) {
				eventText.y = this.y + this.height / 2 - eventText.height / 2;
				eventText.alpha = this.alpha;
				eventText.draw();
			}
		} else if (_noteTypeText != null && _noteTypeText.exists && _noteTypeText.visible) {
			_noteTypeText.x = this.x + this.width / 2 - _noteTypeText.width / 2;
			_noteTypeText.y = this.y + this.height / 2 - _noteTypeText.height / 2;
			_noteTypeText.alpha = this.alpha;
			_noteTypeText.draw();
		}
	}

	override function destroy() {
		if (data != null && data.sprite == this)
			data.sprite = null;
		data = null;
		sustainSprite = FlxDestroyUtil.destroy(sustainSprite);
		eventText = FlxDestroyUtil.destroy(eventText);
		super.destroy();
	}
}
