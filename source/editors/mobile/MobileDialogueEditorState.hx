package editors.mobile;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxMath;
import cutscenes.DialogueBoxPsych;
import cutscenes.DialogueBoxPsych.DialogueFile;
import cutscenes.DialogueBoxPsych.DialogueLine;
import cutscenes.DialogueCharacter;
import objects.TypedAlphabet;
import smidr.UILocale;
import smidr.UIFonts;
import smidr.widgets.UICheckbox;
import smidr.widgets.UILabel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;
import smidr.overlays.UIToast;

/**
 * Touch-native Dialogue editor: the desktop `DialogueEditorState`'s live speech-bubble preview
 * (`DialogueCharacter` + bubble + `TypedAlphabet`) on the mobile shell, with the current line's fields
 * in a rail-opened LINE page and line navigation (prev/next/add/remove) on the action bar. Saves
 * `dialogue.json` (desktop uses a file dialog, absent on touch), same JSON shape as desktop.
 */
class MobileDialogueEditorState extends MobileEditorBase {
	var character:DialogueCharacter;
	var box:FlxSprite;
	var daText:TypedAlphabet;

	var dialogueFile:DialogueFile;
	var defaultLine:DialogueLine;
	var curSelected:Int = 0;
	var curAnim:Int = 0;

	static inline var DEFAULT_TEXT:String = 'coolswag';

	override function create():Void {
		initPsychCamera();
		FlxG.camera.bgColor = 0xFF12141F;

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		defaultLine = {
			portrait: DialogueCharacter.DEFAULT_CHARACTER,
			expression: '',
			text: DEFAULT_TEXT,
			boxState: 'normal',
			speed: 0.05,
			sound: ''
		};
		dialogueFile = {dialogue: [copyDefaultLine()]};

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

		daText = new TypedAlphabet(DialogueBoxPsych.DEFAULT_TEXT_X, DialogueBoxPsych.DEFAULT_TEXT_Y, DEFAULT_TEXT);
		daText.setScale(0.7);
		add(daText);

		buildChrome();
		changeText();

		super.create();
	}

	function buildChrome():Void {
		shell = new MobileEditorShell();
		shell.addLeft('< EXIT', exitEditor);
		shell.railGap(true);
		shell.addLeft('OPEN', openDialogue);
		shell.addLeft('SAVE', saveDialogue, true);

		shell.addRight('LINE', openLinePage);
		shell.addRight('ANIM >', scrollAnim);
		shell.railGap(false);
		shell.addRight('? GUIDE', function() shell.showGuide([
			'LINE      edit the current line (portrait/text/speed/sound/box)',
			'ANIM >    cycle the portrait\'s animations',
			'ACTION BAR   prev / next line, add / remove a line',
			'SAVE      writes dialogue.json'
		]));

		shell.setActionBar([
			{label: '< PREV', cb: function() changeText(-1)},
			{label: 'NEXT >', cb: function() changeText(1)},
			{label: 'ADD', cb: addLine},
			{label: 'REMOVE', cb: removeLine, danger: true}
		]);
		shell.showActionBar(true);
	}

	function openLinePage():Void {
		shell.openPage('DIALOGUE LINE ${curSelected + 1}/${dialogueFile.dialogue.length}', function(pane:UIScrollPane):Float {
			var line:DialogueLine = dialogueFile.dialogue[curSelected];
			var w:Float = shell.pageWidth();
			var y:Float = 6;

			var charInput:UITextInput = new UITextInput('Character:', w, line.portrait, function(v:String) {
				line.portrait = v;
				reloadCharacter();
			});
			charInput.y = y;
			pane.content.addChild(charInput);
			y += 56;

			var textInput:UITextInput = new UITextInput('Text:', w, line.text, function(v:String) {
				line.text = (v != null) ? v : '';
				daText.text = line.text;
				daText.resetDialogue();
			});
			textInput.y = y;
			pane.content.addChild(textInput);
			y += 56;

			var speed:UIStepper = new UIStepper('Speed (ms):', w, (line.speed != null) ? line.speed : 0.05, 0.005, function(v:Float) {
				if (Math.isNaN(v) || v < 0.001)
					v = 0.0;
				line.speed = v;
				daText.delay = v;
			});
			speed.min = 0;
			speed.max = 0.5;
			speed.decimals = 3;
			speed.y = y;
			pane.content.addChild(speed);
			y += 56;

			var angry:UICheckbox = new UICheckbox('Angry Textbox', w, line.boxState == 'angry', function(c:Bool) {
				line.boxState = c ? 'angry' : 'normal';
				updateTextBox();
			});
			angry.y = y;
			pane.content.addChild(angry);
			y += 44;

			var soundInput:UITextInput = new UITextInput('Sound file name:', w, (line.sound != null) ? line.sound : '', function(v:String) {
				line.sound = v;
				daText.sound = (v != null) ? v : '';
			});
			soundInput.y = y;
			pane.content.addChild(soundInput);
			y += 56;

			var hint:UILabel = new UILabel('Use PREV / NEXT on the action bar to move between lines.', 13, 2);
			hint.y = y;
			pane.content.addChild(hint);
			return y + 30;
		});
	}

