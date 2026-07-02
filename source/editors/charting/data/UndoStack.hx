package editors.charting.data;

import backend.SongChart;
import backend.SongChart.ChartSection;
import backend.SongChart.SongNote;
import backend.SongChart.StrumLineData;
import objects.notes.NoteData.KeyCountChange;
import objects.notes.ScrollVelocity.ScrollPoint;
import openfl.Lib;

/**
	Snapshot-based undo/redo over the whole editable chart state (notes, sections, strumlines,
	events, change-points and the scalar meta the section panel edits). Capped at `CAP` entries;
	`snapshotCoalesced` merges rapid same-label edits (stepper hold-repeat) into one entry.
**/
final class UndoStack {
	/** Maximum retained undo entries (oldest drop off past this). **/
	public static inline var CAP:Int = 60;

	final undoStack:Array<ChartSnapshot> = [];
	final redoStack:Array<ChartSnapshot> = [];

	public function new() {}

	/** `true` while an undo entry exists. **/
	public var canUndo(get, never):Bool;

	/** `true` while a redo entry exists. **/
	public var canRedo(get, never):Bool;

	inline function get_canUndo():Bool {
		return undoStack.length > 0;
	}

	inline function get_canRedo():Bool {
		return redoStack.length > 0;
	}

	/** Clears both stacks (chart reload). **/
	public function reset():Void {
		undoStack.resize(0);
		redoStack.resize(0);
	}

	/** Captures the pre-edit state. Call BEFORE mutating the model. **/
	public function snapshot(model:ChartEditorModel, label:String):Void {
		undoStack.push(ChartSnapshot.capture(model.chart, label));
		if (undoStack.length > CAP)
			undoStack.shift();
		redoStack.resize(0);
	}

	/** Like `snapshot`, but rapid repeats with the same label collapse into the first capture. **/
	public function snapshotCoalesced(model:ChartEditorModel, label:String, windowMs:Int = 900):Void {
		var now:Int = Lib.getTimer();
		if (undoStack.length > 0) {
			var top:ChartSnapshot = undoStack[undoStack.length - 1];
			if (top.label == label && now - top.takenAt < windowMs) {
				top.takenAt = now;
				redoStack.resize(0);
				return;
			}
		}
		snapshot(model, label);
	}

	/** Restores the newest snapshot; the current state moves to the redo stack. Returns its label. **/
	public function undo(model:ChartEditorModel):String {
		if (undoStack.length == 0)
			return null;
		var snap:ChartSnapshot = undoStack.pop();
		redoStack.push(ChartSnapshot.capture(model.chart, snap.label));
		snap.applyTo(model);
		return snap.label;
	}

	/** Re-applies the newest redo state. Returns its label. **/
	public function redo(model:ChartEditorModel):String {
		if (redoStack.length == 0)
			return null;
		var snap:ChartSnapshot = redoStack.pop();
		undoStack.push(ChartSnapshot.capture(model.chart, snap.label));
		snap.applyTo(model);
		return snap.label;
	}
}

/** One captured chart state (deep copies; immutable once taken - applying re-clones). **/
private final class ChartSnapshot {
	/** The user-facing edit label ("Place Note", "BPM", ...). **/
	public final label:String;

	/** Capture timestamp in ms (drives `snapshotCoalesced`'s merge window). **/
	public var takenAt:Int;

	final notes:Array<SongNote>;
	final sections:Array<ChartSection>;
	final strumLines:Array<StrumLineData>;
	final keyChanges:Array<KeyCountChange>;
	final scrollPoints:Array<ScrollPoint>;
	final events:Array<Dynamic>;
	final bpm:Float;
	final speed:Float;
	final keyCount:Int;
	final offset:Float;

	function new(label:String, notes:Array<SongNote>, sections:Array<ChartSection>, strumLines:Array<StrumLineData>, keyChanges:Array<KeyCountChange>,
			scrollPoints:Array<ScrollPoint>, events:Array<Dynamic>, bpm:Float, speed:Float, keyCount:Int, offset:Float) {
		this.label = label;
		this.takenAt = Lib.getTimer();
		this.notes = notes;
		this.sections = sections;
		this.strumLines = strumLines;
		this.keyChanges = keyChanges;
		this.scrollPoints = scrollPoints;
		this.events = events;
		this.bpm = bpm;
		this.speed = speed;
		this.keyCount = keyCount;
		this.offset = offset;
	}

