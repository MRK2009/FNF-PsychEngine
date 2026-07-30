package options;

import lime.system.Clipboard;
import objects.notes.Receptor;
import objects.notes.NoteSprite;
import objects.notes.SustainSprite;
import objects.notes.NoteData;
import objects.Note;
import backend.NoteSkinConfig;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.UIColor;
import smidr.input.UIFocus;
import smidr.widgets.UIPanel;
import smidr.widgets.UILabel;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UISegmentedControl;
import smidr.widgets.UIColorPicker;
import smidr.widgets.UIModal;
import smidr.overlays.UITooltip;
import smidr.flixel.FlxSmidr;

/**
	The Note Colours editor, rebuilt on the in-engine UI framework (`smidr`): a left control panel
	(keycount / element / channel selectors, an HSV colour picker, copy-paste, reset and the
	skin-gated link toggles) over a flixel PREVIEW layer on the right - the live lane strip and the
	note / hold / splash / static / pressed / confirm cells, all real game sprites sharing the lane
	palette so an edit recolours every element at once.

	The colour MODEL is unchanged from the old flixel `NotesColorSubState`: the same `arrowRGB*` /
	`assetRGB*` shared and per-keycount stores, the same `[main, border, shadow]` triple per lane, the
	same link semantics. This class is just the renderer + input; because `smidr` hosts above the
	flixel layer, the preview sits in the panel-free right region and shows through.
**/
class NotesColorState extends MusicBeatState
{
	static var PV_ELEMENTS:Array<String> = ['notes', 'holds', 'splash', 'strums', 'pressed', 'confirm'];

	static var ELEMENT_LABEL:Map<String, String> = [
		'notes' => 'Notes', 'holds' => 'Holds', 'splash' => 'Splash', 'strums' => 'Strums (idle)', 'pressed' => 'Pressed', 'confirm' => 'Confirm'
	];

	static var ELEMENT_LINK:Map<String, String> = [
		'holds' => 'linkSustainColor', 'splash' => 'linkSplashColor', 'strums' => 'linkStrumColor',
		'pressed' => 'linkPressedColor', 'confirm' => 'linkConfirmColor'
	];

	static var KEYCOUNT_VALUES:Array<Int> = [0, 4, 5, 6, 7, 8, 9];

	static inline var PANEL_RIGHT:Float = 706;
	var regCX:Float = 0;
	var laneCY:Float = 0;
	var col0:Float = 0;
	var col1:Float = 0;
	var col2:Float = 0;
	var rowTop:Float = 0;
	var rowBot:Float = 0;
	var cellSize:Float = 128;
	var laneStripW:Float = 0;
	var laneArrow:Int = 52;

	var targetKey:Int = 0;
	var onPixel:Bool = false;
	var editElement:String = 'notes';
	var curLane:Int = 0;
	var curChannel:Int = 0;
	var overrideStored:Bool = false;
	var oneColorMode:Bool = false;
	var prevKeyCount:Int = Mania.DEFAULT;
	var dataArray:Array<Array<FlxColor>>;

	var bgSprite:FlxSprite;
	var myNotes:FlxTypedGroup<Receptor>;
	var laneHighlight:FlxSprite;
	var bigNote:NoteSprite;
	var bigStrum:Receptor;
	var bigStatic:Receptor;
	var bigPressed:Receptor;
	var bigHold:SustainSprite;
	var bigSplash:objects.NoteSplash;
	var splashWait:Float = 0;

	var uiRoot:UIRoot;
	var keycountDrop:UIDropdown;
	var elementDrop:UIDropdown;
	var channelSeg:UISegmentedControl;
	var picker:UIColorPicker;
	var hintLabel:UILabel;

	var elementKeys:Array<String> = [];

	override function create():Void
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Note Colors Menu", null);
		#end
		persistentUpdate = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		onPixel = PlayState.isPixelStage;
		prevKeyCount = Mania.current;
		computeLayout();

		bgSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bgSprite);
		bgSprite.color = 0xFF1A1A2E;
		bgSprite.screenCenter();
		bgSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(bgSprite);

		laneHighlight = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		laneHighlight.alpha = 0.18;
		laneHighlight.visible = false;
		add(laneHighlight);

		myNotes = new FlxTypedGroup<Receptor>();
		add(myNotes);

		buildFlxLabels();

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');
		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		UITooltip.install();

		buildChrome();

		Mania.apply(Mania.DEFAULT);
		rebuildPreview();
		syncPicker();

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		super.create();
	}


	/** Builds the left control panel: selectors, colour picker, copy/paste, reset and link toggles. **/
	function buildChrome():Void
	{
		var panel:UIPanel = new UIPanel(690, 632, PANEL);
		panel.x = 16;
		panel.y = 52;
		panel.corner = UITheme.px(10);
		panel.outline = true;
		uiRoot.content.addChild(panel);

		var title:UILabel = new UILabel('NOTE COLOURS', 26, 0);
		title.x = 36;
		title.y = 64;
		uiRoot.content.addChild(title);

		keycountDrop = new UIDropdown('Keycount', 400, function(i:Int, _:String) {
			targetKey = KEYCOUNT_VALUES[i];
			curLane = 0;
			rebuildPreview();
			syncPicker();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		keycountDrop.controlWidth = UITheme.px(160);
		keycountDrop.setItems(['Shared', '4K', '5K', '6K', '7K', '8K', '9K']);
		keycountDrop.x = 36;
		keycountDrop.y = 112;
		uiRoot.content.addChild(keycountDrop);

		elementDrop = new UIDropdown('Element', 400, function(i:Int, _:String) {
			if (i >= 0 && i < elementKeys.length)
				selectElement(elementKeys[i]);
		});
		elementDrop.controlWidth = UITheme.px(160);
		elementDrop.x = 36;
		elementDrop.y = 152;
		uiRoot.content.addChild(elementDrop);

		channelSeg = new UISegmentedControl('Channel', 400, ['Main', 'Border', 'Shadow'], function(i:Int) {
			curChannel = i;
			syncPicker();
		});
		channelSeg.controlWidth = UITheme.px(240);
		channelSeg.x = 36;
		channelSeg.y = 196;
		uiRoot.content.addChild(channelSeg);

		picker = new UIColorPicker(400, 0xFFFF0000, function(argb:Int) applyPickerColor(argb));
		picker.x = 36;
		picker.y = 232;
		uiRoot.content.addChild(picker);

		var pixelCheck:UICheckbox = new UICheckbox('Pixel Colours', 400, onPixel, function(v:Bool) {
			onPixel = v;
			rebuildPreview();
			syncPicker();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		pixelCheck.x = 36;
		pixelCheck.y = 452;
		uiRoot.content.addChild(pixelCheck);

		var resetAllBtn:UIButton = new UIButton('Reset All Colours...', 400, 36, openResetAllModal);
		resetAllBtn.fontSize = 14;
		resetAllBtn.danger = true;
		resetAllBtn.x = 36;
		resetAllBtn.y = 496;
		uiRoot.content.addChild(resetAllBtn);

		hintLabel = new UILabel('Click a lane on the right to edit it.  Arrows switch lanes.', 13, 2);
		hintLabel.x = 36;
		hintLabel.y = 636;
		uiRoot.content.addChild(hintLabel);

		var rx:Float = 456;
		var copyBtn:UIButton = new UIButton('Copy Hex', 230, 32, function() {
			Clipboard.text = getShaderColor().toHexString(false, false);
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		copyBtn.fontSize = 13;
		copyBtn.x = rx;
		copyBtn.y = 232;
		uiRoot.content.addChild(copyBtn);

		var pasteBtn:UIButton = new UIButton('Paste Hex', 230, 32, onPasteHex);
		pasteBtn.fontSize = 13;
		pasteBtn.x = rx;
		pasteBtn.y = 272;
		uiRoot.content.addChild(pasteBtn);

		var resetChanBtn:UIButton = new UIButton('Reset Channel', 230, 32, function() resetLane(false));
		resetChanBtn.fontSize = 13;
		resetChanBtn.x = rx;
		resetChanBtn.y = 318;
		uiRoot.content.addChild(resetChanBtn);

		var resetLaneBtn:UIButton = new UIButton('Reset Lane', 230, 32, function() resetLane(true));
		resetLaneBtn.fontSize = 13;
		resetLaneBtn.x = rx;
		resetLaneBtn.y = 358;
		uiRoot.content.addChild(resetLaneBtn);

		buildLinkToggles(rx, 406);
		refreshElementDropdown();
	}

	/** Builds the per-keycount / one-colour toggles and the skin-gated colour-link toggles. **/
	function buildLinkToggles(x:Float, y:Float):Void
	{
		var cfg:NoteSkinData = null;
		var skin:String = NoteSkinConfig.activeSkin();
		if (skin != null)
			cfg = NoteSkinConfig.forCurrentKeys(skin);

		addToggle(x, y, 'Per-keycount Colours', 'noteColorPerKeycount');
		addToggle(x, y + 30, 'One Colour for All', 'noteColorOneColor');

		var ly:Float = y + 72;
		if (linkSupported(cfg, 'splash'))
		{
			addLinkToggle(x, ly, 'Link Splash Colour', 'linkSplashColor');
			ly += 30;
		}
		if (linkSupported(cfg, 'holds'))
		{
			addLinkToggle(x, ly, 'Link Hold Colour', 'linkSustainColor');
			ly += 30;
		}
		if (linkSupported(cfg, 'pressed'))
		{
			addLinkToggle(x, ly, 'Link Pressed Colour', 'linkPressedColor');
			ly += 30;
		}
		if (linkSupported(cfg, 'confirm'))
		{
			addLinkToggle(x, ly, 'Link Confirm Colour', 'linkConfirmColor');
			ly += 30;
		}
		if (linkSupported(cfg, 'strums'))
			addLinkToggle(x, ly, 'Link Strum Colour', 'linkStrumColor');
	}

	/** A plain ClientPrefs bool toggle that just rebuilds the preview (per-keycount / one-colour). **/
	function addToggle(x:Float, y:Float, label:String, field:String):Void
	{
		var cb:UICheckbox = new UICheckbox(label, 230, Reflect.field(ClientPrefs.data, field) == true, function(v:Bool) {
			Reflect.setField(ClientPrefs.data, field, v);
			rebuildPreview();
			syncPicker();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		cb.x = x;
		cb.y = y;
		uiRoot.content.addChild(cb);
	}

	/** A link toggle: flipping it can make the current element un-editable, so it re-derives that too. **/
	function addLinkToggle(x:Float, y:Float, label:String, field:String):Void
	{
		var cb:UICheckbox = new UICheckbox(label, 230, Reflect.field(ClientPrefs.data, field) == true, function(v:Bool) {
			Reflect.setField(ClientPrefs.data, field, v);
			if (!elementEditable(editElement))
				editElement = 'notes';
			refreshElementDropdown();
			rebuildPreview();
			syncPicker();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		});
		cb.x = x;
		cb.y = y;
		uiRoot.content.addChild(cb);
	}

	/** Rebuilds the element dropdown from the currently editable elements, selecting the active one. **/
	function refreshElementDropdown():Void
	{
		elementKeys = [];
		var display:Array<String> = [];
		for (e in PV_ELEMENTS)
			if (elementEditable(e))
			{
				elementKeys.push(e);
				display.push(ELEMENT_LABEL.get(e));
			}
		elementDrop.setItems(display);
		var idx:Int = elementKeys.indexOf(editElement);
		elementDrop.select(idx < 0 ? 0 : idx);
	}

	/** Computes the preview region + cell grid from the current screen width (widescreen-safe). **/
	function computeLayout():Void
	{
		var regX:Float = PANEL_RIGHT + 24;
		var regRight:Float = FlxG.width - 24;
		if (regRight - regX < 380)
			regRight = regX + 380;
		regCX = (regX + regRight) * 0.5;
		var regW:Float = regRight - regX;

		var colGap:Float = Math.min(200, (regW - cellSize) * 0.5 - 8);
		if (colGap < cellSize * 0.62)
			colGap = cellSize * 0.62;
		col0 = regCX - colGap;
		col1 = regCX;
		col2 = regCX + colGap;

		laneCY = 156;
		rowTop = 336;
		rowBot = rowTop + cellSize + 78;

		laneStripW = Math.min(regW - 16, 62 * 9);
	}

	/** Flixel preview labels (the six cell captions + the lane heading), part of the preview layer. **/
	function buildFlxLabels():Void
	{
		var names:Array<String> = ['NOTE', 'HOLD', 'SPLASH', 'STATIC', 'PRESSED', 'CONFIRM'];
		var cols:Array<Float> = [col0, col1, col2];
		for (i in 0...6)
		{
			var cx:Float = cols[i % 3];
			var ly:Float = ((i < 3) ? rowTop : rowBot) - cellSize * 0.5 - 28;
			var t:FlxText = flxText(cx - 90, ly, 180, names[i], 14, CENTER);
			t.alpha = 0.55;
			add(t);
		}
		var lane:FlxText = flxText(regCX - laneStripW * 0.5, laneCY - 78, laneStripW, 'LANE', 16, CENTER);
		lane.alpha = 0.6;
		add(lane);
	}

	inline function flxText(x:Float, y:Float, w:Float, text:String, size:Int, align:flixel.text.FlxTextAlign):FlxText
	{
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, align, OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		return t;
	}


	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (bigSplash != null && !bigSplash.alive)
		{
			splashWait -= elapsed;
			if (splashWait <= 0)
				triggerSplashPreview();
		}

		if (UIFocus.focused != null || UIRoot.overlayOpen)
			return;

		if (controls.BACK)
		{
			exitState();
			return;
		}

		if (FlxG.mouse.justPressed)
		{
			for (r in myNotes)
				if (FlxG.mouse.overlaps(r))
				{
					selectLane(r.ID);
					break;
				}
		}

		if (controls.UI_LEFT_P)
			selectLane(curLane - 1);
		else if (controls.UI_RIGHT_P)
			selectLane(curLane + 1);

		if (controls.RESET)
			resetLane(false);
	}

	function exitState():Void
	{
		FlxG.mouse.visible = false;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		MusicBeatState.switchState(new options.OptionsState());
	}

	function selectLane(lane:Int):Void
	{
		if (dataArray == null || dataArray.length == 0)
			return;
		lane = FlxMath.wrap(lane, 0, dataArray.length - 1);
		if (lane == curLane)
			return;
		curLane = lane;
		applyPreview();
		syncPicker();
		updateLaneHighlight();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	/** Picks which asset the picker edits (from the element dropdown). **/
	function selectElement(element:String):Void
	{
		if (editElement == element)
			return;
		if (!elementEditable(element))
		{
			refreshElementDropdown();
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
			return;
		}
		editElement = element;
		curLane = 0;
		rebuildPreview();
		syncPicker();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
	}

	function onPasteHex():Void
	{
		var formatted:String = Clipboard.text.trim().toUpperCase().replace('#', '').replace('0X', '');
		var newColor:Null<FlxColor> = FlxColor.fromString('#' + formatted);
		if (newColor != null && formatted.length == 6)
		{
			applyPickerColor(newColor);
			syncPicker();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		}
		else
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
	}


	/** Writes the picker colour into the current lane/channel and the live shared shader. **/
	function applyPickerColor(argb:Int):Void
	{
		var col:FlxColor = 0xFF000000 | (argb & 0xFFFFFF);
		setShaderColor(col);
		writeShaders(curChannel, col);
		recolorPreview();
	}

	/** Resets the current channel (or all three, when `all`) to its note-skin default. **/
	function resetLane(all:Bool):Void
	{
		if (all)
			for (i in 0...3)
			{
				var c:FlxColor = defaultColor(curLane, i);
				dataArray[curLane][i] = c;
				writeShaders(i, c);
			}
		var cur:FlxColor = defaultColor(curLane, curChannel);
		setShaderColor(cur);
		writeShaders(curChannel, cur);
		recolorPreview();
		syncPicker();
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
	}

	/** Writes a channel colour to the live shader(s): every lane in one-colour mode, else the current lane. **/
	inline function writeShaders(channel:Int, color:FlxColor):Void
	{
		if (oneColorMode)
		{
			for (pal in Note.globalRgbShaders)
				if (pal != null)
					writeChannel(pal, channel, color);
		}
		else
			writeChannel(getShader(), channel, color);
	}

	inline function writeChannel(sh:RGBPalette, channel:Int, color:FlxColor):Void
	{
		switch (channel)
		{
			case 0: sh.r = color;
			case 1: sh.g = color;
			default: sh.b = color;
		}
	}

	/** Asks whether a full colour reset applies to just the current keycount or every keycount. **/
	function openResetAllModal():Void
	{
		var modal:UIModal = new UIModal('Reset Colours', 480, 232);

		var scope:String = (targetKey == 0) ? 'the Shared palette' : '${targetKey}K';
		var msg:UILabel = new UILabel('Reset note and asset colours to their defaults.\nThis cannot be undone.', 14, 2);
		msg.x = 24;
		msg.y = 20;
		modal.body.addChild(msg);

		var thisBtn:UIButton = new UIButton('This Keycount', 210, 42, function() {
			resetAllColours(false);
			modal.close();
		}, true);
		thisBtn.tooltip = 'Reset $scope only.';
		thisBtn.x = 24;
		thisBtn.y = 84;
		modal.body.addChild(thisBtn);

		var allBtn:UIButton = new UIButton('All Keycounts', 210, 42, function() {
			resetAllColours(true);
			modal.close();
		});
		allBtn.tooltip = 'Reset the shared palette and every per-keycount override.';
		allBtn.x = 246;
		allBtn.y = 84;
		modal.body.addChild(allBtn);

		var cancelBtn:UIButton = new UIButton('Cancel', 130, 34, modal.close);
		cancelBtn.x = 24;
		cancelBtn.y = 140;
		modal.body.addChild(cancelBtn);

		modal.open();
	}

	/**
		Resets note + asset colours to their defaults. When `allKeycounts`, wipes the shared palette and
		every per-keycount / asset override (both pixel and normal); otherwise only the currently-selected
		keycount (Shared resets the shared palette + shared asset overrides; an NK resets that key's overrides).
	**/
	function resetAllColours(allKeycounts:Bool):Void
	{
		var d = ClientPrefs.defaultData;
		if (allKeycounts)
		{
			ClientPrefs.data.arrowRGB = cloneTriples(d.arrowRGB);
			ClientPrefs.data.arrowRGBPixel = cloneTriples(d.arrowRGBPixel);
			ClientPrefs.data.arrowRGBExtra = cloneTriples(d.arrowRGBExtra);
			ClientPrefs.data.arrowRGBExtraPixel = cloneTriples(d.arrowRGBExtraPixel);
			ClientPrefs.data.arrowRGBByKey = [[], [], [], [], [], [], [], [], []];
			ClientPrefs.data.arrowRGBByKeyPixel = [[], [], [], [], [], [], [], [], []];
			ClientPrefs.data.assetRGB = new Map();
			ClientPrefs.data.assetRGBByKey = new Map();
			ClientPrefs.data.assetRGBPixel = new Map();
			ClientPrefs.data.assetRGBByKeyPixel = new Map();
			ClientPrefs.data.noteColorOneValue = [d.noteColorOneValue[0], d.noteColorOneValue[1], d.noteColorOneValue[2]];
		}
		else if (targetKey == 0)
		{
			ClientPrefs.data.arrowRGB = cloneTriples(d.arrowRGB);
			ClientPrefs.data.arrowRGBPixel = cloneTriples(d.arrowRGBPixel);
			ClientPrefs.data.arrowRGBExtra = cloneTriples(d.arrowRGBExtra);
			ClientPrefs.data.arrowRGBExtraPixel = cloneTriples(d.arrowRGBExtraPixel);
			ClientPrefs.data.assetRGB = new Map();
			ClientPrefs.data.assetRGBPixel = new Map();
			ClientPrefs.data.noteColorOneValue = [d.noteColorOneValue[0], d.noteColorOneValue[1], d.noteColorOneValue[2]];
		}
		else
		{
			var k:Int = targetKey - 1;
			ClientPrefs.data.arrowRGBByKey[k] = [];
			ClientPrefs.data.arrowRGBByKeyPixel[k] = [];
			clearAssetKeycount(ClientPrefs.data.assetRGBByKey, k);
			clearAssetKeycount(ClientPrefs.data.assetRGBByKeyPixel, k);
		}
		overrideStored = false;
		rebuildPreview();
		syncPicker();
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
	}

	/** Deep-copies an array of `[main, border, shadow]` triples (so defaults aren't aliased). **/
	inline function cloneTriples(src:Array<Array<FlxColor>>):Array<Array<FlxColor>>
	{
		var out:Array<Array<FlxColor>> = [];
		for (row in src)
			out.push([row[0], row[1], row[2]]);
		return out;
	}

	/** Drops the per-keycount override at index `k` for every element in an asset by-key store. **/
	inline function clearAssetKeycount(map:Map<String, Array<Array<Array<FlxColor>>>>, k:Int):Void
	{
		for (el in map.keys())
		{
			var arr:Array<Array<Array<FlxColor>>> = map.get(el);
			if (arr != null && k < arr.length)
				arr[k] = [];
		}
	}

	/** Points the picker + channel control at the current lane/channel's stored colour (no callback). **/
	function syncPicker():Void
	{
		channelSeg.select(curChannel);
		var c:Int = getShaderColor();
		picker.color = 0xFF000000 | (c & 0xFFFFFF);
	}

	function setShaderColor(value:FlxColor):Void
	{
		if (!oneColorMode && targetKey > 0 && !overrideStored)
		{
			byKeyStore(editElement)[targetKey - 1] = dataArray;
			overrideStored = true;
		}
		dataArray[curLane][curChannel] = value;
	}

	inline function getShaderColor():FlxColor
		return dataArray[curLane][curChannel];

	inline function getShader():RGBPalette
		return Note.globalRgbShaders[curLane];


	/** Rebuilds the lane strip + preview grid for the current element/keycount/pixel selection. **/
	function rebuildPreview():Void
	{
		if (onPixel)
			PlayState.stageUI = "pixel";

		oneColorMode = (editElement == 'notes' && ClientPrefs.data.noteColorOneColor);

		dataArray = [];
		if (oneColorMode)
		{
			var count:Int = (targetKey == 0) ? 9 : targetKey;
			var one:Array<FlxColor> = ClientPrefs.data.noteColorOneValue;
			for (i in 0...count)
				dataArray.push(one);
			overrideStored = false;
		}
		else if (targetKey == 0)
		{
			dataArray = sharedStore(editElement);
			overrideStored = false;
		}
		else
		{
			var byKey:Array<Array<Array<FlxColor>>> = byKeyStore(editElement);
			var ov:Array<Array<FlxColor>> = byKey[targetKey - 1];
			if (ov != null && ov.length == targetKey)
			{
				dataArray = ov;
				overrideStored = true;
			}
			else
			{
				for (lane in Mania.composeShared(targetKey))
					dataArray.push([lane[0], lane[1], lane[2]]);
				overrideStored = false;
			}
		}
		if (curLane >= dataArray.length)
			curLane = dataArray.length - 1;
		if (curLane < 0)
			curLane = 0;

		myNotes.forEachAlive(function(note:Receptor) {
			note.kill();
			note.destroy();
		});
		myNotes.clear();

		var count:Int = dataArray.length;
		var cellW:Float = laneStripW / count;
		var strumSize:Int = Std.int(Math.min(laneArrow, cellW - 8));
		var startX:Float = regCX - laneStripW * 0.5;

		Mania.apply(count);

		// resetPalettes, not just the active array: the per-keycount caches were seeded from the colours
		// being edited here and would otherwise survive with the old ones.
		objects.notes.NoteDefaults.resetPalettes();
		for (i in 0...count)
		{
			var pal:RGBPalette = new RGBPalette();
			var slotCol:Array<FlxColor> = dataArray[i];
			pal.r = slotCol[0];
			pal.g = slotCol[1];
			pal.b = slotCol[2];
			Note.globalRgbShaders[i] = pal;
		}

		try
		{
			for (i in 0...count)
			{
				var newNote:Receptor = new Receptor(0, 0, i, 0, count);
				newNote.rgbShader.parent = Note.globalRgbShaders[i];
				newNote.shader = Note.globalRgbShaders[i].shader;
				newNote.useRGBShader = true;
				newNote.colorPerAnim = false;
				newNote.setGraphicSize(0, strumSize);
				placeSprite(newNote, startX + cellW * i + cellW * 0.5, laneCY);
				newNote.ID = i;
				myNotes.add(newNote);
			}
			applyPreview();
		}
		catch (e:Dynamic)
		{
			FlxG.log.warn('NotesColorState: preview build failed for the active note skin -- ' + e);
			teardownPreview();
		}

		PlayState.stageUI = "normal";
		updateLaneHighlight();
	}

	/** Highlights the selected lane receptor and moves the highlight box behind it. **/
	function updateLaneHighlight():Void
	{
		for (note in myNotes)
			note.alpha = (note.ID == curLane) ? 1 : 0.55;
		if (curLane >= 0 && curLane < myNotes.length)
		{
			var r:Receptor = myNotes.members[curLane];
			laneHighlight.setPosition(r.x - 6, r.y - 6);
			laneHighlight.setGraphicSize(Std.int(r.width + 12), Std.int(r.height + 12));
			laneHighlight.updateHitbox();
			laneHighlight.setPosition(r.x - 6, r.y - 6);
			laneHighlight.visible = true;
		}
		else
			laneHighlight.visible = false;
	}

	/**
		(Re)builds the six preview cells for the selected lane at the target keycount: note / hold /
		splash on top, static / pressed / confirm below, all sharing the lane palette.
	**/
	function applyPreview():Void
	{
		var count:Int = dataArray.length;
		var col:Int = curLane;
		Mania.apply(count);

		teardownPreview();

		try
		{
			var holdPal:RGBPalette = elementPalette('holds', col);
			bigHold = new SustainSprite();
			var hData:NoteData = new NoteData();
			hData.column = col;
			hData.length = 1000;
			bigHold.apply(hData, count);
			bindPreviewShader(bigHold, bigHold.rgbShader, holdPal);
			bindPreviewShader(bigHold.tail, bigHold.tailRGB, holdPal);
			layoutHold(col1, rowTop);
			add(bigHold);

			var notePal:RGBPalette = elementPalette('notes', col);
			bigNote = new NoteSprite();
			var nData:NoteData = new NoteData();
			nData.column = col;
			bigNote.apply(nData, count);
			bigNote.rgbShader.parent = notePal;
			bigNote.rgbShader.enabled = true;
			bigNote.shader = notePal.shader;
			bigNote.setGraphicSize(0, Std.int(cellSize));
			placeSprite(bigNote, col0, rowTop);
			add(bigNote);

			bigStatic = makeReceptor(col, count, elementPalette('strums', col), 'static');
			placeSprite(bigStatic, col0, rowBot);
			add(bigStatic);
			bigPressed = makeReceptor(col, count, elementPalette('pressed', col), 'pressed');
			placeSprite(bigPressed, col1, rowBot);
			add(bigPressed);
			bigStrum = makeReceptor(col, count, elementPalette('confirm', col), 'confirm');
			placeSprite(bigStrum, col2, rowBot);
			add(bigStrum);

			bigSplash = new objects.NoteSplash();
			bigSplash.inEditor = true;
			add(bigSplash);
			triggerSplashPreview();
		}
		catch (e:Dynamic)
		{
			FlxG.log.warn('NotesColorState: cell preview build failed for the active note skin -- ' + e);
			teardownPreview();
		}
	}

	function teardownPreview():Void
	{
		for (spr in [cast(bigHold, FlxSprite), cast(bigNote, FlxSprite), cast(bigStatic, FlxSprite), cast(bigPressed, FlxSprite),
			cast(bigStrum, FlxSprite), cast(bigSplash, FlxSprite)])
		{
			if (spr != null)
			{
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

	function makeReceptor(col:Int, count:Int, pal:RGBPalette, anim:String):Receptor
	{
		var r:Receptor = new Receptor(0, 0, col, 0, count);
		r.colorPerAnim = false;
		r.useRGBShader = true;
		r.rgbShader.parent = pal;
		r.shader = pal.shader;
		r.playAnim(anim, true);
		if (r.animation.curAnim != null)
			r.animation.curAnim.finish();
		r.setGraphicSize(0, Std.int(cellSize));
		return r;
	}

	function triggerSplashPreview():Void
	{
		if (bigSplash == null)
			return;
		Mania.apply(dataArray.length);
		bigSplash.spawnSplashNote(0, 0, curLane, null, false);
		bigSplash.copyX = bigSplash.copyY = false;
		bigSplash.setGraphicSize(0, Std.int(cellSize));
		placeSprite(bigSplash, col2, rowTop);
		bigSplash.rgbShader.copyValues(elementPalette('splash', curLane));
		splashWait = 0.3;
	}

	/**
		Centres a scaled sprite in a cell. `updateHitbox()` sets `offset` to compensate for centre-origin
		scaling (so `x`/`y` become the visible top-left) -- we must KEEP that offset, not zero it, or a
		heavily-padded frame (e.g. a widescreen skin) shifts the art by half its unscaled size.
	**/
	inline function placeSprite(spr:FlxSprite, cx:Float, cy:Float):Void
	{
		if (spr == null)
			return;
		spr.updateHitbox();
		spr.setPosition(cx - spr.width * 0.5, cy - spr.height * 0.5);
	}

	/** Live-updates the splash on edits (other cells track the shared shader object directly). **/
	function recolorPreview():Void
	{
		if (dataArray == null || curLane >= Note.globalRgbShaders.length || bigSplash == null || !bigSplash.alive)
			return;
		var splashSrc:String = ClientPrefs.data.linkSplashColor ? 'notes' : 'splash';
		if (splashSrc == editElement)
			bigSplash.rgbShader.copyValues(getShader());
	}

	inline function bindPreviewShader(spr:FlxSprite, ref:RGBShaderReference, pal:RGBPalette):Void
	{
		if (ref != null)
		{
			ref.parent = pal;
			ref.enabled = true;
		}
		spr.shader = pal.shader;
	}

	function layoutHold(cx:Float, cy:Float):Void
	{
		var w:Float = cellSize * 0.34;
		var len:Float = cellSize * 1.05;
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


	/** The palette a preview cell draws from: live (globalRgbShaders) when it tracks the edit, else static. **/
	function elementPalette(element:String, col:Int):RGBPalette
	{
		var linked:Bool = (element != 'notes') && (Reflect.field(ClientPrefs.data, ELEMENT_LINK.get(element)) == true);
		var src:String = linked ? 'notes' : element;
		if (src == editElement)
			return Note.globalRgbShaders[col];
		var c:Array<FlxColor>;
		if (targetKey == 0)
			c = sharedStore(src)[col];
		else
		{
			var ov:Array<Array<FlxColor>> = byKeyStore(src)[targetKey - 1];
			c = (ov != null && ov.length == targetKey) ? ov[col] : Mania.composeShared(targetKey)[col];
		}
		var p:RGBPalette = new RGBPalette();
		p.r = c[0];
		p.g = c[1];
		p.b = c[2];
		return p;
	}

	/** The shared (9-lane) colour store for an element; 'notes' is the cardinal+extra arrays. **/
	function sharedStore(element:String):Array<Array<FlxColor>>
	{
		if (element == 'notes')
		{
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
		if (arr == null || arr.length < 9)
		{
			arr = [];
			for (lane in sharedStore('notes'))
				arr.push([lane[0], lane[1], lane[2]]);
			map.set(element, arr);
		}
		return arr;
	}

	/** The per-keycount override store for an element. **/
	function byKeyStore(element:String):Array<Array<Array<FlxColor>>>
	{
		if (element == 'notes')
			return onPixel ? ClientPrefs.data.arrowRGBByKeyPixel : ClientPrefs.data.arrowRGBByKey;
		var map:Map<String, Array<Array<Array<FlxColor>>>> = onPixel ? ClientPrefs.data.assetRGBByKeyPixel : ClientPrefs.data.assetRGBByKey;
		var arr:Array<Array<Array<FlxColor>>> = map.get(element);
		if (arr == null)
		{
			arr = [[], [], [], [], [], [], [], [], []];
			map.set(element, arr);
		}
		return arr;
	}

	/** Whether `element` can be edited independently right now (link off + skin supports it). **/
	function elementEditable(element:String):Bool
	{
		if (element == 'notes')
			return true;
		var lf:String = ELEMENT_LINK.get(element);
		if (lf == null || Reflect.field(ClientPrefs.data, lf) == true)
			return false;
		var cfg:NoteSkinData = (NoteSkinConfig.activeSkin() != null) ? NoteSkinConfig.forCurrentKeys(NoteSkinConfig.activeSkin()) : null;
		return linkSupported(cfg, element);
	}

	/** Whether the active skin can colour `element` (classic skins only wire the splash link). **/
	function linkSupported(cfg:NoteSkinData, element:String):Bool
	{
		return (cfg != null) ? NoteSkinConfig.colorableFor(cfg, element) : (element == 'splash');
	}

	function defaultColor(note:Int, mode:Int):FlxColor
	{
		if (oneColorMode)
			return ClientPrefs.defaultData.noteColorOneValue[mode];
		if (targetKey > 0)
		{
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

	override function destroy():Void
	{
		objects.notes.NoteDefaults.resetPalettes();
		Mania.apply(prevKeyCount);
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		UITooltip.reset();
		FlxSmidr.dispose();
		uiRoot = null;
		super.destroy();
	}
}
