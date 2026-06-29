package editors.charting.tabs;

import editors.content.Prompt;
import editors.ChartingState;
import editors.ChartingState.UndoAction;

/**
	Builds the "Edit" toolbar menu of the chart editor: undo/redo, select-all, lock-events, the autosave
	settings window, and the clear-all-notes/events actions. All edits route through the editor (selection,
	undo stack, note/event arrays). Reaches editor state/widgets via `@:access`.
**/
@:access(editors.ChartingState)
class EditTab {
	/**
		Populates the Edit toolbar menu in `s.upperBox`.
		@param s the chart editor that owns the toolbar and the edit state
	**/
	public static function build(s:ChartingState):Void {
		var tab = s.upperBox.getTab('Edit');
		var tab_group = tab.menu;
		var btnX = tab.x - s.upperBox.x;
		var btnY = 1;
		var btnWid = Std.int(tab.width);

		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Undo', s.undo, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Redo', s.redo, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Select All', function() {
			var sel = s.selectedNotes;
			s.selectedNotes = s.renderedData();
			s.addUndoAction(UndoAction.SELECT_NOTE, {old: sel, current: s.selectedNotes.copy()});
			s.onSelectNote();
			trace('Notes selected: ' + s.selectedNotes.length);
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		if (ChartingState.SHOW_EVENT_COLUMN) {
			btnY++;
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Lock Events', btnWid);
			btn.onClick = function() {
				s.lockedEvents = !s.lockedEvents;
				if (s.lockedEvents)
					btn.text.text = '  Unlock Events';
				else
					btn.text.text = '  Lock Events';
				s.eventLockOverlay.visible = s.lockedEvents;

				if (s.selectedNotes.length >= 1) {
					var sel = s.selectedNotes;
					var onlyNotes = s.selectedNotes.filter((note:ChartNote) -> !note.isEvent);
					s.resetSelectedNotes();
					s.selectedNotes = onlyNotes;
					s.addUndoAction(UndoAction.SELECT_NOTE, {old: sel, current: s.selectedNotes.copy()});
					if (s.selectedNotes.length == 1)
						s.onSelectNote();
				}
				s.softReloadNotes();
			};
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Autosave Settings...', btnWid);
		btn.onClick = function() {
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;
			s.openSubState(new BasePrompt(400, 160, 'Autosave Settings', function(state:BasePrompt) {
				var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
				btn.cameras = state.cameras;
				state.add(btn);

				var checkbox:PsychUICheckBox = null;
				var timeStepper:PsychUINumericStepper = null;

				timeStepper = new PsychUINumericStepper(state.bg.x + 50, state.bg.y + 90, 1, s.autoSaveCap, 1, 30, 0);
				timeStepper.onValueChange = function() {
					s.autoSaveTime = 0;
					checkbox.checked = true;
					s.autoSaveCap = s.chartEditorSave.data.autoSave = Std.int(timeStepper.value);
				};
				timeStepper.cameras = state.cameras;

				checkbox = new PsychUICheckBox(timeStepper.x + 80, timeStepper.y, 'Enabled', 60, function() {
					s.autoSaveTime = 0;
					s.autoSaveCap = s.chartEditorSave.data.autoSave = checkbox.checked ? Std.int(timeStepper.value) : 0;
				});
				checkbox.checked = (s.autoSaveCap > 0);
				checkbox.cameras = state.cameras;

				var maxFileStepper:PsychUINumericStepper = new PsychUINumericStepper(checkbox.x + 140, checkbox.y, 1, s.backupLimit, 0, 50, 0);
				maxFileStepper.onValueChange = function() {
					s.autoSaveTime = 0;
					checkbox.checked = true;
					s.chartEditorSave.data.backupLimit = s.backupLimit = Std.int(maxFileStepper.value);
				};
				maxFileStepper.cameras = state.cameras;

				var txt1:FlxText = new FlxText(timeStepper.x, timeStepper.y - 15, 100, 'Time (in minutes):');
				txt1.cameras = state.cameras;
				var txt2:FlxText = new FlxText(maxFileStepper.x, maxFileStepper.y - 15, 100, 'File Limit:');
				txt2.cameras = state.cameras;

				state.add(txt1);
				state.add(txt2);
				state.add(checkbox);
				state.add(timeStepper);
				state.add(maxFileStepper);
			}));
		};
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Clear All Notes', function() {
			var func:Void->Void = function() {
				s.resetSelectedNotes();
				s.addUndoAction(UndoAction.DELETE_NOTE, {notes: s.notes.copy()});
				s.notes = [];
				s.loadSection();
			}

			if (!s.ignoreProgressCheckBox.checked)
				s.openSubState(new Prompt('Delete all Notes in the song?', func));
			else
				func();
		}, btnWid);
		btn.normalStyle.bgColor = FlxColor.RED;
		btn.normalStyle.textColor = FlxColor.WHITE;
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		if (ChartingState.SHOW_EVENT_COLUMN) {
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Clear All Events', function() {
				var func:Void->Void = function() {
					s.resetSelectedNotes();
					s.addUndoAction(UndoAction.DELETE_NOTE, {events: s.events.copy()});
					s.events = [];
					s.loadSection();
				}

				if (!s.ignoreProgressCheckBox.checked)
					s.openSubState(new Prompt('Delete all Events in the song?', func));
				else
					func();
			}, btnWid);
			btn.normalStyle.bgColor = FlxColor.RED;
			btn.normalStyle.textColor = FlxColor.WHITE;
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}
	}
}
