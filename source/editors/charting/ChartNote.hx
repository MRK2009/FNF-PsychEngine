package editors.charting;

import flixel.util.FlxColor;

/**
	Pure chart-note data + editor state for a single note or event.

	The editor keeps one of these per note/event for the whole song (cheap: no graphics, no shader),
	while a small pool of `MetaNote` drawables renders only the notes inside the visible sections.
	Mirrors the gameplay note-runtime-v2 split (`NoteData` <-> pooled `NoteSprite`) so opening a large
	chart no longer allocates a full `Note` sprite per entry. The `sprite` back-reference is non-null
	only while this entry is realised in the window; data mutations forward to it when present.
**/
class ChartNote {
	/** The raw chart array this note round-trips to/from (`[time, data, sustain, type]`, or an event). **/
	public var songData:Array<Dynamic>;

	public var strumTime:Float = 0;
	public var sustainLength:Float = 0;

	/** Raw column including the side offset, exactly as stored in the chart. **/
	public var chartNoteData:Int = 0;

	/** Column within one side (`chartNoteData % keys`). **/
	public var noteData:Int = 0;
	public var mustPress:Bool = false;
	public var noteType:String = null;
	public var gfNote:Bool = false;

	public var isEvent:Bool = false;

	/** Key count of the section this note was decoded against (multikey remap onto the grid). **/
	public var chartKeyCount:Int = ChartingState.GRID_COLUMNS_PER_PLAYER;

	/** Sub-event groups, only for events (`isEvent`). **/
	public var events:Array<Array<String>> = null;

	/** Natural (downward-time) grid position; recomputed by the editor on zoom/move/section change. **/
	public var chartX:Float = 0;

	public var chartY:Float = 0;

	/** Quant colour override (`null` = use the note's direction colour). **/
	public var quantColor:Null<FlxColor> = null;

	/** True while part of the editor's selection. **/
	public var selected:Bool = false;

	/** Always true; mirrors the old `note.exists` so existing null/destroyed guards keep working. **/
	public var exists:Bool = true;

	/** The live drawable bound to this data, non-null only while realised in the visible window. **/
	public var sprite:MetaNote = null;

	// Zoom + step length the sustain pixel height was last built for, so a fresh drawable bind (or a
	// re-zoom) can rebuild the body sprite without the editor re-supplying the section timing.
	var _lastZoom:Float = -1;
	var _lastStepCrochet:Float = -1;

	public function new(time:Float, data:Int, songData:Array<Dynamic>, isEvent:Bool = false) {
		this.songData = songData;
		this.strumTime = time;
		this.chartNoteData = data;
		this.noteData = data;
		this.isEvent = isEvent;
	}

	public var hasSustain(get, never):Bool;

	inline function get_hasSustain():Bool
		return (!isEvent && sustainLength > 0);

	public function setStrumTime(v:Float):Void {
		songData[0] = v;
		strumTime = v;
		if (sprite != null)
			sprite.strumTime = v;
	}

	public function changeNoteData(v:Int):Void {
		chartNoteData = v;
		songData[1] = v;
		noteData = v % ChartingState.GRID_COLUMNS_PER_PLAYER;
		mustPress = (v < ChartingState.GRID_COLUMNS_PER_PLAYER);
		if (sprite != null)
			sprite.refreshNoteData(this);
	}

	public function setSustainLength(v:Float, stepCrochet:Float, zoom:Float = 1):Void {
		_lastZoom = zoom;
		_lastStepCrochet = stepCrochet;
		v = Math.round(v / (stepCrochet / 2)) * (stepCrochet / 2);
		songData[2] = sustainLength = Math.max(Math.min(v, stepCrochet * 128), 0);
		if (sprite != null)
			sprite.refreshSustain(this, stepCrochet, zoom);
	}

	/** Rebuilds the bound drawable's sustain body from the last-known section timing (used on bind). **/
	public function rebuildSpriteSustain():Void {
		if (sprite != null && !isEvent && sustainLength > 0 && _lastStepCrochet > 0)
			sprite.refreshSustain(this, _lastStepCrochet, _lastZoom);
	}

	public function updateSustainToZoom(stepCrochet:Float, zoom:Float = 1):Void {
		if (_lastZoom == zoom)
			return;
		setSustainLength(sustainLength, stepCrochet, zoom);
	}

	public function updateSustainToStepCrochet(stepCrochet:Float):Void {
		if (_lastZoom < 0)
			return;
		setSustainLength(sustainLength, stepCrochet, _lastZoom);
	}

	public function applyQuantColor(color:FlxColor):Void {
		quantColor = color;
		if (sprite != null)
			sprite.applyQuantColor(color);
	}

	public function restoreDirectionColor():Void {
		quantColor = null;
		if (sprite != null)
			sprite.restoreDirectionColor();
	}

	/** Recomputes the event label from `events` (no-op for notes); used after editing sub-events. **/
	public function updateEventText():Void {
		if (sprite != null)
			sprite.refreshEventText();
	}

	/**
		Detaches the drawable (if any) and drops references. The drawable itself is pooled, not freed --
		this only severs the data<->drawable link so a dropped note stops being rendered.
	**/
	public function destroy():Void {
		if (sprite != null) {
			sprite.unbind();
			sprite = null;
		}
		songData = null;
		events = null;
	}
}
