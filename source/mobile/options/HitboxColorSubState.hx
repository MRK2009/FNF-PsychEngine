package mobile.options;

import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxGradient;
import lime.system.Clipboard;
import objects.notes.NoteDefaults;

/**
 * Manual per-lane colour picker for the mobile gameplay Hitbox. Selecting a lane (left/right or tap)
 * edits one colour via a colour wheel, brightness slider, hex field and R/G/B steppers; the lane strip
 * along the bottom previews the result live. RESET on a lane restores its note-skin colour (SHIFT for
 * all lanes). Writes straight to `ClientPrefs.data.hitboxColors`; opening it implies Custom mode.
 *
 * A trimmed cousin of options.NotesColorState: one flat colour per lane instead of a note RGB triple,
 * with no pixel/keycount/element machinery.
 */
class HitboxColorSubState extends MusicBeatSubstate
{
	var curLane:Int = 0;
	var laneCount:Int = 0;

	var laneStrip:FlxTypedGroup<FlxSprite>;
	var laneLabels:Array<FlxText> = [];
	var laneHighlight:FlxSprite;

	var colorGradient:FlxSprite;
	var colorGradientSelector:FlxSprite;
	var colorPalette:FlxSprite;
	var colorWheel:FlxSprite;
	var colorWheelSelector:FlxSprite;

	var alphabetR:Alphabet;
	var alphabetG:Alphabet;
	var alphabetB:Alphabet;
	var alphabetHex:Alphabet;

	var hexTypeLine:FlxSprite;
	var hexTypeNum:Int = -1;
	var hexTypeVisibleTimer:Float = 0;

	var copyButton:FlxSprite;
	var pasteButton:FlxSprite;

	var stepUp:Array<FlxSprite> = [];
	var stepDown:Array<FlxSprite> = [];
	var stepHold:Float = 0;

	var tipTxt:FlxText;

	var _storedColor:FlxColor;
	var holdingOnObj:FlxSprite;

	var allowedTypeKeys:Map<FlxKey, String> = [
		ZERO => '0', ONE => '1', TWO => '2', THREE => '3', FOUR => '4', FIVE => '5', SIX => '6', SEVEN => '7', EIGHT => '8', NINE => '9',
		NUMPADZERO => '0', NUMPADONE => '1', NUMPADTWO => '2', NUMPADTHREE => '3', NUMPADFOUR => '4', NUMPADFIVE => '5', NUMPADSIX => '6',
		NUMPADSEVEN => '7', NUMPADEIGHT => '8', NUMPADNINE => '9', A => 'A', B => 'B', C => 'C', D => 'D', E => 'E', F => 'F'
	];

	public function new()
	{
		super();

		ClientPrefs.data.hitboxColorSource = 'Custom';
		if (ClientPrefs.data.hitboxColors == null || ClientPrefs.data.hitboxColors.length < 1)
			ClientPrefs.data.hitboxColors = [for (i in 0...9) NoteDefaults.resolveLaneColor(i)];
		laneCount = ClientPrefs.data.hitboxColors.length;

		#if mobile
		addTouchPad('NONE', 'A_B');
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.color = 0xFF1A1A2E;
		bg.screenCenter();
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);

		addPanel(724, 16, 540, 348);

		var prevLabel:FlxText = makeText(740, 22, 200, 'PICKER', 15, LEFT);
		prevLabel.alpha = 0.6;
		add(prevLabel);

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

		var chNames:Array<String> = ['R', 'G', 'B'];
		var chCols:Array<FlxColor> = [0xFFFF7777, 0xFF77FF77, 0xFF77AAFF];
		alphabetR = makeColorAlphabet(1130, 452);
		alphabetG = makeColorAlphabet(1130, 508);
		alphabetB = makeColorAlphabet(1130, 564);
		for (i in 0...3)
		{
			var ry:Float = 446 + i * 56;
			var lab:FlxText = makeText(1014, ry + 4, 34, chNames[i], 22, LEFT);
			lab.color = chCols[i];
			add(lab);
			stepDown.push(makeStepButton(1056, ry, '-'));
			stepUp.push(makeStepButton(1198, ry, '+'));
		}
		add(hexTypeLine);

		buildLaneStrip();

		tipTxt = makeText(0, FlxG.height - 30, FlxG.width, '', 16, CENTER);
		tipTxt.alpha = 0.85;
		tipTxt.text = 'LEFT/RIGHT Select Lane   RESET Reset to Note Skin (SHIFT = all)   ESC Back';
		add(tipTxt);