	/**
		Deep-copies the chart's editable state.
		@param chart the chart to snapshot
		@param label the user-facing edit label
		@return the immutable snapshot
	**/
	public static function capture(chart:SongChart, label:String):ChartSnapshot {
		return new ChartSnapshot(label, cloneNotes(chart.noteList), cloneSections(chart.sections), cloneStrumLines(chart.strumLines),
			cloneKeyChanges(chart.keyCountChanges), cloneScrollPoints(chart.scrollPoints), cloneEvents(chart.events), chart.bpm, chart.speed, chart.keyCount,
			chart.offset);
	}

	/**
		Restores this snapshot onto the model's chart (clones again, so the snapshot stays reusable).
		@param model the model to restore into (timing rebuilt, `onChanged` fired)
	**/
	public function applyTo(model:ChartEditorModel):Void {
		var chart:SongChart = model.chart;
		chart.noteList = cloneNotes(notes);
		chart.sections = cloneSections(sections);
		chart.strumLines = cloneStrumLines(strumLines);
		chart.keyCountChanges = cloneKeyChanges(keyChanges);
		chart.scrollPoints = cloneScrollPoints(scrollPoints);
		chart.events = cloneEvents(events);
		chart.bpm = bpm;
		chart.speed = speed;
		chart.keyCount = keyCount;
		chart.offset = offset;
		model.rebuildTiming();
		model.markDirty();
	}

	/**
		Deep-copies a note list.
		@param src the source notes
		@return field-by-field copies
	**/
	public static function cloneNotes(src:Array<SongNote>):Array<SongNote> {
		var out:Array<SongNote> = [];
		var i:Int = 0;
		var n:Int = src.length;
		while (i < n) {
			var e:SongNote = src[i];
			out.push({
				time: e.time,
				strumLine: e.strumLine,
				column: e.column,
				length: e.length,
				type: e.type,
				altAnim: e.altAnim,
				gfNote: e.gfNote
			});
			i++;
		}
		return out;
	}

	static function cloneSections(src:Array<ChartSection>):Array<ChartSection> {
		var out:Array<ChartSection> = [];
		var i:Int = 0;
		var n:Int = src.length;
		while (i < n) {
			var e:ChartSection = src[i];
			out.push({
				cameraTarget: e.cameraTarget,
				bpm: e.bpm,
				changeBPM: e.changeBPM,
				beats: e.beats,
				denominator: e.denominator
			});
			i++;
		}
		return out;
	}

	static function cloneStrumLines(src:Array<StrumLineData>):Array<StrumLineData> {
		var out:Array<StrumLineData> = [];
		var i:Int = 0;
		var n:Int = src.length;
		while (i < n) {
			var e:StrumLineData = src[i];
			out.push({
				index: e.index,
				id: e.id,
				type: e.type,
				isPlayer: e.isPlayer,
				visible: e.visible,
				characters: e.characters.copy(),
				keyCount: e.keyCount,
				vocalsSuffix: e.vocalsSuffix
			});
			i++;
		}
		return out;
	}

	static function cloneKeyChanges(src:Array<KeyCountChange>):Array<KeyCountChange> {
		var out:Array<KeyCountChange> = [];
		var i:Int = 0;
		var n:Int = src.length;
		while (i < n) {
			out.push({time: src[i].time, count: src[i].count});
			i++;
		}
		return out;
	}

	static function cloneScrollPoints(src:Array<ScrollPoint>):Array<ScrollPoint> {
		var out:Array<ScrollPoint> = [];
		var i:Int = 0;
		var n:Int = src.length;
		while (i < n) {
			out.push(new ScrollPoint(src[i].time, src[i].vel));
			i++;
		}
		return out;
	}

	/** Deep-copies the legacy grouped events (`[time, [[name, v1, v2], ...]]`). **/
	public static function cloneEvents(src:Array<Dynamic>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (src == null)
			return out;
		var i:Int = 0;
		var n:Int = src.length;
		while (i < n) {
			var group:Array<Dynamic> = src[i];
			var subs:Array<Dynamic> = group[1];
			var subCopies:Array<Dynamic> = [];
			if (subs != null) {
				var j:Int = 0;
				var m:Int = subs.length;
				while (j < m) {
					var sub:Array<Dynamic> = subs[j];
					subCopies.push(sub.copy());
					j++;
				}
			}
			out.push([group[0], subCopies]);
			i++;
		}
		return out;
	}
}
