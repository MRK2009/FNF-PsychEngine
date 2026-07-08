package editors;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import haxe.Json;
import objects.MenuCharacter;
import editors.content.Prompt;
import editors.content.PsychJsonPrinter;
import smidr.UIRoot;
import smidr.flixel.FlxSmidr;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;
import smidr.widgets.UISegmented;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;

class MenuCharacterEditorState extends MusicBeatState {
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;
	var characterFile:MenuCharacterFile = null;
	var txtOffsets:FlxText;
	var defaultCharacters:Array<String> = ['dad', 'bf', 'gf'];
	var unsavedProgress:Bool = false;

	var uiRoot:UIRoot;

	override function create() {
		characterFile = {
			image: 'Menu_Dad',
			scale: 1,
			position: [0, 0],
			idle_anim: 'M Dad Idle',
			confirm_anim: 'M Dad Idle',
			flipX: false,
			antialiasing: true
		};

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Menu Character Editor", "Editting: " + characterFile.image);
		#end

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();
		for (char in 0...3) {
			var weekCharacterThing:MenuCharacter = new MenuCharacter((FlxG.width * 0.25) * (1 + char) - 150, defaultCharacters[char]);
			weekCharacterThing.y += 70;
			weekCharacterThing.alpha = 0.2;
			grpWeekCharacters.add(weekCharacterThing);
		}

		add(new FlxSprite(0, 56).makeGraphic(FlxG.width, 386, 0xFFF9CF51));
		add(grpWeekCharacters);

		txtOffsets = new FlxText(20, 10, 0, "[0, 0]", 32);
		txtOffsets.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		txtOffsets.alpha = 0.7;
		add(txtOffsets);

		var tipText:FlxText = new FlxText(0, 540, FlxG.width, "Arrow Keys - Change Offset (Hold shift for 10x speed)
			\nSpace - Play \"Start Press\" animation (Boyfriend Character Type)", 16);
		tipText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
		tipText.scrollFactor.set();
		add(tipText);

		addEditorBox();
		FlxG.mouse.visible = true;
		updateCharacters();

		super.create();
	}

	static inline var PAD:Int = 10;

	var charType:Int = 0;
	var typeSegment:UISegmented;

	function addEditorBox() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;

		// Character type selector (was a radio group in a small box).
		var typeW:Float = 420;
		var typePanel:UIPanel = new UIPanel(typeW, 44, PANEL);
		typePanel.x = 40;
		typePanel.y = FlxG.height - 230;
		uiRoot.content.addChild(typePanel);

		typeSegment = new UISegmented('Character Type:', typeW - PAD * 2, ['Opponent', 'Boyfriend', 'Girlfriend'], function(i:Int) {
			charType = i;
			updateCharacters();
		});
		typeSegment.boxWidth = 250;
		typeSegment.x = typePanel.x + PAD;
		typeSegment.y = typePanel.y + PAD;
		uiRoot.content.addChild(typeSegment);

		// Character properties box.
		var boxW:Float = 280;
		var boxH:Float = 236;
		var boxX:Float = FlxG.width - boxW - 40;
		var boxY:Float = FlxG.height - 265;
		var rowW:Float = boxW - PAD * 2;

		var panel:UIPanel = new UIPanel(boxW, boxH, PANEL);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		var header:UILabel = new UILabel('Character', 14, 0);
		header.x = boxX + PAD;
		header.y = boxY + 8;
		uiRoot.content.addChild(header);

		var rowY:Float = boxY + 32;
		imageInputText = new UITextInput('Image file name:', rowW, characterFile.image, function(v:String) {
			characterFile.image = v;
			unsavedProgress = true;
		});
		imageInputText.x = boxX + PAD;
		imageInputText.y = rowY;
		imageInputText.boxWidth = 115;
		uiRoot.content.addChild(imageInputText);

