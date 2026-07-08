package editors;

import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import objects.Note;
import objects.StrumNote;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.input.keyboard.FlxKey;
import haxe.Json;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITabs;
import smidr.widgets.UITextInput;

using StringTools;

class NoteSkinEditorState extends MusicBeatState {
	var grid:FlxTypedSpriteGroup<FlxSprite> = new FlxTypedSpriteGroup();
	var bounds:FlxTypedSpriteGroup<FlxSprite> = new FlxTypedSpriteGroup();
	var strums:FlxTypedSpriteGroup<StrumNote> = new FlxTypedSpriteGroup();
	var notes:FlxTypedSpriteGroup<Note> = new FlxTypedSpriteGroup();
	var sustains:FlxTypedSpriteGroup<Note> = new FlxTypedSpriteGroup();

	var skinName:String = NoteSkinConfig.DEFAULT;
	var config:NoteSkinData;

	var curKeys:Int = 4;
	var showGrid:Bool = false;
	var showBounds:Bool = false;
	var gridSize:Int = 40;

	var infoText:FlxText;
	var tipText:FlxText;
	var skinDropDown:UIDropdown;
	var skinItems:Array<String> = [];
	var newNameInput:UITextInput;
	var notifyTimer:Float = 0;

	var uiRoot:UIRoot;

	inline function font()
		return Paths.font('vcr.ttf');