		FlxG.mouse.visible = true;
		_storedColor = getColor();
		updateLaneStrip();
		updateColors();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	/** Builds the row of tall lane bars along the bottom, styled like the in-game hitbox. **/
	function buildLaneStrip():Void
	{
		laneHighlight = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		laneHighlight.alpha = 0.85;
		add(laneHighlight);

		laneStrip = new FlxTypedGroup<FlxSprite>();
		add(laneStrip);

		var stripX:Float = 28;
		var stripW:Float = 660;
		var top:Float = 96;
		var barH:Float = 470;
		var gap:Float = 8;
		var barW:Float = (stripW - gap * (laneCount - 1)) / laneCount;

		for (i in 0...laneCount)
		{
			var bar:FlxSprite = new FlxSprite(stripX + i * (barW + gap), top).makeGraphic(1, 1, FlxColor.WHITE);
			bar.scale.set(barW, barH);
			bar.updateHitbox();
			bar.ID = i;
			laneStrip.add(bar);

			var lbl:FlxText = makeText(bar.x, top + barH + 6, barW, Std.string(i + 1), 22, CENTER);
			add(lbl);
			laneLabels.push(lbl);
		}
	}

	function updateLaneStrip():Void
	{
		for (bar in laneStrip)
		{
			bar.color = ClientPrefs.data.hitboxColors[bar.ID];
			bar.alpha = (bar.ID == curLane) ? 0.95 : 0.4;
			if (bar.ID == curLane)
			{
				laneHighlight.setPosition(bar.x - 4, bar.y - 4);
				laneHighlight.scale.set(bar.width + 8, bar.height + 8);
				laneHighlight.updateHitbox();
			}
		}
		for (i in 0...laneLabels.length)
			laneLabels[i].alpha = (i == curLane) ? 1 : 0.5;
	}

