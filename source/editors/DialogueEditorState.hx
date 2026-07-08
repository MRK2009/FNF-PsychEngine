package editors;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import haxe.Json;
import objects.TypedAlphabet;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueCharacter;
import editors.content.Prompt;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;

class DialogueEditorState extends MusicBeatState {
	var character:DialogueCharacter;
	var box:FlxSprite;
	var daText:TypedAlphabet;

	var selectedText:FlxText;
	var animText:FlxText;

	var defaultLine:DialogueLine;
	var dialogueFile:DialogueFile = null;
	var unsavedProgress:Bool = false;

	var uiRoot:UIRoot;

	override function create() {
		persistentUpdate = persistentDraw = true;
		FlxG.camera.bgColor = FlxColor.fromHSL(0, 0, 0.5);

		defaultLine = {
			portrait: DialogueCharacter.DEFAULT_CHARACTER,
			expression: 'talk',
			text: DEFAULT_TEXT,
			boxState: DEFAULT_BUBBLETYPE,
			speed: 0.05,
			sound: ''
		};

		dialogueFile = {
			dialogue: [copyDefaultLine()]
		};

		character = new DialogueCharacter();
		character.scrollFactor.set();
		add(character);

		box = new FlxSprite(70, 370);
		box.antialiasing = ClientPrefs.data.antialiasing;
		box.frames = Paths.getSparrowAtlas('speech_bubble');
		box.scrollFactor.set();
		box.animation.addByPrefix('normal', 'speech bubble normal', 24);
		box.animation.addByPrefix('angry', 'AHH speech bubble', 24);
		box.animation.addByPrefix('center', 'speech bubble middle', 24);
		box.animation.addByPrefix('center-angry', 'AHH Speech Bubble middle', 24);
		box.animation.play('normal', true);
		box.setGraphicSize(Std.int(box.width * 0.9));
		box.updateHitbox();
		add(box);

		addEditorBox();
		FlxG.mouse.visible = true;

		var addLineText:FlxText = new FlxText(10, 10, FlxG.width - 20,
			'Press O to remove the current dialogue line, Press P to add another line after the current one.', 8);
		addLineText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		addLineText.scrollFactor.set();
		add(addLineText);

		selectedText = new FlxText(10, 32, FlxG.width - 20, '', 8);
		selectedText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectedText.scrollFactor.set();
		add(selectedText);

		animText = new FlxText(10, 62, FlxG.width - 20, '', 8);
		animText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		animText.scrollFactor.set();
		add(animText);

		daText = new TypedAlphabet(DialogueBoxPsych.DEFAULT_TEXT_X, DialogueBoxPsych.DEFAULT_TEXT_Y, DEFAULT_TEXT);
		daText.setScale(0.7);
		add(daText);
		changeText();
		super.create();
	}