	function copyDefaultLine():DialogueLine {
		return {
			portrait: defaultLine.portrait,
			expression: defaultLine.expression,
			text: defaultLine.text,
			boxState: defaultLine.boxState,
			speed: defaultLine.speed,
			sound: ''
		};
	}

	function addLine():Void {
		dialogueFile.dialogue.insert(curSelected + 1, copyDefaultLine());
		changeText(1);
	}

	function removeLine():Void {
		if (dialogueFile.dialogue.length <= 1) {
			UIToast.show("Can't remove the only line");
			return;
		}
		dialogueFile.dialogue.remove(dialogueFile.dialogue[curSelected]);
		changeText();
	}

	function changeText(add:Int = 0):Void {
		curSelected = FlxMath.wrap(curSelected + add, 0, dialogueFile.dialogue.length - 1);
		var line:DialogueLine = dialogueFile.dialogue[curSelected];

		character.reloadCharacterJson(line.portrait);
		reloadCharacter();

		daText.text = (line.text != null) ? line.text : '';
		daText.delay = (line.speed != null) ? line.speed : 0.05;
		daText.sound = (line.sound != null) ? line.sound : '';
		daText.resetDialogue();

		updateTextBox();
		updateStatus();
		if (shell.drawerOpen)
			openLinePage(); // refresh the line page for the new current line
	}

	function updateTextBox():Void {
		box.flipX = false;
		var isAngry:Bool = dialogueFile.dialogue[curSelected].boxState == 'angry';
		var anim:String = isAngry ? 'angry' : 'normal';
		switch (character.jsonFile.dialogue_pos) {
			case 'left':
				box.flipX = true;
			case 'center':
				anim = isAngry ? 'center-angry' : 'center';
		}
		box.animation.play(anim, true);
		DialogueBoxPsych.updateBoxOffsets(box);
	}

	function reloadCharacter():Void {
		character.frames = Paths.getSparrowAtlas('dialogue/' + character.jsonFile.image);
		character.reloadAnimations();
		character.setGraphicSize(Std.int(character.width * DialogueCharacter.DEFAULT_SCALE * character.jsonFile.scale));
		character.updateHitbox();
		character.x = DialogueBoxPsych.LEFT_CHAR_X;
		character.y = DialogueBoxPsych.DEFAULT_CHAR_Y;

		switch (character.jsonFile.dialogue_pos) {
			case 'right':
				character.x = FlxG.width - character.width + DialogueBoxPsych.RIGHT_CHAR_X;
			case 'center':
				character.x = FlxG.width / 2 - character.width / 2;
		}

		character.x += character.jsonFile.position[0];
		character.y += character.jsonFile.position[1];
		curAnim = 0;
		character.playAnim();
	}

	function scrollAnim():Void {
		if (character.jsonFile == null || character.jsonFile.animations == null || character.jsonFile.animations.length < 1)
			return;
		curAnim = FlxMath.wrap(curAnim + 1, 0, character.jsonFile.animations.length - 1);
		character.playAnim(character.jsonFile.animations[curAnim].anim, daText.finishedText);
		updateStatus();
	}

	function updateStatus():Void {
		var animName:String = (character.jsonFile != null
			&& character.jsonFile.animations != null
			&& curAnim < character.jsonFile.animations.length) ? character.jsonFile.animations[curAnim].anim : '?';
		shell.setStatus('DIALOGUE EDITOR    line ${curSelected + 1}/${dialogueFile.dialogue.length}    portrait: ${dialogueFile.dialogue[curSelected].portrait}    anim: $animName');
	}

	function saveDialogue():Void {
		saveFile('dialogue.json', haxe.Json.stringify(dialogueFile, '\t'));
	}

	function openDialogue():Void {
		openFile('dialogue.json', 'Open a dialogue file', function(data:String, _:String):Void {
			try {
				dialogueFile = cast haxe.Json.parse(data);
				if (dialogueFile.dialogue == null || dialogueFile.dialogue.length < 1)
					dialogueFile.dialogue = [copyDefaultLine()];
				curSelected = 0;
				changeText();
			} catch (e:Dynamic) {
				UIToast.show('Load failed: ${Std.string(e)}');
			}
		});
	}
}
