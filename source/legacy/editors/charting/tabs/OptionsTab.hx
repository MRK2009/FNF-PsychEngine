package legacy.editors.charting.tabs;

import legacy.editors.ChartingState;

/**
	Builds the "Options" toolbar menu of the chart editor: the character-preview window opener, the quant
	note-color toggle, the metronome sound/accent toggles, and the time-signature / BPM note-adaptation mode
	cyclers. All settings persist through the editor's save. Reaches editor state/widgets via `@:access`.
**/
@:access(legacy.editors.ChartingState)
class OptionsTab {
	/**
		Populates the Options toolbar menu in `s.upperBox`.
		@param s the chart editor that owns the toolbar and option state
	**/
	public static function build(s:ChartingState):Void {
		var tab = s.upperBox.getTab('Options');
		var tab_group = tab.menu;
		var btnX = tab.x - s.upperBox.x;
		var btnY = 1;
		var btnWid = Std.int(tab.width);

		// Load persisted preferences.
		if (s.chartEditorSave.data.quantColors != null) s.quantNoteColors = s.chartEditorSave.data.quantColors;
		if (s.chartEditorSave.data.metronomePreset != null)
			s.metronomePresetIndex = Std.int(FlxMath.bound(s.chartEditorSave.data.metronomePreset, 0, ChartingState.METRONOME_PRESETS.length - 1));
		if (s.chartEditorSave.data.metronomeAccent != null) s.metronomeAccent = s.chartEditorSave.data.metronomeAccent;

		// --- Character preview: opens a small settings window ---
		var charPrefsButton:PsychUIButton = new PsychUIButton(btnX, btnY, '  Character Preview...', function() {
			s.charPreview.openPrompt();
		}, btnWid);
		charPrefsButton.text.alignment = LEFT;
		tab_group.add(charPrefsButton);

		// --- Quant note colors ---
		btnY += 20;
		var quantButton:PsychUIButton = null;
		quantButton = new PsychUIButton(btnX, btnY, '', function() {
			s.quantNoteColors = !s.quantNoteColors;
			s.chartEditorSave.data.quantColors = s.quantNoteColors;
			s.chartEditorSave.flush();
			quantButton.text.text = s.quantNoteColors ? '  Quant Colors: ON' : '  Quant Colors: OFF';
			s.refreshNoteColors();
		}, btnWid);
		quantButton.text.text = s.quantNoteColors ? '  Quant Colors: ON' : '  Quant Colors: OFF';
		quantButton.text.alignment = LEFT;
		tab_group.add(quantButton);

		// --- Metronome ---
		btnY += 20;
		var metroSoundButton:PsychUIButton = null;
		metroSoundButton = new PsychUIButton(btnX, btnY, '', function() {
			s.metronomePresetIndex = (s.metronomePresetIndex + 1) % ChartingState.METRONOME_PRESETS.length;
			s.chartEditorSave.data.metronomePreset = s.metronomePresetIndex;
			s.chartEditorSave.flush();
			metroSoundButton.text.text = '  Metronome: ${ChartingState.METRONOME_PRESETS[s.metronomePresetIndex].name}';
			if (s.metronomeStepper != null && s.metronomeStepper.value > 0)
				FlxG.sound.play(Paths.sound(ChartingState.METRONOME_PRESETS[s.metronomePresetIndex].sound), s.metronomeStepper.value);
		}, btnWid);
		metroSoundButton.text.text = '  Metronome: ${ChartingState.METRONOME_PRESETS[s.metronomePresetIndex].name}';
		metroSoundButton.text.alignment = LEFT;
		tab_group.add(metroSoundButton);

		btnY += 20;
		var accentButton:PsychUIButton = null;
		accentButton = new PsychUIButton(btnX, btnY, '', function() {
			s.metronomeAccent = !s.metronomeAccent;
			s.chartEditorSave.data.metronomeAccent = s.metronomeAccent;
			s.chartEditorSave.flush();
			accentButton.text.text = s.metronomeAccent ? '  Accent: ON' : '  Accent: OFF';
		}, btnWid);
		accentButton.text.text = s.metronomeAccent ? '  Accent: ON' : '  Accent: OFF';
		accentButton.text.alignment = LEFT;
		tab_group.add(accentButton);

		// --- Time-signature note adaptation (how notes follow a numerator/denominator edit) ---
		btnY += 20;
		var adaptButton:PsychUIButton = null;
		adaptButton = new PsychUIButton(btnX, btnY, '', function() {
			s.noteAdaptMode = (s.noteAdaptMode + 1) % ChartingState.ADAPT_LABELS.length;
			s.chartEditorSave.data.noteAdaptMode = s.noteAdaptMode;
			s.chartEditorSave.flush();
			adaptButton.text.text = '  Time Sig: ${ChartingState.ADAPT_SHORT[s.noteAdaptMode]}';
		}, btnWid);
		adaptButton.text.text = '  Time Sig: ${ChartingState.ADAPT_SHORT[s.noteAdaptMode]}';
		adaptButton.text.alignment = LEFT;
		tab_group.add(adaptButton);

		// --- BPM note adaptation (how notes follow a BPM edit) ---
		btnY += 20;
		var bpmAdaptButton:PsychUIButton = null;
		bpmAdaptButton = new PsychUIButton(btnX, btnY, '', function() {
			s.bpmAdaptMode = (s.bpmAdaptMode + 1) % ChartingState.ADAPT_LABELS.length;
			s.chartEditorSave.data.bpmAdaptMode = s.bpmAdaptMode;
			s.chartEditorSave.flush();
			bpmAdaptButton.text.text = '  BPM: ${ChartingState.ADAPT_SHORT[s.bpmAdaptMode]}';
		}, btnWid);
		bpmAdaptButton.text.text = '  BPM: ${ChartingState.ADAPT_SHORT[s.bpmAdaptMode]}';
		bpmAdaptButton.text.alignment = LEFT;
		tab_group.add(bpmAdaptButton);
	}
}
