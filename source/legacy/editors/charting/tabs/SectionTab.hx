package legacy.editors.charting.tabs;

import legacy.editors.ChartingState;
import legacy.editors.ChartingState.UndoAction;

/**
	Builds the "Section" tab of the chart editor's main box: per-section flags (must-hit, gf, alt-anim),
	the BPM / time-signature / scroll-speed / key-count overrides, and the copy/paste/clear/swap/duet/mirror
	section operations. The bulk of timing edits route through the editor's note-adapt path. Reaches editor
	state/widgets via `@:access`.
**/
@:access(legacy.editors.ChartingState)
class SectionTab {
	/**
		Populates the Section tab in `s.mainBox`.
		@param s the chart editor that owns the tab box, section widgets and clipboard
	**/
	public static function build(s:ChartingState):Void {
		var affectNotes:PsychUICheckBox = null;
		var affectEvents:PsychUICheckBox = null;
		var copyLastSecStepper:PsychUINumericStepper = null;
		var tab_group = s.mainBox.getTab('Section').menu;
		var objX = 10;
		var objY = 10;
		function copyNotesOnSection(?secOff:Int = 0, ?showMessage:Bool = true) // Used on "Copy Section" and "Copy Last Section" buttons
		{
			var curSectionTime:Null<Float> = s.cachedSectionTimes[s.curSec - secOff];
			if (curSectionTime == null) {
				// showOutput('ERROR: Unknown section??', true);
				return;
			}

			var nextSectionTime:Null<Float> = s.cachedSectionTimes[s.curSec - secOff + 1];
			if (nextSectionTime == null)
				Math.POSITIVE_INFINITY;

			var notesCopyNum:Int = 0;
			if (affectNotes.checked) {
				s.copiedNotes = [];
				for (note in s.notes) {
					if (note.strumTime >= curSectionTime && note.strumTime < nextSectionTime) {
						var dataCopy:Array<Dynamic> = s.makeNoteDataCopy(note.songData, false);
						dataCopy[0] = note.strumTime - curSectionTime;
						s.copiedNotes.push(dataCopy);
						notesCopyNum++;
					}
				}
			}

			var eventsCopyNum:Int = 0;
			if (affectEvents.checked) {
				s.copiedEvents = [];
				for (event in s.events) {
					if (event.strumTime >= curSectionTime && event.strumTime < nextSectionTime) {
						var dataCopy:Array<Dynamic> = s.makeNoteDataCopy(event.songData, true);
						dataCopy[0] = event.strumTime - curSectionTime;
						s.copiedEvents.push(dataCopy);
						eventsCopyNum++;
					}
				}
			}

			if (showMessage) {
				if (notesCopyNum == 0 && eventsCopyNum == 0) {
					s.showOutput('Nothing to copy!', true);
					return;
				}

				var str:String = '';
				if (notesCopyNum > 0)
					str += 'Notes Copied: $notesCopyNum';
				if (eventsCopyNum > 0) {
					if (str.length > 0)
						str += '\n';
					str += 'Events Copied: $eventsCopyNum';
				}

				if (str.length > 0)
					s.showOutput(str);
			}
		}

		s.mustHitCheckBox = new PsychUICheckBox(objX, objY, 'Must Hit Sec.', 70, function() {
			var sec = s.getCurChartSection();
			if (sec != null)
				sec.mustHitSection = s.mustHitCheckBox.checked;
			s.updateHeads(true);
		});
		s.gfSectionCheckBox = new PsychUICheckBox(objX + 100, objY, 'GF Section', 70, function() {
			var sec = s.getCurChartSection();
			if (sec != null)
				sec.gfSection = s.gfSectionCheckBox.checked;
			s.updateHeads(true);
		});
		s.altAnimSectionCheckBox = new PsychUICheckBox(objX + 200, objY, 'Alt Anim', 70, function() {
			var sec = s.getCurChartSection();
			if (sec != null)
				sec.altAnim = s.altAnimSectionCheckBox.checked;
		});

		objY += 35;
		s.changeBpmCheckBox = new PsychUICheckBox(objX, objY, 'Change BPM', 80, function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
				sec.changeBPM = s.changeBpmCheckBox.checked;
				if (!Reflect.hasField(sec, 'bpm'))
					sec.bpm = s.changeBpmStepper.value;
				s.adaptNotesToNewTimes(oldTimes, s.bpmAdaptMode);
			}
		});

		// Per-section time signature override, gated like Change BPM. Off == inherit
		// the song's base time signature (see Conductor.getSectionBeats).
		s.changeTimeSigCheckBox = new PsychUICheckBox(objX + 150, objY, 'Change Time Sig.', 110, function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
				sec.changeTimeSignature = s.changeTimeSigCheckBox.checked;
				if (s.changeTimeSigCheckBox.checked) {
					sec.sectionBeats = s.beatsPerSecStepper.value;
					sec.sectionDenominator = Std.int(s.denominatorStepper.value);
				}
				s.adaptNotesToNewTimes(oldTimes);
			}
		});

		objY += 25;
		s.changeBpmStepper = new PsychUINumericStepper(objX, objY, 1, 0, 1, 400, 3);
		s.changeBpmStepper.onValueChange = function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
				sec.bpm = s.changeBpmStepper.value;
				sec.changeBPM = true;
				s.changeBpmCheckBox.checked = true;
				s.adaptNotesToNewTimes(oldTimes, s.bpmAdaptMode);
			}
		};

		s.beatsPerSecStepper = new PsychUINumericStepper(objX + 150, objY, 1, 4, 1, 16, 2, 50);
		s.beatsPerSecStepper.onValueChange = function() {
			s.beatsPerSecStepper.value = Math.round(s.beatsPerSecStepper.value * 4) / 4;
			var sec = s.getCurChartSection();
			if (sec != null) {
				var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
				sec.sectionBeats = s.beatsPerSecStepper.value;
				sec.changeTimeSignature = true;
				s.changeTimeSigCheckBox.checked = true;
				s.adaptNotesToNewTimes(oldTimes);
			}
		};

		// Time-signature denominator. Only powers of two {1,2,4,8,16} are valid (so
		// 16/denominator is an integer), so we snap to the next/previous power of two
		// relative to the section's current value instead of stepping by 1.
		s.denominatorStepper = new PsychUINumericStepper(objX + 210, objY, 1, 4, 1, 16, 0, 50);
		s.denominatorStepper.onValueChange = function() {
			var sec = s.getCurChartSection();
			if (sec == null) {
				s.denominatorStepper.value = 4;
				return;
			}
			var cur:Int = Conductor.getSectionDenominator(PlayState.SONG, s.curSec);
			var v:Int = Std.int(s.denominatorStepper.value);
			var snapped:Int = (v > cur) ? Std.int(Math.min(16, cur * 2)) : (v < cur ? Std.int(Math.max(1, Std.int(cur / 2))) : cur);
			s.denominatorStepper.value = snapped;

			var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
			sec.sectionDenominator = snapped;
			sec.changeTimeSignature = true;
			s.changeTimeSigCheckBox.checked = true;
			s.adaptNotesToNewTimes(oldTimes);
		};

		// Per-section scroll speed override (gated like Change BPM). Applied at the
		// section boundary in gameplay (PlayState.sectionHit).
		objY += 30;
		s.changeScrollSpeedCheckBox = new PsychUICheckBox(objX, objY, 'Change Scroll Speed', 130, function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				sec.changeScrollSpeed = s.changeScrollSpeedCheckBox.checked;
				if (sec.scrollSpeed == null)
					sec.scrollSpeed = s.scrollSpeedStepperSec.value;
			}
		});
		s.scrollSpeedStepperSec = new PsychUINumericStepper(objX + 150, objY, 0.1, 1, 0.1, 10, 2);
		s.scrollSpeedStepperSec.onValueChange = function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				sec.scrollSpeed = s.scrollSpeedStepperSec.value;
				sec.changeScrollSpeed = true;
				s.changeScrollSpeedCheckBox.checked = true;
			}
		};

		// Per-section key count override (multikey mid-song lane change). Gameplay
		// rebuilds the strums + input when crossing into this section.
		objY += 30;
		s.changeKeyCountCheckBox = new PsychUICheckBox(objX, objY, 'Change Key Amount', 130, function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				s.updateChartData();
				var old:Array<Int> = s.snapshotEffectives();
				sec.changeKeyCount = s.changeKeyCountCheckBox.checked;
				if (sec.keyCount == null)
					sec.keyCount = Std.int(s.keyCountStepperSec.value);
				s.commitKeyCountChange(old);
			}
		});
		s.keyCountStepperSec = new PsychUINumericStepper(objX + 150, objY, 1, ChartingState.GRID_COLUMNS_PER_PLAYER, Mania.MIN, Mania.MAX, 0);
		s.keyCountStepperSec.onValueChange = function() {
			var sec = s.getCurChartSection();
			if (sec != null) {
				s.updateChartData();
				var old:Array<Int> = s.snapshotEffectives();
				sec.keyCount = Std.int(s.keyCountStepperSec.value);
				sec.changeKeyCount = true;
				s.changeKeyCountCheckBox.checked = true;
				s.commitKeyCountChange(old);
			}
		};

		objY += 35;
		var copyButton:PsychUIButton = new PsychUIButton(objX, objY, 'Copy Section', copyNotesOnSection.bind());
		var pasteButton:PsychUIButton = new PsychUIButton(objX + 100, objY, 'Paste Section', function() {
			s.pasteCopiedNotesToSection(affectNotes.checked, affectEvents.checked);
		});
		var clearButton:PsychUIButton = new PsychUIButton(objX + 200, objY, 'Clear', function() {
			for (note in s.curRenderedNotes) {
				if (note == null || note.data == null)
					continue;

				if (!note.isEvent && affectNotes.checked)
					s.notes.remove(note.data);
				if (note.isEvent && affectEvents.checked)
					s.events.remove(note.data);

				s.selectedNotes.remove(note.data);
			}
			s.softReloadNotes(true);
		});
		clearButton.normalStyle.bgColor = FlxColor.RED;
		clearButton.normalStyle.textColor = FlxColor.WHITE;

		objY += 25;
		affectNotes = new PsychUICheckBox(objX, objY, 'Notes', 60);
		affectNotes.checked = true;
		affectEvents = new PsychUICheckBox(objX + 100, objY, 'Events', 60);

		objY += 32;
		var copyLastSecButton:PsychUIButton = new PsychUIButton(objX, objY, 'Copy Last Section', function() {
			var lastCopiedNotes = s.copiedNotes;
			var lastCopiedEvents = s.copiedEvents;
			copyNotesOnSection(Std.int(copyLastSecStepper.value), false);
			s.pasteCopiedNotesToSection(affectNotes.checked, affectEvents.checked);
			s.copiedNotes = lastCopiedNotes;
			s.copiedEvents = lastCopiedEvents;
		});
		copyLastSecButton.resize(80, 26);
		copyLastSecStepper = new PsychUINumericStepper(objX + 110, objY + 2, 1, 1, -999, 999, 0);

		objY += 40;
		var swapSectionButton:PsychUIButton = new PsychUIButton(objX, objY, 'Swap Section', function() {
			var maxData:Int = ChartingState.GRID_COLUMNS_PER_PLAYER * ChartingState.GRID_PLAYERS;
			for (note in s.curRenderedNotes) {
				if (note != null && note.data != null && !note.isEvent) {
					var data:Int = note.songData[1] + ChartingState.GRID_COLUMNS_PER_PLAYER;
					if (data >= maxData)
						data -= maxData;
					note.changeNoteData(data);
					s.positionNoteXByData(note.data);
				}
			}
			s.hardRefreshNotes();
		});
		var duetSectionButton:PsychUIButton = new PsychUIButton(objX + 100, objY, 'Duet Section', function() {
			var side:Int = -1;
			for (note in s.curRenderedNotes.members) {
				if (note == null || note.data == null || note.isEvent)
					continue;

				// First figure out if there are notes on more than one player's sides to cancel operation early
				if (side > -1) {
					if (Math.floor(note.songData[1] / ChartingState.GRID_COLUMNS_PER_PLAYER) != side) {
						s.showOutput('You cannot press this button with notes on more than one side.');
						return;
					}
				} else
					side = Math.floor(note.songData[1] / ChartingState.GRID_COLUMNS_PER_PLAYER);
			}

			var pushedNotes:Array<ChartNote> = [];
			for (note in s.curRenderedNotes.members) {
				if (note == null || note.data == null || note.isEvent)
					continue;

				for (i in 0...ChartingState.GRID_PLAYERS) {
					if (i == side)
						continue;

					var songDataCopy:Array<Dynamic> = note.songData.copy();
					songDataCopy[1] = note.noteData + i * ChartingState.GRID_COLUMNS_PER_PLAYER;
					var newNote = s.createNote(songDataCopy);
					s.notes.push(newNote);
					pushedNotes.push(newNote);
				}
			}
			s.notes.sort(PlayState.sortByTime);
			s.softReloadNotes(true);

			s.addUndoAction(UndoAction.ADD_NOTE, {notes: pushedNotes});
		});
		var mirrorNotesButton:PsychUIButton = new PsychUIButton(objX + 200, objY, 'Mirror Notes', function() {
			var maxData:Int = ChartingState.GRID_COLUMNS_PER_PLAYER * ChartingState.GRID_PLAYERS;
			for (note in s.curRenderedNotes) {
				if (note == null || note.data == null || note.isEvent)
					continue;

				var data:Int = Std.int(note.songData[1]);
				note.changeNoteData((Math.floor(data / ChartingState.GRID_COLUMNS_PER_PLAYER) * ChartingState.GRID_COLUMNS_PER_PLAYER) + ChartingState.GRID_COLUMNS_PER_PLAYER - note.noteData - 1);
				s.positionNoteXByData(note.data);
			}
			s.hardRefreshNotes();
		});

		tab_group.add(s.mustHitCheckBox);
		tab_group.add(s.gfSectionCheckBox);
		tab_group.add(s.altAnimSectionCheckBox);

		// No "Time Signature:" label here -- the "Change Time Sig." checkbox above
		// the steppers already names them. Just the num/den separator.
		tab_group.add(new FlxText(s.denominatorStepper.x - 12, s.denominatorStepper.y + 3, 12, '/'));
		tab_group.add(s.changeBpmCheckBox);
		tab_group.add(s.changeTimeSigCheckBox);
		tab_group.add(s.changeBpmStepper);
		tab_group.add(s.beatsPerSecStepper);
		tab_group.add(s.denominatorStepper);
		tab_group.add(s.changeScrollSpeedCheckBox);
		tab_group.add(s.scrollSpeedStepperSec);
		tab_group.add(s.changeKeyCountCheckBox);
		tab_group.add(s.keyCountStepperSec);

		tab_group.add(copyButton);
		tab_group.add(pasteButton);
		tab_group.add(clearButton);
		tab_group.add(affectNotes);
		tab_group.add(affectEvents);

		tab_group.add(copyLastSecButton);
		tab_group.add(copyLastSecStepper);

		tab_group.add(swapSectionButton);
		tab_group.add(duetSectionButton);
		tab_group.add(mirrorNotesButton);
	}
}