		idleInputText = new UITextInput('Idle anim (.XML):', rowW, characterFile.idle_anim, function(v:String) {
			characterFile.idle_anim = v;
			unsavedProgress = true;
		});
		idleInputText.x = boxX + PAD;
		idleInputText.y = rowY + 32;
		idleInputText.boxWidth = 110;
		uiRoot.content.addChild(idleInputText);

		confirmInputText = new UITextInput('Start Press anim:', rowW, characterFile.confirm_anim, function(v:String) {
			characterFile.confirm_anim = v;
			unsavedProgress = true;
		});
		confirmInputText.x = boxX + PAD;
		confirmInputText.y = rowY + 64;
		confirmInputText.boxWidth = 110;
		uiRoot.content.addChild(confirmInputText);

		scaleStepper = new UIStepper('Scale:', rowW, 1, 0.05, function(v:Float) {
			characterFile.scale = v;
			reloadSelectedCharacter();
			unsavedProgress = true;
		});
		scaleStepper.min = 0.1;
		scaleStepper.max = 30;
		scaleStepper.decimals = 2;
		scaleStepper.x = boxX + PAD;
		scaleStepper.y = rowY + 96;
		uiRoot.content.addChild(scaleStepper);

		flipXCheckbox = new UICheckbox("Flip X", (rowW - 10) / 2, false, function(checked:Bool) {
			grpWeekCharacters.members[charType].flipX = checked;
			characterFile.flipX = checked;
			unsavedProgress = true;
		});
		flipXCheckbox.x = boxX + PAD;
		flipXCheckbox.y = rowY + 128;
		uiRoot.content.addChild(flipXCheckbox);

		antialiasingCheckbox = new UICheckbox("Antialiasing", (rowW - 10) / 2, grpWeekCharacters.members[charType].antialiasing, function(checked:Bool) {
			grpWeekCharacters.members[charType].antialiasing = checked;
			characterFile.antialiasing = checked;
			unsavedProgress = true;
		});
		antialiasingCheckbox.x = boxX + PAD + (rowW - 10) / 2 + 10;
		antialiasingCheckbox.y = rowY + 128;
		uiRoot.content.addChild(antialiasingCheckbox);

		var reloadImageButton:UIButton = new UIButton("Reload Char", rowW, 26, function() {
			reloadSelectedCharacter();
		});
		reloadImageButton.x = boxX + PAD;
		reloadImageButton.y = rowY + 162;
		uiRoot.content.addChild(reloadImageButton);

		// Load / Save row (was two floating PsychUIButtons).
		var loadButton:UIButton = new UIButton("Load Character", 150, 28, function() {
			loadCharacter();
		});
		loadButton.x = FlxG.width / 2 - 160;
		loadButton.y = 480;
		uiRoot.content.addChild(loadButton);

