package editors;

import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import objects.Note;
import objects.StrumNote;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.input.keyboard.FlxKey;
import haxe.Json;

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
	var skinDropDown:PsychUIDropDownMenu;
	var newNameInput:PsychUIInputText;
	var notifyTimer:Float = 0;

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

	var box:PsychUIBox;

	function addUI() {
		box = new PsychUIBox(FlxG.width - 330, 20, 320, 430, ['General', 'Properties', 'Images', 'Offsets']);
		box.canMove = box.canMinimize = true;
		box.scrollFactor.set();
		add(box);
		addGeneralTab();
		addPropertiesTab();
		addImagesTab();
		addOffsetsTab();
	}

	function label(t:FlxSpriteGroup, x:Float, y:Float, text:String, size:Int = 12):FlxText {
		var f = new FlxText(x, y, 0, text, size);
		f.setFormat(font(), size, FlxColor.WHITE);
		t.add(f);
		return f;
	}

	function addGeneralTab() {
		var t = box.getTab('General').menu;

		label(t, 10, 8, 'Folder skin:');
		var skins = NoteSkinConfig.list();
		if (skins.length < 1)
			skins.push(skinName);
		skinDropDown = new PsychUIDropDownMenu(10, 28, skins, function(id:Int, name:String) {
			loadSkin(name);
			refreshFields();
		});
		skinDropDown.selectedLabel = skinName;

		var reload = new PsychUIButton(10, 62, 'Reload', function() {
			NoteSkinConfig.reset();
			loadSkin(skinName);
			refreshFields();
		});
		reload.resize(90, 26);
		t.add(reload);

		var saveBtn = new PsychUIButton(110, 62, 'Save', saveSkin);
		saveBtn.resize(80, 26);
		t.add(saveBtn);

		var saveRootBtn = new PsychUIButton(200, 62, 'Save to game folder', saveToRoot);
		saveRootBtn.resize(110, 26);
		t.add(saveRootBtn);

		label(t, 10, 96, 'New skin name:', 11);
		newNameInput = new PsychUIInputText(115, 93, 120, 'skin', 8);
		t.add(newNameInput);
		var createBtn = new PsychUIButton(240, 91, 'Create', createNewSkin);
		createBtn.resize(70, 26);
		t.add(createBtn);

		label(t, 10, 126, 'Keys:');
		var keysStep = new PsychUINumericStepper(60, 123, 1, 4, Mania.MIN, Mania.MAX, 0, 60);
		keysStep.onValueChange = function() {
			setKeyCount(Std.int(keysStep.value));
			buildPreview();
			refreshFields();
		};
		t.add(keysStep);

		var gridCheck = new PsychUICheckBox(140, 125, 'Show grid', 110);
		gridCheck.checked = showGrid;
		gridCheck.onClick = function() {
			showGrid = gridCheck.checked;
			destroyGroup(grid);
			buildGrid();
		};
		t.add(gridCheck);

		label(t, 10, 160, 'Grid size:');
		var gridStep = new PsychUINumericStepper(85, 157, 4, gridSize, 8, 200, 0, 60);
		gridStep.onValueChange = function() {
			gridSize = Std.int(gridStep.value);
			destroyGroup(grid);
			buildGrid();
		};
		t.add(gridStep);

		var boundsCheck = new PsychUICheckBox(160, 159, 'Frame bounds', 130);
		boundsCheck.checked = showBounds;
		boundsCheck.onClick = function() {
			showBounds = boundsCheck.checked;
			destroyGroup(bounds);
			buildBounds();
		};
		t.add(boundsCheck);

		label(t, 10, 196, 'Save: shared skins write to', 11);
		label(t, 10, 210, 'mods/images/noteSkins/<name>-modified/', 11);

		t.add(skinDropDown);
	}

	var scaleStep:PsychUINumericStepper;
	var alphaStep:PsychUINumericStepper;
	var confirmFpsStep:PsychUINumericStepper;
	var angleSteps:Array<PsychUINumericStepper> = [];
	var colorableCheck:PsychUICheckBox;
	var rotateCheck:PsychUICheckBox;
	var pixelCheck:PsychUICheckBox;
	var pixelVarCheck:PsychUICheckBox;
	var aaCheck:PsychUICheckBox;
	var holdAACheck:PsychUICheckBox;

	function addPropertiesTab() {
		var t = box.getTab('Properties').menu;

		label(t, 10, 10, 'Scale:');
		scaleStep = new PsychUINumericStepper(75, 7, 0.05, 0.7, 0.05, 4, 2, 70);
		scaleStep.onValueChange = function() {
			config.scale = scaleStep.value;
			buildPreview();
		};
		t.add(scaleStep);

		label(t, 170, 10, 'Hold alpha:');
		alphaStep = new PsychUINumericStepper(250, 7, 0.05, 1, 0, 1, 2, 60);
		alphaStep.onValueChange = function() {
			config.holdAlpha = alphaStep.value;
			buildPreview();
		};
		t.add(alphaStep);

		label(t, 10, 44, 'Anim FPS:');
		confirmFpsStep = new PsychUINumericStepper(105, 41, 1, 24, 0, 60, 0, 60);
		confirmFpsStep.onValueChange = function() {
			config.fps = Std.int(confirmFpsStep.value);
			buildPreview();
		};
		t.add(confirmFpsStep);

		colorableCheck = makeCheck(t, 10, 78, 'Colorable (RGB) - all', function(v) {
			config.colorable = v;
			if (imgColorableCheck != null)
				imgColorableCheck.checked = NoteSkinConfig.colorableFor(config, elemField(curElem));
		});
		rotateCheck = makeCheck(t, 160, 78, 'Rotate shared', function(v) config.rotate = v);
		pixelCheck = makeCheck(t, 10, 104, 'Pixel perfect render', function(v) config.pixel = v);
		aaCheck = makeCheck(t, 10, 130, 'Antialiasing', function(v) config.antialiasing = v);
		holdAACheck = makeCheck(t, 160, 130, 'Hold AA', function(v) config.holdAntialiasing = v);
		pixelVarCheck = makeCheck(t, 10, 156, 'Has pixel variant (-pixel)', function(v) config.pixelVariant = v);

		label(t, 10, 214, 'Direction angles (L / D / U / R):', 11);
		var labels = ['L', 'D', 'U', 'R'];
		for (i in 0...4) {
			label(t, 10 + i * 74, 234, labels[i], 11);
			var step = new PsychUINumericStepper(28 + i * 74, 231, 15, [-90, 180, 0, 90][i], -360, 360, 0, 44);
			var idx = i;
			step.onValueChange = function() {
				if (config.directionAngles == null)
					config.directionAngles = [-90, 180, 0, 90];
				config.directionAngles[idx] = step.value;
				buildPreview();
			};
			angleSteps.push(step);
			t.add(step);
		}

		label(t, 10, 270, 'Scalars & angles are shared across all', 11);
		label(t, 10, 284, 'keycounts; images are per keycount.', 11);
	}

	function makeCheck(t:FlxSpriteGroup, x:Float, y:Float, lbl:String, onSet:Bool->Void):PsychUICheckBox {
		var c = new PsychUICheckBox(x, y, lbl, 200);
		c.onClick = function() {
			onSet(c.checked);
			buildPreview();
		};
		t.add(c);
		return c;
	}

	var imgKeysLabel:FlxText;
	var imgElemDrop:PsychUIDropDownMenu;
	var imgPerDir:PsychUICheckBox;
	var imgColorableCheck:PsychUICheckBox;
	var imgAnimatedCheck:PsychUICheckBox;
	var imgIn:Array<PsychUIInputText> = [];
	var imgLbl:Array<FlxText> = [];
	var curElem:String = 'Note';
	var curPerDir:Bool = false;

	static final IMG_ELEMS = ['Note', 'Strum', 'Pressed', 'Confirm', 'Hold', 'End'];

	function addImagesTab() {
		var t = box.getTab('Images').menu;
		imgKeysLabel = label(t, 8, 6, '', 11);

		label(t, 8, 28, 'Element:', 11);
		imgElemDrop = new PsychUIDropDownMenu(70, 24, IMG_ELEMS.copy(), function(id, name) {
			curElem = name;
			loadImageInputs();
		});

		imgPerDir = new PsychUICheckBox(190, 26, 'Per-direction', 130);
		imgPerDir.onClick = function() {
			curPerDir = imgPerDir.checked;
			loadImageInputs();
		};
		t.add(imgPerDir);

		imgColorableCheck = new PsychUICheckBox(8, 48, 'Colorable', 150);
		imgColorableCheck.onClick = function() {
			setColorable(elemField(curElem), imgColorableCheck.checked);
		};
		t.add(imgColorableCheck);

		imgAnimatedCheck = new PsychUICheckBox(165, 48, 'Animated', 150);
		imgAnimatedCheck.onClick = function() {
			setAnimated(elemField(curElem), imgAnimatedCheck.checked);
		};
		t.add(imgAnimatedCheck);

		var y:Float = 76;
		for (i in 0...5) {
			imgLbl.push(label(t, 8, y + 3, '', 11));
			var inp = new PsychUIInputText(85, y, 150, '', 8);
			imgIn.push(inp);
			t.add(inp);
			y += 30;
		}

		var apply = new PsychUIButton(8, y + 8, 'Apply images', function() applyImagesFor(curElem));
		apply.resize(150, 26);
		t.add(apply);
		label(t, 8, y + 42, 'Click Apply to write. Empty = use shared', 10);
		label(t, 8, y + 55, 'arrow. Per-direction = distinct per lane.', 10);

		t.add(imgElemDrop);
		imgElemDrop.selectedLabel = 'Note';
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
				imgLbl[i].text = names[i] + ':';
				imgIn[i].visible = true;
				imgIn[i].text = perDirVal(field, names[i]);
			}
		} else if (isDirectional(curElem)) {
			imgLbl[0].text = 'Arrow:';
			imgLbl[4].text = 'Square:';
			imgIn[0].visible = imgIn[4].visible = true;
			imgIn[0].text = fieldArrow(field);
			imgIn[4].text = fieldSquare(field);
			imgLbl[1].text = imgLbl[2].text = imgLbl[3].text = '';
		} else {
			imgLbl[0].text = 'Image:';
			imgIn[0].visible = true;
			imgIn[0].text = fieldArrow(field);
			imgLbl[1].text = imgLbl[2].text = imgLbl[3].text = imgLbl[4].text = '';
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

		var blockInput:Bool = PsychUIInputText.focusOn != null;
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
		super.destroy();

		FlxG.sound.muteKeys = [FlxKey.ZERO];
		FlxG.sound.volumeDownKeys = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
		FlxG.sound.volumeUpKeys = [FlxKey.NUMPADPLUS, FlxKey.PLUS];
	}

	var offElemDrop:PsychUIDropDownMenu;
	var offDirDrop:PsychUIDropDownMenu;
	var offX:PsychUINumericStepper;
	var offY:PsychUINumericStepper;

	static final OFF_ELEMS = ['Note', 'Strum', 'Hold'];

	function addOffsetsTab() {
		var t = box.getTab('Offsets').menu;

		label(t, 10, 10, 'Nudge art per direction to center it.', 11);

		label(t, 10, 40, 'Element:');
		offElemDrop = new PsychUIDropDownMenu(75, 36, OFF_ELEMS.copy(), function(id, name) loadOffsetSteppers());
		label(t, 10, 74, 'Direction:');
		offDirDrop = new PsychUIDropDownMenu(85, 70, ['left', 'down', 'up', 'right', 'square'], function(id, name) loadOffsetSteppers());

		label(t, 10, 112, 'X:');
		offX = new PsychUINumericStepper(35, 109, 1, 0, -300, 300, 0, 70);
		offX.onValueChange = function() applyOffsetSteppers();
		t.add(offX);

		label(t, 130, 112, 'Y:');
		offY = new PsychUINumericStepper(155, 109, 1, 0, -300, 300, 0, 70);
		offY.onValueChange = function() applyOffsetSteppers();
		t.add(offY);

		var resetBtn = new PsychUIButton(10, 145, 'Reset this', function() {
			offX.value = 0;
			offY.value = 0;
			applyOffsetSteppers();
		});
		resetBtn.resize(100, 26);
		t.add(resetBtn);

		label(t, 10, 185, 'Offsets are shared across keycounts,', 11);
		label(t, 10, 199, 'keyed by direction.', 11);

		t.add(offElemDrop);
		t.add(offDirDrop);

		offElemDrop.selectedLabel = 'Note';
		offDirDrop.selectedLabel = 'left';
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
		var f:Dynamic = Reflect.field(config, offsetFieldName(offElemDrop.selectedLabel));
		var v:Dynamic = (f == null) ? null : Reflect.field(f, offDirDrop.selectedLabel);
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
		var fn = offsetFieldName(offElemDrop.selectedLabel);
		var f:Dynamic = Reflect.field(config, fn);
		if (f == null) {
			f = {};
			Reflect.setField(config, fn, f);
		}
		Reflect.setField(f, offDirDrop.selectedLabel, [offX.value, offY.value]);
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
			skinDropDown.list = NoteSkinConfig.list();
			skinDropDown.selectedLabel = skinName;
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
