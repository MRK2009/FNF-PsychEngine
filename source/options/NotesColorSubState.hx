package options;

import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxSpriteUtil;
import lime.system.Clipboard;
import flixel.util.FlxGradient;
import objects.notes.Receptor;
import objects.notes.NoteSprite;
import objects.notes.SustainSprite;
import objects.notes.NoteData;
import objects.Note;
import backend.NoteSkinConfig;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

class NotesColorSubState extends MusicBeatSubstate {
	var onModeColumn:Bool = true;
	var curSelectedMode:Int = 0;
	var curSelectedNote:Int = 0;
	var onPixel:Bool = false;
	var prevKeyCount:Int = Mania.DEFAULT;
	var targetKey:Int = 0;
	var overrideStored:Bool = false;
	var targetText:FlxText;
	var pixelText:FlxText;
	var dataArray:Array<Array<FlxColor>>;

	// Which asset is being edited. 'notes' always; the others only when their link is OFF and the skin
	// allows colouring them. Indexed parallel to the preview cells (NOTE/HOLD/SPLASH/STATIC/PRESSED/CONFIRM).
	var editElement:String = 'notes';

	static var PV_ELEMENTS:Array<String> = ['notes', 'holds', 'splash', 'strums', 'pressed', 'confirm'];

	static var ELEMENT_LINK:Map<String, String> = [
		'holds' => 'linkSustainColor', 'splash' => 'linkSplashColor', 'strums' => 'linkStrumColor',
		'pressed' => 'linkPressedColor', 'confirm' => 'linkConfirmColor'
	];

	var checkSprs:Array<FlxSprite> = [];
	var checkLabels:Array<FlxText> = [];
	var checkFields:Array<String> = [];
	var checkRespawn:Array<Bool> = [];
	var checkOnGfx:FlxGraphic;
	var checkOffGfx:FlxGraphic;

	static inline var CHECK_SIZE:Int = 28;

	var hexTypeLine:FlxSprite;
	var hexTypeNum:Int = -1;
	var hexTypeVisibleTimer:Float = 0;

	var copyButton:FlxSprite;
	var pasteButton:FlxSprite;

	var colorGradient:FlxSprite;
	var colorGradientSelector:FlxSprite;
	var colorPalette:FlxSprite;
	var colorWheel:FlxSprite;
	var colorWheelSelector:FlxSprite;

	var alphabetR:Alphabet;
	var alphabetG:Alphabet;
	var alphabetB:Alphabet;
	var alphabetHex:Alphabet;

	var stepUp:Array<FlxSprite> = [];
	var stepDown:Array<FlxSprite> = [];
	var stepHold:Float = 0;

	var modeBG:FlxSprite;
	var notesBG:FlxSprite;
	var cellHighlight:FlxSprite;

	// controller support
	var controllerPointer:FlxSprite;
	var _lastControllerMode:Bool = false;
	var tipTxt:FlxText;

	public function new() {
		super();

		#if mobile
		addTouchPad('FULL', 'A_B_C');
		#end

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Note Colors Menu", null);
		#end

		onPixel = PlayState.isPixelStage;
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.color = 0xFF1A1A2E;
		bg.screenCenter();
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);

		addPanel(4, 4, 700, 684);
		addPanel(712, 4, 564, 684);

		checkOnGfx = makeCheckGraphic(true);
		checkOffGfx = makeCheckGraphic(false);

		// channel cells + lane strip frames
		for (i in 0...3)
			addPanel(28 + i * 150, 134, 124, 80);
		addPanel(18, 276, 670, 98);

		modeBG = new FlxSprite(28, 134).makeGraphic(424, 80, FlxColor.WHITE);
		modeBG.visible = false;
		modeBG.alpha = 0.12;
		add(modeBG);

		notesBG = new FlxSprite(22, 280).makeGraphic(662, 90, FlxColor.WHITE);
		notesBG.visible = false;
		notesBG.alpha = 0.12;
		add(notesBG);

		modeNotes = new FlxTypedGroup<FlxSprite>();
		add(modeNotes);

		myNotes = new FlxTypedGroup<Receptor>();
		add(myNotes);

		var kcHint:FlxText = makeText(30, 26, 180, 'KEYCOUNT', 18, LEFT);
		kcHint.alpha = 0.7;
		add(kcHint);
		targetText = makeText(216, 22, 240, 'SHARED', 26, LEFT);
		add(targetText);
		var kcKeys:FlxText = makeText(468, 28, 220, '( Q / E )', 15, LEFT);
		kcKeys.alpha = 0.5;
		add(kcKeys);
		var pxHint:FlxText = makeText(30, 64, 180, 'PIXEL', 18, LEFT);
		pxHint.alpha = 0.7;
		add(pxHint);
		pixelText = makeText(216, 60, 240, 'OFF', 26, LEFT);
		add(pixelText);
		var pxKeys:FlxText = makeText(468, 66, 220, '( CTRL )', 15, LEFT);
		pxKeys.alpha = 0.5;
		add(pxKeys);
		var chLabel:FlxText = makeText(30, 108, 200, 'CHANNEL', 18, LEFT);
		chLabel.alpha = 0.7;
		add(chLabel);
		var chNames:Array<String> = ['Main', 'Border', 'Shadow'];
		for (i in 0...3) {
			var cl:FlxText = makeText(28 + i * 150, 216, 124, chNames[i], 15, CENTER);
			cl.alpha = 0.7;
			add(cl);
		}
		var laneLabel:FlxText = makeText(30, 250, 200, 'LANE', 18, LEFT);
		laneLabel.alpha = 0.7;
		add(laneLabel);

		// preview frame + element labels
		addPanel(724, 16, 540, 348);
		cellHighlight = new FlxSprite(0, 0).makeGraphic(PV_BOX + 10, PV_BOX + 10, FlxColor.WHITE);
		cellHighlight.alpha = 0.14;
		cellHighlight.scrollFactor.set();
		cellHighlight.visible = false;
		add(cellHighlight);
		var prevLabel:FlxText = makeText(740, 22, 200, 'PREVIEW', 15, LEFT);
		prevLabel.alpha = 0.6;
		add(prevLabel);
		var prevNames:Array<String> = ['NOTE', 'HOLD', 'SPLASH', 'STATIC', 'PRESSED', 'CONFIRM'];
		var prevCols:Array<Float> = [820, 990, 1160];
		for (i in 0...6) {
			var cx:Float = prevCols[i % 3];
			var ly:Float = (i < 3) ? 178 : 338;
			var pl:FlxText = makeText(cx - 75, ly, 150, prevNames[i], 14, CENTER);
			pl.alpha = 0.55;
			add(pl);
		}