	override function update(elapsed:Float):Void
	{
		if (controls.BACK)
		{
			FlxG.mouse.visible = false;
			ClientPrefs.saveSettings();
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		super.update(elapsed);

		handleSteppers(elapsed);

		if (hexTypeNum > -1)
		{
			updateHexTyping(elapsed);
		}
		else
		{
			if (controls.UI_LEFT_P)
				changeLane(-1);
			else if (controls.UI_RIGHT_P)
				changeLane(1);
			hexTypeLine.visible = false;
		}

		var moved:Bool = FlxG.mouse.justMoved;
		var pressed:Bool = FlxG.mouse.justPressed;
		if (moved)
		{
			copyButton.alpha = 0.6;
			pasteButton.alpha = 0.6;
		}

		if (pressed)
			handleClick();
		handleCopyPaste(pressed);
		handleHolding(moved, pressed);

		if (holdingOnObj == null && controls.RESET && hexTypeNum < 0)
		{
			if (FlxG.keys.pressed.SHIFT || FlxG.gamepads.anyPressed(LEFT_SHOULDER))
				for (i in 0...laneCount)
					ClientPrefs.data.hitboxColors[i] = NoteDefaults.resolveLaneColor(i);
			setColor(NoteDefaults.resolveLaneColor(curLane));
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			_storedColor = getColor();
			updateColors();
			updateLaneStrip();
		}
	}

	function changeLane(change:Int):Void
	{
		curLane = FlxMath.wrap(curLane + change, 0, laneCount - 1);
		_storedColor = getColor();
		hexTypeNum = -1;
		updateColors();
		updateLaneStrip();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	function updateHexTyping(elapsed:Float):Void
	{
		var keyPressed:FlxKey = cast(FlxG.keys.firstJustPressed(), FlxKey);
		hexTypeVisibleTimer += elapsed;
		var changed:Bool = false;
		if (changed = FlxG.keys.justPressed.LEFT)
			hexTypeNum--;
		else if (changed = FlxG.keys.justPressed.RIGHT)
			hexTypeNum++;
		else if (allowedTypeKeys.exists(keyPressed))
		{
			var curColor:String = alphabetHex.text;
			var newColor:String = curColor.substring(0, hexTypeNum) + allowedTypeKeys.get(keyPressed) + curColor.substring(hexTypeNum + 1);
			setColor(FlxColor.fromString('#' + newColor));
			_storedColor = getColor();
			updateColors();
			updateLaneStrip();
			hexTypeNum++;
			changed = true;
		}
		else if (FlxG.keys.justPressed.ENTER)
			hexTypeNum = -1;

		var end:Bool = false;
		if (changed)
		{
			if (hexTypeNum > 5)
			{
				hexTypeNum = -1;
				end = true;
				hexTypeLine.visible = false;
			}
			else
			{
				if (hexTypeNum < 0)
					hexTypeNum = 0;
				centerHexTypeLine();
				hexTypeLine.visible = true;
			}
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}
		if (!end)
			hexTypeLine.visible = Math.floor(hexTypeVisibleTimer * 2) % 2 == 0;
	}

	function handleClick():Void
	{
		hexTypeNum = -1;

		for (bar in laneStrip)
		{
			if (FlxG.mouse.overlaps(bar) && curLane != bar.ID)
			{
				curLane = bar.ID;
				_storedColor = getColor();
				updateColors();
				updateLaneStrip();
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				return;
			}
		}

		if (FlxG.mouse.overlaps(colorWheel))
		{
			_storedColor = getColor();
			holdingOnObj = colorWheel;
		}
		else if (FlxG.mouse.overlaps(colorGradient))
		{
			_storedColor = getColor();
			holdingOnObj = colorGradient;
		}
		else if (FlxG.mouse.overlaps(colorPalette))
		{
			setColor(colorPalette.pixels.getPixel32(Std.int((FlxG.mouse.x - colorPalette.x) / colorPalette.scale.x),
				Std.int((FlxG.mouse.y - colorPalette.y) / colorPalette.scale.y)));
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			updateColors();
			updateLaneStrip();
		}
		else if (FlxG.mouse.y >= hexTypeLine.y && FlxG.mouse.y < hexTypeLine.y + hexTypeLine.height && Math.abs(FlxG.mouse.x - 800) <= 84)
		{
			hexTypeNum = 0;
			for (letter in alphabetHex.letters)
			{
				if (letter.x - letter.offset.x + letter.width <= FlxG.mouse.x)
					hexTypeNum++;
				else
					break;
			}
			if (hexTypeNum > 5)
				hexTypeNum = 5;
			hexTypeLine.visible = true;
			centerHexTypeLine();
		}
		else
			holdingOnObj = null;
	}

	function handleCopyPaste(pressed:Bool):Void
	{
		if (FlxG.mouse.overlaps(copyButton))
		{
			copyButton.alpha = 1;
			if (pressed)
			{
				Clipboard.text = getColor().toHexString(false, false);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			}
			hexTypeNum = -1;
		}
		else if (FlxG.mouse.overlaps(pasteButton))
		{
			pasteButton.alpha = 1;
			if (pressed)
			{
				var formatted:String = Clipboard.text.trim().toUpperCase().replace('#', '').replace('0X', '');
				var newColor:Null<FlxColor> = FlxColor.fromString('#' + formatted);
				if (newColor != null && formatted.length == 6)
				{
					setColor(newColor);
					_storedColor = getColor();
					updateColors();
					updateLaneStrip();
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				}
				else
					FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			}
			hexTypeNum = -1;
		}
	}

	function handleHolding(moved:Bool, pressed:Bool):Void
	{
		if (holdingOnObj == null)
			return;

		if (FlxG.mouse.justReleased)
		{
			holdingOnObj = null;
			_storedColor = getColor();
			updateColors();
			updateLaneStrip();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}
		else if (moved || pressed)
		{
			if (holdingOnObj == colorGradient)
			{
				var newBrightness:Float = 1 - FlxMath.bound((FlxG.mouse.y - colorGradient.y) / colorGradient.height, 0, 1);
				_storedColor.alpha = 1;
				if (_storedColor.brightness == 0)
					setColor(FlxColor.fromRGBFloat(newBrightness, newBrightness, newBrightness));
				else
					setColor(FlxColor.fromHSB(_storedColor.hue, _storedColor.saturation, newBrightness));
				updateColors(_storedColor);
				updateLaneStrip();
			}
			else if (holdingOnObj == colorWheel)
			{
				var center:FlxPoint = new FlxPoint(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
				var mouse:FlxPoint = FlxG.mouse.getScreenPosition();
				var hue:Float = FlxMath.wrap(FlxMath.wrap(Std.int(mouse.degreesTo(center)), 0, 360) - 90, 0, 360);
				var sat:Float = FlxMath.bound(mouse.dist(center) / colorWheel.width * 2, 0, 1);
				if (sat != 0)
					setColor(FlxColor.fromHSB(hue, sat, _storedColor.brightness));
				else
					setColor(FlxColor.fromRGBFloat(_storedColor.brightness, _storedColor.brightness, _storedColor.brightness));
				updateColors();
				updateLaneStrip();
			}
		}
	}

	function updateColors(specific:Null<FlxColor> = null):Void
	{
		var color:FlxColor = getColor();
		var wheelColor:FlxColor = specific == null ? color : specific;
		alphabetR.text = Std.string(color.red);
		alphabetG.text = Std.string(color.green);
		alphabetB.text = Std.string(color.blue);
		alphabetHex.text = color.toHexString(false, false);
		for (letter in alphabetHex.letters)
			letter.color = color;

		colorWheel.color = FlxColor.fromHSB(0, 0, color.brightness);
		colorWheelSelector.setPosition(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
		if (wheelColor.brightness != 0)
		{
			var hueWrap:Float = wheelColor.hue * Math.PI / 180;
			colorWheelSelector.x += Math.sin(hueWrap) * colorWheel.width / 2 * wheelColor.saturation;
			colorWheelSelector.y -= Math.cos(hueWrap) * colorWheel.height / 2 * wheelColor.saturation;
		}
		colorGradientSelector.y = colorGradient.y + colorGradient.height * (1 - color.brightness);
	}

	function handleSteppers(elapsed:Float):Void
	{
		var held:Int = -1;
		var dir:Int = 0;
		for (i in 0...3)
		{
			if (FlxG.mouse.overlaps(stepUp[i]))
			{
				if (FlxG.mouse.justPressed)
					adjustChannel(i, 1);
				if (FlxG.mouse.pressed)
				{
					held = i;
					dir = 1;
				}
			}
			else if (FlxG.mouse.overlaps(stepDown[i]))
			{
				if (FlxG.mouse.justPressed)
					adjustChannel(i, -1);
				if (FlxG.mouse.pressed)
				{
					held = i;
					dir = -1;
				}
			}
		}
		if (held >= 0 && !FlxG.mouse.justPressed)
		{
			stepHold += elapsed;
			if (stepHold > 0.35)
			{
				adjustChannel(held, dir);
				stepHold = 0.32;
			}
		}
		else if (held < 0)
			stepHold = 0;
	}

	function adjustChannel(i:Int, delta:Int):Void
	{
		var c:FlxColor = getColor();
		var r:Int = c.red;
		var g:Int = c.green;
		var b:Int = c.blue;
		switch (i)
		{
			case 0:
				r = Std.int(Math.max(0, Math.min(255, r + delta)));
			case 1:
				g = Std.int(Math.max(0, Math.min(255, g + delta)));
			default:
				b = Std.int(Math.max(0, Math.min(255, b + delta)));
		}
		setColor(FlxColor.fromRGB(r, g, b));
		_storedColor = getColor();
		updateColors();
		updateLaneStrip();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.3);
	}

	function centerHexTypeLine():Void
	{
		if (hexTypeNum > 0)
		{
			var letter = alphabetHex.letters[hexTypeNum - 1];
			hexTypeLine.x = letter.x - letter.offset.x + letter.width;
		}
		else
		{
			var letter = alphabetHex.letters[0];
			hexTypeLine.x = letter.x - letter.offset.x;
		}
		hexTypeLine.x += hexTypeLine.width;
		hexTypeVisibleTimer = 0;
	}

	inline function getColor():FlxColor
		return ClientPrefs.data.hitboxColors[curLane];

	inline function setColor(value:FlxColor):Void
		ClientPrefs.data.hitboxColors[curLane] = value;

	function addPanel(x:Int, y:Int, w:Int, h:Int):Void
	{
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

	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, align:flixel.text.FlxTextAlign):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, align, OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		return t;
	}

	function makeColorAlphabet(x:Float = 0, y:Float = 0):Alphabet
	{
		var text:Alphabet = new Alphabet(x, y, '', true);
		text.alignment = CENTERED;
		text.setScale(0.6);
		add(text);
		return text;
	}

	function makeStepButton(x:Float, y:Float, sym:String):FlxSprite
	{
		var b:FlxSprite = new FlxSprite(x, y);
		b.makeGraphic(38, 38, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRect(b, 1, 1, 35, 35, 0xFF20243A, {thickness: 2, color: 0xFF3A3F58});
		b.scrollFactor.set();
		add(b);
		var t:FlxText = makeText(x, y + 3, 38, sym, 26, CENTER);
		add(t);
		return b;
	}

	override function destroy():Void
	{
		FlxG.mouse.visible = false;
		super.destroy();
	}
}
