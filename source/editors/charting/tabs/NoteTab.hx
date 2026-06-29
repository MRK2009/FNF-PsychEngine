package editors.charting.tabs;

import editors.ChartingState;

/**
	Builds the "Note" tab of the chart editor's main box: sustain length, hit-time and note-type controls
	for the currently selected note(s). Edits mutate selected notes and refresh the field through the
	editor. Reaches editor state/widgets via `@:access`.
**/
@:access(editors.ChartingState)
class NoteTab {
	/**
		Populates the Note tab in `s.mainBox`.
		@param s the chart editor that owns the tab box and the selected-note state
	**/
	public static function build(s:ChartingState):Void {
		var tab_group = s.mainBox.getTab('Note').menu;
		var objX = 10;
		var objY = 25;

		s.susLengthStepper = new PsychUINumericStepper(objX, objY, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 128, 1, 80);
		s.susLengthStepper.onValueChange = function() {
			var halfStep:Float = (Conductor.stepCrochet / 2);
			trace(halfStep, s.susLengthStepper.value);
			var val:Float = Math.round(s.susLengthStepper.value / halfStep) * halfStep;
			s.susLengthStepper.value = val;
			if (s.susLengthLastVal != s.susLengthStepper.value) {
				if (s.selectedNotes.length > 1) {
					for (note in s.selectedNotes) {
						if (note == null && !note.isEvent)
							continue;
						note.setSustainLength(note.sustainLength + (s.susLengthStepper.value - s.susLengthLastVal), Conductor.stepCrochet, s.curZoom);
					}
				} else if (s.selectedNotes.length == 1)
					s.selectedNotes[0].setSustainLength(s.susLengthStepper.value, Conductor.stepCrochet, s.curZoom);
				s.susLengthLastVal = s.susLengthStepper.value;
			}
		};

		objY += 40;
		s.strumTimeStepper = new PsychUINumericStepper(objX, objY, Conductor.stepCrochet, 0, -5000, Math.POSITIVE_INFINITY, 3, 120);
		s.strumTimeStepper.onValueChange = function() {
			if (s.selectedNotes.length < 1)
				return;

			var firstTime:Float = s.selectedNotes[0].strumTime;
			for (note in s.selectedNotes) {
				if (note == null)
					continue;

				note.setStrumTime(Math.max(-5000, s.strumTimeStepper.value + (note.strumTime - firstTime)));
				s.positionNoteYOnTime(note, s.curSec);

				if (note.isEvent)
					note.updateEventText();
			}
			s.softReloadNotes();
		};

		objY += 40;
		s.noteTypeDropDown = new PsychUIDropDownMenu(objX, objY, [], function(id:Int, changeToType:String) {
			var newSelected:Array<ChartNote> = [];
			var typeSelected:String = s.noteTypes[id].trim();
			for (note in s.selectedNotes) {
				if (note == null || note.isEvent)
					continue;

				if (typeSelected != null && typeSelected.length > 0)
					note.songData[3] = typeSelected;
				else
					note.songData.remove(note.songData[3]);

				var id:Int = s.notes.indexOf(note);
				if (id > -1) {
					s.notes[id] = s.createNote(note.songData, s.curSec);
					s.actionReplaceNotes(note, s.notes[id]);
					newSelected.push(s.notes[id]);
					note.destroy();
				}
			}
			s.selectedNotes = newSelected;
			s.softReloadNotes();
		}, 150);

		tab_group.add(new FlxText(s.susLengthStepper.x, s.susLengthStepper.y - 15, 80, 'Sustain length:'));
		tab_group.add(new FlxText(s.strumTimeStepper.x, s.strumTimeStepper.y - 15, 100, 'Note Hit time (ms):'));
		tab_group.add(new FlxText(s.noteTypeDropDown.x, s.noteTypeDropDown.y - 15, 80, 'Note Type:'));
		tab_group.add(s.susLengthStepper);
		tab_group.add(s.strumTimeStepper);
		tab_group.add(s.noteTypeDropDown);
	}
}