	override function create() {
		setKeyCount(4);
		Conductor.bpm = 100;
		Conductor.songPosition = 0;

		FlxG.mouse.visible = true;
		FlxG.sound.volumeUpKeys = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys = [];

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Note Skin Editor');
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF1B1B26;
		add(bg);

		add(grid);
		add(bounds);
		add(sustains);
		add(strums);
		add(notes);

		var available = NoteSkinConfig.list();
		if (!NoteSkinConfig.isFolderSkin(skinName) && available.length > 0)
			skinName = available[0];

		loadSkin(skinName);

		addUI();

		infoText = new FlxText(8, FlxG.height - 44, 0, '', 14);
		infoText.setFormat(font(), 14, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		infoText.scrollFactor.set();
		add(infoText);

		tipText = new FlxText(8, FlxG.height - 64, 0, '', 13);
		tipText.setFormat(font(), 13, FlxColor.YELLOW, LEFT, OUTLINE, FlxColor.BLACK);
		tipText.scrollFactor.set();
		add(tipText);

		refreshFields();
		super.create();
	}

	inline function setKeyCount(count:Int) {
		curKeys = Mania.apply(count);
	}

	function loadSkin(name:String) {
		skinName = name;
		NoteSkinConfig.editorOverride = name;

		var loaded = NoteSkinConfig.isFolderSkin(name) ? NoteSkinConfig.get(name) : null;
		config = (loaded != null) ? loaded : defaultConfig();
		NoteSkinConfig.setConfig(name, config);
		NoteSkinConfig.pixelMode = config.pixelVariant == true;

		buildPreview();
	}

	function defaultConfig():NoteSkinData {
		return {
			colorable: true,
			rotate: true,
			scale: 0.7,
			antialiasing: true,
			holdAlpha: 1,
			holdAntialiasing: false,
			directionAngles: [-90, 180, 0, 90],
			fps: 24,
			notes: {arrow: 'note', square: 'noteCenter'},
			holds: 'holdPiece',
			ends: 'holdEnd',
			strums: {arrow: 'strum', square: 'strumCenter'},
			pressed: {arrow: 'up press', square: 'centerPress'},
			confirm: {arrow: 'up confirm', square: 'centerConfirm'}
		};
	}

	function buildPreview() {
		setKeyCount(curKeys);
		NoteSkinConfig.setConfig(skinName, config);
		NoteSkinConfig.clearAnimCache();
		NoteSkinConfig.pixelMode = (config.pixel == true) || (config.pixelVariant == true);
		Note.globalRgbShaders = [];

		destroyGroup(strums);
		destroyGroup(notes);
		destroyGroup(sustains);
		destroyGroup(grid);
		destroyGroup(bounds);

		var strumLineX:Float = PlayState.STRUM_X_MIDDLESCROLL;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		var baseTime:Float = Conductor.stepCrochet;

		for (i in 0...curKeys) {
			var strum:StrumNote = new StrumNote(strumLineX, strumLineY, i, 1);
			strum.downScroll = ClientPrefs.data.downScroll;
			strum.ID = i;
			strums.add(strum);
			strum.playerPosition();
			strum.playAnim('static');

			var head:Note = new Note(baseTime, i, null, false, true);
			notes.add(head);
			var prev:Note = head;
			for (s in 0...6) {
				var piece:Note = new Note(baseTime + (s + 1) * Conductor.stepCrochet, i, prev, true, true);
				sustains.add(piece);
				prev = piece;
			}
		}

		for (head in notes.members)
			if (head != null)
				head.followStrumNote(strums.members[head.noteData], Conductor.crochet, 1);
		for (piece in sustains.members)
			if (piece != null)
				piece.followStrumNote(strums.members[piece.noteData], Conductor.crochet, 1);

		buildGrid();
		buildBounds();
	}

	function destroyGroup(group:FlxTypedSpriteGroup<Dynamic>) {
		for (m in group.members.copy())
			if (m != null)
				m.destroy();
		group.clear();
	}

	function buildGrid() {
		if (!showGrid)
			return;
		var faint:Int = 0xFF2C2C3D;
		var x:Int = 0;
		while (x <= FlxG.width) {
			addLine(grid, x, 0, 1, FlxG.height, faint, 0.4);
			x += gridSize;
		}
		var y:Int = 0;
		while (y <= FlxG.height) {
			addLine(grid, 0, y, FlxG.width, 1, faint, 0.4);
			y += gridSize;
		}
		for (strum in strums.members) {
			if (strum == null)
				continue;
			addLine(grid, strum.x + strum.width / 2 - 1, 0, 2, FlxG.height, 0xFF00FFAA, 0.55);
			addLine(grid, 0, strum.y + strum.height / 2 - 1, FlxG.width, 2, 0xFFFF6E6E, 0.45);
		}
	}

	function buildBounds() {
		if (!showBounds)
			return;
		for (strum in strums.members)
			if (strum != null)
				outline(strum.x, strum.y, strum.width, strum.height, 0xFFFFFFFF);
		for (head in notes.members)
			if (head != null)
				outline(head.x, head.y, head.width, head.height, 0xFFFFD24A);
	}

	function outline(x:Float, y:Float, w:Float, h:Float, color:Int) {
		addLine(bounds, x, y, w, 1, color, 0.9);
		addLine(bounds, x, y + h - 1, w, 1, color, 0.9);
		addLine(bounds, x, y, 1, h, color, 0.9);
		addLine(bounds, x + w - 1, y, 1, h, color, 0.9);
	}

	inline function addLine(group:FlxTypedSpriteGroup<FlxSprite>, x:Float, y:Float, w:Float, h:Float, color:Int, a:Float) {
		var l = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), color);
		l.alpha = a;
		l.scrollFactor.set();
		group.add(l);
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
	static inline var BOX_W:Int = 350;

	var boxTabs:UITabs;
	var tabPanes:Array<UIScrollPane> = [];

	function addUI() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		var boxX:Float = FlxG.width - BOX_W - 10;
		var boxY:Float = 20;

		boxTabs = new UITabs(BOX_W, [{label: 'General'}, {label: 'Properties'}, {label: 'Images'}, {label: 'Offsets'}], function(i:Int):Void {
			for (n in 0...tabPanes.length)
				tabPanes[n].visible = (n == i);
		});

		var paneH:Float = 340;
		var boxH:Float = boxTabs.h + 8 + paneH + PAD;

