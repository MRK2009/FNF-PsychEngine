package legacy.editors.charting;

import legacy.editors.ChartingState.UndoStruct;
import legacy.editors.ChartingState.UndoAction;
import legacy.editors.ChartingState;

/**
	Bounded undo/redo history for the chart editor.

	Each entry is an `UndoStruct` describing one reversible edit (add/delete/move/select). The stack
	keeps the newest entry at index 0 and `currentUndo` as the cursor into already-undone entries, so a
	redo simply walks back toward 0. Capped at 15 entries; evicted add/move entries destroy the
	`ChartNote` drawables they own. All note/selection mutation goes through the editor it holds.
**/
@:access(legacy.editors.ChartingState)
class ChartUndoStack {
	var editor:ChartingState;

	var undoActions:Array<UndoStruct> = [];

	/** Cursor: how many entries (from index 0) are currently in the "undone" state. **/
	var currentUndo:Int = 0;

	/**
		@param editor the chart editor whose notes/events/selection these actions mutate
	**/
	public function new(editor:ChartingState) {
		this.editor = editor;
	}

	/** Wipes all history (used when the chart is reloaded/replaced). **/
	public function clear():Void {
		undoActions = [];
		currentUndo = 0;
	}

	/** Destroys every non-null `ChartNote` in `arr` (used when an owning entry is evicted). **/
	function destroyFromArr(arr:Array<ChartNote>):Void {
		if (arr == null || arr.length < 1)
			return;

		for (note in arr)
			if (note != null)
				note.destroy();
	}

	/**
		Pushes a new reversible action, discarding any redo tail and trimming the oldest entries past the
		15-entry cap (destroying the notes those evicted entries own).
		@param action the kind of edit
		@param data the payload (note/event arrays the undo/redo paths read)
	**/
	public function add(action:UndoAction, data:Dynamic):Void {
		if (currentUndo > 0)
			undoActions = undoActions.slice(currentUndo);
		currentUndo = 0;
		undoActions.insert(0, {action: action, data: data});
		while (undoActions.length > 15) {
			var lastAction:UndoStruct = undoActions.pop();
			if (lastAction != null) {
				switch (lastAction.action) {
					case DELETE_NOTE:
						destroyFromArr(lastAction.data.notes);
						destroyFromArr(lastAction.data.events);
					case MOVE_NOTE:
						destroyFromArr(lastAction.data.originalNotes);
						destroyFromArr(lastAction.data.originalEvents);
					default:
				}
			}
		}
	}

	/** Reverts the action at the cursor and advances the cursor toward the history tail. **/
	public function undo():Void {
		if (editor.isMovingNotes || currentUndo >= undoActions.length) {
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
			return;
		}

		var action:UndoStruct = undoActions[currentUndo];
		switch (action.action) {
			case ADD_NOTE:
				actionRemoveNotes(action.data.notes, action.data.events);

			case DELETE_NOTE:
				actionPushNotes(action.data.notes, action.data.events);

			case MOVE_NOTE:
				actionRemoveNotes(action.data.movedNotes, action.data.movedEvents);
				actionPushNotes(action.data.originalNotes, action.data.originalEvents);
				editor.onSelectNote();

			case SELECT_NOTE:
				editor.resetSelectedNotes();
				editor.selectedNotes = action.data.old;
				if (editor.lockedEvents)
					editor.selectedNotes = editor.selectedNotes.filter((note:ChartNote) -> !note.isEvent);
				editor.onSelectNote();
		}
		editor.showOutput('Undo #${currentUndo + 1}: ${action.action}');
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		currentUndo++;
	}

	/** Re-applies the most recently undone action and moves the cursor back toward index 0. **/
	public function redo():Void {
		if (editor.isMovingNotes || currentUndo < 1) {
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
			return;
		}

		currentUndo--;
		var action:UndoStruct = undoActions[currentUndo];
		switch (action.action) {
			case ADD_NOTE:
				actionPushNotes(action.data.notes, action.data.events);

			case DELETE_NOTE:
				actionRemoveNotes(action.data.notes, action.data.events);

			case MOVE_NOTE:
				actionRemoveNotes(action.data.originalNotes, action.data.originalEvents);
				actionPushNotes(action.data.movedNotes, action.data.movedEvents);
				editor.onSelectNote();

			case SELECT_NOTE:
				editor.resetSelectedNotes();
				editor.selectedNotes = action.data.current;
				if (editor.lockedEvents)
					editor.selectedNotes = editor.selectedNotes.filter((note:ChartNote) -> !note.isEvent);
				editor.onSelectNote();
		}
		editor.showOutput('Redo #${currentUndo + 1}: ${action.action}');
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	/** Re-inserts notes/events into the chart (selecting them) and refreshes the rendered field. **/
	function actionPushNotes(dataNotes:Array<ChartNote>, dataEvents:Array<ChartNote>):Void {
		editor.resetSelectedNotes();
		if (dataNotes != null && dataNotes.length > 0) {
			for (note in dataNotes) {
				if (note != null) {
					editor.notes.push(note);
					editor.selectedNotes.push(note);
					note.songData[0] = note.strumTime;
					note.songData[1] = note.chartNoteData;
				}
			}
			editor.notes.sort(PlayState.sortByTime);
		}
		if (dataEvents != null && dataEvents.length > 0) {
			for (event in dataEvents) {
				if (event != null) {
					editor.events.push(event);
					editor.selectedNotes.push(event);
					event.songData[0] = event.strumTime;
				}
			}
			editor.events.sort(PlayState.sortByTime);
		}
		editor.softReloadNotes();
	}

	/** Removes notes/events from the chart, resetting their drawable tint/frame, then refreshes. **/
	function actionRemoveNotes(dataNotes:Array<ChartNote>, dataEvents:Array<ChartNote>):Void {
		if (dataNotes != null && dataNotes.length > 0) {
			for (note in dataNotes) {
				if (note != null) {
					editor.notes.remove(note);
					editor.selectedNotes.remove(note);

					if (note.sprite != null) {
						note.sprite.colorTransform.redMultiplier = note.sprite.colorTransform.greenMultiplier = note.sprite.colorTransform.blueMultiplier = 1;
						if (note.sprite.animation.curAnim != null)
							note.sprite.animation.curAnim.curFrame = 0;
					}
				}
			}
		}
		if (dataEvents != null && dataEvents.length > 0) {
			for (event in dataEvents) {
				if (event != null) {
					trace(editor.events.remove(event));
					editor.selectedNotes.remove(event);

					if (event.sprite != null) {
						event.sprite.colorTransform.redMultiplier = event.sprite.colorTransform.greenMultiplier = event.sprite.colorTransform.blueMultiplier = 1;
						if (event.sprite.animation.curAnim != null)
							event.sprite.animation.curAnim.curFrame = 0;
					}
				}
			}
		}
		editor.softReloadNotes();
	}

	/**
		Rewrites every history reference to `oldNote` so it points at `newNote`, keeping undo/redo valid
		after a note is replaced in place (e.g. a type change that rebuilds the `ChartNote`).
	**/
	public function replaceNotes(oldNote:ChartNote, newNote:ChartNote):Void {
		for (act in undoActions) {
			for (field in Reflect.fields(act.data)) {
				var fld:Array<ChartNote> = cast Reflect.field(act.data, field);
				if (fld != null && fld.length > 0)
					for (num => actNote in fld)
						if (actNote == oldNote)
							fld[num] = newNote;
			}
		}
	}
}
