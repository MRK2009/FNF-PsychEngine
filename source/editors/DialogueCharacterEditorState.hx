package editors;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import haxe.Json;
import lime.system.Clipboard;
import objects.TypedAlphabet;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueCharacter;
import editors.content.Prompt;
import openfl.display.Sprite;
import smidr.UIRoot;
import smidr.flixel.FlxSmidr;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UIPanel;
import smidr.widgets.UISegmented;
import smidr.widgets.UIStepper;
import smidr.widgets.UITabs;
import smidr.widgets.UITextInput;

class DialogueCharacterEditorState extends MusicBeatState {
	var box:FlxSprite;
	var daText:TypedAlphabet = null;

	private static var TIP_TEXT_MAIN:String = 'JKLI - Move camera (Hold Shift to move 4x faster)
	\nQ/E - Zoom out/in
	\nR - Reset Camera
	\nH - Toggle Speech Bubble
	\nSpace - Reset text';

	private static var TIP_TEXT_OFFSET:String = 'JKLI - Move camera (Hold Shift to move 4x faster)
	\nQ/E - Zoom out/in
	\nR - Reset Camera
	\nH - Toggle Ghosts
	\nWASD - Move Looping animation offset (Red)
	\nArrow Keys - Move Idle/Finished animation offset (Blue)
	\nHold Shift to move offsets 10x faster';

	var tipText:FlxText;
	var offsetLoopText:FlxText;
	var offsetIdleText:FlxText;
	var animText:FlxText;

	var camGame:FlxCamera;
	var camHUD:FlxCamera;

	var mainGroup:FlxSpriteGroup;
	var hudGroup:FlxSpriteGroup;

	var character:DialogueCharacter;
	var ghostLoop:DialogueCharacter;
	var ghostIdle:DialogueCharacter;

	var curAnim:Int = 0;
	var unsavedProgress:Bool = false;

	var uiRoot:UIRoot;

	override function create() {
		persistentUpdate = persistentDraw = true;
		camGame = initPsychCamera();
		camGame.bgColor = FlxColor.fromHSL(0, 0, 0.5);
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		mainGroup = new FlxSpriteGroup();
		mainGroup.cameras = [camGame];
		hudGroup = new FlxSpriteGroup();
		hudGroup.cameras = [camGame];
		add(mainGroup);
		add(hudGroup);

		character = new DialogueCharacter();
		character.scrollFactor.set();
		mainGroup.add(character);

		ghostLoop = new DialogueCharacter();
		ghostLoop.alpha = 0;
		ghostLoop.color = FlxColor.RED;
		ghostLoop.isGhost = true;
		ghostLoop.jsonFile = character.jsonFile;
		ghostLoop.cameras = [camGame];
		mainGroup.add(ghostLoop);

		ghostIdle = new DialogueCharacter();
		ghostIdle.alpha = 0;
		ghostIdle.color = FlxColor.BLUE;
		ghostIdle.isGhost = true;
		ghostIdle.jsonFile = character.jsonFile;
		ghostIdle.cameras = [camGame];
		mainGroup.add(ghostIdle);

		box = new FlxSprite(70, 370);
		box.antialiasing = ClientPrefs.data.antialiasing;
		box.frames = Paths.getSparrowAtlas('speech_bubble');
		box.scrollFactor.set();
		box.animation.addByPrefix('normal', 'speech bubble normal', 24);
		box.animation.addByPrefix('center', 'speech bubble middle', 24);
		box.animation.play('normal', true);
		box.setGraphicSize(Std.int(box.width * 0.9));
		box.updateHitbox();
		hudGroup.add(box);

		tipText = new FlxText(10, 10, FlxG.width - 20, TIP_TEXT_MAIN, 8);
		tipText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		tipText.cameras = [camHUD];
		tipText.scrollFactor.set();
		add(tipText);

		offsetLoopText = new FlxText(10, 10, 0, '', 32);
		offsetLoopText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		offsetLoopText.cameras = [camHUD];
		offsetLoopText.scrollFactor.set();
		add(offsetLoopText);
		offsetLoopText.visible = false;

		offsetIdleText = new FlxText(10, 46, 0, '', 32);
		offsetIdleText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		offsetIdleText.cameras = [camHUD];
		offsetIdleText.scrollFactor.set();
		add(offsetIdleText);
		offsetIdleText.visible = false;

		animText = new FlxText(10, 22, FlxG.width - 20, '', 8);
		animText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		animText.scrollFactor.set();
		animText.cameras = [camHUD];
		add(animText);

		reloadCharacter();
		updateTextBox();

		daText = new TypedAlphabet(DialogueBoxPsych.DEFAULT_TEXT_X, DialogueBoxPsych.DEFAULT_TEXT_Y, '', 0.05, false);
		daText.setScale(0.7);
		daText.text = DEFAULT_TEXT;
		hudGroup.add(daText);

		addEditorBox();
		FlxG.mouse.visible = true;
		updateCharTypeBox();

		super.create();
	}

