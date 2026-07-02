package legacy.editors.charting.tabs;

import legacy.editors.ChartingState;

/**
	Builds the "Data" tab of the chart editor's main box: song-level metadata not tied to timing — game
	over character/sounds, the note-RGB toggle, and the note/splash texture overrides. Texture changes
	rebuild the note pool through the editor. Reaches editor widget fields and hooks via `@:access`.
**/
@:access(legacy.editors.ChartingState)
class DataTab {
	/**
		Populates the Data tab in `s.mainBox`.
		@param s the chart editor that owns the tab box and the widget fields assigned here
	**/
	public static function build(s:ChartingState):Void {
		var tab_group = s.mainBox.getTab('Data').menu;
		var objX = 10;
		var objY = 25;
		s.gameOverCharDropDown = new PsychUIDropDownMenu(objX, objY, [''], function(id:Int, character:String) {
			PlayState.SONG.gameOverChar = character;
			if (character.length < 1)
				Reflect.deleteField(PlayState.SONG, 'gameOverChar');
			trace('selected $character');
		});

		objY += 40;
		s.gameOverSndInputText = new PsychUIInputText(objX, objY, 120, '', 8);
		s.gameOverSndInputText.onChange = function(old:String, cur:String) {
			PlayState.SONG.gameOverSound = cur;
			if (cur.trim().length < 1)
				Reflect.deleteField(PlayState.SONG, 'gameOverSound');
		}
		objY += 40;
		s.gameOverLoopInputText = new PsychUIInputText(objX, objY, 120, '', 8);
		s.gameOverLoopInputText.onChange = function(old:String, cur:String) {
			PlayState.SONG.gameOverLoop = cur;
			if (cur.trim().length < 1)
				Reflect.deleteField(PlayState.SONG, 'gameOverLoop');
		}
		objY += 40;
		s.gameOverRetryInputText = new PsychUIInputText(objX, objY, 120, '', 8);
		s.gameOverRetryInputText.onChange = function(old:String, cur:String) {
			PlayState.SONG.gameOverEnd = cur;
			if (cur.trim().length < 1)
				Reflect.deleteField(PlayState.SONG, 'gameOverEnd');
		}

		objY += 35;
		s.noRGBCheckBox = new PsychUICheckBox(objX, objY, 'Disable Note RGB', 100, s.updateNotesRGB);

		objY += 40;
		s.noteTextureInputText = new PsychUIInputText(objX, objY, 120, '');
		s.noteTextureInputText.unfocus = function() {
			var changed:Bool = false;
			if (PlayState.SONG.arrowSkin != s.noteTextureInputText.text)
				changed = true;
			PlayState.SONG.arrowSkin = s.noteTextureInputText.text.trim();
			if (PlayState.SONG.arrowSkin.trim().length < 1)
				PlayState.SONG.arrowSkin = null;

			if (changed) {
				var textureLoad:String = 'images/${s.noteTextureInputText.text}.png';
				if (Paths.fileExists(textureLoad, IMAGE) || s.noteTextureInputText.text.trim() == '') {
					s.reskinNotePool();
					if (s.noteTextureInputText.text.trim().length > 0)
						s.showOutput('Reloaded notes to: "$textureLoad"');
					else
						s.showOutput('Reloaded notes to default texture');
				} else
					s.showOutput('ERROR: "$textureLoad" not found.', true);
			}
		};

		s.noteSplashesInputText = new PsychUIInputText(objX + 140, objY, 120, '');
		s.noteSplashesInputText.onChange = function(old:String, cur:String) {
			PlayState.SONG.splashSkin = cur;
			if (cur.trim().length < 1)
				PlayState.SONG.splashSkin = null;
		}

		tab_group.add(new FlxText(s.gameOverCharDropDown.x, s.gameOverCharDropDown.y - 15, 120, 'Game Over Character:'));
		tab_group.add(new FlxText(s.gameOverSndInputText.x, s.gameOverSndInputText.y - 15, 180, 'Game Over Death Sound (sounds/):'));
		tab_group.add(new FlxText(s.gameOverLoopInputText.x, s.gameOverLoopInputText.y - 15, 180, 'Game Over Loop Music (music/):'));
		tab_group.add(new FlxText(s.gameOverRetryInputText.x, s.gameOverRetryInputText.y - 15, 180, 'Game Over Retry Music (music/):'));
		tab_group.add(s.gameOverSndInputText);
		tab_group.add(s.gameOverLoopInputText);
		tab_group.add(s.gameOverRetryInputText);
		tab_group.add(s.noRGBCheckBox);

		tab_group.add(new FlxText(s.noteTextureInputText.x, s.noteTextureInputText.y - 15, 100, 'Note Texture:'));
		tab_group.add(new FlxText(s.noteSplashesInputText.x, s.noteSplashesInputText.y - 15, 120, 'Note Splashes Texture:'));
		tab_group.add(s.noteTextureInputText);
		tab_group.add(s.noteSplashesInputText);

		tab_group.add(s.gameOverCharDropDown); // lowest priority to display properly
	}
}
