package legacy.editors.charting.tabs;

import legacy.editors.ChartingState;

/**
	Builds the "Charting" tab of the chart editor's main box: editor-only conveniences (playback rate,
	mouse-snap, hitsound/metronome volumes, per-track inst/vocal volume and mute). None of these affect
	gameplay. Reaches the editor's widget fields and audio hooks through `@:access`.
**/
@:access(legacy.editors.ChartingState)
class ChartingTab {
	/**
		Populates the Charting tab in `s.mainBox`.
		@param s the chart editor that owns the tab box and the widget fields assigned here
	**/
	public static function build(s:ChartingState):Void {
		var tab_group = s.mainBox.getTab('Charting').menu;
		var objX = 10;
		var objY = 10;

		var txt = new FlxText(objX, objY, 280, "Any options here won't actually affect gameplay!");
		txt.alignment = CENTER;
		tab_group.add(txt);

		objY += 25;
		s.playbackSlider = new PsychUISlider(50, objY, function(v:Float) s.setPitch(s.playbackRate = v), 1, 0.1, 5.0, 200);
		s.playbackSlider.label = 'Playback Rate';

		objY += 60;
		s.mouseSnapCheckBox = new PsychUICheckBox(objX, objY, 'Mouse Scroll Snap', 100,
			function() s.chartEditorSave.data.mouseScrollSnap = s.mouseSnapCheckBox.checked);
		s.mouseSnapCheckBox.checked = s.chartEditorSave.data.mouseScrollSnap;

		s.ignoreProgressCheckBox = new PsychUICheckBox(objX + 150, objY, 'Ignore Progress Warnings', 100,
			function() s.chartEditorSave.data.ignoreProgressWarns = s.ignoreProgressCheckBox.checked);
		s.ignoreProgressCheckBox.checked = s.chartEditorSave.data.ignoreProgressWarns;

		objY += 50;
		s.hitsoundPlayerStepper = new PsychUINumericStepper(objX, objY, 0.2, 0, 0, 1, 1);
		s.hitsoundOpponentStepper = new PsychUINumericStepper(objX + 100, objY, 0.2, 0, 0, 1, 1);
		s.metronomeStepper = new PsychUINumericStepper(objX + 200, objY, 0.2, 0, 0, 1, 1);

		objY += 50;
		s.instVolumeStepper = new PsychUINumericStepper(objX, objY, 0.1, 0.6, 0, 1, 1);
		s.instVolumeStepper.onValueChange = s.updateAudioVolume;
		s.playerVolumeStepper = new PsychUINumericStepper(objX + 100, objY, 0.1, 1, 0, 1, 1);
		s.playerVolumeStepper.onValueChange = s.updateAudioVolume;
		s.opponentVolumeStepper = new PsychUINumericStepper(objX + 200, objY, 0.1, 1, 0, 1, 1);
		s.opponentVolumeStepper.onValueChange = s.updateAudioVolume;

		objY += 25;
		s.instMuteCheckBox = new PsychUICheckBox(objX, objY, 'Mute', 60, s.updateAudioVolume);
		s.playerMuteCheckBox = new PsychUICheckBox(objX + 100, objY, 'Mute', 60, s.updateAudioVolume);
		s.opponentMuteCheckBox = new PsychUICheckBox(objX + 200, objY, 'Mute', 60, s.updateAudioVolume);

		tab_group.add(s.playbackSlider);
		tab_group.add(s.mouseSnapCheckBox);
		tab_group.add(s.ignoreProgressCheckBox);

		tab_group.add(new FlxText(s.hitsoundPlayerStepper.x, s.hitsoundPlayerStepper.y - 15, 100, 'Hitsound (Player):'));
		tab_group.add(new FlxText(s.hitsoundOpponentStepper.x, s.hitsoundOpponentStepper.y - 15, 100, 'Hitsound (Opp.):'));
		tab_group.add(new FlxText(s.metronomeStepper.x, s.metronomeStepper.y - 15, 100, 'Metronome:'));
		tab_group.add(s.hitsoundPlayerStepper);
		tab_group.add(s.hitsoundOpponentStepper);
		tab_group.add(s.metronomeStepper);

		tab_group.add(new FlxText(s.instVolumeStepper.x, s.instVolumeStepper.y - 15, 100, 'Inst. Volume:'));
		tab_group.add(new FlxText(s.playerVolumeStepper.x, s.playerVolumeStepper.y - 15, 100, 'Main Vocals:'));
		tab_group.add(new FlxText(s.opponentVolumeStepper.x, s.opponentVolumeStepper.y - 15, 100, 'Opp. Vocals:'));
		tab_group.add(s.instVolumeStepper);
		tab_group.add(s.instMuteCheckBox);
		tab_group.add(s.playerVolumeStepper);
		tab_group.add(s.playerMuteCheckBox);
		tab_group.add(s.opponentVolumeStepper);
		tab_group.add(s.opponentMuteCheckBox);
	}
}