		var panel:UIPanel = new UIPanel(BOX_W, boxH, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		boxTabs.x = boxX;
		boxTabs.y = boxY;
		uiRoot.content.addChild(boxTabs);

		tabPanes = [];
		for (i in 0...4) {
			var pane:UIScrollPane = new UIScrollPane(BOX_W - PAD * 2, paneH);
			pane.x = boxX + PAD;
			pane.y = boxY + boxTabs.h + 8;
			pane.visible = false;
			uiRoot.content.addChild(pane);
			tabPanes.push(pane);
		}

		addGeneralTab(tabPanes[0]);
		addPropertiesTab(tabPanes[1]);
		addImagesTab(tabPanes[2]);
		addOffsetsTab(tabPanes[3]);

		boxTabs.select(0);
		tabPanes[0].visible = true;
	}

	inline function paneRowW(pane:UIScrollPane):Float
		return pane.w - PAD - 12;

	function paneLabel(pane:UIScrollPane, x:Float, y:Float, text:String, size:Int = 11):UILabel {
		var l:UILabel = new UILabel(text, size, 2);
		l.x = x;
		l.y = y;
		pane.content.addChild(l);
		return l;
	}

	function addGeneralTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		skinItems = NoteSkinConfig.list();
		if (skinItems.length < 1)
			skinItems.push(skinName);
		skinDropDown = new UIDropdown('Folder skin:', rowW, function(id:Int, name:String) {
			loadSkin(name);
			refreshFields();
		});
		skinDropDown.setItems(skinItems.copy());
		skinDropDown.select(Std.int(Math.max(0, skinItems.indexOf(skinName))));
		pane.content.addChild(skinDropDown);

		var reload:UIButton = new UIButton('Reload', 90, 26, function() {
			NoteSkinConfig.reset();
			loadSkin(skinName);
			refreshFields();
		});
		reload.y = 34;
		pane.content.addChild(reload);

		var saveBtn:UIButton = new UIButton('Save', 80, 26, saveSkin, true);
		saveBtn.x = 100;
		saveBtn.y = 34;
		pane.content.addChild(saveBtn);

		var saveRootBtn:UIButton = new UIButton('Save to game folder', rowW - 190, 26, saveToRoot);
		saveRootBtn.x = 190;
		saveRootBtn.y = 34;
		pane.content.addChild(saveRootBtn);

		newNameInput = new UITextInput('New skin name:', rowW - 80, 'skin');
		newNameInput.y = 70;
		pane.content.addChild(newNameInput);

		var createBtn:UIButton = new UIButton('Create', 70, 24, createNewSkin);
		createBtn.x = rowW - 70;
		createBtn.y = 70;
		pane.content.addChild(createBtn);

		var keysStep:UIStepper = new UIStepper('Keys:', halfW, 4, 1, function(v:Float) {
			setKeyCount(Std.int(v));
			buildPreview();
			refreshFields();
		});
		keysStep.min = Mania.MIN;
		keysStep.max = Mania.MAX;
		keysStep.y = 104;
		pane.content.addChild(keysStep);

		var gridCheck:UICheckbox = new UICheckbox('Show grid', halfW, showGrid, function(v:Bool) {
			showGrid = v;
			destroyGroup(grid);
			buildGrid();
		});
		gridCheck.x = halfW + 10;
		gridCheck.y = 104;
		pane.content.addChild(gridCheck);

		var gridStep:UIStepper = new UIStepper('Grid size:', halfW, gridSize, 4, function(v:Float) {
			gridSize = Std.int(v);
			destroyGroup(grid);
			buildGrid();
		});
		gridStep.min = 8;
		gridStep.max = 200;
		gridStep.y = 136;
		pane.content.addChild(gridStep);

		var boundsCheck:UICheckbox = new UICheckbox('Frame bounds', halfW, showBounds, function(v:Bool) {
			showBounds = v;
			destroyGroup(bounds);
			buildBounds();
		});
		boundsCheck.x = halfW + 10;
		boundsCheck.y = 136;
		pane.content.addChild(boundsCheck);

		paneLabel(pane, 0, 172, 'Save: shared skins write to');
		paneLabel(pane, 0, 186, 'mods/images/noteSkins/<name>-modified/');

