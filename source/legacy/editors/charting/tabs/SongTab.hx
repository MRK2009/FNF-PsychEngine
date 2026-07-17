package legacy.editors.charting.tabs;

import backend.StageData;
import backend.Song; // provides Song + the SwagSong typedef (used by the #if mac Reload JSON button)
import backend.Highscore;
import legacy.editors.content.Prompt;
import legacy.editors.ChartingState;

/**
	Builds the "Song" tab of the chart editor's main box: song name / vocals / audio reload, BPM, scroll
	speed, audio offset, base time signature, key count, and the stage/character dropdowns. Owns
	`applyBaseTimeSignature`, which propagates the base signature to every section. Reaches editor
	state/widgets via `@:access`.
**/
@:access(legacy.editors.ChartingState)
class SongTab {
	/**
		Populates the Song tab in `s.mainBox`.
		@param s the chart editor that owns the tab box and the song-level widgets
	**/
	public static function build(s:ChartingState):Void {
		var tab_group = s.mainBox.getTab('Song').menu;
		var objX = 10;
		var objY = 25;

		s.songNameInputText = new PsychUIInputText(objX, objY, 100, 'None', 8);
		s.songNameInputText.onChange = function(old:String, cur:String) PlayState.SONG.song = cur;

		s.allowVocalsCheckBox = new PsychUICheckBox(objX, objY + 20, 'Allow Vocals', 80, function() {
			PlayState.SONG.needsVoices = s.allowVocalsCheckBox.checked;
			s.loadMusic();
		});
		var reloadAudioButton:PsychUIButton = new PsychUIButton(objX + 120, objY, 'Reload Audio', function() s.loadMusic(true), 80);

		#if mac
		var reloadJsonButton:PsychUIButton = new PsychUIButton(objX + 205, objY, 'Reload JSON', function() {
			var cur = Paths.formatToSongPath(s.songNameInputText.text);
			var curdiff = Highscore.formatSong(cur, PlayState.storyDifficulty);
			var diff = false;
			var loadedChart:SwagSong = try {
				diff = true;
				Song.getChart(curdiff, cur);
			} catch (e) {
				diff = false;
				Song.getChart(cur, cur);
			}
			if (loadedChart == null || !Reflect.hasField(loadedChart, 'song')) // Check if chart is ACTUALLY a chart and valid
			{
				s.showOutput('Error: File loaded is not a Psych Engine/FNF 0.2.x.x chart.', true);
				return;
			}

			var func:Void->Void = function() {
				s.loadChart(loadedChart);
				Song.chartPath = diff ? curdiff : cur;
				s.reloadNotesDropdowns();
				s.prepareReload();
				s.showOutput('Opened chart "${diff ? curdiff : cur}" successfully!');
			}

			if (!s.ignoreProgressCheckBox.checked)
				s.openSubState(new Prompt('Warning: Any unsaved progress\nwill be lost.', func));
			else
				func();
		}, 80);
		#end

		objY += 65;
		// (x:Float = 0, y:Float = 0, step:Float = 1, defValue:Float = 0, min:Float = -999, max:Float = 999, decimals:Int = 0, ?wid:Int = 60, ?isPercent:Bool = false)
		s.bpmStepper = new PsychUINumericStepper(objX, objY, 1, 1, 1, 400, 3);
		s.bpmStepper.onValueChange = function() {
			var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
			PlayState.SONG.bpm = s.bpmStepper.value;
			s.adaptNotesToNewTimes(oldTimes, s.bpmAdaptMode);
		};

		s.scrollSpeedStepper = new PsychUINumericStepper(objX + 90, objY, 0.1, 1, 0.1, 10, 2);
		s.scrollSpeedStepper.onValueChange = function() PlayState.SONG.speed = s.scrollSpeedStepper.value;

		s.audioOffsetStepper = new PsychUINumericStepper(objX + 180, objY, 1, 0, -500, 500, 0);
		s.audioOffsetStepper.onValueChange = function() {
			PlayState.SONG.offset = s.audioOffsetStepper.value;
			Conductor.offset = s.audioOffsetStepper.value;
			s.waveform.redraw(s);
		};

		tab_group.add(new FlxText(s.songNameInputText.x, s.songNameInputText.y - 15, 80, 'Song Name:'));
		tab_group.add(s.songNameInputText);
		tab_group.add(s.allowVocalsCheckBox);
		tab_group.add(reloadAudioButton);
		#if mac
		tab_group.add(reloadJsonButton);
		#end

		// Find characters
		var characters:Array<String> = [];
		//

		objY += 40;
		// Song structure steppers (time signature + key count) share the row right
		// under BPM/Scroll Speed; the character dropdowns sit below them so their
		// open lists can't cover the steppers.
		var baseSig:Array<Int> = Conductor.getBaseTimeSignature(PlayState.SONG);
		s.timeSigNumStepper = new PsychUINumericStepper(objX, objY, 1, baseSig[0], 1, 16, 0, 50);
		s.timeSigNumStepper.onValueChange = function() applyBaseTimeSignature(s);
		s.timeSigDenStepper = new PsychUINumericStepper(objX + 60, objY, 1, baseSig[1], 1, 16, 0, 50);
		s.timeSigDenStepper.onValueChange = function() applyBaseTimeSignature(s);

		s.playerDropDown = new PsychUIDropDownMenu(objX, objY + 40, [''], function(id:Int, character:String) {
			PlayState.SONG.player1 = character;
			PlayState.SONG.syncPrimaryCharacters();
			s.updateJsonData();
			s.updateHeads(true);
			s.loadMusic();
			if (s.charPreview.showChars) s.charPreview.reloadEditorChars();
			trace('selected $character');
		});
		s.stageDropDown = new PsychUIDropDownMenu(objX + 140, objY + 40, [''], function(id:Int, stage:String) {
			PlayState.SONG.stage = stage;
			StageData.loadDirectory(PlayState.SONG);
			trace('selected $stage');
		});

		s.opponentDropDown = new PsychUIDropDownMenu(objX, objY + 80, [''], function(id:Int, character:String) {
			PlayState.SONG.player2 = character;
			PlayState.SONG.syncPrimaryCharacters();
			s.updateJsonData();
			s.updateHeads(true);
			s.loadMusic();
			if (s.charPreview.showChars) s.charPreview.reloadEditorChars();
			trace('selected $character');
		});

		s.girlfriendDropDown = new PsychUIDropDownMenu(objX, objY + 120, [''], function(id:Int, character:String) {
			PlayState.SONG.gfVersion = character;
			PlayState.SONG.syncPrimaryCharacters();
			if (s.charPreview.showChars) s.charPreview.reloadEditorChars();
			trace('selected $character');
		});

		tab_group.add(new FlxText(s.bpmStepper.x, s.bpmStepper.y - 15, 50, 'BPM:'));
		tab_group.add(new FlxText(s.scrollSpeedStepper.x, s.scrollSpeedStepper.y - 15, 80, 'Scroll Speed:'));
		tab_group.add(new FlxText(s.audioOffsetStepper.x, s.audioOffsetStepper.y - 15, 100, 'Audio Offset (ms):'));
		tab_group.add(s.bpmStepper);
		tab_group.add(s.scrollSpeedStepper);
		tab_group.add(s.audioOffsetStepper);

		// dropdowns
		tab_group.add(new FlxText(s.stageDropDown.x, s.stageDropDown.y - 15, 80, 'Stage:'));
		tab_group.add(new FlxText(s.playerDropDown.x, s.playerDropDown.y - 15, 80, 'Player:'));
		tab_group.add(new FlxText(s.opponentDropDown.x, s.opponentDropDown.y - 15, 80, 'Opponent:'));
		tab_group.add(new FlxText(s.girlfriendDropDown.x, s.girlfriendDropDown.y - 15, 80, 'Girlfriend:'));
		tab_group.add(s.stageDropDown);
		tab_group.add(s.girlfriendDropDown);
		tab_group.add(s.opponentDropDown);
		tab_group.add(s.playerDropDown);

		tab_group.add(new FlxText(s.timeSigNumStepper.x, s.timeSigNumStepper.y - 15, 120, 'Time Signature:'));
		tab_group.add(new FlxText(s.timeSigDenStepper.x - 12, s.timeSigDenStepper.y + 3, 12, '/'));
		tab_group.add(s.timeSigNumStepper);
		tab_group.add(s.timeSigDenStepper);

		// Multikey: column count per side (1-9). Live-rebuilds the grid + strums.
		// Shares the Time Signature row (above the dropdowns) so dropdown lists
		// don't cover it.
		s.keyCountStepper = new PsychUINumericStepper(objX + 180, objY, 1,
			Mania.resolveKeyCount(PlayState.SONG.keyCount), Mania.MIN, Mania.MAX, 0, 50);
		s.keyCountStepper.onValueChange = function() s.changeKeyCount(Std.int(s.keyCountStepper.value));
		tab_group.add(new FlxText(s.keyCountStepper.x, s.keyCountStepper.y - 15, 120, 'Key Count:'));
		tab_group.add(s.keyCountStepper);
	}

	/**
		Sets the song's base time signature and applies it to every section (sections can still be
		individually overridden afterwards in the Section tab). The denominator snaps to a power of two,
		like the per-section stepper.
		@param s the chart editor whose song/sections are retimed
	**/
	static function applyBaseTimeSignature(s:ChartingState):Void {
		var num:Float = Math.max(1, Math.round(s.timeSigNumStepper.value));
		var curDen:Int = Conductor.getBaseTimeSignature(PlayState.SONG)[1];
		var v:Int = Std.int(s.timeSigDenStepper.value);
		var den:Int = (v > curDen) ? Std.int(Math.min(16, curDen * 2)) : (v < curDen ? Std.int(Math.max(1, Std.int(curDen / 2))) : curDen);

		s.timeSigNumStepper.value = num;
		s.timeSigDenStepper.value = den;

		var oldTimes:Array<Float> = s.cachedSectionTimes.copy();
		PlayState.SONG.timeSignature = [Std.int(num), den];
		for (section in PlayState.SONG.notes) {
			section.sectionBeats = num;
			section.sectionDenominator = den;
		}
		s.adaptNotesToNewTimes(oldTimes);
	}
}