	static inline var PAD:Int = 10;
	static inline var BOX_W:Int = 300;

	var mainTabs:UITabs;
	var tabPanes:Array<Sprite> = [];
	var curTabName:String = 'Character';
	var typeSegment:UISegmented;

	function addEditorBox() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;

		// Dialogue position selector (was a radio group box).
		var typeW:Float = 400;
		var typePanel:UIPanel = new UIPanel(typeW, 44, PANEL);
		typePanel.x = 40;
		typePanel.y = FlxG.height - 60;
		uiRoot.content.addChild(typePanel);

		typeSegment = new UISegmented('Position:', typeW - PAD * 2, ['Left', 'Center', 'Right'], function(i:Int) {
			switch (i) {
				case 0:
					character.jsonFile.dialogue_pos = 'left';
				case 1:
					character.jsonFile.dialogue_pos = 'center';
				case 2:
					character.jsonFile.dialogue_pos = 'right';
			}
			updateCharTypeBox();
			unsavedProgress = true;
		});
		typeSegment.boxWidth = 220;
		typeSegment.x = typePanel.x + PAD;
		typeSegment.y = typePanel.y + PAD;
		uiRoot.content.addChild(typeSegment);

		// Animations / Character box.
		mainTabs = new UITabs(BOX_W, [{label: 'Animations'}, {label: 'Character'}], function(i:Int):Void {
			for (n in 0...tabPanes.length)
				tabPanes[n].visible = (n == i);
			curTabName = (i == 0) ? 'Animations' : 'Character';
		});

		var paneH:Float = 250;
		var boxH:Float = mainTabs.h + 8 + paneH + PAD;
		var boxX:Float = FlxG.width - BOX_W - 10;
		var boxY:Float = FlxG.height - boxH - 10;

		var panel:UIPanel = new UIPanel(BOX_W, boxH, PANEL);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		mainTabs.x = boxX;
		mainTabs.y = boxY;
		uiRoot.content.addChild(mainTabs);

		tabPanes = [];
		for (i in 0...2) {
			var pane:Sprite = new Sprite();
			pane.x = boxX + PAD;
			pane.y = boxY + mainTabs.h + 8;
			pane.visible = false;
			uiRoot.content.addChild(pane);
			tabPanes.push(pane);
		}

		addAnimationsUI(tabPanes[0]);
		addCharacterUI(tabPanes[1]);

