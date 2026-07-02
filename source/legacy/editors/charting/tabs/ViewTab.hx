package legacy.editors.charting.tabs;

import flixel.util.FlxStringUtil;
import editors.content.Prompt;
import legacy.editors.ChartingState;
import legacy.editors.ChartingState.ChartingTheme;
import legacy.editors.ChartingState.WaveformTarget;

/**
	Builds the "View" toolbar menu of the chart editor: grid/label visibility toggles, stage-event and FPS
	toggles, downscroll, the vortex editor, and the waveform / go-to / theme / reset-boxes windows. Toggles
	persist through the editor's save. Reaches editor state/widgets via `@:access`.
**/
@:access(legacy.editors.ChartingState)
class ViewTab {
	/**
		Populates the View toolbar menu in `s.upperBox`.
		@param s the chart editor that owns the toolbar and view state
	**/
	public static function build(s:ChartingState):Void {
		var tab = s.upperBox.getTab('View');
		var tab_group = tab.menu;
		var btnX = tab.x - s.upperBox.x;
		var btnY = 1;
		var btnWid = Std.int(tab.width);

		if (s.chartEditorSave.data.showStageEvents != null)
			s.showStageEvents = s.chartEditorSave.data.showStageEvents;
		if (s.chartEditorSave.data.waveformEnabled != null)
			s.waveformEnabled = s.chartEditorSave.data.waveformEnabled;
		if (s.chartEditorSave.data.waveformTarget != null)
			s.waveformTarget = s.chartEditorSave.data.waveformTarget;
		if (s.chartEditorSave.data.waveformColor != null)
			s.waveformSprite.color = CoolUtil.colorFromString(s.chartEditorSave.data.waveformColor);

		s.showLastGridButton = new PsychUIButton(btnX, btnY, '', function() {
			s.showPreviousSection = !s.showPreviousSection;
			s.updateGridVisibility();
		}, btnWid);
		s.showLastGridButton.text.alignment = LEFT;
		tab_group.add(s.showLastGridButton);

		btnY += 20;
		s.showNextGridButton = new PsychUIButton(btnX, btnY, '', function() {
			s.showNextSection = !s.showNextSection;
			s.updateGridVisibility();
		}, btnWid);
		s.showNextGridButton.text.alignment = LEFT;
		tab_group.add(s.showNextGridButton);

		btnY++;
		btnY += 20;
		s.noteTypeLabelsButton = new PsychUIButton(btnX, btnY, '', function() {
			s.showNoteTypeLabels = !s.showNoteTypeLabels;
			s.updateGridVisibility();
		}, btnWid);
		s.noteTypeLabelsButton.text.alignment = LEFT;
		tab_group.add(s.noteTypeLabelsButton);

		btnY++;
		btnY += 20;
		// Show/hide the vanilla stage/song-locked events in the Events dropdown.
		s.stageEventsButton = new PsychUIButton(btnX, btnY, '', function() {
			s.showStageEvents = !s.showStageEvents;
			s.chartEditorSave.data.showStageEvents = s.showStageEvents;
			s.chartEditorSave.flush();
			s.stageEventsButton.text.text = s.showStageEvents ? '  Stage Events: Shown' : '  Stage Events: Hidden';
			s.reloadNotesDropdowns();
		}, btnWid);
		s.stageEventsButton.text.text = s.showStageEvents ? '  Stage Events: Shown' : '  Stage Events: Hidden';
		s.stageEventsButton.text.alignment = LEFT;
		tab_group.add(s.stageEventsButton);

		btnY++;
		btnY += 20;
		// Toggle the global FPS counter without leaving the editor.
		s.fpsCounterButton = new PsychUIButton(btnX, btnY, '', function() {
			if (Main.fpsVar != null) {
				Main.fpsVar.visible = !Main.fpsVar.visible;
				s.fpsCounterButton.text.text = Main.fpsVar.visible ? '  FPS Counter: ON' : '  FPS Counter: OFF';
			}
		}, btnWid);
		s.fpsCounterButton.text.text = (Main.fpsVar != null && Main.fpsVar.visible) ? '  FPS Counter: ON' : '  FPS Counter: OFF';
		s.fpsCounterButton.text.alignment = LEFT;
		tab_group.add(s.fpsCounterButton);

		btnY++;
		btnY += 20;
		// Flip the whole timeline (downscroll). Reloads the section so grids/notes reposition.
		s.downScrollButton = new PsychUIButton(btnX, btnY, '', function() {
			ChartingState.downScroll = !ChartingState.downScroll;
			s.chartEditorSave.data.downScroll = ChartingState.downScroll;
			s.chartEditorSave.flush();
			s.downScrollButton.text.text = ChartingState.downScroll ? '  Downscroll: ON' : '  Downscroll: OFF';
			s.repositionAllNotesY(); // note Y is absolute world-space; recompute it for the new orientation
			s.createStrumLineNotes(); // receptor row mirrors to the other side of the center line
			s.vortexIndicator.y = s.strumLineY();
			s.positionTimeLine(); // time head shifts with the scroll direction
			s.loadSection();
			s.updateScrollY();
			s.waveform.redraw(s);
		}, btnWid);
		s.downScrollButton.text.text = ChartingState.downScroll ? '  Downscroll: ON' : '  Downscroll: OFF';
		s.downScrollButton.text.alignment = LEFT;
		tab_group.add(s.downScrollButton);

		btnY++;
		btnY += 20;
		s.vortexEditorButton = new PsychUIButton(btnX, btnY, s.vortexEnabled ? '  Vortex Editor ON' : '  Vortex Editor OFF', function() {
			s.vortexEnabled = !s.vortexEnabled;
			s.chartEditorSave.data.vortex = s.vortexEnabled;
			s.vortexIndicator.visible = s.strumLineNotes.visible = s.strumLineNotes.active = s.vortexEnabled;
			s.vortexEditorButton.text.text = s.vortexEnabled ? '  Vortex Editor ON' : '  Vortex Editor OFF';

			for (note in s.strumLineNotes) {
				note.playAnim('static');
				note.resetAnim = 0;
			}
			s.prevGridBg.vortexLineEnabled = s.gridBg.vortexLineEnabled = s.nextGridBg.vortexLineEnabled = s.vortexEnabled;
		}, btnWid);
		s.vortexEditorButton.text.alignment = LEFT;
		tab_group.add(s.vortexEditorButton);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Waveform...', function() {
			ClientPrefs.toggleVolumeKeys(false);
			s.openSubState(new BasePrompt(320, 200, 'Waveform Settings', function(state:BasePrompt) {
				s.upperBox.isMinimized = true;
				s.upperBox.bg.visible = false;

				var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
				btn.cameras = state.cameras;
				state.add(btn);

				var check:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, state.bg.y + 80, 'Enabled', 60);
				check.onClick = function() {
					s.chartEditorSave.data.waveformEnabled = s.waveformEnabled = check.checked;
					s.waveform.redraw(s);
				};
				check.cameras = state.cameras;
				check.checked = s.waveformEnabled;
				state.add(check);

				var waveformC:String = '0000FF';
				if (s.chartEditorSave.data.waveformColor != null)
					waveformC = s.chartEditorSave.data.waveformColor;

				var input:PsychUIInputText = new PsychUIInputText(check.x, check.y + 50, 60, waveformC, 10);
				input.onChange = function(old:String, cur:String) {
					s.chartEditorSave.data.waveformColor = cur;
					s.waveformSprite.color = CoolUtil.colorFromString(cur);
				}
				input.maxLength = 6;
				input.filterMode = ONLY_HEXADECIMAL;
				input.cameras = state.cameras;
				input.forceCase = UPPER_CASE;

				var options:Array<WaveformTarget> = [INST, PLAYER, OPPONENT];
				var radioGrp:PsychUIRadioGroup = new PsychUIRadioGroup(check.x + 120, check.y, ['Instrumental', 'Main Vocals', 'Opponent Vocals']);
				radioGrp.cameras = state.cameras;
				radioGrp.onClick = function() {
					s.waveformTarget = s.chartEditorSave.data.waveformTarget = options[radioGrp.checked];
					s.waveform.redraw(s);
				};
				radioGrp.checked = options.indexOf(s.waveformTarget);
				state.add(radioGrp);

				var txt1:FlxText = new FlxText(input.x, input.y - 15, 80, 'Color (Hex):');
				txt1.cameras = state.cameras;
				state.add(txt1);
				state.add(input);
			}));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Go to...', function() {
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;
			s.openSubState(new BasePrompt(420, 200, 'Go to Time/Section:', function(state:BasePrompt) {
				var curTime:Float = Conductor.songPosition;
				var currentSec:Int = s.curSec;

				var timeStepper:PsychUINumericStepper = new PsychUINumericStepper(state.bg.x + 100, state.bg.y + 90, 1, Math.floor(curTime) / 1000, 0,
					FlxG.sound.music.length / 1000 - 0.01, 2, 80);
				timeStepper.cameras = state.cameras;
				var sectionStepper:PsychUINumericStepper = new PsychUINumericStepper(timeStepper.x + 160, timeStepper.y, 1, currentSec, 0,
					PlayState.SONG.notes.length - 1, 0);
				sectionStepper.cameras = state.cameras;

				var txt1:FlxText = new FlxText(timeStepper.x, timeStepper.y - 15, 100, 'Time (in seconds):');
				var txt2:FlxText = new FlxText(sectionStepper.x, sectionStepper.y - 15, 100, 'Section:');
				txt1.cameras = state.cameras;
				txt2.cameras = state.cameras;
				state.add(txt1);
				state.add(txt2);
				state.add(timeStepper);
				state.add(sectionStepper);

				var timeTxt:FlxText = new FlxText(15, state.bg.y + state.bg.height - 75, 230, '', 16);
				timeTxt.alignment = CENTER;
				timeTxt.screenCenter(X);
				timeTxt.cameras = state.cameras;
				state.add(timeTxt);
				function updateTime() {
					var tm:String = FlxStringUtil.formatTime(curTime / 1000, true);
					var ln:String = FlxStringUtil.formatTime(FlxG.sound.music.length / 1000, true);
					timeTxt.text = '$tm / $ln';
				}
				updateTime();

				timeStepper.onValueChange = function() {
					curTime = timeStepper.value * 1000;
					for (i => time in s.cachedSectionTimes) {
						if (time <= curTime)
							currentSec = i;
						else
							break;
					}
					updateTime();
				};
				sectionStepper.onValueChange = function() {
					currentSec = Std.int(sectionStepper.value);
					curTime = s.cachedSectionTimes[currentSec] + 0.000001;
					updateTime();
				};

				var btn:PsychUIButton = new PsychUIButton(0, timeTxt.y + 30, 'Go To', function() {
					s.curSec = currentSec;
					FlxG.sound.music.time = FlxMath.bound(curTime, 0, FlxG.sound.music.length - 1);
					s.loadSection();
					state.close();
				});
				btn.cameras = state.cameras;
				btn.screenCenter(X);
				btn.x -= 60;
				state.add(btn);

				var btn:PsychUIButton = new PsychUIButton(0, btn.y, 'Cancel', state.close);
				btn.cameras = state.cameras;
				btn.screenCenter(X);
				btn.x += 60;
				state.add(btn);
			}));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Theme...', function() {
			if (!s.fileDialog.completed)
				return;
			s.upperBox.isMinimized = true;
			s.upperBox.bg.visible = false;

