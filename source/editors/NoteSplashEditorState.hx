package editors;

import objects.Note;
import objects.NoteSplash;
import objects.StrumNote;
import openfl.net.FileFilter;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.input.keyboard.FlxKey;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
import haxe.Json;
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
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;

@:access(objects.NoteSplash)
class NoteSplashEditorState extends MusicBeatState {
	var strums:FlxTypedSpriteGroup<StrumNote> = new FlxTypedSpriteGroup();
	var splashes:FlxTypedSpriteGroup<NoteSplash> = new FlxTypedSpriteGroup();
	var config = NoteSplash.createConfig();

	var tipText:FlxText;
	var errorText:FlxText;
	var curText:FlxText;

	static var imageSkin:String = null;

	var splash:NoteSplash;

	var uiRoot:UIRoot;

	static inline var PAD:Int = 10;
	static inline var ANIM_W:Int = 300;
	static inline var PROP_W:Int = 290;
	static inline var SHADER_W:Int = 210;

	override function create() {
		if (imageSkin == null)
			imageSkin = NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix();

		FlxG.mouse.visible = true;

		FlxG.sound.volumeUpKeys = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys = [];

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Note Splash Editor');
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF505050;
		add(bg);

		for (i in 0...4) {
			var babyArrow:StrumNote = new StrumNote(-273, 50, i % 4, 1);
			babyArrow.playerPosition();
			babyArrow.screenCenter(Y);
			babyArrow.ID = i;
			strums.add(babyArrow);
		}

		add(strums);
		add(splashes);

		splash = new NoteSplash(0, 0, imageSkin); // this cannot be recycled
		splash.inEditor = true;
		splash.alpha = .0;
		splashes.add(splash);

		if (splash.config != null)
			config = splash.config;

		parseRGB();

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		// Stage-attached with viewport auto-sync: the UI tracks window resizes/fullscreen (FlxG.game
		// is only offset by the scale mode, never scaled, so above-game attachment would not scale).
		uiRoot = FlxSmidr.init(false);
		FlxSmidr.autoBlockMouse = true;
		var fpsCounter = Main.fpsVar;
		if (fpsCounter != null && fpsCounter.parent == FlxG.stage)
			FlxG.stage.setChildIndex(uiRoot, FlxG.stage.getChildIndex(fpsCounter));

		addPropertiesTab();
		addAnimTab();
		addShadersTab();

		var tipText:FlxText = new FlxText();
		tipText.setFormat(null, 24);
		tipText.text = "Press F1 for Help";
		tipText.setPosition(20, 20);
		add(tipText);

		errorText = new FlxText();
		errorText.setFormat(null, 16, FlxColor.RED);
		errorText.text = "ERROR!";
		errorText.y = FlxG.height - errorText.height;
		errorText.alpha = .0;
		add(errorText);

		curText = new FlxText();
		curText.setFormat(null, 24, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		curText.text = 'Copied Offsets: [0, 0]\nCurrent Animation: NONE';
		curText.y = FlxG.height - curText.height;
		curText.x += 5;
		add(curText);

		super.create();
	}

	/** Builds a titled panel and returns its widget container (positioned inside the panel). **/
	function makePanel(x:Float, y:Float, w:Float, h:Float, title:String):Sprite {
		var panel:UIPanel = new UIPanel(w, h, UITheme.panel);
		panel.x = x;
		panel.y = y;
		uiRoot.content.addChild(panel);

		var header:UILabel = new UILabel(title, 14, 0);
		header.x = x + PAD;
		header.y = y + 8;
		uiRoot.content.addChild(header);

		var pane:Sprite = new Sprite();
		pane.x = x + PAD;
		pane.y = y + 30;
		uiRoot.content.addChild(pane);
		return pane;
	}

	var animDropDown:UIDropdown;
	var animItems:Array<String> = [];
	var curAnim:String;
	var addButton:UIButton;
	var curAnimText:UITextInput = null;
	var numericStepperData:UIStepper;
	var templateButton:UIButton;

	function addAnimTab() {
		var pane:Sprite = makePanel(FlxG.width - ANIM_W - 10, 20, ANIM_W, 260, 'Animation');
		var rowW:Float = ANIM_W - PAD * 2;
		var halfW:Float = (rowW - 10) / 2;

		var name_input:UITextInput = new UITextInput('Animation Name:', rowW, '');
		curAnimText = name_input;
		name_input.y = 32;
		pane.addChild(name_input);

		var prefix_input:UITextInput = new UITextInput('Animation Prefix:', rowW, '');
		prefix_input.y = 64;
		pane.addChild(prefix_input);

		var indices_input:UITextInput = new UITextInput('Indices (OPTIONAL):', rowW, '');
		indices_input.y = 96;
		pane.addChild(indices_input);

		numericStepperData = new UIStepper('Note Data:', rowW, 0, 1);
		numericStepperData.min = 0;
		numericStepperData.max = 999;
		numericStepperData.y = 128;
		pane.addChild(numericStepperData);

		var minFps:UIStepper = new UIStepper('Min FPS:', halfW, 22, 1);
		minFps.min = 1;
		minFps.max = 120;
		minFps.y = 160;
		pane.addChild(minFps);

		var maxFps:UIStepper = new UIStepper('Max FPS:', halfW, 26, 1);
		maxFps.min = 1;
		maxFps.max = 120;
		maxFps.x = halfW + 10;
		maxFps.y = 160;
		pane.addChild(maxFps);

		animDropDown = new UIDropdown('Animations:', rowW, function(id:Int, name:String) {
			if (config != null && name.length > 0) {
				var i = config.animations.get(name);
				if (i != null) {
					name_input.text = name;
					prefix_input.text = i.prefix;
					numericStepperData.min = 0;
					numericStepperData.value = i.noteData;
					curAnim = name;
					minFps.value = i.fps[0];
					maxFps.value = i.fps[1];
					if (i.indices != null && i.indices.length > 0)
						indices_input.text = i.indices.toString().substring(1, i.indices.toString().length - 2);

					playStrumAnim(curAnim, i.noteData);
				}
			}
		});
		pane.addChild(animDropDown);

		function setAnimDropDown() {
			var anims:Array<String> = [];
			if (config != null && config.animations != null)
				for (i in config.animations.keys()) {
					anims.push(i);
				}

			if (anims.length < 1)
				anims.push("");

			if (curAnim == null && anims[0].length > 0)
				curAnim = anims[0];

			animItems = anims;
			animDropDown.setItems(anims.copy());
			animDropDown.select(Std.int(Math.max(0, anims.indexOf(curAnim))));
		}

		setAnimDropDown();

		templateButton.onClick = function() {
			NoteSplash.configs.clear();
			config = NoteSplash.createConfig();

			curAnim = null;
			name_input.text = "";
			prefix_input.text = "";
			indices_input.text = "";
			numericStepperData.value = 0;
			minFps.value = 22;
			maxFps.value = 26;
			setAnimDropDown();
			parseRGB();
			selectShaderChannel('Red');
		}

		addButton = new UIButton("Add/Update", halfW, 26, function() {
			var indices:Array<Int> = [];
			if (indices_input.text.split(',').length > 1) {
				for (i in indices_input.text.split(',')) {
					var index:Null<Int> = Std.parseInt(i);
					if (!Math.isNaN(index) && index != null) {
						indices.push(index);
					}
				}
			}

			var offsets:Array<Float> = [0, 0];
			var conf = config.animations.get(name_input.text);

			if (conf != null)
				offsets = conf.offsets;

			if (offsets == null)
				offsets = [0, 0];
			else
				offsets = offsets.copy();

			config = NoteSplash.addAnimationToConfig(config, scaleNumericStepper.value, name_input.text, prefix_input.text,
				[cast minFps.value, cast maxFps.value], offsets, indices, cast numericStepperData.value);
			curAnim = name_input.text;
			playStrumAnim(curAnim, cast numericStepperData.value);
			setAnimDropDown();
		}, true);
		addButton.y = 192;
		pane.addChild(addButton);

		var removeButton:UIButton = new UIButton("Remove", halfW, 26, function() {
			if (config != null) {
				if (config.animations.exists(curAnim)) {
					config.animations.remove(curAnim);

					curAnim = null;
					name_input.text = "";
					prefix_input.text = "";
					indices_input.text = "";
					numericStepperData.value = 0;
					setAnimDropDown();
				}
			}
		});
		removeButton.danger = true;
		removeButton.x = halfW + 10;
		removeButton.y = 192;
		pane.addChild(removeButton);

		reloadImage = function() {
			imageSkin = imageInputText.text;

			errorText.color = FlxColor.RED;
			FlxTween.cancelTweensOf(errorText);

			var image = Paths.image(imageSkin);
			if (image == null) {
				errorText.text = 'ERROR! Couldn\'t find $imageSkin.png';
				errorText.alpha = 1;
				return;
			} else {
				errorText.color = FlxColor.GREEN;
				errorText.alpha = 1;
				errorText.text = 'Succesfully loaded $imageSkin.png';
			}

			NoteSplash.configs.clear();

			FlxTween.tween(errorText, {alpha: 0}, 1, {
				startDelay: 1,
				onComplete: (twn) -> {
					errorText.color = FlxColor.RED;
				}
			});

			splash.loadSplash(imageSkin);
			splash.alpha = 0.0001;

			if (splash.config != null)
				config = splash.config;
			else
				config = NoteSplash.createConfig();

			curAnim = null;
			name_input.text = "";
			prefix_input.text = "";
			indices_input.text = "";
			numericStepperData.value = 0;
			minFps.value = 22;
			maxFps.value = 26;
			setAnimDropDown();
			parseRGB();
			selectShaderChannel('Red');
		}
	}

	var imageInputText:UITextInput;
	var scaleNumericStepper:UIStepper;

	function addPropertiesTab() {
		var pane:Sprite = makePanel(FlxG.width - ANIM_W - PROP_W - 20, 20, PROP_W, 230, 'Properties');
		var rowW:Float = PROP_W - PAD * 2;
		var halfW:Float = (rowW - 10) / 2;

		imageInputText = new UITextInput('Image:', rowW, imageSkin);
		pane.addChild(imageInputText);

		var reloadButton:UIButton = new UIButton("Reload Image", rowW, 26, function() {
			reloadImage();
		});
		reloadButton.y = 32;
		pane.addChild(reloadButton);

		scaleNumericStepper = new UIStepper('Scale:', rowW, 1, 0.1);
		scaleNumericStepper.min = 0;
		scaleNumericStepper.max = 4;
		scaleNumericStepper.decimals = 2;
		scaleNumericStepper.y = 66;
		pane.addChild(scaleNumericStepper);

		scaleNumericStepper.value = config != null ? config.scale : 1;

		var allowRGBCheck:UICheckbox = new UICheckbox("Allow RGB?", halfW, config != null
			&& cast(config.allowRGB, Null<Bool>) != null ? config.allowRGB : false, function(checked:Bool) {
				if (config != null)
					config.allowRGB = checked;
			});
		allowRGBCheck.y = 98;
		pane.addChild(allowRGBCheck);

		var allowPixelCheck:UICheckbox = new UICheckbox("Allow Pixel?", halfW, config != null
			&& cast(config.allowPixel, Null<Bool>) != null ? config.allowPixel : false, function(checked:Bool) {
				if (config != null)
					config.allowPixel = checked;
			});
		allowPixelCheck.x = halfW + 10;
		allowPixelCheck.y = 98;
		pane.addChild(allowPixelCheck);

		var saveButton:UIButton = new UIButton("Save", halfW, 26, saveSplash, true);
		saveButton.y = 132;
		pane.addChild(saveButton);

		templateButton = new UIButton("Template", halfW, 26);
		templateButton.danger = true;
		templateButton.x = halfW + 10;
		templateButton.y = 132;
		pane.addChild(templateButton);

		var loadButton:UIButton = new UIButton("Convert TXT", rowW, 26, loadTxt);
		loadButton.y = 164;
		pane.addChild(loadButton);
	}

	var redEnabled:Bool = true;
	var blueEnabled:Bool = true;
	var greenEnabled:Bool = true;
	var redShader:Array<Int> = [0, 0, 0];
	var greenShader:Array<Int> = [0, 0, 0];
	var blueShader:Array<Int> = [0, 0, 0];
	var changeShader:UIDropdown;
	var curShaderChannel:String = 'Red';
	var defaultButton:UICheckbox;
	var shaderPane:Sprite;

	function addShadersTab() {
		shaderPane = makePanel(FlxG.width - SHADER_W - 10, 300, SHADER_W, 220, 'Shader');
		var pane:Sprite = shaderPane;
		var rowW:Float = SHADER_W - PAD * 2;

		var red:UIStepper = null;
		var green:UIStepper = null;
		var blue:UIStepper = null;

		function onCheck(change:Bool = true) {
			pane.alpha = defaultButton.checked ? 0.6 : 1;

			if (change)
				switch (curShaderChannel) {
					case "Red":
						redEnabled = !defaultButton.checked;
					case "Green":
						greenEnabled = !defaultButton.checked;
					case "Blue":
						blueEnabled = !defaultButton.checked;
				}

			setConfigRGB();
		}

		changeShader = new UIDropdown('Color to Replace:', rowW, function(id:Int, name:String) {
			curShaderChannel = name;
			var shader = switch (name) {
				case "Red": redShader;
				case "Green": greenShader;
				case _: blueShader;
			}

			red.value = shader[0];
			green.value = shader[1];
			blue.value = shader[2];

			// changing checked doesn't re-run onCheck, so refresh the dim state manually
			defaultButton.checked = switch (name) {
				case "Red": !redEnabled;
				case "Green": !greenEnabled;
				case _: !blueEnabled;
			}
			onCheck(false);
		});
		changeShader.setItems(['Red', 'Green', 'Blue']);
		pane.addChild(changeShader);

		defaultButton = new UICheckbox("Do not replace", rowW, false, function(_) onCheck());
		defaultButton.y = 32;
		pane.addChild(defaultButton);

		red = new UIStepper('Red:', rowW, redShader[0], 1, function(v:Float) {
			switch (curShaderChannel) {
				case "Red": redShader[0] = Std.int(v);
				case "Green": greenShader[0] = Std.int(v);
				case _: blueShader[0] = Std.int(v);
			}
			setConfigRGB();
		});
		red.min = 0;
		red.max = 255;
		red.y = 66;
		pane.addChild(red);

		green = new UIStepper('Green:', rowW, redShader[1], 1, function(v:Float) {
			switch (curShaderChannel) {
				case "Red": redShader[1] = Std.int(v);
				case "Green": greenShader[1] = Std.int(v);
				case _: blueShader[1] = Std.int(v);
			}
			setConfigRGB();
		});
		green.min = 0;
		green.max = 255;
		green.y = 98;
		pane.addChild(green);

		blue = new UIStepper('Blue:', rowW, redShader[2], 1, function(v:Float) {
			switch (curShaderChannel) {
				case "Red": redShader[2] = Std.int(v);
				case "Green": greenShader[2] = Std.int(v);
				case _: blueShader[2] = Std.int(v);
			}
			setConfigRGB();
		});
		blue.min = 0;
		blue.max = 255;
		blue.y = 130;
		pane.addChild(blue);

		selectShaderChannel('Red');
	}

	/** Re-selects a shader channel and replays its dropdown callback (used by template/reload). **/
	function selectShaderChannel(name:String):Void {
		if (changeShader == null)
			return;
		changeShader.select(['Red', 'Green', 'Blue'].indexOf(name));
		if (changeShader.onSelect != null)
			changeShader.onSelect(['Red', 'Green', 'Blue'].indexOf(name), name);
	}

	dynamic function reloadImage() // Dynamic because needs to be changed later
	{
		//
	}

	var holdingArrowsTime:Float = 0;
	var holdingArrowsElapsed:Float = 0;
	var copiedOffset:Array<Float> = [0, 0];

	override function update(elapsed:Float) {
		super.update(elapsed);

		errorText.x = FlxG.width - errorText.width - 5;

		curText.text = 'Copied Offsets: ${Std.string(copiedOffset).replace(',', ', ')}\n';
		curText.text += 'Current Animation: ${curAnim == null || curAnim.length < 1 ? "NONE" : curAnim}';

		if (config != null && !curText.text.contains('NONE')) {
			var offsets:Array<Float> = try config.animations.get(curAnim).offsets catch (e) [0, 0];
			curText.text += ' ($offsets)'.replace(',', ', ');
		}

		if (config != null) {
			var currentAnim:String = curAnimText.text;
			if (config.animations.exists(currentAnim) && config.animations.get(currentAnim) != null)
				addButton.label = 'Update';
			else
				addButton.label = 'Add';

			config.scale = scaleNumericStepper.value;
		}

		var blockInput:Bool = (UIFocus.focused != null) || UIRoot.overlayOpen;
		if (!blockInput && config != null && config.animations != null && config.animations.exists(curAnim) && curAnim != null && curAnim.length > 0) {
			function splash() {
				if (config.animations.get(curAnim) != null) {
					playStrumAnim(curAnim, config.animations.get(curAnim).noteData);
					FlxTween.cancelTweensOf(errorText);
					errorText.alpha = 0;
				}
			}

			var changedOffset = false;
			if (FlxG.keys.pressed.CONTROL && config.animations.get(curAnim) != null) {
				if (FlxG.keys.justPressed.C) {
					copiedOffset = config.animations.get(curAnim).offsets.copy();
				} else if (FlxG.keys.justPressed.V) {
					var conf = config.animations.get(curAnim);
					conf.offsets = copiedOffset.copy();
					config.animations.set(curAnim, conf);
					changedOffset = true;
				} else if (FlxG.keys.justPressed.R) {
					var conf = config.animations.get(curAnim);
					conf.offsets = [0, 0];
					config.animations.set(curAnim, conf);
					changedOffset = true;
				}
			}

			var multiplier:Int = (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyPressed(LEFT_SHOULDER)) ? 10 : 1;

			var moveKeysP = [
				FlxG.keys.justPressed.LEFT,
				FlxG.keys.justPressed.RIGHT,
				FlxG.keys.justPressed.UP,
				FlxG.keys.justPressed.DOWN
			];
			if (moveKeysP.contains(true)) {
				config.animations[curAnim].offsets[0] += ((moveKeysP[0] ? 1 : 0) - (moveKeysP[1] ? 1 : 0)) * multiplier;
				config.animations[curAnim].offsets[1] += ((moveKeysP[2] ? 1 : 0) - (moveKeysP[3] ? 1 : 0)) * multiplier;
				changedOffset = true;
			}

			var moveKeys = [
				FlxG.keys.pressed.LEFT,
				FlxG.keys.pressed.RIGHT,
				FlxG.keys.pressed.UP,
				FlxG.keys.pressed.DOWN
			];
			if (moveKeys.contains(true)) {
				holdingArrowsTime += elapsed;
				if (holdingArrowsTime > 0.6) {
					holdingArrowsElapsed += elapsed;
					while (holdingArrowsElapsed > (1 / 60)) {
						config.animations[curAnim].offsets[0] += ((moveKeys[0] ? 1 : 0) - (moveKeys[1] ? 1 : 0)) * multiplier;
						config.animations[curAnim].offsets[1] += ((moveKeys[2] ? 1 : 0) - (moveKeys[3] ? 1 : 0)) * multiplier;
						holdingArrowsElapsed -= (1 / 60);
						changedOffset = true;
					}
				}
			} else
				holdingArrowsTime = 0;

			if (changedOffset || FlxG.keys.justPressed.SPACE)
				splash();
		}

		if (!blockInput) {
			if (controls.BACK)
				MusicBeatState.switchState(new MasterEditorMenu());
			if (FlxG.keys.justPressed.F1)
				openSubState(new NoteSplashEditorHelpSubState());
		}

		if (!FlxSmidr.mouseBlocked && FlxG.mouse.overlaps(strums)) {
			strums.forEach(function(strum:StrumNote) {
				if (FlxG.mouse.overlaps(strum)) {
					if (!FlxG.mouse.justPressed) {
						if (strum.animation.curAnim.name != 'pressed' && strum.animation.curAnim.name != 'confirm')
							strum.playAnim('pressed');
					} else {
						strum.playAnim('confirm', true);

						var splash:NoteSplash = new NoteSplash(0, 0, imageSkin);
						splash.inEditor = true;
						splash.config = config;
						splash.babyArrow = strum;
						splash.spawnSplashNote(0, 0, strum.ID % 4);
						splashes.add(splash);
					}
				} else
					strum.playAnim('static');
			});
		} else {
			for (strum in strums)
				strum.playAnim('static');
		}
	}

	function playStrumAnim(?name:String, noteData:Int) {
		var splash:NoteSplash = new NoteSplash(0, 0, imageSkin);
		splash.inEditor = true;
		splash.config = config;
		if (noteData < 0)
			noteData = 0;

		if (name != null && splash.animation.exists(name)) {
			splash.babyArrow = strums.members[noteData % 4];
			splash.spawnSplashNote(0, 0, noteData, null, false);
			splash.alpha = 1;
			splashes.add(splash);
		} else {
			errorText.alpha = 1;
			errorText.text = "ERROR while playing splash";

			FlxTween.cancelTweensOf(errorText);
			FlxTween.tween(errorText, {alpha: 0}, {startDelay: 1});
		}
	}

	function resetRGB() {
		redShader = [0, 0, 0];
		greenShader = [0, 0, 0];
		blueShader = [0, 0, 0];
	}

	function parseRGB() {
		resetRGB();
		if (config.rgb != null)
			for (i in 0...config.rgb.length) {
				if (i > 2)
					break;

				var rgb = config.rgb[i];
				if (rgb == null) {
					if (i == 0)
						redEnabled = false;
					else if (i == 1)
						greenEnabled = false;
					else if (i == 2)
						blueEnabled = false;

					continue;
				} else {
					if (i == 0)
						redEnabled = true;
					else if (i == 1)
						greenEnabled = true;
					else if (i == 2)
						blueEnabled = true;
				}

				var colors = [rgb.r, rgb.g, rgb.b];
				if (i == 0)
					redShader = colors;
				else if (i == 1)
					greenShader = colors;
				else if (i == 2)
					blueShader = colors;
			}
		else {
			resetRGB();
			redEnabled = blueEnabled = greenEnabled = false;
		}
	}

	function setConfigRGB() {
		if (config == null)
			config = NoteSplash.createConfig();

		if (!redEnabled && !greenEnabled && !blueEnabled) {
			config.rgb = null;
			return;
		}

		config.rgb = [];

		if (redEnabled)
			config.rgb.push({r: redShader[0], g: redShader[1], b: redShader[2]});
		else
			config.rgb.push(null);

		if (greenEnabled)
			config.rgb.push({r: greenShader[0], g: greenShader[1], b: greenShader[2]});
		else
			config.rgb.push(null);

		if (blueEnabled)
			config.rgb.push({r: blueShader[0], g: blueShader[1], b: blueShader[2]});
		else
			config.rgb.push(null);
	}

	var _file:FileReference;

	function onSaveComplete(_):Void {
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved file.");
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void {
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void {
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving file");
	}

	function saveSplash() {
		imageSkin = imageInputText.text;
		var data:String = Json.stringify(config, "\t");
		if (data.length > 0) {
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, imageSkin + ".json");
		}
	}

	public function loadTxt() {
		var jsonFilter:FileFilter = new FileFilter('Select a note splash TXT', '*.txt');
		_file = new FileReference();
		_file.addEventListener(Event.SELECT, onLoadComplete);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file.browse([#if !mac jsonFilter #end]);
	}

	function onLoadComplete(_):Void {
		_file.removeEventListener(Event.SELECT, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		try {
			var txtLoaded:Dynamic = Json.parse(Json.stringify(_file));
			var txt:String = null;
			var file:String = "config.json";
			#if MODS_ALLOWED
			if (txtLoaded.__path != null) {
				try
					txt = File.getContent(txtLoaded.__path)
				catch (e)
					txt = null;
				file = txtLoaded.__path;
				file = file.substring(0, file.length - 4) + ".json";
			}

			var conf = parseTxt(txt);
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(Json.stringify(conf, "\t"), file);
			#end
		} catch (e) {
			trace(e.stack);
		}
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onLoadCancel(_):Void {
		_file.removeEventListener(Event.SELECT, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Cancelled file loading.");
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onLoadError(_):Void {
		_file.removeEventListener(Event.SELECT, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Problem loading file");
	}

	override function destroy() {
		NoteSplash.configs.clear();
		if (uiRoot != null) {
			FlxSmidr.dispose();
			uiRoot = null;
		}
		super.destroy();

		FlxG.sound.music.volume = 1;
		FlxG.sound.muteKeys = [FlxKey.ZERO];
		FlxG.sound.volumeDownKeys = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
		FlxG.sound.volumeUpKeys = [FlxKey.NUMPADPLUS, FlxKey.PLUS];
	}

	public static function parseTxt(content:String):NoteSplashConfig {
		var config = NoteSplash.createConfig();
		if (content == null)
			return config;

		var trim:String = content.trim();
		if (trim.length < 1) // empty txt
			return config;

		var configs = content.split('\n');
		// checks for empty txts
		if (configs.length < 2 || configs[0].trim() == "")
			return config;

		var animation:String = configs[0].rtrim();
		var fps:Array<Null<Int>> = [22, 26];
		if (configs[1] != null && configs[1].trim() != "") {
			var newFps = configs[1].trim().split(" ");
			fps = [Std.parseInt(newFps[0]), Std.parseInt(newFps[1])];
			if (fps[0] == null)
				fps[0] = 22;
			if (fps[1] == null)
				fps[1] = 26;
		}

		var offsets:Array<Array<Null<Float>>> = [[0, 0]];
		if (configs.length > 2) {
			offsets = [];
			for (i in 2...configs.length) {
				var offset = configs[i].trim();
				if (offset != "") {
					var offset:Array<String> = offset.split(" ");
					var x:Float = Std.parseFloat(offset[0]);
					var y:Float = Std.parseFloat(offset[1]);
					if (Math.isNaN(x))
						x = 0;
					if (Math.isNaN(y))
						y = 0;
					offsets.push([x, y]);
				}
			}
		}

		var i = 0;
		var k = 1;
		while (true) {
			for (col in Note.colArray) {
				var anim = k <= 1 ? col : '$col' + k;
				var offset = offsets[FlxMath.wrap(i, 0, Std.int(offsets.length - 1))];

				config = NoteSplash.addAnimationToConfig(config, 1, anim, '$animation $col $k', fps, offset, [], i);
				i++;
			}
			if (offsets[i] == null)
				break;
			k++;
		}

		return config;
	}
}

class NoteSplashEditorHelpSubState extends MusicBeatSubstate {
	public function new() {
		super();

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.6;
		add(bg);

		var str:Array<String> = [
			"Click on a Strum or Press Space",
			"to spawn a Splash",
			"",
			"Arrow Keys - Move Offset",
			"Hold Shift - Move Offsets 10x faster",
			"",
			"Ctrl + C - Copy Current Offset",
			"Ctrl + V - Paste Copied Offset on Current Splash",
			"Ctrl + R - Reset Current Offset",
			"",
			"On every 4 subsequent note datas",
			"an extra set of animations will be added"
		];

		var helpTexts:FlxSpriteGroup = new FlxSpriteGroup();
		for (i => txt in str) {
			if (txt.length < 1)
				continue;

			var helpText:FlxText = new FlxText(0, 0, 0, txt, 24);
			helpText.setFormat(null, 24, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
			helpText.borderColor = FlxColor.BLACK;
			helpText.scrollFactor.set();
			helpText.borderSize = 1;
			helpText.screenCenter();
			add(helpText);
			helpText.y += ((i - str.length / 2) * 32) + 16;
			helpTexts.add(helpText);
		}
		add(helpTexts);

		var noteDataText:FlxText = new FlxText();
		noteDataText.setFormat(null, 24, FlxColor.WHITE, RIGHT, OUTLINE_FAST, FlxColor.BLACK);
		noteDataText.text = "NOTE DATAS:\nLEFT: 0\nDOWN: 1\nUP: 2\nRIGHT: 3";
		noteDataText.x = FlxG.width - noteDataText.width - 5;
		noteDataText.y = FlxG.height - noteDataText.height - 5;

		add(noteDataText);
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (controls.BACK || FlxG.keys.justPressed.F1)
			close();
	}
}