	/** Layers the UI root above the game view but below the FPS counter. **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	function onGameResized(_:Int, _:Int):Void
		syncViewport();

	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	static inline var PAD:Int = 10;

	var characterInputText:UITextInput;
	var lineInputText:UITextInput;
	var angryCheckbox:UICheckbox;
	var speedStepper:UIStepper;
	var soundInputText:UITextInput;

	function addEditorBox() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		var boxW:Float = 280;
		var boxH:Float = 236;
		var boxX:Float = FlxG.width - boxW - 10;
		var boxY:Float = 10;
		var rowW:Float = boxW - PAD * 2;

		var panel:UIPanel = new UIPanel(boxW, boxH, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		var header:UILabel = new UILabel('Dialogue Line', 14, 0);
		header.x = boxX + PAD;
		header.y = boxY + 8;
		uiRoot.content.addChild(header);

		var rowY:Float = boxY + 32;

		characterInputText = new UITextInput('Character:', rowW, DialogueCharacter.DEFAULT_CHARACTER, function(v:String) {
			character.reloadCharacterJson(v);
			reloadCharacter();
			if (character.jsonFile.animations.length > 0) {
				curAnim = 0;
				if (character.jsonFile.animations.length > curAnim && character.jsonFile.animations[curAnim] != null) {
					character.playAnim(character.jsonFile.animations[curAnim].anim, daText.finishedText);
					animText.text = 'Animation: '
						+ character.jsonFile.animations[curAnim].anim
							+ ' ('
							+ (curAnim + 1)
							+ ' / '
							+ character.jsonFile.animations.length
							+ ') - Press W or S to scroll';
				} else {
					animText.text = 'ERROR! NO ANIMATIONS FOUND';
				}
				characterAnimSpeed();
			}
			dialogueFile.dialogue[curSelected].portrait = v;
			reloadText(false);
			updateTextBox();
			unsavedProgress = true;
		});
		characterInputText.x = boxX + PAD;
		characterInputText.y = rowY;
		uiRoot.content.addChild(characterInputText);

		speedStepper = new UIStepper('Interval/Speed (ms):', rowW, 0.05, 0.005, function(v:Float) {
			dialogueFile.dialogue[curSelected].speed = v;
			if (Math.isNaN(dialogueFile.dialogue[curSelected].speed)
				|| dialogueFile.dialogue[curSelected].speed == null
				|| dialogueFile.dialogue[curSelected].speed < 0.001) {
				dialogueFile.dialogue[curSelected].speed = 0.0;
			}
			daText.delay = dialogueFile.dialogue[curSelected].speed;
			reloadText(false);
			unsavedProgress = true;
		});
		speedStepper.min = 0;
		speedStepper.max = 0.5;
		speedStepper.decimals = 3;
		speedStepper.x = boxX + PAD;
		speedStepper.y = rowY + 32;
		uiRoot.content.addChild(speedStepper);

		angryCheckbox = new UICheckbox("Angry Textbox", rowW, false, function(checked:Bool) {
			updateTextBox();
			dialogueFile.dialogue[curSelected].boxState = (checked ? 'angry' : 'normal');
			unsavedProgress = true;
		});
		angryCheckbox.x = boxX + PAD;
		angryCheckbox.y = rowY + 64;
		uiRoot.content.addChild(angryCheckbox);

		soundInputText = new UITextInput('Sound file name:', rowW, '', function(v:String) {
			daText.finishText();
			dialogueFile.dialogue[curSelected].sound = v;
			daText.sound = v;
			if (daText.sound == null)
				daText.sound = '';
			unsavedProgress = true;
		});
		soundInputText.x = boxX + PAD;
		soundInputText.y = rowY + 96;
		uiRoot.content.addChild(soundInputText);

		lineInputText = new UITextInput('Text:', rowW, DEFAULT_TEXT, function(v:String) {
			dialogueFile.dialogue[curSelected].text = v;

			daText.text = v;
			if (daText.text == null)
				daText.text = '';
			reloadText(true);
			unsavedProgress = true;
		});
		lineInputText.onEnter = function(v:String) {
			// Shift+Enter appends a line break (multi-line dialogue), plain Enter blurs.
			if (FlxG.keys.pressed.SHIFT) {
				lineInputText.text = v + '\n';
				dialogueFile.dialogue[curSelected].text = lineInputText.text;
				reloadText(true);
			} else
				UIFocus.clear();
		};
		lineInputText.x = boxX + PAD;
		lineInputText.y = rowY + 128;
		uiRoot.content.addChild(lineInputText);

		var loadButton:UIButton = new UIButton("Load Dialogue", (rowW - 10) / 2, 26, function() {
			loadDialogue();
		});
		loadButton.x = boxX + PAD;
		loadButton.y = rowY + 164;
		uiRoot.content.addChild(loadButton);

		var saveButton:UIButton = new UIButton("Save Dialogue", (rowW - 10) / 2, 26, function() {
			saveDialogue();
		}, true);
		saveButton.x = boxX + PAD + (rowW - 10) / 2 + 10;
		saveButton.y = rowY + 164;
		uiRoot.content.addChild(saveButton);
	}

	function copyDefaultLine():DialogueLine {
		var copyLine:DialogueLine = {
			portrait: defaultLine.portrait,
			expression: defaultLine.expression,
			text: defaultLine.text,
			boxState: defaultLine.boxState,
			speed: defaultLine.speed,
			sound: ''
		};
		return copyLine;
	}

	function updateTextBox() {
		box.flipX = false;
		var isAngry:Bool = angryCheckbox.checked;
		var anim:String = isAngry ? 'angry' : 'normal';

		switch (character.jsonFile.dialogue_pos) {
			case 'left':
				box.flipX = true;
			case 'center':
				if (isAngry) {
					anim = 'center-angry';
				} else {
					anim = 'center';
				}
		}
		box.animation.play(anim, true);
		DialogueBoxPsych.updateBoxOffsets(box);
	}

	function reloadCharacter() {
		character.frames = Paths.getSparrowAtlas('dialogue/' + character.jsonFile.image);
		character.jsonFile = character.jsonFile;
		character.reloadAnimations();
		character.setGraphicSize(Std.int(character.width * DialogueCharacter.DEFAULT_SCALE * character.jsonFile.scale));
		character.updateHitbox();
		character.x = DialogueBoxPsych.LEFT_CHAR_X;
		character.y = DialogueBoxPsych.DEFAULT_CHAR_Y;

		switch (character.jsonFile.dialogue_pos) {
			case 'right':
				character.x = FlxG.width - character.width + DialogueBoxPsych.RIGHT_CHAR_X;

			case 'center':
				character.x = FlxG.width / 2;
				character.x -= character.width / 2;
		}
		character.x += character.jsonFile.position[0];
		character.y += character.jsonFile.position[1];
		character.playAnim(); // Plays random animation
		characterAnimSpeed();

		if (character.animation.curAnim != null && character.jsonFile.animations != null) {
			animText.text = 'Animation: '
				+ character.jsonFile.animations[curAnim].anim
					+ ' ('
					+ (curAnim + 1)
					+ ' / '
					+ character.jsonFile.animations.length
					+ ') - Press W or S to scroll';
		} else {
			animText.text = 'ERROR! NO ANIMATIONS FOUND';
		}
	}

	private static var DEFAULT_TEXT:String = "coolswag";
	private static var DEFAULT_SPEED:Float = 0.05;
	private static var DEFAULT_BUBBLETYPE:String = "normal";

	function reloadText(skipDialogue:Bool) {
		var textToType:String = lineInputText.text;
		if (textToType == null || textToType.length < 1)
			textToType = ' ';

		daText.text = textToType;

		if (skipDialogue)
			daText.finishText();
		else if (daText.delay > 0) {
			if (character.jsonFile.animations.length > curAnim && character.jsonFile.animations[curAnim] != null) {
				character.playAnim(character.jsonFile.animations[curAnim].anim);
			}
			characterAnimSpeed();
		}

		daText.y = DialogueBoxPsych.DEFAULT_TEXT_Y;
		if (daText.rows > 2)
			daText.y -= DialogueBoxPsych.LONG_TEXT_ADD;

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		var rpcText:String = lineInputText.text;
		if (rpcText == null || rpcText.length < 1)
			rpcText = '(Empty)';
		if (rpcText.length < 3)
			rpcText += '   '; // Fixes a bug on RPC that triggers an error when the text is too short
		DiscordClient.changePresence("Dialogue Editor", rpcText);
		#end
	}

	var curSelected:Int = 0;
	var curAnim:Int = 0;
	var transitioning:Bool = false;

	override function update(elapsed:Float) {
		if (transitioning) {
			super.update(elapsed);
			return;
		}

		if (character.animation.curAnim != null) {
			if (daText.finishedText) {
				if (character.animationIsLoop() && character.animation.curAnim.finished) {
					character.playAnim(character.animation.curAnim.name, true);
				}
			} else if (character.animation.curAnim.finished) {
				character.animation.curAnim.restart();
			}
		}

		if (UIFocus.focused == null) {
			ClientPrefs.toggleVolumeKeys(true);
			if (FlxG.keys.justPressed.SPACE) {
				reloadText(false);
			}
			if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
				if (!unsavedProgress) {
					MusicBeatState.switchState(new editors.MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					transitioning = true;
				} else
					openSubState(new ExitConfirmationPrompt(function() transitioning = true));
				return;
			}
			var negaMult:Array<Int> = [1, -1];
			var controlAnim:Array<Bool> = [FlxG.keys.justPressed.W, FlxG.keys.justPressed.S];
			var controlText:Array<Bool> = [FlxG.keys.justPressed.D, FlxG.keys.justPressed.A];
			for (i in 0...controlAnim.length) {
				if (controlAnim[i] && character.jsonFile.animations.length > 0) {
					curAnim -= negaMult[i];
					if (curAnim < 0)
						curAnim = character.jsonFile.animations.length - 1;
					else if (curAnim >= character.jsonFile.animations.length)
						curAnim = 0;

					var animToPlay:String = character.jsonFile.animations[curAnim].anim;
					if (character.dialogueAnimations.exists(animToPlay)) {
						character.playAnim(animToPlay, daText.finishedText);
						dialogueFile.dialogue[curSelected].expression = animToPlay;
					}
					animText.text = 'Animation: ' + animToPlay + ' (' + (curAnim + 1) + ' / ' + character.jsonFile.animations.length
						+ ') - Press W or S to scroll';
				}
				if (controlText[i]) {
					changeText(negaMult[i]);
				}
			}

			if (FlxG.keys.justPressed.O) {
				dialogueFile.dialogue.remove(dialogueFile.dialogue[curSelected]);
				if (dialogueFile.dialogue.length < 1) // You deleted everything, dumbo!
				{
					dialogueFile.dialogue = [copyDefaultLine()];
				}
				changeText();
			} else if (FlxG.keys.justPressed.P) {
				dialogueFile.dialogue.insert(curSelected + 1, copyDefaultLine());
				changeText(1);
			}
		} else
			ClientPrefs.toggleVolumeKeys(false);
		super.update(elapsed);
	}

	function changeText(add:Int = 0) {
		curSelected = FlxMath.wrap(curSelected + add, 0, dialogueFile.dialogue.length - 1);

		var curDialogue:DialogueLine = dialogueFile.dialogue[curSelected];
		characterInputText.text = curDialogue.portrait;
		lineInputText.text = curDialogue.text;
		angryCheckbox.checked = (curDialogue.boxState == 'angry');
		speedStepper.value = curDialogue.speed;

		if (curDialogue.sound == null)
			curDialogue.sound = '';
		soundInputText.text = curDialogue.sound;

		daText.delay = speedStepper.value;
		daText.sound = soundInputText.text;
		if (daText.sound != null && daText.sound.trim() == '')
			daText.sound = 'dialogue';

		curAnim = 0;
		character.reloadCharacterJson(characterInputText.text);
		reloadCharacter();
		reloadText(false);
		updateTextBox();

		if (character.jsonFile.animations.length > 0) {
			for (num => animData in character.jsonFile.animations) {
				if (animData != null && animData.anim == curDialogue.expression) {
					curAnim = num;
					break;
				}
			}

			var selectedAnim:String = character.jsonFile.animations[curAnim].anim;
			character.playAnim(selectedAnim, daText.finishedText);
			animText.text = 'Animation: $selectedAnim (${curAnim + 1} / ${character.jsonFile.animations.length} ) - Press W or S to scroll';
		} else
			animText.text = 'ERROR! NO ANIMATIONS FOUND';
		characterAnimSpeed();

		selectedText.text = 'Line: (' + (curSelected + 1) + ' / ' + dialogueFile.dialogue.length + ') - Press A or D to scroll';
	}

	function characterAnimSpeed() {
		if (character.animation.curAnim != null) {
			var speed:Float = speedStepper.value;
			var rate:Float = 24 - (((speed - 0.05) / 5) * 480);
			if (rate < 12)
				rate = 12;
			else if (rate > 48)
				rate = 48;
			character.animation.curAnim.frameRate = rate;
		}
	}

	var _file:FileReference = null;

	function loadDialogue() {
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
				var loadedDialog:DialogueFile = cast Json.parse(rawJson);
				if (loadedDialog.dialogue != null && loadedDialog.dialogue.length > 0) // Make sure it's really a dialogue file
				{
					var cutName:String = _file.name.substr(0, _file.name.length - 5);
					trace("Successfully loaded file: " + cutName);
					dialogueFile = loadedDialog;
					changeText();
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

	function saveDialogue() {
		var data:String = haxe.Json.stringify(dialogueFile, "\t");
		if (data.length > 0) {
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, "dialogue.json");
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
		FlxG.signals.gameResized.remove(onGameResized);
		ClientPrefs.toggleVolumeKeys(true);
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
