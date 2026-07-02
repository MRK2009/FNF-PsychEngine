package editors.charting.data;

import backend.SongChart.SongNote;

/**
	The editor clipboard: note copies (times relative to a copy anchor) plus event copies.
	Pasting clones again, so one copy can paste many times.
**/
final class ClipboardModel {
	final notes:Array<SongNote> = [];
	final eventTimes:Array<Float> = [];
	final eventSubs:Array<Array<Dynamic>> = [];

	public function new() {}

	/** `true` while the clipboard holds any notes or events. **/
	public var hasContent(get, never):Bool;

	inline function get_hasContent():Bool {
		return notes.length > 0 || eventTimes.length > 0;
	}

	/** The number of copied notes. **/
	public var noteCount(get, never):Int;

	inline function get_noteCount():Int {
		return notes.length;
	}

	/** Empties the clipboard. **/
	public function clear():Void {
		notes.resize(0);
		eventTimes.resize(0);
		eventSubs.resize(0);
	}

	/** Copies specific notes (selection), times made relative to `anchor`. **/
	public function copyNotes(list:Array<SongNote>, anchor:Float):Void {
		clear();
		var i:Int = 0;
		var n:Int = list.length;
		while (i < n) {
			var e:SongNote = list[i];
			notes.push({
				time: e.time - anchor,
				strumLine: e.strumLine,
				column: e.column,
				length: e.length,
				type: e.type,
				altAnim: e.altAnim,
				gfNote: e.gfNote
			});
			i++;
		}
	}

	/** Copies everything in `[from, to)` (notes + events), times relative to `from`. **/
	public function copyRange(model:ChartEditorModel, from:Float, to:Float):Void {
		var scratch:Array<SongNote> = [];
		model.notesBetween(from, to, scratch);
		copyNotes(scratch, from);

		var groups:Array<Dynamic> = [];
		model.eventsBetween(from, to, groups);
		var i:Int = 0;
		var n:Int = groups.length;
		while (i < n) {
			var group:Array<Dynamic> = groups[i];
			var subs:Array<Dynamic> = group[1];
			var j:Int = 0;
			var m:Int = (subs != null) ? subs.length : 0;
			while (j < m) {
				var sub:Array<Dynamic> = subs[j];
				eventTimes.push((group[0] : Float) - from);
				eventSubs.push(sub.copy());
				j++;
			}
			i++;
		}
	}

	/** Copies one whole section. **/
	public function copySection(model:ChartEditorModel, sec:Int):Void {
		copyRange(model, model.sectionStart(sec), model.sectionEnd(sec));
	}

	/** Pastes at `atTime` (occupied spots skipped). Returns how many notes+events landed. **/
	public function paste(model:ChartEditorModel, atTime:Float):Int {
		var placed:Int = 0;
		var i:Int = 0;
		var n:Int = notes.length;
		while (i < n) {
			var e:SongNote = notes[i];
			var t:Float = atTime + e.time;
			if (model.noteAt(t, e.strumLine, e.column) == null) {
				model.addNote(t, e.strumLine, e.column, e.length, e.type, e.altAnim, e.gfNote);
				placed++;
			}
			i++;
		}
		i = 0;
		n = eventTimes.length;
		while (i < n) {
			var sub:Array<Dynamic> = eventSubs[i];
			var v1:String = (sub.length > 1 && sub[1] != null) ? sub[1] : '';
			var v2:String = (sub.length > 2 && sub[2] != null) ? sub[2] : '';
			model.addEvent(atTime + eventTimes[i], sub[0], v1, v2);
			placed++;
			i++;
		}
		return placed;
	}
}