		mainTabs.select(1);
		tabPanes[1].visible = true;
		curTabName = 'Character';
		lastTab = curTabName;
	}

	var curSelectedAnim:String;
	var animationArray:Array<String> = [];
	var animationDropDown:UIDropdown;
	var animationInputText:UITextInput;
	var loopInputText:UITextInput;
	var idleInputText:UITextInput;

	function addAnimationsUI(pane:Sprite) {
		var rowW:Float = BOX_W - PAD * 2;

		animationDropDown = new UIDropdown('Animations:', rowW, function(id:Int, animation:String) {
			if (character.dialogueAnimations.exists(animation)) {
				ghostLoop.playAnim(animation);
				ghostIdle.playAnim(animation, true);

				curSelectedAnim = animation;
				var animShit:DialogueAnimArray = character.dialogueAnimations.get(curSelectedAnim);
				offsetLoopText.text = 'Loop: ' + animShit.loop_offsets;
				offsetIdleText.text = 'Idle: ' + animShit.idle_offsets;

				animationInputText.text = animShit.anim;
				loopInputText.text = animShit.loop_name;
				idleInputText.text = animShit.idle_name;
			}
		});
		pane.addChild(animationDropDown);

		animationInputText = new UITextInput('Animation name:', rowW, '');
		animationInputText.y = 32;
		animationInputText.boxWidth = 135;
		pane.addChild(animationInputText);

		loopInputText = new UITextInput('Loop name (.XML):', rowW, '');
		loopInputText.y = 64;
		loopInputText.boxWidth = 120;
		pane.addChild(loopInputText);

		idleInputText = new UITextInput('Idle/Finished (.XML):', rowW, '');
		idleInputText.y = 96;
		idleInputText.boxWidth = 100;
		pane.addChild(idleInputText);

		var addUpdateButton:UIButton = new UIButton("Add/Update", (rowW - 10) / 2, 26, function() {
			var theAnim:String = animationInputText.text.trim();
			if (character.dialogueAnimations.exists(theAnim)) // Update
			{
				for (i in 0...character.jsonFile.animations.length) {
					var animArray:DialogueAnimArray = character.jsonFile.animations[i];
					if (animArray.anim.trim() == theAnim) {
						animArray.loop_name = loopInputText.text;
						animArray.idle_name = idleInputText.text;
						break;
					}
				}

				character.reloadAnimations();
				ghostLoop.reloadAnimations();
				ghostIdle.reloadAnimations();
				if (curSelectedAnim == theAnim) {
					ghostLoop.playAnim(theAnim);
					ghostIdle.playAnim(theAnim, true);
				}
			} else // Add
			{
				var newAnim:DialogueAnimArray = {
					anim: theAnim,
					loop_name: loopInputText.text,
					loop_offsets: [0, 0],
					idle_name: idleInputText.text,
					idle_offsets: [0, 0]
				}
				character.jsonFile.animations.push(newAnim);

				var lastSelected:String = selectedDropDownLabel();
				character.reloadAnimations();
				ghostLoop.reloadAnimations();
				ghostIdle.reloadAnimations();
				reloadAnimationsDropDown();
				selectDropDownLabel(lastSelected);
			}
			unsavedProgress = true;
		}, true);
		addUpdateButton.y = 132;
		pane.addChild(addUpdateButton);

		var removeUpdateButton:UIButton = new UIButton("Remove", (rowW - 10) / 2, 26, function() {
			for (i in 0...character.jsonFile.animations.length) {
				var animArray:DialogueAnimArray = character.jsonFile.animations[i];
				if (animArray != null && animArray.anim.trim() == animationInputText.text.trim()) {
					var lastSelected:String = selectedDropDownLabel();
					character.jsonFile.animations.remove(animArray);
					character.reloadAnimations();
					ghostLoop.reloadAnimations();
					ghostIdle.reloadAnimations();
					reloadAnimationsDropDown();
					if (character.jsonFile.animations.length > 0 && lastSelected == animArray.anim.trim()) {
						var animToPlay:String = character.jsonFile.animations[0].anim;
						ghostLoop.playAnim(animToPlay);
						ghostIdle.playAnim(animToPlay, true);
					}
					selectDropDownLabel(lastSelected);
					animationInputText.text = '';
					loopInputText.text = '';
					idleInputText.text = '';
					unsavedProgress = true;
					break;
				}
			}
		});
		removeUpdateButton.danger = true;
		removeUpdateButton.x = (rowW - 10) / 2 + 10;
		removeUpdateButton.y = 132;
		pane.addChild(removeUpdateButton);

		reloadAnimationsDropDown();
	}

	inline function selectedDropDownLabel():String {
		var i:Int = animationDropDown.selectedIndex;
		return (i >= 0 && i < animationArray.length) ? animationArray[i] : '';
	}

	function selectDropDownLabel(label:String):Void {
		var idx:Int = animationArray.indexOf(label);
		animationDropDown.select(idx >= 0 ? idx : 0);
	}

	function reloadAnimationsDropDown() {
		animationArray = [];
		for (anim in character.jsonFile.animations) {
			animationArray.push(anim.anim);
		}

		if (animationArray.length < 1)
			animationArray = [''];
		animationDropDown.setItems(animationArray);
	}

	var imageInputText:UITextInput;
	var scaleStepper:UIStepper;
	var xStepper:UIStepper;
	var yStepper:UIStepper;

	function addCharacterUI(pane:Sprite) {
		var rowW:Float = BOX_W - PAD * 2;
		var halfW:Float = (rowW - 10) / 2;

		imageInputText = new UITextInput('Image file name:', rowW, character.jsonFile.image, function(v:String) {
			character.jsonFile.image = v;
			unsavedProgress = true;
		});
		imageInputText.boxWidth = 130;
		pane.addChild(imageInputText);

		xStepper = new UIStepper('Offset X:', halfW, character.jsonFile.position[0], 10, function(v:Float) {
			character.jsonFile.position[0] = v;
			reloadCharacter();
			unsavedProgress = true;
		});
		xStepper.boxWidth = 56;
		xStepper.min = -2000;
		xStepper.max = 2000;
		xStepper.y = 32;
		pane.addChild(xStepper);

		yStepper = new UIStepper('Y:', halfW, character.jsonFile.position[1], 10, function(v:Float) {
			character.jsonFile.position[1] = v;
			reloadCharacter();
			unsavedProgress = true;
		});
		yStepper.boxWidth = 56;
		yStepper.min = -2000;
		yStepper.max = 2000;
		yStepper.x = halfW + 10;
		yStepper.y = 32;
		pane.addChild(yStepper);

		scaleStepper = new UIStepper('Scale:', halfW, character.jsonFile.scale, 0.05, function(v:Float) {
			character.jsonFile.scale = v;
			reloadCharacter();
			unsavedProgress = true;
		});
		scaleStepper.boxWidth = 56;
		scaleStepper.min = 0.1;
		scaleStepper.max = 10;
		scaleStepper.decimals = 2;
		scaleStepper.y = 64;
		pane.addChild(scaleStepper);

		var noAntialiasingCheckbox:UICheckbox = new UICheckbox("No Antialiasing", halfW, (character.jsonFile.no_antialiasing == true), function(checked:Bool) {
			character.jsonFile.no_antialiasing = checked;
			character.antialiasing = !character.jsonFile.no_antialiasing;
			unsavedProgress = true;
		});
		noAntialiasingCheckbox.x = halfW + 10;
		noAntialiasingCheckbox.y = 64;
		pane.addChild(noAntialiasingCheckbox);

		var reloadImageButton:UIButton = new UIButton("Reload Image", rowW, 26, function() {
			reloadCharacter();
		});
		reloadImageButton.y = 100;
		pane.addChild(reloadImageButton);

		var loadButton:UIButton = new UIButton("Load Character", halfW, 26, function() {
			loadCharacter();
		});
		loadButton.y = 134;
		pane.addChild(loadButton);

		var saveButton:UIButton = new UIButton("Save Character", halfW, 26, function() {
			saveCharacter();
		}, true);
		saveButton.x = halfW + 10;
		saveButton.y = 134;
		pane.addChild(saveButton);
	}

	function updateCharTypeBox() {
		if (typeSegment != null)
			switch (character.jsonFile.dialogue_pos) {
				case 'left':
					typeSegment.select(0);
				case 'center':
					typeSegment.select(1);
				default:
					typeSegment.select(2);
			}
		reloadCharacter();
		updateTextBox();
	}

	private static var DEFAULT_TEXT:String = 'Lorem ipsum dolor sit amet';

	function reloadCharacter() {
		var charsArray:Array<DialogueCharacter> = [character, ghostLoop, ghostIdle];
		for (char in charsArray) {
			char.frames = Paths.getSparrowAtlas('dialogue/' + character.jsonFile.image);
			char.jsonFile = character.jsonFile;
			char.reloadAnimations();
			char.setGraphicSize(Std.int(char.width * DialogueCharacter.DEFAULT_SCALE * character.jsonFile.scale));
			char.updateHitbox();
		}
		character.x = DialogueBoxPsych.LEFT_CHAR_X;
		character.y = DialogueBoxPsych.DEFAULT_CHAR_Y;

		switch (character.jsonFile.dialogue_pos) {
			case 'right':
				character.x = FlxG.width - character.width + DialogueBoxPsych.RIGHT_CHAR_X;

			case 'center':
				character.x = FlxG.width / 2;
				character.x -= character.width / 2;
		}
		character.x += character.jsonFile.position[0] + mainGroup.x;
		character.y += character.jsonFile.position[1] + mainGroup.y;
		character.playAnim(character.jsonFile.animations[0].anim);
		if (character.jsonFile.animations.length > 0) {
			curSelectedAnim = character.jsonFile.animations[0].anim;
			var animShit:DialogueAnimArray = character.dialogueAnimations.get(curSelectedAnim);
			ghostLoop.playAnim(animShit.anim);
			ghostIdle.playAnim(animShit.anim, true);
			offsetLoopText.text = 'Loop: ' + animShit.loop_offsets;
			offsetIdleText.text = 'Idle: ' + animShit.idle_offsets;
		}

		curAnim = 0;
		animText.text = 'Animation: '
			+ character.jsonFile.animations[curAnim].anim
				+ ' ('
				+ (curAnim + 1)
				+ ' / '
				+ character.jsonFile.animations.length
				+ ') - Press W or S to scroll';

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Dialogue Character Editor", "Editting: " + character.jsonFile.image);
		#end
	}

	function updateTextBox() {
		box.flipX = false;
		var anim:String = 'normal';
		switch (character.jsonFile.dialogue_pos) {
			case 'left':
				box.flipX = true;
			case 'center':
				anim = 'center';
		}
		box.animation.play(anim, true);
		DialogueBoxPsych.updateBoxOffsets(box);
	}

	var currentGhosts:Int = 0;
	var lastTab:String = 'Character';
	var transitioning:Bool = false;

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (transitioning)
			return;

		if (character.animation.curAnim != null) {
			if (daText.finishedText) {
				if (character.animationIsLoop()) {
					character.playAnim(character.animation.curAnim.name, true);
				}
			} else if (character.animation.curAnim.finished) {
				character.animation.curAnim.restart();
			}
		}

		if (UIFocus.focused == null && !UIRoot.overlayOpen) {
			ClientPrefs.toggleVolumeKeys(true);
			if (FlxG.keys.justPressed.SPACE && curTabName == 'Character') {
				character.playAnim(character.jsonFile.animations[curAnim].anim);
				daText.resetDialogue();
				updateTextBox();
			}

			// lots of Ifs lol get trolled
			var offsetAdd:Int = 1;
			var speed:Float = 300;
			if (FlxG.keys.pressed.SHIFT) {
				speed = 1200;
				offsetAdd = 10;
			}

			var negaMult:Array<Int> = [1, 1, -1, -1];
			var controlArray:Array<Bool> = [
				FlxG.keys.pressed.J,
				FlxG.keys.pressed.I,
				FlxG.keys.pressed.L,
				FlxG.keys.pressed.K
			];
			for (i in 0...controlArray.length) {
				if (controlArray[i]) {
					if (i % 2 == 1) {
						mainGroup.y += speed * elapsed * negaMult[i];
					} else {
						mainGroup.x += speed * elapsed * negaMult[i];
					}
				}
			}

			if (curTabName == 'Animations' && curSelectedAnim != null && character.dialogueAnimations.exists(curSelectedAnim)) {
				var moved:Bool = false;
				var animShit:DialogueAnimArray = character.dialogueAnimations.get(curSelectedAnim);
				var controlArrayLoop:Array<Bool> = [
					FlxG.keys.justPressed.A,
					FlxG.keys.justPressed.W,
					FlxG.keys.justPressed.D,
					FlxG.keys.justPressed.S
				];
				var controlArrayIdle:Array<Bool> = [
					FlxG.keys.justPressed.LEFT,
					FlxG.keys.justPressed.UP,
					FlxG.keys.justPressed.RIGHT,
					FlxG.keys.justPressed.DOWN
				];
				for (i in 0...controlArrayLoop.length) {
					if (controlArrayLoop[i]) {
						if (i % 2 == 1) {
							animShit.loop_offsets[1] += offsetAdd * negaMult[i];
						} else {
							animShit.loop_offsets[0] += offsetAdd * negaMult[i];
						}
						moved = true;
					}
				}
				for (i in 0...controlArrayIdle.length) {
					if (controlArrayIdle[i]) {
						if (i % 2 == 1) {
							animShit.idle_offsets[1] += offsetAdd * negaMult[i];
						} else {
							animShit.idle_offsets[0] += offsetAdd * negaMult[i];
						}
						moved = true;
					}
				}

				if (moved) {
					offsetLoopText.text = 'Loop: ' + animShit.loop_offsets;
					offsetIdleText.text = 'Idle: ' + animShit.idle_offsets;
					ghostLoop.offset.set(animShit.loop_offsets[0], animShit.loop_offsets[1]);
					ghostIdle.offset.set(animShit.idle_offsets[0], animShit.idle_offsets[1]);
					unsavedProgress = true;
				}
			}

			if (FlxG.keys.pressed.Q && camGame.zoom > 0.1) {
				camGame.zoom -= elapsed * camGame.zoom;
				if (camGame.zoom < 0.1)
					camGame.zoom = 0.1;
			}
			if (FlxG.keys.pressed.E && camGame.zoom < 1) {
				camGame.zoom += elapsed * camGame.zoom;
				if (camGame.zoom > 1)
					camGame.zoom = 1;
			}
			if (FlxG.keys.justPressed.H) {
				if (curTabName == 'Animations') {
					currentGhosts++;
					if (currentGhosts > 2)
						currentGhosts = 0;

					ghostLoop.visible = (currentGhosts != 1);
					ghostIdle.visible = (currentGhosts != 2);
					ghostLoop.alpha = (currentGhosts == 2 ? 1 : 0.6);
					ghostIdle.alpha = (currentGhosts == 1 ? 1 : 0.6);
				} else {
					hudGroup.visible = !hudGroup.visible;
				}
			}
			if (FlxG.keys.justPressed.R) {
				camGame.zoom = 1;
				mainGroup.setPosition(0, 0);
				hudGroup.visible = true;
			}

			if (curTabName != lastTab) {
				if (curTabName == 'Animations') {
					hudGroup.alpha = 0;
					mainGroup.alpha = 0;
					ghostLoop.alpha = 0.6;
					ghostIdle.alpha = 0.6;
					tipText.text = TIP_TEXT_OFFSET;
					offsetLoopText.visible = true;
					offsetIdleText.visible = true;
					animText.visible = false;
					currentGhosts = 0;
				} else {
					hudGroup.alpha = 1;
					mainGroup.alpha = 1;
					ghostLoop.alpha = 0;
					ghostIdle.alpha = 0;
					tipText.text = TIP_TEXT_MAIN;
					offsetLoopText.visible = false;
					offsetIdleText.visible = false;
					animText.visible = true;
					updateTextBox();
					daText.resetDialogue();

					if (curAnim < 0)
						curAnim = character.jsonFile.animations.length - 1;
					else if (curAnim >= character.jsonFile.animations.length)
						curAnim = 0;

					character.playAnim(character.jsonFile.animations[curAnim].anim);
					animText.text = 'Animation: '
						+ character.jsonFile.animations[curAnim].anim
							+ ' ('
							+ (curAnim + 1)
							+ ' / '
							+ character.jsonFile.animations.length
							+ ') - Press W or S to scroll';
				}
				lastTab = curTabName;
				currentGhosts = 0;
			}

			if (curTabName == 'Character') {
				var negaMult:Array<Int> = [1, -1];
				var controlAnim:Array<Bool> = [FlxG.keys.justPressed.W, FlxG.keys.justPressed.S];

				if (controlAnim.contains(true)) {
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
							}
						}
					}
					animText.text = 'Animation: '
						+ character.jsonFile.animations[curAnim].anim
							+ ' ('
							+ (curAnim + 1)
							+ ' / '
							+ character.jsonFile.animations.length
							+ ') - Press W or S to scroll';
				}
			}

			if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
				if (!unsavedProgress) {
					MusicBeatState.switchState(new editors.MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					transitioning = true;
				} else
					openSubState(new ExitConfirmationPrompt(function() transitioning = true));
			}

			ghostLoop.setPosition(character.x, character.y);
			ghostIdle.setPosition(character.x, character.y);
			hudGroup.x = mainGroup.x;
			hudGroup.y = mainGroup.y;
		} else
			ClientPrefs.toggleVolumeKeys(false);
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
				var loadedChar:DialogueCharacterFile = cast Json.parse(rawJson);
				if (loadedChar.dialogue_pos != null) // Make sure it's really a dialogue character
				{
					var cutName:String = _file.name.substr(0, _file.name.length - 5);
					trace("Successfully loaded file: " + cutName);
					character.jsonFile = loadedChar;
					reloadCharacter();
					reloadAnimationsDropDown();
					updateCharTypeBox();
					updateTextBox();
					daText.resetDialogue();
					imageInputText.text = character.jsonFile.image;
					scaleStepper.value = character.jsonFile.scale;
					xStepper.value = character.jsonFile.position[0];
					yStepper.value = character.jsonFile.position[1];
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
		var data:String = haxe.Json.stringify(character.jsonFile, "\t");
		if (data.length > 0) {
			var splittedImage:Array<String> = imageInputText.text.trim().split('_');
			var characterName:String = splittedImage[0].toLowerCase().replace(' ', '');

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

	function ClipboardAdd(prefix:String = ''):String {
		if (prefix.toLowerCase().endsWith('v')) // probably copy paste attempt
		{
			prefix = prefix.substring(0, prefix.length - 1);
		}

		var text:String = prefix + Clipboard.text.replace('\n', '');
		return text;
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