			s.openSubState(new BasePrompt(500, 260, 'Chart Editor Theme', function(state:BasePrompt) {
				var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
				btn.cameras = state.cameras;
				state.add(btn);

				var btnY = 320;
				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Light', s.changeTheme.bind(ChartingTheme.LIGHT));
				btn.screenCenter(X);
				btn.x -= 180;
				btn.cameras = state.cameras;
				state.add(btn);

				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Dark', s.changeTheme.bind(ChartingTheme.DARK));
				btn.screenCenter(X);
				btn.x -= 60;
				btn.cameras = state.cameras;
				state.add(btn);

				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Default', s.changeTheme.bind(ChartingTheme.DEFAULT));
				btn.screenCenter(X);
				btn.cameras = state.cameras;
				btn.x += 60;
				state.add(btn);

				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'V-Slice', s.changeTheme.bind(ChartingTheme.VSLICE));
				btn.screenCenter(X);
				btn.x += 180;
				btn.cameras = state.cameras;
				state.add(btn);

				btnY += 60;
				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Custom', s.changeTheme.bind(ChartingTheme.CUSTOM));
				btn.screenCenter(X);
				btn.x -= 180;
				btn.cameras = state.cameras;
				state.add(btn);

				var customBgC:String = '303030';
				if (s.chartEditorSave.data.customBgColor != null)
					customBgC = s.chartEditorSave.data.customBgColor;

				var input:PsychUIInputText = new PsychUIInputText(0, btnY, 80, customBgC, 10);
				input.maxLength = 6;
				input.filterMode = ONLY_HEXADECIMAL;
				input.forceCase = UPPER_CASE;
				input.screenCenter(X);
				input.x -= 60;
				input.cameras = state.cameras;
				input.onChange = function(old:String, cur:String) {
					s.chartEditorSave.data.customBgColor = cur;
					s.changeTheme(ChartingTheme.CUSTOM);
				}

				var txt:FlxText = new FlxText(input.x, input.y - 15, 120, 'BG Color:');
				txt.cameras = state.cameras;
				state.add(txt);
				state.add(input);

				var customGridC:Array<String> = ['DFDFDF', 'BFBFBF'];
				if (s.chartEditorSave.data.customGridColors != null && s.chartEditorSave.data.customGridColors.length > 1)
					customGridC = s.chartEditorSave.data.customGridColors;

				var input:PsychUIInputText = new PsychUIInputText(0, btnY, 80, customGridC[0], 10);
				input.maxLength = 6;
				input.filterMode = ONLY_HEXADECIMAL;
				input.forceCase = UPPER_CASE;
				input.screenCenter(X);
				input.x += 60;
				input.cameras = state.cameras;
				input.onChange = function(old:String, cur:String) {
					s.chartEditorSave.data.customGridColors[0] = cur;
					s.changeTheme(ChartingTheme.CUSTOM);
				}

				var txt:FlxText = new FlxText(input.x, input.y - 15, 120, 'Grid Colors:');
				txt.cameras = state.cameras;
				state.add(txt);
				state.add(input);

				var input:PsychUIInputText = new PsychUIInputText(0, btnY + 30, 80, customGridC[1], 10);
				input.maxLength = 6;
				input.filterMode = ONLY_HEXADECIMAL;
				input.forceCase = UPPER_CASE;
				input.screenCenter(X);
				input.x += 60;
				input.cameras = state.cameras;
				input.onChange = function(old:String, cur:String) {
					s.chartEditorSave.data.customGridColors[1] = cur;
					s.changeTheme(ChartingTheme.CUSTOM);
				}
				state.add(input);

				var customGridOtherC:Array<String> = ['5F5F5F', '4A4A4A'];
				if (s.chartEditorSave.data.customNextGridColors != null && s.chartEditorSave.data.customNextGridColors.length > 1)
					customGridOtherC = s.chartEditorSave.data.customNextGridColors;

				var input:PsychUIInputText = new PsychUIInputText(0, btnY, 80, customGridOtherC[0], 10);
				input.maxLength = 6;
				input.filterMode = ONLY_HEXADECIMAL;
				input.forceCase = UPPER_CASE;
				input.screenCenter(X);
				input.x += 180;
				input.cameras = state.cameras;
				input.onChange = function(old:String, cur:String) {
					s.chartEditorSave.data.customNextGridColors[0] = cur;
					s.changeTheme(ChartingTheme.CUSTOM);
				}

				var txt:FlxText = new FlxText(input.x, input.y - 15, 120, 'Next Grid Colors:');
				txt.cameras = state.cameras;
				state.add(txt);
				state.add(input);

				var input:PsychUIInputText = new PsychUIInputText(0, btnY + 30, 80, customGridOtherC[1], 10);
				input.maxLength = 6;
				input.filterMode = ONLY_HEXADECIMAL;
				input.forceCase = UPPER_CASE;
				input.screenCenter(X);
				input.x += 180;
				input.cameras = state.cameras;
				input.onChange = function(old:String, cur:String) {
					s.chartEditorSave.data.customNextGridColors[1] = cur;
					s.changeTheme(ChartingTheme.CUSTOM);
				}
				state.add(input);
			}));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '  Reset UI Boxes', function() {
			s.mainBox.setPosition(s.mainBoxPosition.x, s.mainBoxPosition.y);
			s.infoBox.setPosition(s.infoBoxPosition.x, s.infoBoxPosition.y);
			s.UIEvent(PsychUIBox.DROP_EVENT, btn); // to force a save
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
	}
}