		var saveButton:UIButton = new UIButton("Save Character", 150, 28, function() {
			saveCharacter();
		}, true);
		saveButton.x = FlxG.width / 2 + 10;
		saveButton.y = 480;
		uiRoot.content.addChild(saveButton);
	}

	var imageInputText:UITextInput;
	var idleInputText:UITextInput;
	var confirmInputText:UITextInput;
	var scaleStepper:UIStepper;
	var flipXCheckbox:UICheckbox;
	var antialiasingCheckbox:UICheckbox;

	function updateCharacters() {
		for (i in 0...3) {
			var char:MenuCharacter = grpWeekCharacters.members[i];
			char.alpha = 0.2;
			char.character = '';
			char.changeCharacter(defaultCharacters[i]);
		}
		reloadSelectedCharacter();
	}

	function reloadSelectedCharacter() {
		var char:MenuCharacter = grpWeekCharacters.members[charType];

		char.alpha = 1;
		char.frames = Paths.getSparrowAtlas('menucharacters/' + characterFile.image);
		char.animation.addByPrefix('idle', characterFile.idle_anim, 24);
		if (charType == 1)
			char.animation.addByPrefix('confirm', characterFile.confirm_anim, 24, false);
		char.flipX = (characterFile.flipX == true);

		char.scale.set(characterFile.scale, characterFile.scale);
		char.updateHitbox();
		char.animation.play('idle');
		updateOffset();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Menu Character Editor", "Editting: " + characterFile.image);
		#end
	}

	override function update(elapsed:Float) {
		if (UIFocus.focused == null) {
			ClientPrefs.toggleVolumeKeys(true);
			if (!UIRoot.overlayOpen) {
				if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
					if (!unsavedProgress) {
						MusicBeatState.switchState(new editors.MasterEditorMenu());
						FlxG.sound.playMusic(Paths.music('freakyMenu'));
					} else
						openSubState(new ExitConfirmationPrompt());
				}

				var shiftMult:Int = 1;
				if (FlxG.keys.pressed.SHIFT)
					shiftMult = 10;

				if (FlxG.keys.justPressed.LEFT) {
					characterFile.position[0] += shiftMult;
					updateOffset();
				}
				if (FlxG.keys.justPressed.RIGHT) {
					characterFile.position[0] -= shiftMult;
					updateOffset();
				}
				if (FlxG.keys.justPressed.UP) {
					characterFile.position[1] += shiftMult;
					updateOffset();
				}
				if (FlxG.keys.justPressed.DOWN) {
					characterFile.position[1] -= shiftMult;
					updateOffset();
				}

				if (FlxG.keys.justPressed.SPACE && charType == 1) {
					grpWeekCharacters.members[charType].animation.play('confirm', true);
				}
			}
		} else
			ClientPrefs.toggleVolumeKeys(false);

		var char:MenuCharacter = grpWeekCharacters.members[1];
		if (char.animation.curAnim != null && char.animation.curAnim.name == 'confirm' && char.animation.curAnim.finished)
			char.animation.play('idle', true);

		super.update(elapsed);
	}

	function updateOffset() {
		var char:MenuCharacter = grpWeekCharacters.members[charType];
		char.offset.set(characterFile.position[0], characterFile.position[1]);
		txtOffsets.text = '' + characterFile.position;
	}

	var _file:FileReference = null;

	function loadCharacter() {
		var jsonFilter:FileFilter = new FileFilter('JSON', 'json');
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file.browse([#if !mac jsonFilter #end]);
	}

	function onLoadComplete(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		#if sys
		var fullPath:String = null;
		@:privateAccess
		if (_file.__path != null)
			fullPath = _file.__path;

		if (fullPath != null) {
			var rawJson:String = File.getContent(fullPath);
			if (rawJson != null) {
				var loadedChar:MenuCharacterFile = cast Json.parse(rawJson);
				if (loadedChar.idle_anim != null && loadedChar.confirm_anim != null) // Make sure it's really a character
				{
					var cutName:String = _file.name.substr(0, _file.name.length - 5);
					trace("Successfully loaded file: " + cutName);
					characterFile = loadedChar;
					reloadSelectedCharacter();
					imageInputText.text = characterFile.image;
					idleInputText.text = characterFile.idle_anim;
					confirmInputText.text = characterFile.confirm_anim;
					scaleStepper.value = characterFile.scale;
					updateOffset();
					_file = null;
					return;
				}
			}
		}
		_file = null;
		#else
		trace("File couldn't be loaded! You aren't on Desktop, are you?");
		#end
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onLoadCancel(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Cancelled file loading.");
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onLoadError(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Problem loading file");
	}

	function saveCharacter() {
		var data:String = PsychJsonPrinter.print(characterFile, ['position']);
		if (data.length > 0) {
			var splittedImage:Array<String> = imageInputText.text.trim().split('_');
			var characterName:String = splittedImage[splittedImage.length - 1].toLowerCase().replace(' ', '');

			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, characterName + ".json");
		}
	}

	function onSaveComplete(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved file.");
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving file");
	}

	override function destroy() {
		ClientPrefs.toggleVolumeKeys(true);
		if (uiRoot != null) {
			FlxSmidr.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