		pane.refreshContent(210);
	}

	var scaleStep:UIStepper;
	var alphaStep:UIStepper;
	var confirmFpsStep:UIStepper;
	var angleSteps:Array<UIStepper> = [];
	var colorableCheck:UICheckbox;
	var rotateCheck:UICheckbox;
	var pixelCheck:UICheckbox;
	var pixelVarCheck:UICheckbox;
	var aaCheck:UICheckbox;
	var holdAACheck:UICheckbox;

	function addPropertiesTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		scaleStep = new UIStepper('Scale:', halfW, 0.7, 0.05, function(v:Float) {
			config.scale = v;
			buildPreview();
		});
		scaleStep.min = 0.05;
		scaleStep.max = 4;
		scaleStep.decimals = 2;
		pane.content.addChild(scaleStep);

		alphaStep = new UIStepper('Hold alpha:', halfW, 1, 0.05, function(v:Float) {
			config.holdAlpha = v;
			buildPreview();
		});
		alphaStep.min = 0;
		alphaStep.max = 1;
		alphaStep.decimals = 2;
		alphaStep.x = halfW + 10;
		pane.content.addChild(alphaStep);

		confirmFpsStep = new UIStepper('Anim FPS:', halfW, 24, 1, function(v:Float) {
			config.fps = Std.int(v);
			buildPreview();
		});
		confirmFpsStep.min = 0;
		confirmFpsStep.max = 60;
		confirmFpsStep.y = 32;
		pane.content.addChild(confirmFpsStep);

		colorableCheck = makeCheck(pane, 0, 68, 'Colorable (RGB) - all', halfW, function(v) {
			config.colorable = v;
			if (imgColorableCheck != null)
				imgColorableCheck.checked = NoteSkinConfig.colorableFor(config, elemField(curElem));
		});
		rotateCheck = makeCheck(pane, halfW + 10, 68, 'Rotate shared', halfW, function(v) config.rotate = v);
		pixelCheck = makeCheck(pane, 0, 96, 'Pixel perfect render', halfW, function(v) config.pixel = v);
		aaCheck = makeCheck(pane, halfW + 10, 96, 'Antialiasing', halfW, function(v) config.antialiasing = v);
		holdAACheck = makeCheck(pane, 0, 124, 'Hold AA', halfW, function(v) config.holdAntialiasing = v);
		pixelVarCheck = makeCheck(pane, halfW + 10, 124, 'Has pixel variant (-pixel)', halfW, function(v) config.pixelVariant = v);

		paneLabel(pane, 0, 160, 'Direction angles (L / D / U / R):');
		var quarterW:Float = (rowW - 30) / 4;
		var labels = ['L:', 'D:', 'U:', 'R:'];
		angleSteps = [];
		for (i in 0...4) {
			var step:UIStepper = new UIStepper(labels[i], quarterW, [-90, 180, 0, 90][i], 15, null);
			var idx = i;
			step.onChange = function(v:Float) {
				if (config.directionAngles == null)
					config.directionAngles = [-90, 180, 0, 90];
				config.directionAngles[idx] = v;
				buildPreview();
			};
			step.min = -360;
			step.max = 360;
			step.boxWidth = 52;
			step.x = i * (quarterW + 10);
			step.y = 182;
			angleSteps.push(step);
			pane.content.addChild(step);
		}

		paneLabel(pane, 0, 218, 'Scalars & angles are shared across all');
		paneLabel(pane, 0, 232, 'keycounts; images are per keycount.');

		pane.refreshContent(256);
	}

	function makeCheck(pane:UIScrollPane, x:Float, y:Float, lbl:String, w:Float, onSet:Bool->Void):UICheckbox {
		var c:UICheckbox = new UICheckbox(lbl, w, false, function(v:Bool) {
			onSet(v);
			buildPreview();
		});
		c.x = x;
		c.y = y;
		pane.content.addChild(c);
		return c;
	}

	var imgKeysLabel:UILabel;
	var imgElemDrop:UIDropdown;
	var imgPerDir:UICheckbox;
	var imgColorableCheck:UICheckbox;
	var imgAnimatedCheck:UICheckbox;
	var imgIn:Array<UITextInput> = [];
	var curElem:String = 'Note';
	var curPerDir:Bool = false;

	static final IMG_ELEMS = ['Note', 'Strum', 'Pressed', 'Confirm', 'Hold', 'End'];

	function addImagesTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		imgKeysLabel = paneLabel(pane, 0, 0, '');

		imgElemDrop = new UIDropdown('Element:', halfW, function(id, name) {
			curElem = name;
			loadImageInputs();
		});
		imgElemDrop.setItems(IMG_ELEMS.copy());
		imgElemDrop.select(0);
		imgElemDrop.y = 20;
		pane.content.addChild(imgElemDrop);

		imgPerDir = new UICheckbox('Per-direction', halfW, false, function(v:Bool) {
			curPerDir = v;
			loadImageInputs();
		});
		imgPerDir.x = halfW + 10;
		imgPerDir.y = 20;
		pane.content.addChild(imgPerDir);

		imgColorableCheck = new UICheckbox('Colorable', halfW, false, function(v:Bool) {
			setColorable(elemField(curElem), v);
		});
		imgColorableCheck.y = 52;
		pane.content.addChild(imgColorableCheck);

		imgAnimatedCheck = new UICheckbox('Animated', halfW, false, function(v:Bool) {
			setAnimated(elemField(curElem), v);
		});
		imgAnimatedCheck.x = halfW + 10;
		imgAnimatedCheck.y = 52;
		pane.content.addChild(imgAnimatedCheck);

		imgIn = [];
		var y:Float = 86;
		for (i in 0...5) {
			var inp:UITextInput = new UITextInput('', rowW, '');
			inp.y = y;
			imgIn.push(inp);
			pane.content.addChild(inp);
			y += 32;
		}

		var apply:UIButton = new UIButton('Apply images', 150, 26, function() applyImagesFor(curElem), true);
		apply.y = y + 6;
		pane.content.addChild(apply);
		paneLabel(pane, 0, y + 40, 'Click Apply to write. Empty = use shared');
		paneLabel(pane, 0, y + 54, 'arrow. Per-direction = distinct per lane.');

		pane.refreshContent(y + 80);
	}

	inline function isDirectional(elem:String):Bool
		return elem != 'Hold' && elem != 'End';

	inline function elemField(elem:String):String
		return switch (elem) {
			case 'Strum': 'strums';
			case 'Pressed': 'pressed';
			case 'Confirm': 'confirm';
			case 'Hold': 'holds';
			case 'End': 'ends';
			default: 'notes';
		}

	function keysSection(count:Int):Dynamic {
		if (config.keys == null)
			config.keys = {};
		var key:String = Std.string(count);
		var sec:Dynamic = Reflect.field(config.keys, key);
		if (sec == null) {
			sec = {};
			Reflect.setField(config.keys, key, sec);
		}
		return sec;
	}

	inline function trimI(i:Int):String {
		var v = imgIn[i].text.trim();
		return v.length < 1 ? null : v;
	}

	function loadImageInputs() {
		if (imgIn.length < 5)
			return;
		if (imgColorableCheck != null)
			imgColorableCheck.checked = NoteSkinConfig.colorableFor(config, elemField(curElem));
		if (imgAnimatedCheck != null)
			imgAnimatedCheck.checked = NoteSkinConfig.animatedFor(config, elemField(curElem));
		var eff:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		var field:Dynamic = (eff == null) ? null : Reflect.field(eff, elemField(curElem));

		for (i in 0...5)
			imgIn[i].visible = false;

		if (curPerDir) {
			var names = ['left', 'down', 'up', 'right', 'square'];
			for (i in 0...5) {
				imgIn[i].label = names[i] + ':';
				imgIn[i].visible = true;
				imgIn[i].text = perDirVal(field, names[i]);
			}
		} else if (isDirectional(curElem)) {
			imgIn[0].label = 'Arrow:';
			imgIn[4].label = 'Square:';
			imgIn[0].visible = imgIn[4].visible = true;
			imgIn[0].text = fieldArrow(field);
			imgIn[4].text = fieldSquare(field);
		} else {
			imgIn[0].label = 'Image:';
			imgIn[0].visible = true;
			imgIn[0].text = fieldArrow(field);
		}
	}

	static final COLOR_ELEMS = ['notes', 'holds', 'ends', 'strums', 'pressed', 'confirm'];

	function anyColorable(c:NoteSkinData):Bool {
		if (c == null || c.colorable == null)
			return false;
		if (Std.isOfType(c.colorable, Bool))
			return c.colorable == true;
		for (e in COLOR_ELEMS)
			if (NoteSkinConfig.colorableFor(c, e))
				return true;
		return false;
	}

	function setColorable(element:String, value:Bool) {
		var obj:Dynamic = {};
		for (e in COLOR_ELEMS)
			Reflect.setField(obj, e, NoteSkinConfig.colorableFor(config, e));
		Reflect.setField(obj, element, value);
		config.colorable = obj;
		if (colorableCheck != null)
			colorableCheck.checked = anyColorable(config);
		buildPreview();
	}

	function setAnimated(element:String, value:Bool) {
		var obj:Dynamic = {};
		for (e in COLOR_ELEMS)
			Reflect.setField(obj, e, NoteSkinConfig.animatedFor(config, e));
		Reflect.setField(obj, element, value);
		config.animated = obj;
		buildPreview();
	}

	function perDirVal(field:Dynamic, dir:String):String {
		if (field == null || Std.isOfType(field, String) || Std.isOfType(field, Array))
			return '';
		var v = Reflect.field(field, dir);
		return v == null ? '' : Std.string(v);
	}

	function applyImagesFor(elem:String) {
		var target:Dynamic = (curKeys == 4) ? cast config : keysSection(curKeys);
		var val:Dynamic = null;
		if (curPerDir) {
			var names = ['left', 'down', 'up', 'right', 'square'];
			var obj:Dynamic = {};
			var any = false;
			for (i in 0...5) {
				var v = trimI(i);
				if (v != null) {
					Reflect.setField(obj, names[i], v);
					any = true;
				}
			}
			val = any ? obj : null;
		} else if (isDirectional(elem)) {
			var a = trimI(0);
			var s = trimI(4);
			val = (a == null && s == null) ? null : (s == null ? a : {arrow: a, square: s});
		} else {
			val = trimI(0);
		}
		Reflect.setField(target, elemField(elem), val);
		buildPreview();
	}

	function refreshFields() {
		if (scaleStep == null)
			return;

		scaleStep.value = config.scale == null ? 0.7 : config.scale;
		alphaStep.value = config.holdAlpha == null ? 0.6 : config.holdAlpha;
		confirmFpsStep.value = config.fps == null ? 24 : config.fps;
		colorableCheck.checked = anyColorable(config);
		rotateCheck.checked = config.rotate != false;
		pixelCheck.checked = config.pixel == true;
		pixelVarCheck.checked = config.pixelVariant == true;
		aaCheck.checked = config.antialiasing != false;
		holdAACheck.checked = config.holdAntialiasing != false;

		var angles:Array<Float> = config.directionAngles == null ? [-90, 180, 0, 90] : config.directionAngles;
		for (i in 0...4)
			angleSteps[i].value = (i < angles.length) ? angles[i] : 0;

		if (imgKeysLabel != null) {
			var inherited:Bool = curKeys != 4 && (config.keys == null || Reflect.field(config.keys, Std.string(curKeys)) == null);
			imgKeysLabel.text = 'Images for ${curKeys}K' + (inherited ? ' (inherited)' : '') + ':';
		}
		loadImageInputs();
	}

	function fieldArrow(f:Dynamic):String {
		if (f == null)
			return '';
		if (Std.isOfType(f, String))
			return f;
		if (Std.isOfType(f, Array)) {
			var a:Array<Dynamic> = f;
			return a.length > 0 ? Std.string(a[0]) : '';
		}
		for (k in ['arrow', 'up', 'left', 'down', 'right', 'square'])
			if (Reflect.hasField(f, k))
				return Std.string(Reflect.field(f, k));
		return '';
	}

	function fieldSquare(f:Dynamic):String {
		if (f == null || Std.isOfType(f, String) || Std.isOfType(f, Array))
			return '';
		var v = Reflect.field(f, 'square');
		return v == null ? '' : Std.string(v);
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		infoText.text = 'Note Skin Editor - ${skinName} (${curKeys}K)   |   ESC: editor menu';
		if (notifyTimer > 0)
			notifyTimer -= elapsed;
		else {
			tipText.color = FlxColor.YELLOW;
			tipText.text = 'Hover a strum = pressed, click = confirm';
		}

		var blockInput:Bool = (UIFocus.focused != null) || UIRoot.overlayOpen;
		if (!blockInput && controls.BACK) {
			NoteSkinConfig.editorOverride = null;
			NoteSkinConfig.pixelMode = false;
			NoteSkinConfig.reset();
			setKeyCount(Mania.DEFAULT);
			MusicBeatState.switchState(new MasterEditorMenu());
			return;
		}

		strums.forEach(function(strum:StrumNote) {
			var over = FlxG.mouse.overlaps(strum);
			var name = strum.animation.curAnim != null ? strum.animation.curAnim.name : '';
			if (over) {
				if (FlxG.mouse.justPressed)
					strum.playAnim('confirm', true);
				else if (name == 'static' || (name == 'confirm' && strum.animation.finished))
					strum.playAnim('pressed');
			} else if (name != 'static')
				strum.playAnim('static');
		});
	}

	override function destroy() {
		NoteSkinConfig.editorOverride = null;
		NoteSkinConfig.pixelMode = false;
		FlxG.signals.gameResized.remove(onGameResized);
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();

		FlxG.sound.muteKeys = [FlxKey.ZERO];
		FlxG.sound.volumeDownKeys = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
		FlxG.sound.volumeUpKeys = [FlxKey.NUMPADPLUS, FlxKey.PLUS];
	}

	var offElemDrop:UIDropdown;
	var offDirDrop:UIDropdown;
	var offX:UIStepper;
	var offY:UIStepper;
	var curOffElem:String = 'Note';
	var curOffDir:String = 'left';

	static final OFF_ELEMS = ['Note', 'Strum', 'Hold'];

	function addOffsetsTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		paneLabel(pane, 0, 0, 'Nudge art per direction to center it.');

		offElemDrop = new UIDropdown('Element:', rowW, function(id, name) {
			curOffElem = name;
			loadOffsetSteppers();
		});
		offElemDrop.setItems(OFF_ELEMS.copy());
		offElemDrop.select(0);
		offElemDrop.y = 22;
		pane.content.addChild(offElemDrop);

		offDirDrop = new UIDropdown('Direction:', rowW, function(id, name) {
			curOffDir = name;
			loadOffsetSteppers();
		});
		offDirDrop.setItems(['left', 'down', 'up', 'right', 'square']);
		offDirDrop.select(0);
		offDirDrop.y = 54;
		pane.content.addChild(offDirDrop);

		offX = new UIStepper('X:', halfW, 0, 1, function(_) applyOffsetSteppers());
		offX.min = -300;
		offX.max = 300;
		offX.y = 90;
		pane.content.addChild(offX);

		offY = new UIStepper('Y:', halfW, 0, 1, function(_) applyOffsetSteppers());
		offY.min = -300;
		offY.max = 300;
		offY.x = halfW + 10;
		offY.y = 90;
		pane.content.addChild(offY);

		var resetBtn:UIButton = new UIButton('Reset this', 100, 26, function() {
			offX.value = 0;
			offY.value = 0;
			applyOffsetSteppers();
		});
		resetBtn.y = 124;
		pane.content.addChild(resetBtn);

		paneLabel(pane, 0, 160, 'Offsets are shared across keycounts,');
		paneLabel(pane, 0, 174, 'keyed by direction.');

		pane.refreshContent(198);

		loadOffsetSteppers();
	}

	inline function offsetFieldName(elem:String):String
		return switch (elem) {
			case 'Strum': 'strumOffsets';
			case 'Hold': 'holdOffsets';
			default: 'noteOffsets';
		}

	function loadOffsetSteppers() {
		if (offX == null)
			return;
		var f:Dynamic = Reflect.field(config, offsetFieldName(curOffElem));
		var v:Dynamic = (f == null) ? null : Reflect.field(f, curOffDir);
		if (v != null && Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			offX.value = a.length > 0 ? a[0] : 0;
			offY.value = a.length > 1 ? a[1] : 0;
		} else {
			offX.value = 0;
			offY.value = 0;
		}
	}

	function applyOffsetSteppers() {
		var fn = offsetFieldName(curOffElem);
		var f:Dynamic = Reflect.field(config, fn);
		if (f == null) {
			f = {};
			Reflect.setField(config, fn, f);
		}
		Reflect.setField(f, curOffDir, [offX.value, offY.value]);
		buildPreview();
	}

	function notify(msg:String, ?good:Bool = true) {
		tipText.color = good ? FlxColor.LIME : FlxColor.RED;
		tipText.text = msg;
		notifyTimer = 4;
	}

	function ensureDir(path:String) {
		#if sys
		var parts = path.split('/');
		var cur = '';
		for (p in parts) {
			if (p.length < 1)
				continue;
			cur += (cur.length > 0 ? '/' : '') + p;
			if (!sys.FileSystem.exists(cur))
				sys.FileSystem.createDirectory(cur);
		}
		#end
	}

	function saveDir():String {
		var name = skinName.substr(skinName.lastIndexOf('/') + 1);
		#if sys
		var hasShared = sys.FileSystem.exists('assets/shared/images/$skinName/skin.tcfg')
			|| sys.FileSystem.exists('assets/shared/images/$skinName/skin.json');
		var inMod = skinFileExists('mods/images/$skinName');
		#if MODS_ALLOWED
		if (!inMod && Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			inMod = skinFileExists('mods/${Mods.currentModDirectory}/images/$skinName');
		#end
		var fromShared = hasShared && !inMod;
		if (fromShared)
			name += '-modified';
		#end
		return 'mods/images/noteSkins/$name';
	}

	// Exists check for either supported folder-skin config in a dir.
	inline function skinFileExists(dir:String):Bool {
		#if sys
		return sys.FileSystem.exists('$dir/skin.tcfg') || sys.FileSystem.exists('$dir/skin.json');
		#else
		return false;
		#end
	}

	function saveSkin() {
		#if sys
		var dir = saveDir();
		try {
			ensureDir(dir);
			sys.io.File.saveContent('$dir/skin.tcfg', backend.config.TcfgWriter.write(config));
			NoteSkinConfig.reset();
			notify('Saved to $dir/skin.tcfg');
		} catch (e:Dynamic)
			notify('Save failed: $e', false);
		#else
		notify('Saving needs a desktop build', false);
		#end
	}

	function saveToRoot() {
		#if sys
		try {
			var path = Sys.getCwd() + '/skin.tcfg';
			sys.io.File.saveContent(path, backend.config.TcfgWriter.write(config));
			notify('Saved skin.tcfg to game folder');
		} catch (e:Dynamic)
			notify('Save failed: $e', false);
		#else
		notify('Saving needs a desktop build', false);
		#end
	}

	function createNewSkin() {
		#if sys
		var name = newNameInput.text.trim();
		if (name.length < 1) {
			notify('Enter a skin name first', false);
			return;
		}
		var dir = 'mods/images/noteSkins/$name';
		try {
			ensureDir(dir);
			config = defaultConfig();
			sys.io.File.saveContent('$dir/skin.tcfg', backend.config.TcfgWriter.write(config));
			NoteSkinConfig.reset();
			skinName = 'noteSkins/$name';
			skinItems = NoteSkinConfig.list();
			skinDropDown.setItems(skinItems.copy());
			skinDropDown.select(Std.int(Math.max(0, skinItems.indexOf(skinName))));
			loadSkin(skinName);
			refreshFields();
			notify('Created $dir/skin.tcfg');
		} catch (e:Dynamic)
			notify('Create failed: $e', false);
		#else
		notify('Creating needs a desktop build', false);
		#end
	}
}