		copyButton = new FlxSprite(1158, 374).loadGraphic(Paths.image('noteColorMenu/copy'));
		copyButton.setGraphicSize(42, 42);
		copyButton.updateHitbox();
		copyButton.alpha = 0.6;
		add(copyButton);

		pasteButton = new FlxSprite(1210, 374).loadGraphic(Paths.image('noteColorMenu/paste'));
		pasteButton.setGraphicSize(42, 42);
		pasteButton.updateHitbox();
		pasteButton.alpha = 0.6;
		add(pasteButton);

		colorGradient = FlxGradient.createGradientFlxSprite(34, 180, [FlxColor.WHITE, FlxColor.BLACK]);
		colorGradient.setPosition(958, 432);
		add(colorGradient);

		colorGradientSelector = new FlxSprite(955, 432).makeGraphic(40, 10, FlxColor.WHITE);
		colorGradientSelector.offset.y = 5;
		add(colorGradientSelector);

		colorPalette = new FlxSprite(730, 624).loadGraphic(Paths.image('noteColorMenu/palette', false));
		colorPalette.scale.set(12, 12);
		colorPalette.updateHitbox();
		colorPalette.antialiasing = false;
		add(colorPalette);

		colorWheel = new FlxSprite(732, 432).loadGraphic(Paths.image('noteColorMenu/colorWheel'));
		colorWheel.setGraphicSize(184, 184);
		colorWheel.updateHitbox();
		add(colorWheel);

		colorWheelSelector = new FlxShapeCircle(0, 0, 8, {thickness: 0}, FlxColor.WHITE);
		colorWheelSelector.offset.set(8, 8);
		colorWheelSelector.alpha = 0.6;
		add(colorWheelSelector);

		alphabetHex = makeColorAlphabet(810, 384);
		hexTypeLine = new FlxSprite(0, 376).makeGraphic(5, 44, FlxColor.WHITE);
		hexTypeLine.visible = false;

		// R / G / B steppers (spinboxes) to the right of the brightness slider
		var chNames:Array<String> = ['R', 'G', 'B'];
		var chCols:Array<FlxColor> = [0xFFFF7777, 0xFF77FF77, 0xFF77AAFF];
		alphabetR = makeColorAlphabet(1130, 452);
		alphabetG = makeColorAlphabet(1130, 508);
		alphabetB = makeColorAlphabet(1130, 564);
		for (i in 0...3) {
			var ry:Float = 446 + i * 56;
			var lab:FlxText = makeText(1014, ry + 4, 34, chNames[i], 22, LEFT);
			lab.color = chCols[i];
			add(lab);
			stepDown.push(makeStepButton(1056, ry, '-'));
			stepUp.push(makeStepButton(1198, ry, '+'));
		}
		add(hexTypeLine);

		buildCheckboxes();

		prevKeyCount = Mania.current;
		Mania.apply(Mania.DEFAULT);

		spawnNotes();
		updateNotes(true);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);

		tipTxt = makeText(0, FlxG.height - 30, FlxG.width, '', 16, CENTER);
		tipTxt.alpha = 0.85;
		add(tipTxt);
		updateTip();

		controllerPointer = new FlxShapeCircle(0, 0, 20, {thickness: 0}, FlxColor.WHITE);
		controllerPointer.offset.set(20, 20);
		controllerPointer.screenCenter();
		controllerPointer.alpha = 0.6;
		add(controllerPointer);

		FlxG.mouse.visible = !controls.controllerMode;
		controllerPointer.visible = controls.controllerMode;
		_lastControllerMode = controls.controllerMode;
	}

	function updateTip() {
		tipTxt.text = 'ARROWS Select   Q/E Keycount   CTRL Pixel   RESET Reset (SHIFT = all)   ESC Back';
	}

	var _storedColor:FlxColor;
	var changingNote:Bool = false;
	var holdingOnObj:FlxSprite;
	var allowedTypeKeys:Map<FlxKey, String> = [
		ZERO => '0',
		ONE => '1',
		TWO => '2',
		THREE => '3',
		FOUR => '4',
		FIVE => '5',
		SIX => '6',
		SEVEN => '7',
		EIGHT => '8',
		NINE => '9',
		NUMPADZERO => '0',
		NUMPADONE => '1',
		NUMPADTWO => '2',
		NUMPADTHREE => '3',
		NUMPADFOUR => '4',
		NUMPADFIVE => '5',
		NUMPADSIX => '6',
		NUMPADSEVEN => '7',
		NUMPADEIGHT => '8',
		NUMPADNINE => '9',
		A => 'A',
		B => 'B',
		C => 'C',
		D => 'D',
		E => 'E',
		F => 'F'
	];

	override function update(elapsed:Float) {
		if (controls.BACK) {
			FlxG.mouse.visible = false;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		super.update(elapsed);

		handleSteppers(elapsed);

		// Replay the splash preview a moment after it self-kills, so the cell isn't left empty.
		if (bigSplash != null && !bigSplash.alive) {
			splashWait -= elapsed;
			if (splashWait <= 0)
				triggerSplashPreview();
		}

		// Early controller checking
		if (FlxG.gamepads.anyJustPressed(ANY))
			controls.controllerMode = true;
		else if (FlxG.mouse.justPressed || FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0)
			controls.controllerMode = false;
		//

		var changedToController:Bool = false;
		if (controls.controllerMode != _lastControllerMode) {
			// trace('changed controller mode');
			FlxG.mouse.visible = !controls.controllerMode;
			controllerPointer.visible = controls.controllerMode;

			// changed to controller mid state
			if (controls.controllerMode) {
				controllerPointer.x = FlxG.mouse.x;
				controllerPointer.y = FlxG.mouse.y;
				changedToController = true;
			}
			// changed to keyboard mid state
			/*else
				{
					FlxG.mouse.x = controllerPointer.x;
					FlxG.mouse.y = controllerPointer.y;
				}
				// apparently theres no easy way to change mouse position that i know, oh well
			 */
			_lastControllerMode = controls.controllerMode;
			updateTip();
		}

		// controller things
		var analogX:Float = 0;
		var analogY:Float = 0;
		var analogMoved:Bool = false;
		if (controls.controllerMode && (changedToController || FlxG.gamepads.anyInput())) {
			for (gamepad in FlxG.gamepads.getActiveGamepads()) {
				analogX = gamepad.getXAxis(LEFT_ANALOG_STICK);
				analogY = gamepad.getYAxis(LEFT_ANALOG_STICK);
				analogMoved = (analogX != 0 || analogY != 0);
				if (analogMoved)
					break;
			}
			controllerPointer.x = Math.max(0, Math.min(FlxG.width, controllerPointer.x + analogX * 1000 * elapsed));
			controllerPointer.y = Math.max(0, Math.min(FlxG.height, controllerPointer.y + analogY * 1000 * elapsed));
		}
		var controllerPressed:Bool = (controls.controllerMode && controls.ACCEPT);
		//

		if (FlxG.keys.justPressed.CONTROL) {
			onPixel = !onPixel;
			pixelText.text = onPixel ? 'ON' : 'OFF';
			spawnNotes();
			updateNotes(true);
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}

		if (hexTypeNum < 0 && (FlxG.keys.justPressed.Q || FlxG.keys.justPressed.E)) {
			targetKey = FlxMath.wrap(targetKey + (FlxG.keys.justPressed.E ? 1 : -1), 0, 9);
			curSelectedNote = 0;
			spawnNotes();
			updateNotes(true);
			updateTargetText();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}

		if (hexTypeNum > -1) {
			var keyPressed:FlxKey = cast(FlxG.keys.firstJustPressed(), FlxKey);
			hexTypeVisibleTimer += elapsed;
			var changed:Bool = false;
			if (changed = FlxG.keys.justPressed.LEFT)
				hexTypeNum--;
			else if (changed = FlxG.keys.justPressed.RIGHT)
				hexTypeNum++;
			else if (allowedTypeKeys.exists(keyPressed)) {
				// trace('keyPressed: $keyPressed, lil str: ' + allowedTypeKeys.get(keyPressed));
				var curColor:String = alphabetHex.text;
				var newColor:String = curColor.substring(0, hexTypeNum) + allowedTypeKeys.get(keyPressed) + curColor.substring(hexTypeNum + 1);

				var colorHex:FlxColor = FlxColor.fromString('#' + newColor);
				setShaderColor(colorHex);
				_storedColor = getShaderColor();
				updateColors();

				// move you to next letter
				hexTypeNum++;
				changed = true;
			} else if (FlxG.keys.justPressed.ENTER)
				hexTypeNum = -1;

			var end:Bool = false;
			if (changed) {
				if (hexTypeNum > 5) // Typed last letter
				{
					hexTypeNum = -1;
					end = true;
					hexTypeLine.visible = false;
				} else {
					if (hexTypeNum < 0)
						hexTypeNum = 0;
					else if (hexTypeNum > 5)
						hexTypeNum = 5;
					centerHexTypeLine();
					hexTypeLine.visible = true;
				}
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			}
			if (!end)
				hexTypeLine.visible = Math.floor(hexTypeVisibleTimer * 2) % 2 == 0;
		} else {
			var add:Int = 0;
			if (analogX == 0 && !changedToController) {
				if (controls.UI_LEFT_P)
					add = -1;
				else if (controls.UI_RIGHT_P)
					add = 1;
			}

			if (analogY == 0 && !changedToController && (controls.UI_UP_P || controls.UI_DOWN_P)) {
				onModeColumn = !onModeColumn;
				modeBG.visible = onModeColumn;
				notesBG.visible = !onModeColumn;
			}

			if (add != 0) {
				if (onModeColumn)
					changeSelectionMode(add);
				else
					changeSelectionNote(add);
			}
			hexTypeLine.visible = false;
		}

		// Copy/Paste buttons
		var generalMoved:Bool = (FlxG.mouse.justMoved || analogMoved);
		var generalPressed:Bool = (FlxG.mouse.justPressed || controllerPressed);
		if (generalMoved) {
			copyButton.alpha = 0.6;
			pasteButton.alpha = 0.6;
		}

		if (generalPressed) {
			// Click a preview cell to choose which asset the picker edits.
			var pcols:Array<Float> = [PV_C0, PV_C1, PV_C2];
			for (ci in 0...6) {
				var cx:Float = pcols[ci % 3];
				var cy:Float = (ci < 3) ? PV_R1 : PV_R2;
				if (Math.abs(pointerX() - cx) <= PV_BOX / 2 && Math.abs(pointerY() - cy) <= PV_BOX / 2) {
					selectElement(PV_ELEMENTS[ci]);
					return;
				}
			}

			for (i in 0...checkSprs.length) {
				if (!pointerOverlaps(checkSprs[i]))
					continue;
				var on:Bool = !(Reflect.field(ClientPrefs.data, checkFields[i]) == true);
				Reflect.setField(ClientPrefs.data, checkFields[i], on);
				redrawCheck(checkSprs[i], on);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				// A link toggle can make the current edit target uneditable -- fall back to notes. Either
				// way, rebuild so the preview live-updates to the new linked/independent colours.
				if (!elementEditable(editElement))
					editElement = 'notes';
				spawnNotes();
				updateNotes(true);
				return;
			}
		}

		if (pointerOverlaps(copyButton)) {
			copyButton.alpha = 1;
			if (generalPressed) {
				Clipboard.text = getShaderColor().toHexString(false, false);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				trace('copied: ' + Clipboard.text);
			}
			hexTypeNum = -1;
		} else if (pointerOverlaps(pasteButton)) {
			pasteButton.alpha = 1;
			if (generalPressed) {
				var formattedText = Clipboard.text.trim().toUpperCase().replace('#', '').replace('0x', '');
				var newColor:Null<FlxColor> = FlxColor.fromString('#' + formattedText);
				// trace('#${Clipboard.text.trim().toUpperCase()}');
				if (newColor != null && formattedText.length == 6) {
					setShaderColor(newColor);
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					_storedColor = getShaderColor();
					updateColors();
				} else // errored
					FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			}
			hexTypeNum = -1;
		}

		// Click
		if (generalPressed) {
			hexTypeNum = -1;
			if (pointerOverlaps(modeNotes)) {
				modeNotes.forEachAlive(function(note:FlxSprite) {
					if (curSelectedMode != note.ID && pointerOverlaps(note)) {
						modeBG.visible = notesBG.visible = false;
						curSelectedMode = note.ID;
						onModeColumn = true;
						updateNotes();
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					}
				});
			} else if (pointerOverlaps(myNotes)) {
				myNotes.forEachAlive(function(note:Receptor) {
					if (curSelectedNote != note.ID && pointerOverlaps(note)) {
						modeBG.visible = notesBG.visible = false;
						curSelectedNote = note.ID;
						onModeColumn = false;
						applyPreview();
						updateNotes();
						FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
					}
				});
			} else if (pointerOverlaps(colorWheel)) {
				_storedColor = getShaderColor();
				holdingOnObj = colorWheel;
			} else if (pointerOverlaps(colorGradient)) {
				_storedColor = getShaderColor();
				holdingOnObj = colorGradient;
			} else if (pointerOverlaps(colorPalette)) {
				setShaderColor(colorPalette.pixels.getPixel32(Std.int((pointerX() - colorPalette.x) / colorPalette.scale.x),
					Std.int((pointerY() - colorPalette.y) / colorPalette.scale.y)));
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				updateColors();
			} else if (pointerOverlaps(skinNote)) {
				onPixel = !onPixel;
				spawnNotes();
				updateNotes(true);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			} else if (pointerY() >= hexTypeLine.y
				&& pointerY() < hexTypeLine.y + hexTypeLine.height
				&& Math.abs(pointerX() - 800) <= 84) {
				hexTypeNum = 0;
				for (letter in alphabetHex.letters) {
					if (letter.x - letter.offset.x + letter.width <= pointerX())
						hexTypeNum++;
					else
						break;
				}
				if (hexTypeNum > 5)
					hexTypeNum = 5;
				hexTypeLine.visible = true;
				centerHexTypeLine();
			} else
				holdingOnObj = null;
		}
		// holding
		if (holdingOnObj != null) {
			if (FlxG.mouse.justReleased || (controls.controllerMode && controls.justReleased('accept'))) {
				holdingOnObj = null;
				_storedColor = getShaderColor();
				updateColors();
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			} else if (generalMoved || generalPressed) {
				if (holdingOnObj == colorGradient) {
					var newBrightness = 1 - FlxMath.bound((pointerY() - colorGradient.y) / colorGradient.height, 0, 1);
					_storedColor.alpha = 1;
					if (_storedColor.brightness == 0) // prevent bug
						setShaderColor(FlxColor.fromRGBFloat(newBrightness, newBrightness, newBrightness));
					else
						setShaderColor(FlxColor.fromHSB(_storedColor.hue, _storedColor.saturation, newBrightness));
					updateColors(_storedColor);
				} else if (holdingOnObj == colorWheel) {
					var center:FlxPoint = new FlxPoint(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
					var mouse:FlxPoint = pointerFlxPoint();
					var hue:Float = FlxMath.wrap(FlxMath.wrap(Std.int(mouse.degreesTo(center)), 0, 360) - 90, 0, 360);
					var sat:Float = FlxMath.bound(mouse.dist(center) / colorWheel.width * 2, 0, 1);
					// trace('$hue, $sat');
					if (sat != 0)
						setShaderColor(FlxColor.fromHSB(hue, sat, _storedColor.brightness));
					else
						setShaderColor(FlxColor.fromRGBFloat(_storedColor.brightness, _storedColor.brightness, _storedColor.brightness));
					updateColors();
				}
			}
		} else if (controls.RESET && hexTypeNum < 0) {
			if (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyPressed(LEFT_SHOULDER)) {
				for (i in 0...3) {
					var color:FlxColor = defaultColor(curSelectedNote, i);
					switch (i) {
						case 0:
							getShader().r = color;
						case 1:
							getShader().g = color;
						case 2:
							getShader().b = color;
					}
					dataArray[curSelectedNote][i] = color;
				}
			}
			setShaderColor(defaultColor(curSelectedNote, curSelectedMode));
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			updateColors();
		}
	}

	function pointerOverlaps(obj:Dynamic) {
		if (!controls.controllerMode)
			return FlxG.mouse.overlaps(obj);
		return FlxG.overlap(controllerPointer, obj);
	}

	function pointerX():Float {
		if (!controls.controllerMode)
			return FlxG.mouse.x;
		return controllerPointer.x;
	}

	function pointerY():Float {
		if (!controls.controllerMode)
			return FlxG.mouse.y;
		return controllerPointer.y;
	}

	function pointerFlxPoint():FlxPoint {
		if (!controls.controllerMode)
			return FlxG.mouse.getScreenPosition();
		return controllerPointer.getScreenPosition();
	}

	function centerHexTypeLine() {
		// trace(hexTypeNum);
		if (hexTypeNum > 0) {
			var letter = alphabetHex.letters[hexTypeNum - 1];
			hexTypeLine.x = letter.x - letter.offset.x + letter.width;
		} else {
			var letter = alphabetHex.letters[0];
			hexTypeLine.x = letter.x - letter.offset.x;
		}
		hexTypeLine.x += hexTypeLine.width;
		hexTypeVisibleTimer = 0;
	}

	function changeSelectionMode(change:Int = 0) {
		curSelectedMode += change;
		if (curSelectedMode < 0)
			curSelectedMode = 2;
		if (curSelectedMode >= 3)
			curSelectedMode = 0;

		modeBG.visible = true;
		notesBG.visible = false;
		updateNotes();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function changeSelectionNote(change:Int = 0) {
		curSelectedNote += change;
		if (curSelectedNote < 0)
			curSelectedNote = dataArray.length - 1;
		if (curSelectedNote >= dataArray.length)
			curSelectedNote = 0;

		modeBG.visible = false;
		notesBG.visible = true;
		applyPreview();
		updateNotes();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	/** Options-styled framed panel (border + fill), matching OptionsState's look. **/
	function addPanel(x:Int, y:Int, w:Int, h:Int):Void {
		var border:FlxSprite = new FlxSprite(x - 2, y - 2).makeGraphic(1, 1, 0xFF3A3F58);
		border.scale.set(w + 4, h + 4);
		border.updateHitbox();
		border.alpha = 0.4;
		border.scrollFactor.set();
		add(border);
		var panel:FlxSprite = new FlxSprite(x, y).makeGraphic(1, 1, 0xFF12141F);
		panel.scale.set(w, h);
		panel.updateHitbox();
		panel.alpha = 0.55;
		panel.scrollFactor.set();
		add(panel);
	}

	/** vcr-font text matching the options menu styling. **/
	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, align:flixel.text.FlxTextAlign):FlxText {
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, align, OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		return t;
	}

	/** Checkbox graphic in the options menu style. **/
	function makeCheckGraphic(on:Bool):FlxGraphic {
		var s:FlxSprite = new FlxSprite();
		s.makeGraphic(CHECK_SIZE, CHECK_SIZE, FlxColor.TRANSPARENT, false, 'ncCheck_' + on);
		FlxSpriteUtil.drawRect(s, 1, 1, CHECK_SIZE - 3, CHECK_SIZE - 3, on ? 0xFF1E7A45 : FlxColor.TRANSPARENT,
			{thickness: 3, color: on ? 0xFF2EC46B : 0xFF8A8A8A});
		if (on) {
			FlxSpriteUtil.drawLine(s, 7, 15, 12, 21, {thickness: 4, color: FlxColor.WHITE});
			FlxSpriteUtil.drawLine(s, 12, 21, 22, 7, {thickness: 4, color: FlxColor.WHITE});
		}
		return s.graphic;
	}

	function redrawCheck(spr:FlxSprite, on:Bool):Void {
		spr.loadGraphic(on ? checkOnGfx : checkOffGfx);
		spr.setGraphicSize(CHECK_SIZE, CHECK_SIZE);
		spr.updateHitbox();
	}

	var _checkY:Float = 0;

	/** Builds the colorable/link toggle checkboxes (skin-gated) under the preview. **/
	function buildCheckboxes():Void {
		var cfg:NoteSkinData = null;
		var skin:String = NoteSkinConfig.activeSkin();
		if (skin != null)
			cfg = NoteSkinConfig.forCurrentKeys(skin);

		_checkY = 412;
		addCheck('Per-keycount Colours', 'noteColorPerKeycount', true);
		addCheck('One Colour for All', 'noteColorOneColor', true);
		_checkY += 12;
		if (linkSupported(cfg, 'splash'))
			addCheck('Link Splash Colour', 'linkSplashColor', false);
		if (linkSupported(cfg, 'holds'))
			addCheck('Link Hold Colour', 'linkSustainColor', false);
		if (linkSupported(cfg, 'pressed'))
			addCheck('Link Pressed Colour', 'linkPressedColor', false);
		if (linkSupported(cfg, 'confirm'))
			addCheck('Link Confirm Colour', 'linkConfirmColor', false);
		if (linkSupported(cfg, 'strums'))
			addCheck('Link Strum Colour', 'linkStrumColor', false);
	}

	function addCheck(label:String, field:String, respawn:Bool):Void {
		var on:Bool = (Reflect.field(ClientPrefs.data, field) == true);
		var spr:FlxSprite = new FlxSprite(30, _checkY);
		spr.scrollFactor.set();
		redrawCheck(spr, on);
		add(spr);
		var lbl:FlxText = makeText(30 + CHECK_SIZE + 12, _checkY + 4, 360, label, 18, LEFT);
		add(lbl);
		checkSprs.push(spr);
		checkLabels.push(lbl);
		checkFields.push(field);
		checkRespawn.push(respawn);
		_checkY += 34;
	}

	/** Whether the active skin can colour `element` (classic skins only wire the splash link). **/
	function linkSupported(cfg:NoteSkinData, element:String):Bool {
		return (cfg != null) ? NoteSkinConfig.colorableFor(cfg, element) : (element == 'splash');
	}

	// alphabets
	function makeColorAlphabet(x:Float = 0, y:Float = 0):Alphabet {
		var text:Alphabet = new Alphabet(x, y, '', true);
		text.alignment = CENTERED;
		text.setScale(0.6);
		add(text);
		return text;
	}

	/** A small options-styled stepper button with a centred symbol. **/
	function makeStepButton(x:Float, y:Float, sym:String):FlxSprite {
		var b:FlxSprite = new FlxSprite(x, y);
		b.makeGraphic(38, 38, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRect(b, 1, 1, 35, 35, 0xFF20243A, {thickness: 2, color: 0xFF3A3F58});
		b.scrollFactor.set();
		add(b);
		var t:FlxText = makeText(x, y + 3, 38, sym, 26, CENTER);
		add(t);
		return b;
	}

	/** Handles clicks/holds on the R/G/B stepper buttons (auto-repeat after a short delay). **/
	function handleSteppers(elapsed:Float):Void {
		var held:Int = -1;
		var dir:Int = 0;
		for (i in 0...3) {
			if (FlxG.mouse.overlaps(stepUp[i])) {
				if (FlxG.mouse.justPressed)
					adjustChannel(i, 1);
				if (FlxG.mouse.pressed) {
					held = i;
					dir = 1;
				}
			} else if (FlxG.mouse.overlaps(stepDown[i])) {
				if (FlxG.mouse.justPressed)
					adjustChannel(i, -1);
				if (FlxG.mouse.pressed) {
					held = i;
					dir = -1;
				}
			}
		}
		if (held >= 0 && !FlxG.mouse.justPressed) {
			stepHold += elapsed;
			if (stepHold > 0.35) {
				adjustChannel(held, dir);
				stepHold = 0.32;
			}
		} else if (held < 0)
			stepHold = 0;
	}

	/** Nudges one R/G/B component (0..255) of the current colour and applies it. **/
	function adjustChannel(i:Int, delta:Int):Void {
		var c:FlxColor = getShaderColor();
		var r:Int = c.red;
		var g:Int = c.green;
		var b:Int = c.blue;
		switch (i) {
			case 0:
				r = Std.int(Math.max(0, Math.min(255, r + delta)));
			case 1:
				g = Std.int(Math.max(0, Math.min(255, g + delta)));
			default:
				b = Std.int(Math.max(0, Math.min(255, b + delta)));
		}
		setShaderColor(FlxColor.fromRGB(r, g, b));
		_storedColor = getShaderColor();
		updateColors();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.3);
	}

	// notes sprites functions
	var skinNote:FlxSprite;
	var modeNotes:FlxTypedGroup<FlxSprite>;
	var myNotes:FlxTypedGroup<Receptor>;
	var bigNote:NoteSprite;
	var bigStrum:Receptor;
	var bigStatic:Receptor;
	var bigPressed:Receptor;
	var bigHold:SustainSprite;
	var bigSplash:objects.NoteSplash;
	var splashWait:Float = 0;

	public function spawnNotes() {
		if (pixelText != null)
			pixelText.text = onPixel ? 'ON' : 'OFF';
		if (onPixel)
			PlayState.stageUI = "pixel";

		dataArray = [];
		if (targetKey == 0) {
			dataArray = sharedStore(editElement);
			overrideStored = false;
		} else {
			var byKey:Array<Array<Array<FlxColor>>> = byKeyStore(editElement);
			var ov:Array<Array<FlxColor>> = byKey[targetKey - 1];
			if (ov != null && ov.length == targetKey) {
				dataArray = ov;
				overrideStored = true;
			} else {
				for (lane in Mania.composeShared(targetKey))
					dataArray.push([lane[0], lane[1], lane[2]]);
				overrideStored = false;
			}
		}
		if (curSelectedNote >= dataArray.length)
			curSelectedNote = dataArray.length - 1;

		// clear groups
		modeNotes.forEachAlive(function(note:FlxSprite) {
			note.kill();
			note.destroy();
		});
		myNotes.forEachAlive(function(note:Receptor) {
			note.kill();
			note.destroy();
		});
		modeNotes.clear();
		myNotes.clear();

		if (skinNote != null) {
			remove(skinNote);
			skinNote.destroy();
		}

		// respawn stuff -- skin/pixel toggle note next to the PIXEL row
		var res:Int = onPixel ? 17 : 160;
		skinNote = new FlxSprite(386, 50).loadGraphic(Paths.image('noteColorMenu/' + (onPixel ? 'notePixel' : 'note')), true, res, res);
		skinNote.antialiasing = ClientPrefs.data.antialiasing;
		skinNote.setGraphicSize(52);
		skinNote.updateHitbox();
		skinNote.animation.add('anim', [0], 24, true);
		skinNote.animation.play('anim', true);
		if (onPixel)
			skinNote.antialiasing = false;
		add(skinNote);

		// channel notes, centred in the three CHANNEL cells
		var res:Int = !onPixel ? 160 : 17;
		for (i in 0...3) {
			var newNote:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image('noteColorMenu/' + (!onPixel ? 'note' : 'notePixel')), true, res,
				res);
			newNote.antialiasing = ClientPrefs.data.antialiasing;
			newNote.setGraphicSize(64);
			newNote.updateHitbox();
			newNote.animation.add('anim', [i], 24, true);
			newNote.animation.play('anim', true);
			newNote.setPosition(90 + 150 * i - newNote.width * 0.5, 174 - newNote.height * 0.5);
			newNote.ID = i;
			if (onPixel)
				newNote.antialiasing = false;
			modeNotes.add(newNote);
		}

		Note.globalRgbShaders = [];
		var count:Int = dataArray.length;
		var stripX:Float = 28;
		var stripW:Float = 650;
		var stripCY:Float = 325;
		var cellW:Float = Math.min(96, stripW / count);
		var strumSize:Int = Std.int(Math.min(84, cellW - 10));
		var startX:Float = stripX + (stripW - cellW * count) * 0.5;
		// Build at the target keycount so the active note skin resolves the real per-lane graphics (incl.
		// the folder skin's centre note for odd keycounts); destroy() restores the saved keycount.
		Mania.apply(count);
		for (i in 0...count) {
			var pal:RGBPalette = new RGBPalette();
			var slotCol:Array<FlxColor> = dataArray[i];
			pal.r = slotCol[0];
			pal.g = slotCol[1];
			pal.b = slotCol[2];
			Note.globalRgbShaders[i] = pal;
			var newNote:Receptor = new Receptor(startX + (cellW * i), stripCY, i, 0, count);
			newNote.rgbShader.parent = Note.globalRgbShaders[i];
			newNote.shader = Note.globalRgbShaders[i].shader;
			newNote.useRGBShader = true;
			newNote.colorPerAnim = false;
			newNote.setGraphicSize(strumSize);
			newNote.updateHitbox();
			newNote.offset.set();
			newNote.setPosition(startX + cellW * i + (cellW - newNote.width) * 0.5, stripCY - newNote.height * 0.5);
			newNote.ID = i;
			myNotes.add(newNote);
		}

		applyPreview();
		_storedColor = getShaderColor();
		PlayState.stageUI = "normal";
	}

	// 2x3 preview grid: NOTE / HOLD / SPLASH over STATIC / PRESSED / CONFIRM. Every asset is fit + centred
	// inside a uniform PV_BOX cell so nothing overflows its slot.
	static inline var PV_C0:Float = 820;
	static inline var PV_C1:Float = 990;
	static inline var PV_C2:Float = 1160;
	static inline var PV_R1:Float = 98;
	static inline var PV_R2:Float = 258;
	static inline var PV_BOX:Int = 150;

	/**
		(Re)builds the preview grid for the selected lane at the target keycount: note / hold / splash on
		top, static / pressed / confirm receptors below -- all sharing the lane's palette so the colour
		shows on every element.
	**/
	function applyPreview():Void {
		var count:Int = dataArray.length;
		var col:Int = curSelectedNote;
		Mania.apply(count);

		teardownPreview();

		var ei:Int = PV_ELEMENTS.indexOf(editElement);
		if (cellHighlight != null && ei >= 0) {
			var hx:Float = [PV_C0, PV_C1, PV_C2][ei % 3];
			var hy:Float = (ei < 3) ? PV_R1 : PV_R2;
			cellHighlight.setPosition(hx - cellHighlight.width / 2, hy - cellHighlight.height / 2);
			cellHighlight.visible = true;
		}

		var holdPal:RGBPalette = elementPalette('holds', col);
		bigHold = new SustainSprite();
		var hData:NoteData = new NoteData();
		hData.column = col;
		hData.length = 1000;
		bigHold.apply(hData, count);
		bindPreviewShader(bigHold, bigHold.rgbShader, holdPal);
		bindPreviewShader(bigHold.tail, bigHold.tailRGB, holdPal);
		layoutHold(PV_C1, PV_R1);
		add(bigHold);

		var notePal:RGBPalette = elementPalette('notes', col);
		bigNote = new NoteSprite();
		var nData:NoteData = new NoteData();
		nData.column = col;
		bigNote.apply(nData, count);
		bigNote.rgbShader.parent = notePal;
		bigNote.rgbShader.enabled = true;
		bigNote.shader = notePal.shader;
		fitCell(bigNote, PV_C0, PV_R1);
		add(bigNote);

		bigStatic = makeReceptor(col, count, elementPalette('strums', col), 'static');
		fitCell(bigStatic, PV_C0, PV_R2);
		add(bigStatic);
		bigPressed = makeReceptor(col, count, elementPalette('pressed', col), 'pressed');
		fitCell(bigPressed, PV_C1, PV_R2);
		add(bigPressed);
		bigStrum = makeReceptor(col, count, elementPalette('confirm', col), 'confirm');
		fitCell(bigStrum, PV_C2, PV_R2);
		add(bigStrum);

		bigSplash = new objects.NoteSplash();
		bigSplash.inEditor = true;
		add(bigSplash);
		triggerSplashPreview();
	}

	/** Removes + destroys every preview drawable. **/
	function teardownPreview():Void {
		for (spr in [cast(bigHold, FlxSprite), cast(bigNote, FlxSprite), cast(bigStatic, FlxSprite), cast(bigPressed, FlxSprite),
			cast(bigStrum, FlxSprite), cast(bigSplash, FlxSprite)]) {
			if (spr != null) {
				remove(spr);
				spr.destroy();
			}
		}
		bigHold = null;
		bigNote = null;
		bigStatic = null;
		bigPressed = null;
		bigStrum = null;
		bigSplash = null;
	}

	/** A receptor locked to one animation state, coloured from the shared palette. **/
	function makeReceptor(col:Int, count:Int, pal:RGBPalette, anim:String):Receptor {
		var r:Receptor = new Receptor(0, 0, col, 0, count);
		r.colorPerAnim = false;
		r.useRGBShader = true;
		r.rgbShader.parent = pal;
		r.shader = pal.shader;
		r.playAnim(anim, true);
		if (r.animation.curAnim != null)
			r.animation.curAnim.finish();
		return r;
	}

	/** (Re)spawns the splash preview, fit into its cell and tinted with the lane colour. **/
	function triggerSplashPreview():Void {
		if (bigSplash == null)
			return;
		Mania.apply(dataArray.length);
		bigSplash.spawnSplashNote(0, 0, curSelectedNote, null, false);
		bigSplash.copyX = bigSplash.copyY = false;
		fitCell(bigSplash, PV_C2, PV_R1);
		bigSplash.rgbShader.copyValues(elementPalette('splash', curSelectedNote));
		splashWait = 0.3;
	}

	/** Scales a sprite to fit inside PV_BOX (preserving aspect) and centres it at (cx, cy). **/
	inline function fitCell(spr:FlxSprite, cx:Float, cy:Float):Void {
		spr.updateHitbox();
		var big:Float = Math.max(spr.frameWidth, spr.frameHeight);
		var s:Float = (big > 0) ? PV_BOX / big : 1;
		spr.scale.set(s, s);
		spr.updateHitbox();
		spr.offset.set();
		spr.setPosition(cx - spr.width / 2, cy - spr.height / 2);
	}

	/** Live-updates the splash on edits. Other cells track the shared shader object directly, so editing
		the live palette recolours them automatically; the splash needs an explicit value copy. **/
	function recolorPreview():Void {
		if (dataArray == null || curSelectedNote >= Note.globalRgbShaders.length || bigSplash == null || !bigSplash.alive)
			return;
		var splashSrc:String = ClientPrefs.data.linkSplashColor ? 'notes' : 'splash';
		if (splashSrc == editElement)
			bigSplash.rgbShader.copyValues(getShader());
	}

	inline function bindPreviewShader(spr:FlxSprite, ref:RGBShaderReference, pal:RGBPalette):Void {
		if (ref != null) {
			ref.parent = pal;
			ref.enabled = true;
		}
		spr.shader = pal.shader;
	}

	/** Lays out the sustain body + tail (end flipped outward) centred in the (cx, cy) cell, within PV_BOX. **/
	function layoutHold(cx:Float, cy:Float):Void {
		var w:Float = PV_BOX * 0.34;
		var len:Float = PV_BOX * 0.92;
		var tail:FlxSprite = bigHold.tail;
		tail.flipY = true;
		tail.scale.x = w / tail.frameWidth;
		tail.scale.y = Math.abs(tail.scale.x);
		tail.updateHitbox();
		var tailH:Float = tail.height;
		bigHold.scale.x = w / bigHold.frameWidth;
		bigHold.scale.y = Math.max(0.01, (len - tailH) / bigHold.frameHeight);
		bigHold.updateHitbox();
		var top:Float = cy - len / 2;
		tail.setPosition(cx - tail.width / 2, top);
		bigHold.setPosition(cx - bigHold.width / 2, top + tailH);
	}

	function updateNotes(?instant:Bool = false) {
		for (note in modeNotes)
			note.alpha = (curSelectedMode == note.ID) ? 1 : 0.6;

		for (note in myNotes) {
			var newAnim:String = curSelectedNote == note.ID ? 'confirm' : 'pressed';
			note.alpha = (curSelectedNote == note.ID) ? 1 : 0.6;
			if (note.animation.curAnim == null || note.animation.curAnim.name != newAnim)
				note.playAnim(newAnim, true);
			if (instant && note.animation.curAnim != null)
				note.animation.curAnim.finish();
		}
		if (bigNote.animation.getByName('note') != null)
			bigNote.animation.play('note', true);
		updateColors();
	}

	function updateColors(specific:Null<FlxColor> = null) {
		var color:FlxColor = getShaderColor();
		var wheelColor:FlxColor = specific == null ? getShaderColor() : specific;
		alphabetR.text = Std.string(color.red);
		alphabetG.text = Std.string(color.green);
		alphabetB.text = Std.string(color.blue);
		alphabetHex.text = color.toHexString(false, false);
		for (letter in alphabetHex.letters)
			letter.color = color;

		colorWheel.color = FlxColor.fromHSB(0, 0, color.brightness);
		colorWheelSelector.setPosition(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
		if (wheelColor.brightness != 0) {
			var hueWrap:Float = wheelColor.hue * Math.PI / 180;
			colorWheelSelector.x += Math.sin(hueWrap) * colorWheel.width / 2 * wheelColor.saturation;
			colorWheelSelector.y -= Math.cos(hueWrap) * colorWheel.height / 2 * wheelColor.saturation;
		}
		colorGradientSelector.y = colorGradient.y + colorGradient.height * (1 - color.brightness);

		// Drive the one shared lane palette; the lane row + every preview element draw from its shader, so
		// they all recolour together (writing the per-sprite reference would clone it off and desync them).
		switch (curSelectedMode) {
			case 0:
				getShader().r = color;
			case 1:
				getShader().g = color;
			case 2:
				getShader().b = color;
		}
		recolorPreview();
	}

	function setShaderColor(value:FlxColor) {
		if (targetKey > 0 && !overrideStored) {
			byKeyStore(editElement)[targetKey - 1] = dataArray;
			overrideStored = true;
		}
		dataArray[curSelectedNote][curSelectedMode] = value;
	}

	/** The shared (9-lane) colour store for an element; 'notes' is the existing cardinal+extra arrays. **/
	function sharedStore(element:String):Array<Array<FlxColor>> {
		if (element == 'notes') {
			var cards:Array<Array<FlxColor>> = onPixel ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB;
			var ext:Array<Array<FlxColor>> = onPixel ? ClientPrefs.data.arrowRGBExtraPixel : ClientPrefs.data.arrowRGBExtra;
			var out:Array<Array<FlxColor>> = [];
			for (c in cards)
				out.push(c);
			for (e in ext)
				out.push(e);
			return out;
		}
		var map:Map<String, Array<Array<FlxColor>>> = onPixel ? ClientPrefs.data.assetRGBPixel : ClientPrefs.data.assetRGB;
		var arr:Array<Array<FlxColor>> = map.get(element);
		if (arr == null || arr.length < 9) {
			arr = [];
			for (lane in sharedStore('notes'))
				arr.push([lane[0], lane[1], lane[2]]);
			map.set(element, arr);
		}
		return arr;
	}

	/** The per-keycount override store for an element. **/
	function byKeyStore(element:String):Array<Array<Array<FlxColor>>> {
		if (element == 'notes')
			return onPixel ? ClientPrefs.data.arrowRGBByKeyPixel : ClientPrefs.data.arrowRGBByKey;
		var map:Map<String, Array<Array<Array<FlxColor>>>> = onPixel ? ClientPrefs.data.assetRGBByKeyPixel : ClientPrefs.data.assetRGBByKey;
		var arr:Array<Array<Array<FlxColor>>> = map.get(element);
		if (arr == null) {
			arr = [[], [], [], [], [], [], [], [], []];
			map.set(element, arr);
		}
		return arr;
	}

	/** Whether `element` can be edited independently right now (link off + skin supports it). **/
	function elementEditable(element:String):Bool {
		if (element == 'notes')
			return true;
		var lf:String = ELEMENT_LINK.get(element);
		if (lf == null || Reflect.field(ClientPrefs.data, lf) == true)
			return false;
		var cfg:NoteSkinData = (NoteSkinConfig.activeSkin() != null) ? NoteSkinConfig.forCurrentKeys(NoteSkinConfig.activeSkin()) : null;
		return linkSupported(cfg, element);
	}

	/** Selects which asset the picker edits (from a clicked preview cell). **/
	function selectElement(element:String):Void {
		if (editElement == element)
			return;
		if (!elementEditable(element)) {
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
			return;
		}
		editElement = element;
		curSelectedNote = 0;
		spawnNotes();
		updateNotes(true);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	/** The palette a preview cell should draw from: live (globalRgbShaders) when it tracks the edit, else
		a static palette built from its stored/linked colour. **/
	function elementPalette(element:String, col:Int):RGBPalette {
		var linked:Bool = (element != 'notes') && (Reflect.field(ClientPrefs.data, ELEMENT_LINK.get(element)) == true);
		var src:String = linked ? 'notes' : element;
		if (src == editElement)
			return Note.globalRgbShaders[col];
		var c:Array<FlxColor>;
		if (targetKey == 0)
			c = sharedStore(src)[col];
		else {
			var ov:Array<Array<FlxColor>> = byKeyStore(src)[targetKey - 1];
			c = (ov != null && ov.length == targetKey) ? ov[col] : Mania.composeShared(targetKey)[col];
		}
		var p:RGBPalette = new RGBPalette();
		p.r = c[0];
		p.g = c[1];
		p.b = c[2];
		return p;
	}

	function getShaderColor()
		return dataArray[curSelectedNote][curSelectedMode];

	function defaultColor(note:Int, mode:Int):FlxColor {
		if (targetKey > 0) {
			var prevUI:String = PlayState.stageUI;
			PlayState.stageUI = onPixel ? "pixel" : "normal";
			var c:FlxColor = Mania.composeShared(targetKey)[note][mode];
			PlayState.stageUI = prevUI;
			return c;
		}
		if (note < 4)
			return onPixel ? ClientPrefs.defaultData.arrowRGBPixel[note][mode] : ClientPrefs.defaultData.arrowRGB[note][mode];
		return onPixel ? ClientPrefs.defaultData.arrowRGBExtraPixel[note - 4][mode] : ClientPrefs.defaultData.arrowRGBExtra[note - 4][mode];
	}

	function updateTargetText() {
		if (targetText != null)
			targetText.text = (targetKey == 0) ? 'SHARED' : targetKey + 'K';
	}

	function getShader()
		return Note.globalRgbShaders[curSelectedNote];

	override function destroy() {
		Note.globalRgbShaders = [];
		Mania.apply(prevKeyCount);
		super.destroy();
	}
}
