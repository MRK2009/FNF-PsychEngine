package editors;

import backend.StageData;
import backend.PsychCamera;
import objects.Character;
import psychlua.LuaUtils;
import flixel.FlxObject;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.FlxGridOverlay;
import flixel.math.FlxRect;
import flixel.util.FlxDestroyUtil;
import openfl.utils.Assets;
import openfl.display.Sprite;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import psychlua.ModchartSprite;
import flash.net.FileFilter;
import editors.content.Prompt;
import editors.content.PreloadListSubState;
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
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITabs;
import smidr.widgets.UITextInput;

class StageEditorState extends MusicBeatState {
	final minZoom = 0.1;
	final maxZoom = 2;

	var gf:Character;
	var dad:Character;
	var boyfriend:Character;
	var stageJson:StageFile;

	var camGame:FlxCamera;

	public var camHUD:FlxCamera;

	public var uiRoot:UIRoot;

	/** Container for the whole main-state chrome, so the substate/HUD toggle can hide it at once. **/
	public var mainUI:Sprite;

	var stageSprites:Array<StageEditorMetaSprite> = [];

	public function new(stageToLoad:String = 'stage', cachedJson:StageFile = null) {
		lastLoadedStage = stageToLoad;
		stageJson = cachedJson;
		super();
	}

	var lastLoadedStage:String;
	var camFollow:FlxObject = new FlxObject(0, 0, 1, 1);

	var helpBg:FlxSprite;
	var helpTexts:FlxSpriteGroup;
	var posTxt:FlxText;
	var outputTxt:FlxText;

	var animationEditor:StageEditorAnimationSubstate;
	var unsavedProgress:Bool = false;

	var selectionSprites:FlxSpriteGroup = new FlxSpriteGroup();

	override function create() {
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Stage Editor', 'Stage: ' + lastLoadedStage);
		#end

		if (stageJson == null)
			stageJson = StageData.getStageFile(lastLoadedStage);
		FlxG.camera.follow(null, LOCKON, 0);

		loadJsonAssetDirectory();
		gf = new Character(0, 0, stageJson._editorMeta != null ? stageJson._editorMeta.gf : 'gf');
		gf.visible = !(stageJson.hide_girlfriend);
		gf.scrollFactor.set(0.95, 0.95);
		dad = new Character(0, 0, stageJson._editorMeta != null ? stageJson._editorMeta.dad : 'dad');
		boyfriend = new Character(0, 0, stageJson._editorMeta != null ? stageJson._editorMeta.boyfriend : 'bf', true);

		for (i in 0...4) {
			var spr:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.LIME);
			spr.alpha = 0.8;
			selectionSprites.add(spr);
		}

		FlxG.camera.zoom = stageJson.defaultZoom;
		repositionGirlfriend();
		repositionDad();
		repositionBoyfriend();
		var point = focusOnTarget('boyfriend');
		FlxG.camera.scroll.set(point.x - FlxG.width / 2, point.y - FlxG.height / 2);

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		// Stage-attached with viewport auto-sync: the UI tracks window resizes/fullscreen (FlxG.game
		// is only offset by the scale mode, never scaled, so above-game attachment would not scale).
		uiRoot = FlxSmidr.init(false);
		FlxSmidr.autoBlockMouse = true;
		var fpsCounter = Main.fpsVar;
		if (fpsCounter != null && fpsCounter.parent == FlxG.stage)
			FlxG.stage.setChildIndex(uiRoot, FlxG.stage.getChildIndex(fpsCounter));

		mainUI = new Sprite();
		uiRoot.content.addChild(mainUI);

		screenUI();
		spriteCreatePopup();
		editorUI();

		add(camFollow);
		updateSpriteList();

		addHelpScreen();
		FlxG.mouse.visible = true;
		animationEditor = new StageEditorAnimationSubstate();

		super.create();
	}

	function loadJsonAssetDirectory() {
		var directory:String = 'shared';
		var weekDir:String = stageJson.directory;
		if (weekDir != null && weekDir.length > 0 && weekDir != '')
			directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);
	}

	var showSelectionQuad:Bool = true;

	function addHelpScreen() {
		#if FLX_DEBUG
		var btn = 'F3';
		#else
		var btn = 'F2';
		#end

		var str:Array<String> = [
			"E/Q - Camera Zoom In/Out",
			"J/K/L/I - Move Camera",
			"R - Reset Camera Zoom",
			"Arrow Keys/Mouse & Right Click - Move Object",
			"",
			'$btn - Toggle HUD',
			"F12 - Toggle Selection Rectangle",
			"Hold Shift - Move Objects and Camera 4x faster",
			"Hold Control - Move Objects pixel-by-pixel and Camera 4x slower"
		];

		helpBg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		helpBg.scale.set(FlxG.width, FlxG.height);
		helpBg.updateHitbox();
		helpBg.alpha = 0.6;
		helpBg.cameras = [camHUD];
		helpBg.active = helpBg.visible = false;
		add(helpBg);

		helpTexts = new FlxSpriteGroup();
		helpTexts.cameras = [camHUD];
		for (i => txt in str) {
			if (txt.length < 1)
				continue;

			var helpText:FlxText = new FlxText(0, 0, 680, txt, 16);
			helpText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
			helpText.borderColor = FlxColor.BLACK;
			helpText.scrollFactor.set();
			helpText.borderSize = 1;
			helpText.screenCenter();
			add(helpText);
			helpText.y += ((i - str.length / 2) * 32) + 16;
			helpText.active = false;
			helpTexts.add(helpText);
		}
		helpTexts.active = helpTexts.visible = false;
		add(helpTexts);
	}

	function updateSpriteList() {
		for (spr in stageSprites)
			if (spr != null && !StageData.reservedNames.contains(spr.type))
				spr.sprite = FlxDestroyUtil.destroy(spr.sprite);

		stageSprites = [];
		var list:Map<String, FlxSprite> = [];
		if (stageJson.objects != null && stageJson.objects.length > 0) {
			list = StageData.addObjectsToState(stageJson.objects, gf, dad, boyfriend, null, true);
			for (key => spr in list)
				stageSprites[spr.ID] = new StageEditorMetaSprite(stageJson.objects[spr.ID], spr);
		}

		for (character in ['gf', 'dad', 'boyfriend'])
			if (!list.exists(character))
				stageSprites.push(new StageEditorMetaSprite({type: character}, Reflect.field(this, character)));

		updateSpriteListRadio();
	}

	// ---- Sprite list (top-first display order, like the old radio group) ----

	/** Display-order labels (index 0 = topmost row, i.e. the LAST entry of `stageSprites`). **/
	var spriteListLabels:Array<String> = [];

	/** Selected row in display order, `-1` for none (mirrors the old radio group's `checked`). **/
	var spriteListChecked:Int = -1;

	var spriteListPane:UIScrollPane;
	var spriteListButtons:Array<UIButton> = [];

	/** Camera focus target index into `focusTargets`, `-1` for free camera. **/
	var focusChecked:Int = -1;

	final focusTargets:Array<String> = ['dad', 'boyfriend', 'gf'];
	var focusButtons:Array<UIButton> = [];

	var lowQualityFilterCheckbox:UICheckbox;
	var highQualityFilterCheckbox:UICheckbox;

	static inline var PAD:Int = 10;
	static inline var LIST_W:Int = 250;
	static inline var BOX_W:Int = 275;

	function screenUI() {
		function visibilityFilterUpdate() {
			curFilters = 0;
			if (lowQualityFilterCheckbox.checked)
				curFilters |= LOW_QUALITY;
			if (highQualityFilterCheckbox.checked)
				curFilters |= HIGH_QUALITY;
		}

		// Sprite List panel + the action buttons docked at its right edge.
		var listX:Float = 25;
		var listY:Float = 40;
		var listH:Float = 330;

		var listPanel:UIPanel = new UIPanel(LIST_W, listH, UITheme.panel);
		listPanel.x = listX;
		listPanel.y = listY;
		mainUI.addChild(listPanel);

		var listHeader:UILabel = new UILabel('Sprite List', 14, 0);
		listHeader.x = listX + PAD;
		listHeader.y = listY + 8;
		mainUI.addChild(listHeader);

		spriteListPane = new UIScrollPane(LIST_W - PAD * 2, listH - 40);
		spriteListPane.x = listX + PAD;
		spriteListPane.y = listY + 30;
		mainUI.addChild(spriteListPane);

		var buttonX:Float = listX + LIST_W + 10;
		var buttonY:Float = listY;
		function listButton(label:String, onClick:Void->Void):UIButton {
			var btn:UIButton = new UIButton(label, 100, 26, onClick);
			btn.x = buttonX;
			btn.y = buttonY;
			mainUI.addChild(btn);
			buttonY += 30;
			return btn;
		}

		listButton('Move Up', function() {
			var selected:Int = spriteListChecked;
			if (selected < 0)
				return;

			var selected:Int = spriteListLabels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null)
				return;

			var newSel:Int = Std.int(Math.min(stageSprites.length - 1, selected + 1));
			stageSprites.remove(spr);
			stageSprites.insert(newSel, spr);

			updateSpriteListRadio();
		});

		listButton('Move Down', function() {
			var selected:Int = spriteListChecked;
			if (selected < 0)
				return;

			var selected:Int = spriteListLabels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null)
				return;

			var newSel:Int = Std.int(Math.max(0, selected - 1));
			stageSprites.remove(spr);
			stageSprites.insert(newSel, spr);

			updateSpriteListRadio();
		});

		var createBtn:UIButton = listButton('New', function() setCreatePopupVisible(true));
		createBtn.accent = true;

		listButton('Duplicate', function() {
			var selected:Int = spriteListChecked;
			if (selected < 0)
				return;

			var selected:Int = spriteListLabels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null || StageData.reservedNames.contains(spr.type))
				return;

			var copiedSpr = new ModchartSprite();
			var copiedMeta:StageEditorMetaSprite = new StageEditorMetaSprite(null, copiedSpr);
			for (field in Reflect.fields(spr)) {
				if (field == 'sprite')
					continue; // do NOT copy sprite or it might get messy

				try {
					var fld:Dynamic = Reflect.getProperty(spr, field);
					if (fld is Array) {
						var arr:Array<Dynamic> = fld;
						arr = arr.copy();
						if (arr != null) {
							for (k => v in arr) {
								var indices:Array<Int> = v.indices;
								if (indices != null)
									indices = indices.copy();

								var offs:Array<Int> = v.offsets;
								if (offs != null)
									offs = offs.copy();

								fld[k] = {
									anim: v.anim,
									name: v.name,
									fps: v.fps,
									loop: v.loop,
									indices: indices,
									offsets: offs
								}
							}
						}
						fld = arr;
					}

					Reflect.setProperty(copiedMeta, field, fld);
				} catch (e:Dynamic) {}
			}

			if (copiedMeta.animations != null) {
				for (num => anim in copiedMeta.animations) {
					if (anim == null || anim.anim == null)
						continue;

					if (anim.indices != null && anim.indices.length > 0)
						copiedSpr.animation.addByIndices(anim.anim, anim.name, anim.indices, '', anim.fps, anim.loop);
					else
						copiedSpr.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);

					if (anim.offsets != null && anim.offsets.length > 1)
						copiedSpr.addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);

					if (copiedSpr.animation.curAnim == null || copiedMeta.firstAnimation == anim.anim)
						copiedSpr.playAnim(anim.anim, true);
				}
			}
			copiedMeta.setScale(copiedMeta.scale[0], copiedMeta.scale[1]);
			copiedMeta.setScrollFactor(copiedMeta.scroll[0], copiedMeta.scroll[1]);
			copiedMeta.name = findUnoccupiedName('${copiedMeta.name}_copy');
			insertMeta(copiedMeta, 1);
		});

		var deleteBtn:UIButton = listButton('Delete', function() {
			var selected:Int = spriteListChecked;
			if (selected < 0)
				return;

			var selected:Int = spriteListLabels.length - selected - 1;
			var spr = stageSprites[selected];
			if (spr == null || StageData.reservedNames.contains(spr.type))
				return;

			stageSprites.remove(spr);
			spr.sprite = FlxDestroyUtil.destroy(spr.sprite);

			updateSpriteListRadio();
		});
		deleteBtn.danger = true;

		var bg:FlxSprite = new FlxSprite(0, FlxG.height - 60).makeGraphic(1, 1, FlxColor.BLACK);
		bg.cameras = [camHUD];
		bg.alpha = 0.4;
		bg.scale.set(FlxG.width, FlxG.height - bg.y);
		bg.updateHitbox();
		add(bg);

		var tipText:FlxText = new FlxText(0, FlxG.height - 44, 300, 'Press F1 for Help', 20);
		tipText.alignment = CENTER;
		tipText.cameras = [camHUD];
		tipText.scrollFactor.set();
		tipText.screenCenter(X);
		tipText.active = false;
		add(tipText);

		var targetTxt:FlxText = new FlxText(30, FlxG.height - 56, 300, 'Camera Target', 16);
		targetTxt.alignment = LEFT;
		targetTxt.cameras = [camHUD];
		targetTxt.scrollFactor.set();
		targetTxt.active = false;
		add(targetTxt);

		// Camera-focus toggle buttons (was a horizontal radio group).
		var focusLabels:Array<String> = ['Opponent', 'Boyfriend', 'Girlfriend'];
		focusButtons = [];
		for (i in 0...focusTargets.length) {
			var idx:Int = i;
			var btn:UIButton = new UIButton(focusLabels[i], 100, 22, function() setFocus(idx));
			btn.fontSize = 11;
			btn.x = 160 + i * 106;
			btn.y = FlxG.height - 30;
			mainUI.addChild(btn);
			focusButtons.push(btn);
		}

		lowQualityFilterCheckbox = new UICheckbox('Can see Low Quality Sprites?', 230, false, function(_) {
			visibilityFilterUpdate();
			unsavedProgress = true;
		});
		lowQualityFilterCheckbox.fontSize = 11;
		lowQualityFilterCheckbox.x = FlxG.width - 480;
		lowQualityFilterCheckbox.y = FlxG.height - 30;
		mainUI.addChild(lowQualityFilterCheckbox);

		highQualityFilterCheckbox = new UICheckbox('Can see High Quality Sprites?', 230, true, function(_) {
			visibilityFilterUpdate();
			unsavedProgress = true;
		});
		highQualityFilterCheckbox.fontSize = 11;
		highQualityFilterCheckbox.x = FlxG.width - 240;
		highQualityFilterCheckbox.y = FlxG.height - 30;
		mainUI.addChild(highQualityFilterCheckbox);
		visibilityFilterUpdate();

		posTxt = new FlxText(0, 50, 500, 'X: 0\nY: 0', 24);
		posTxt.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		posTxt.borderSize = 2;
		posTxt.cameras = [camHUD];
		posTxt.screenCenter(X);
		posTxt.visible = false;
		add(posTxt);

		outputTxt = new FlxText(0, 0, 800, '', 24);
		outputTxt.alignment = CENTER;
		outputTxt.borderStyle = OUTLINE_FAST;
		outputTxt.borderSize = 1;
		outputTxt.cameras = [camHUD];
		outputTxt.screenCenter();
		outputTxt.alpha = 0;
		add(outputTxt);
	}

	/** Sets (or clears with `-1`) the camera focus target, mirroring the old radio group. **/
	function setFocus(idx:Int):Void {
		focusChecked = idx;
		for (n in 0...focusButtons.length)
			focusButtons[n].accent = (n == idx);
		if (idx > -1) {
			var point = focusOnTarget(focusTargets[idx]);
			camFollow.setPosition(point.x, point.y);
			FlxG.camera.target = camFollow;
		}
	}

	/** Selects a sprite row (display order) and refreshes the list highlight + Object tab. **/
	function selectSpriteRow(idx:Int, refreshUI:Bool = true):Void {
		spriteListChecked = idx;
		for (n in 0...spriteListButtons.length)
			spriteListButtons[n].accent = (n == idx);
		if (refreshUI) {
			checkUIOnObject();
			updateSelectedUI();
		}
	}

	function showOutput(txt:String, isError:Bool = false) {
		outputTxt.color = isError ? FlxColor.RED : FlxColor.WHITE;
		outputTxt.text = txt;
		outputTime = 3;

		if (isError)
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
		else
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	var createPopupUI:Sprite;
	var createPopupVisible:Bool = false;

	function setCreatePopupVisible(v:Bool):Void {
		createPopupVisible = v;
		if (createPopupUI != null)
			createPopupUI.visible = v;
	}

	function findUnoccupiedName(prefix = 'sprite') {
		var num:Int = 1;
		var name:String = 'unnamed';
		while (true) {
			var cantUseName:Bool = false;

			name = prefix + num;
			for (basic in stageSprites) {
				if (basic.name == name) {
					cantUseName = true;
					break;
				}
			}

			if (cantUseName) {
				num++;
				continue;
			}
			break;
		}
		return name;
	}

	function insertMeta(meta, insertOffset:Int = 0) {
		var num:Int = Std.int(Math.max(0, Math.min(spriteListLabels.length, spriteListLabels.length - spriteListChecked - 1 + insertOffset)));
		stageSprites.insert(num, meta);
		updateSpriteListRadio();
		setCreatePopupVisible(false);
		selectSpriteRow(spriteListLabels.length - num - 1, false);
		updateSelectedUI();
		unsavedProgress = true;
	}

	function spriteCreatePopup() {
		createPopupUI = new Sprite();
		uiRoot.content.addChild(createPopupUI);

		var w:Float = 300;
		var h:Float = 220;
		var px:Float = (FlxG.width - w) / 2;
		var py:Float = (FlxG.height - h) / 2;

		var panel:UIPanel = new UIPanel(w, h, UITheme.panel2);
		panel.x = px;
		panel.y = py;
		createPopupUI.addChild(panel);

		var txt:UILabel = new UILabel('New Sprite', 20, 0);
		txt.render();
		txt.x = px + (w - txt.width) / 2;
		txt.y = py + 14;
		createPopupUI.addChild(txt);

		var btnY:Float = py + 56;
		for (def in [
			{label: 'No Animation', cb: function() loadImage('sprite')},
			{label: 'Animated', cb: function() loadImage('animatedSprite')},
			{
				label: 'Solid Color',
				cb: function() {
					var meta:StageEditorMetaSprite = new StageEditorMetaSprite({type: 'square', scale: [200, 200], name: findUnoccupiedName()},
						new ModchartSprite());
					meta.sprite.makeGraphic(1, 1, FlxColor.WHITE);
					meta.sprite.scale.set(200, 200);
					meta.sprite.updateHitbox();
					meta.sprite.screenCenter();
					insertMeta(meta);
				}
			}
		]) {
			var btn:UIButton = new UIButton(def.label, 200, 30, def.cb);
			btn.x = px + (w - 200) / 2;
			btn.y = btnY;
			createPopupUI.addChild(btn);
			btnY += 44;
		}

		createPopupUI.visible = false;
	}

	function updateSpriteListRadio() {
		var _sel:String = (spriteListChecked >= 0 && spriteListChecked < spriteListLabels.length) ? spriteListLabels[spriteListChecked] : null;
		var nameList:Array<String> = [];
		for (spr in stageSprites) {
			if (spr == null)
				continue;

			switch (spr.type) {
				case 'gf':
					nameList.push('- Girlfriend -');
				case 'boyfriend':
					nameList.push('- Boyfriend -');
				case 'dad':
					nameList.push('- Opponent -');
				default:
					nameList.push(spr.name);
			}
		}
		nameList.reverse();

		spriteListLabels = nameList;
		spriteListChecked = (_sel != null) ? nameList.indexOf(_sel) : -1;
		rebuildSpriteListButtons();
	}

	function rebuildSpriteListButtons():Void {
		var i:Int = spriteListPane.content.numChildren;
		while (--i >= 0) {
			var c = spriteListPane.content.getChildAt(i);
			if (c is smidr.UIComponent)
				(cast c : smidr.UIComponent).dispose();
		}
		spriteListPane.content.removeChildren();

		spriteListButtons = [];
		var rowW:Float = spriteListPane.w - PAD - 12;
		var y:Float = 2;
		for (n in 0...spriteListLabels.length) {
			var idx:Int = n;
			var btn:UIButton = new UIButton(spriteListLabels[n], rowW, 24, function() selectSpriteRow(idx));
			btn.fontSize = 11;
			btn.accent = (n == spriteListChecked);
			btn.y = y;
			spriteListPane.content.addChild(btn);
			spriteListButtons.push(btn);
			y += 27;
		}
		spriteListPane.refreshContent(y + 2);
	}

	function editorUI() {
		addStageTab();

		boxTabs = new UITabs(BOX_W, [{label: 'Meta'}, {label: 'Data'}, {label: 'Object'}], function(i:Int):Void {
			for (n in 0...boxPanes.length)
				boxPanes[n].visible = (n == i);
			curTabName = ['Meta', 'Data', 'Object'][i];
			if (curTabName == 'Object')
				checkUIOnObject();
		});

		var boxX:Float = FlxG.width - BOX_W - 10;
		var boxY:Float = 140;
		var paneH:Float = 400;
		var boxH:Float = boxTabs.h + 8 + paneH + PAD;

		var panel:UIPanel = new UIPanel(BOX_W, boxH, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		mainUI.addChild(panel);

		boxTabs.x = boxX;
		boxTabs.y = boxY;
		mainUI.addChild(boxTabs);

		boxPanes = [];
		for (i in 0...3) {
			var pane:UIScrollPane = new UIScrollPane(BOX_W - PAD * 2, paneH);
			pane.x = boxX + PAD;
			pane.y = boxY + boxTabs.h + 8;
			pane.visible = false;
			mainUI.addChild(pane);
			boxPanes.push(pane);
		}

		addMetaTab(boxPanes[0]);
		addDataTab(boxPanes[1]);
		addObjectTab(boxPanes[2]);

		selectTabByName('Data');
	}

	var boxTabs:UITabs;
	var boxPanes:Array<UIScrollPane> = [];
	var curTabName:String = 'Data';

	function selectTabByName(name:String):Void {
		var idx:Int = ['Meta', 'Data', 'Object'].indexOf(name);
		if (idx < 0)
			return;
		boxTabs.select(idx);
		for (n in 0...boxPanes.length)
			boxPanes[n].visible = (n == idx);
		curTabName = name;
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

	var directoryDropDown:UIDropdown;
	var directoryList:Array<String> = [];
	var uiInputText:UITextInput;
	var hideGirlfriendCheckbox:UICheckbox;
	var zoomStepper:UIStepper;
	var cameraSpeedStepper:UIStepper;
	var camDadStepperX:UIStepper;
	var camDadStepperY:UIStepper;
	var camGfStepperX:UIStepper;
	var camGfStepperY:UIStepper;
	var camBfStepperX:UIStepper;
	var camBfStepperY:UIStepper;

	function addDataTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		directoryList = [''];
		#if sys
		for (folder in FileSystem.readDirectory('assets/'))
			if (FileSystem.isDirectory('assets/$folder') && folder != 'shared' && !Mods.ignoreModFolders.contains(folder))
				directoryList.push(folder);
		#end

		directoryDropDown = new UIDropdown('Compiled Assets:', rowW, function(sel:Int, selected:String) {
			stageJson.directory = selected;
			saveObjectsToJson();
			FlxTransitionableState.skipNextTransIn = FlxTransitionableState.skipNextTransOut = true;
			MusicBeatState.switchState(new StageEditorState(lastLoadedStage, stageJson));
		});
		directoryDropDown.setItems(directoryList.copy());
		directoryDropDown.select(Std.int(Math.max(0, directoryList.indexOf(stageJson.directory))));
		pane.content.addChild(directoryDropDown);

		uiInputText = new UITextInput('UI Style:', rowW, stageJson.stageUI != null ? stageJson.stageUI : '', function(v:String) {
			stageJson.stageUI = v;
			unsavedProgress = true;
		});
		uiInputText.y = 32;
		pane.content.addChild(uiInputText);

		hideGirlfriendCheckbox = new UICheckbox('Hide Girlfriend?', rowW, !gf.visible, function(checked:Bool) {
			stageJson.hide_girlfriend = checked;
			gf.visible = !checked;
			if (focusChecked > -1) {
				var point = focusOnTarget(focusTargets[focusChecked]);
				camFollow.setPosition(point.x, point.y);
			}
			unsavedProgress = true;
		});
		hideGirlfriendCheckbox.y = 64;
		pane.content.addChild(hideGirlfriendCheckbox);

		paneLabel(pane, 0, 98, 'Camera Offsets:', 12);

		var cx:Float = 0;
		var cy:Float = 0;
		if (stageJson.camera_opponent != null && stageJson.camera_opponent.length > 1) {
			cx = stageJson.camera_opponent[0];
			cy = stageJson.camera_opponent[1];
		}
		var camDadChanged = function(_) {
			if (stageJson.camera_opponent == null)
				stageJson.camera_opponent = [0, 0];
			stageJson.camera_opponent[0] = camDadStepperX.value;
			stageJson.camera_opponent[1] = camDadStepperY.value;
			_updateCamera();
			unsavedProgress = true;
		};
		camDadStepperX = new UIStepper('Opp X:', halfW, cx, 50, camDadChanged);
		camDadStepperX.min = -10000;
		camDadStepperX.max = 10000;
		camDadStepperX.y = 118;
		pane.content.addChild(camDadStepperX);
		camDadStepperY = new UIStepper('Y:', halfW, cy, 50, camDadChanged);
		camDadStepperY.min = -10000;
		camDadStepperY.max = 10000;
		camDadStepperY.x = halfW + 10;
		camDadStepperY.y = 118;
		pane.content.addChild(camDadStepperY);

		var cx:Float = 0;
		var cy:Float = 0;
		if (stageJson.camera_girlfriend != null && stageJson.camera_girlfriend.length > 1) {
			cx = stageJson.camera_girlfriend[0];
			cy = stageJson.camera_girlfriend[1];
		}
		var camGfChanged = function(_) {
			if (stageJson.camera_girlfriend == null)
				stageJson.camera_girlfriend = [0, 0];
			stageJson.camera_girlfriend[0] = camGfStepperX.value;
			stageJson.camera_girlfriend[1] = camGfStepperY.value;
			_updateCamera();
			unsavedProgress = true;
		};
		camGfStepperX = new UIStepper('GF X:', halfW, cx, 50, camGfChanged);
		camGfStepperX.min = -10000;
		camGfStepperX.max = 10000;
		camGfStepperX.y = 150;
		pane.content.addChild(camGfStepperX);
		camGfStepperY = new UIStepper('Y:', halfW, cy, 50, camGfChanged);
		camGfStepperY.min = -10000;
		camGfStepperY.max = 10000;
		camGfStepperY.x = halfW + 10;
		camGfStepperY.y = 150;
		pane.content.addChild(camGfStepperY);

		var cx:Float = 0;
		var cy:Float = 0;
		if (stageJson.camera_boyfriend != null && stageJson.camera_boyfriend.length > 1) {
			cx = stageJson.camera_boyfriend[0];
			cy = stageJson.camera_boyfriend[1];
		}
		var camBfChanged = function(_) {
			if (stageJson.camera_boyfriend == null)
				stageJson.camera_boyfriend = [0, 0];
			stageJson.camera_boyfriend[0] = camBfStepperX.value;
			stageJson.camera_boyfriend[1] = camBfStepperY.value;
			_updateCamera();
			unsavedProgress = true;
		};
		camBfStepperX = new UIStepper('BF X:', halfW, cx, 50, camBfChanged);
		camBfStepperX.min = -10000;
		camBfStepperX.max = 10000;
		camBfStepperX.y = 182;
		pane.content.addChild(camBfStepperX);
		camBfStepperY = new UIStepper('Y:', halfW, cy, 50, camBfChanged);
		camBfStepperY.min = -10000;
		camBfStepperY.max = 10000;
		camBfStepperY.x = halfW + 10;
		camBfStepperY.y = 182;
		pane.content.addChild(camBfStepperY);

		paneLabel(pane, 0, 216, 'Camera Data:', 12);

		zoomStepper = new UIStepper('Zoom:', halfW, stageJson.defaultZoom, 0.05, function(v:Float) {
			stageJson.defaultZoom = v;
			FlxG.camera.zoom = stageJson.defaultZoom;
			unsavedProgress = true;
		});
		zoomStepper.min = minZoom;
		zoomStepper.max = maxZoom;
		zoomStepper.decimals = 2;
		zoomStepper.y = 236;
		pane.content.addChild(zoomStepper);

		cameraSpeedStepper = new UIStepper('Speed:', halfW, stageJson.camera_speed != null ? stageJson.camera_speed : 1, 0.1, function(v:Float) {
			stageJson.camera_speed = v;
			FlxG.camera.followLerp = 0.04 * stageJson.camera_speed;
			unsavedProgress = true;
		});
		cameraSpeedStepper.min = 0;
		cameraSpeedStepper.max = 10;
		cameraSpeedStepper.decimals = 2;
		cameraSpeedStepper.x = halfW + 10;
		cameraSpeedStepper.y = 236;
		pane.content.addChild(cameraSpeedStepper);
		FlxG.camera.followLerp = 0.04 * cameraSpeedStepper.value;

		var saveButton:UIButton = new UIButton('Save', rowW, 30, function() {
			saveData();
		}, true);
		saveButton.y = 276;
		pane.content.addChild(saveButton);

		pane.refreshContent(316);
	}

	function _updateCamera() {
		if (focusChecked > -1) {
			var point = focusOnTarget(focusTargets[focusChecked]);
			camFollow.setPosition(point.x, point.y);
		}
	}

	var colorInputText:UITextInput;
	var nameInputText:UITextInput;
	var imgTxt:UILabel;

	var scaleStepperX:UIStepper;
	var scaleStepperY:UIStepper;
	var scrollStepperX:UIStepper;
	var scrollStepperY:UIStepper;
	var angleStepper:UIStepper;
	var alphaStepper:UIStepper;

	var antialiasingCheckbox:UICheckbox;
	var flipXCheckBox:UICheckbox;
	var flipYCheckBox:UICheckbox;
	var lowQualityCheckbox:UICheckbox;
	var highQualityCheckbox:UICheckbox;

	function getSelected(blockReserved:Bool = true) {
		var selected:Int = spriteListChecked;
		if (selected >= 0) {
			var spr = stageSprites[spriteListLabels.length - selected - 1];
			if (spr != null && (!blockReserved || !StageData.reservedNames.contains(spr.type)))
				return spr;
		}
		return null;
	}

	function addObjectTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		nameInputText = new UITextInput('Name (Lua/HScript):', rowW, '', function(v:String) {
			// change name
			var selected = getSelected();
			if (selected != null) {
				var changedName:String = v;
				if (changedName.length < 1) {
					showOutput('Sprite name cannot be empty!', true);
					return;
				}

				if (StageData.reservedNames.contains(changedName)) {
					showOutput('To avoid conflicts, this name cannot be used!', true);
					return;
				}

				for (basic in stageSprites) {
					if (selected != basic && basic.name == changedName) {
						showOutput('Name "$changedName" is already in use!', true);
						return;
					}
				}

				selected.name = changedName;
				if (spriteListChecked >= 0 && spriteListChecked < spriteListLabels.length) {
					spriteListLabels[spriteListChecked] = changedName;
					if (spriteListButtons[spriteListChecked] != null)
						spriteListButtons[spriteListChecked].label = changedName;
				}
				outputTime = 0;
				outputTxt.alpha = 0;
				unsavedProgress = true;
			}
		});
		nameInputText.filter = function(charCode:Int):Bool {
			// letters, digits, underscore and dash only (matches the old input filter)
			return (charCode >= '0'.code && charCode <= '9'.code) || (charCode >= 'A'.code && charCode <= 'Z'.code)
				|| (charCode >= 'a'.code && charCode <= 'z'.code) || charCode == '_'.code || charCode == '-'.code;
		};
		pane.content.addChild(nameInputText);

		imgTxt = paneLabel(pane, 0, 34, 'Image: ');

		var imgButton:UIButton = new UIButton('Change Image', halfW, 26, function() {
			trace('attempt to load image');
			loadImage();
		});
		imgButton.y = 52;
		pane.content.addChild(imgButton);

		var animationsButton:UIButton = new UIButton('Animations', halfW, 26, function() {
			var selected = getSelected();
			if (selected == null)
				return;

			if (selected.type != 'animatedSprite') {
				showOutput('Only Animated Sprites can hold Animation data.', true);
				return;
			}

			destroySubStates = false;
			persistentDraw = false;
			animationEditor.target = selected;
			unsavedProgress = true;
			mainUI.visible = false;
			openSubState(animationEditor);
		});
		animationsButton.x = halfW + 10;
		animationsButton.y = 52;
		pane.content.addChild(animationsButton);

		colorInputText = new UITextInput('Color:', rowW, 'FFFFFF', function(v:String) {
			// change color
			var selected = getSelected();
			if (selected != null)
				selected.color = v;
			unsavedProgress = true;
		});
		colorInputText.y = 88;
		pane.content.addChild(colorInputText);

		function updateScale(_) {
			// scale
			var selected = getSelected();
			if (selected != null)
				selected.setScale(scaleStepperX.value, scaleStepperY.value);
			unsavedProgress = true;
		}

		paneLabel(pane, 0, 122, 'Scale (X/Y):');
		scaleStepperX = new UIStepper('X:', halfW, 1, 0.05, updateScale);
		scaleStepperX.min = 0.05;
		scaleStepperX.max = 10;
		scaleStepperX.decimals = 2;
		scaleStepperX.y = 140;
		pane.content.addChild(scaleStepperX);
		scaleStepperY = new UIStepper('Y:', halfW, 1, 0.05, updateScale);
		scaleStepperY.min = 0.05;
		scaleStepperY.max = 10;
		scaleStepperY.decimals = 2;
		scaleStepperY.x = halfW + 10;
		scaleStepperY.y = 140;
		pane.content.addChild(scaleStepperY);

		function updateScroll(_) {
			// scroll factor
			var selected = getSelected();
			if (selected != null)
				selected.setScrollFactor(scrollStepperX.value, scrollStepperY.value);
			unsavedProgress = true;
		}

		paneLabel(pane, 0, 172, 'Scroll Factor (X/Y):');
		scrollStepperX = new UIStepper('X:', halfW, 1, 0.05, updateScroll);
		scrollStepperX.min = 0;
		scrollStepperX.max = 10;
		scrollStepperX.decimals = 2;
		scrollStepperX.y = 190;
		pane.content.addChild(scrollStepperX);
		scrollStepperY = new UIStepper('Y:', halfW, 1, 0.05, updateScroll);
		scrollStepperY.min = 0;
		scrollStepperY.max = 10;
		scrollStepperY.decimals = 2;
		scrollStepperY.x = halfW + 10;
		scrollStepperY.y = 190;
		pane.content.addChild(scrollStepperY);

		alphaStepper = new UIStepper('Opacity:', halfW, 1, 0.1, function(v:Float) {
			// alpha/opacity
			var selected = getSelected();
			if (selected != null)
				selected.alpha = v;
			unsavedProgress = true;
		});
		alphaStepper.min = 0;
		alphaStepper.max = 1;
		alphaStepper.decimals = 2;
		alphaStepper.y = 224;
		pane.content.addChild(alphaStepper);

		antialiasingCheckbox = new UICheckbox('Anti-Aliasing', halfW, false, function(checked:Bool) {
			// antialiasing
			var selected = getSelected();
			if (selected != null) {
				if (selected.type != 'square')
					selected.antialiasing = checked;
				else {
					antialiasingCheckbox.checked = false;
					selected.antialiasing = false;
				}
			}
			unsavedProgress = true;
		});
		antialiasingCheckbox.x = halfW + 10;
		antialiasingCheckbox.y = 224;
		pane.content.addChild(antialiasingCheckbox);

		angleStepper = new UIStepper('Angle:', halfW, 0, 10, function(v:Float) {
			var selected = getSelected();
			if (selected != null)
				selected.angle = v;
			unsavedProgress = true;
		});
		angleStepper.min = 0;
		angleStepper.max = 360;
		angleStepper.y = 256;
		pane.content.addChild(angleStepper);

		function updateFlip(_) {
			// flip X and flip Y
			var selected = getSelected();
			if (selected != null) {
				if (selected.type != 'square') {
					selected.flipX = flipXCheckBox.checked;
					selected.flipY = flipYCheckBox.checked;
				} else {
					flipXCheckBox.checked = flipYCheckBox.checked = false;
					selected.flipX = selected.flipY = false;
				}
			}
			unsavedProgress = true;
		}

		flipXCheckBox = new UICheckbox('Flip X', halfW, false, updateFlip);
		flipXCheckBox.y = 288;
		pane.content.addChild(flipXCheckBox);
		flipYCheckBox = new UICheckbox('Flip Y', halfW, false, updateFlip);
		flipYCheckBox.x = halfW + 10;
		flipYCheckBox.y = 288;
		pane.content.addChild(flipYCheckBox);

		function recalcFilter(_) {
			// low and/or high quality
			var selected = getSelected();
			if (selected != null) {
				var filt = 0;
				if (lowQualityCheckbox.checked)
					filt |= LOW_QUALITY;
				if (highQualityCheckbox.checked)
					filt |= HIGH_QUALITY;
				selected.filters = filt;
			}
			unsavedProgress = true;
		};
		paneLabel(pane, 0, 322, 'Visible in:');
		lowQualityCheckbox = new UICheckbox('Low Quality', halfW, false, recalcFilter);
		lowQualityCheckbox.y = 340;
		pane.content.addChild(lowQualityCheckbox);
		highQualityCheckbox = new UICheckbox('High Quality', halfW, false, recalcFilter);
		highQualityCheckbox.x = halfW + 10;
		highQualityCheckbox.y = 340;
		pane.content.addChild(highQualityCheckbox);

		pane.refreshContent(374);
	}

	var oppDropdown:UIDropdown;
	var gfDropdown:UIDropdown;
	var plDropdown:UIDropdown;
	var characterList:Array<String> = [];

	function addMetaTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);

		characterList = Mods.mergeAllTextsNamed('data/characterList.txt');
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'characters/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
				if (file.toLowerCase().endsWith('.json')) {
					var charToCheck:String = file.substr(0, file.length - 5);
					if (!characterList.contains(charToCheck))
						characterList.push(charToCheck);
				}

		if (characterList.length < 1)
			characterList.push(''); // Prevents crash

		var openPreloadButton:UIButton = new UIButton('Preload List', rowW, 28, function() {
			var lockedList:Array<String> = [];
			var currentMap:Map<String, LoadFilters> = [];
			for (spr in stageSprites) {
				if (spr == null || StageData.reservedNames.contains(spr.type))
					continue;

				switch (spr.type) {
					case 'sprite', 'animatedSprite':
						if (spr.image != null && spr.image.length > 0 && !lockedList.contains(spr.image))
							lockedList.push(spr.image);
				}
			}

			if (stageJson.preload != null) {
				for (field in Reflect.fields(stageJson.preload)) {
					if (!currentMap.exists(field) && !lockedList.contains(field))
						currentMap.set(field, Reflect.field(stageJson.preload, field));
				}
			}

			destroySubStates = true;
			openSubState(new PreloadListSubState(function(newSave:Map<String, LoadFilters>) {
				var len:Int = 0;
				for (name in newSave.keys())
					len++;

				stageJson.preload = {};
				for (key => value in newSave) {
					Reflect.setField(stageJson.preload, key, value);
				}
				unsavedProgress = true;
				showOutput('Saved new Preload List with $len files/folders!');
			}, lockedList, currentMap));
		});
		pane.content.addChild(openPreloadButton);

		function setMetaData(data:String, char:String) {
			if (stageJson._editorMeta == null)
				stageJson._editorMeta = {dad: 'dad', gf: 'gf', boyfriend: 'bf'};
			Reflect.setField(stageJson._editorMeta, data, char);
		}

		plDropdown = new UIDropdown('Player:', rowW, function(sel:Int, selected:String) {
			if (selected == null || selected.length < 1)
				return;
			boyfriend.changeCharacter(selected);
			setMetaData('boyfriend', selected);
			repositionBoyfriend();
			unsavedProgress = true;
		});
		plDropdown.setItems(characterList.copy());
		plDropdown.select(Std.int(Math.max(0, characterList.indexOf(boyfriend.curCharacter))));
		plDropdown.y = 44;
		pane.content.addChild(plDropdown);

		gfDropdown = new UIDropdown('Girlfriend:', rowW, function(sel:Int, selected:String) {
			if (selected == null || selected.length < 1)
				return;
			gf.changeCharacter(selected);
			setMetaData('gf', selected);
			repositionGirlfriend();
			unsavedProgress = true;
		});
		gfDropdown.setItems(characterList.copy());
		gfDropdown.select(Std.int(Math.max(0, characterList.indexOf(gf.curCharacter))));
		gfDropdown.y = 80;
		pane.content.addChild(gfDropdown);

		oppDropdown = new UIDropdown('Opponent:', rowW, function(sel:Int, selected:String) {
			if (selected == null || selected.length < 1)
				return;
			dad.changeCharacter(selected);
			setMetaData('dad', selected);
			repositionDad();
			unsavedProgress = true;
		});
		oppDropdown.setItems(characterList.copy());
		oppDropdown.select(Std.int(Math.max(0, characterList.indexOf(dad.curCharacter))));
		oppDropdown.y = 116;
		pane.content.addChild(oppDropdown);

		pane.refreshContent(152);
	}

	var stageDropDown:UIDropdown;
	var stageList:Array<String> = [];

	function addStageTab() {
		var stageX:Float = FlxG.width - BOX_W - 10;
		var stageY:Float = 10;
		var stageH:Float = 120;
		var rowW:Float = BOX_W - PAD * 2;
		var halfW:Float = (rowW - 10) / 2;

		var panel:UIPanel = new UIPanel(BOX_W, stageH, UITheme.panel);
		panel.x = stageX;
		panel.y = stageY;
		mainUI.addChild(panel);

		var header:UILabel = new UILabel('Stage', 14, 0);
		header.x = stageX + PAD;
		header.y = stageY + 8;
		mainUI.addChild(header);

		stageDropDown = new UIDropdown('Stage:', rowW, function(sel:Int, selected:String) {
			var characterPath:String = 'stages/$selected.json';
			var path:String = Paths.getPath(characterPath, TEXT, null, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(path))
			#else
			if (Assets.exists(path))
			#end
			{
				stageJson = StageData.getStageFile(selected);
				lastLoadedStage = selected;
				#if DISCORD_ALLOWED
				DiscordClient.changePresence('Stage Editor', 'Stage: ' + lastLoadedStage);
				#end
				updateSpriteList();
				updateStageDataUI();
				reloadCharacters();
				reloadStageDropDown();
			}
		else {
			FlxG.sound.play(Paths.sound('cancelMenu'));
			reloadStageDropDown();
		}
		});
		stageDropDown.x = stageX + PAD;
		stageDropDown.y = stageY + 30;
		mainUI.addChild(stageDropDown);

		var reloadStage:UIButton = new UIButton('Reload', halfW, 26, function() {
			#if DISCORD_ALLOWED
			DiscordClient.changePresence('Stage Editor', 'Stage: ' + lastLoadedStage);
			#end

			stageJson = StageData.getStageFile(lastLoadedStage);
			updateSpriteList();
			updateStageDataUI();
			reloadCharacters();
			reloadStageDropDown();
		});
		reloadStage.x = stageX + PAD;
		reloadStage.y = stageY + 64;
		mainUI.addChild(reloadStage);

		var dummyStage:UIButton = new UIButton('Load Template', halfW, 26, function() {
			#if DISCORD_ALLOWED
			DiscordClient.changePresence('Stage Editor', 'New Stage');
			#end

			stageJson = StageData.dummy();
			updateSpriteList();
			updateStageDataUI();
			reloadCharacters();
		});
		dummyStage.danger = true;
		dummyStage.x = stageX + PAD + halfW + 10;
		dummyStage.y = stageY + 64;
		mainUI.addChild(dummyStage);

		reloadStageDropDown();
	}

	function updateStageDataUI() {
		// input texts
		uiInputText.text = (stageJson.stageUI != null ? stageJson.stageUI : '');
		// checkboxes
		hideGirlfriendCheckbox.checked = (stageJson.hide_girlfriend);
		gf.visible = !hideGirlfriendCheckbox.checked;
		// steppers
		zoomStepper.value = FlxG.camera.zoom = stageJson.defaultZoom;

		if (stageJson.camera_speed != null)
			cameraSpeedStepper.value = stageJson.camera_speed;
		else
			cameraSpeedStepper.value = 1;
		FlxG.camera.followLerp = 0.04 * cameraSpeedStepper.value;

		if (stageJson.camera_opponent != null && stageJson.camera_opponent.length > 1) {
			camDadStepperX.value = stageJson.camera_opponent[0];
			camDadStepperY.value = stageJson.camera_opponent[1];
		} else
			camDadStepperX.value = camDadStepperY.value = 0;

		if (stageJson.camera_girlfriend != null && stageJson.camera_girlfriend.length > 1) {
			camGfStepperX.value = stageJson.camera_girlfriend[0];
			camGfStepperY.value = stageJson.camera_girlfriend[1];
		} else
			camGfStepperX.value = camGfStepperY.value = 0;

		if (stageJson.camera_boyfriend != null && stageJson.camera_boyfriend.length > 1) {
			camBfStepperX.value = stageJson.camera_boyfriend[0];
			camBfStepperY.value = stageJson.camera_boyfriend[1];
		} else
			camBfStepperX.value = camBfStepperY.value = 0;

		if (focusChecked > -1) {
			var point = focusOnTarget(focusTargets[focusChecked]);
			camFollow.setPosition(point.x, point.y);
		}
		loadJsonAssetDirectory();
	}

	function updateSelectedUI() {
		posTxt.visible = false;
		var selected = getSelected(false);
		if (selected == null)
			return;

		var displayX:Float = Math.round(selected.x);
		var displayY:Float = Math.round(selected.y);

		var char:Character = cast selected.sprite;
		if (char != null) {
			displayX -= char.positionArray[0];
			displayY -= char.positionArray[1];
		}

		posTxt.text = 'X: $displayX\nY: $displayY';
		posTxt.visible = true;

		var selected = getSelected();
		if (selected == null)
			return;

		// Texts/Input Texts
		colorInputText.text = selected.color;
		nameInputText.text = selected.name;
		imgTxt.text = 'Image: ' + selected.image;

		// Steppers
		if (selected.type != 'square') {
			scaleStepperX.decimals = scaleStepperY.decimals = 2;
			scaleStepperX.max = scaleStepperY.max = 10;
			scaleStepperX.min = scaleStepperY.min = 0.05;
			scaleStepperX.step = scaleStepperY.step = 0.05;
		} else {
			scaleStepperX.decimals = scaleStepperY.decimals = 0;
			scaleStepperX.max = scaleStepperY.max = 10000;
			scaleStepperX.min = scaleStepperY.min = 50;
			scaleStepperX.step = scaleStepperY.step = 50;
		}
		scaleStepperX.value = selected.scale[0];
		scaleStepperY.value = selected.scale[1];
		scrollStepperX.value = selected.scroll[0];
		scrollStepperY.value = selected.scroll[1];
		angleStepper.value = selected.angle;
		alphaStepper.value = selected.alpha;

		// Checkboxes
		antialiasingCheckbox.checked = selected.antialiasing;
		flipXCheckBox.checked = selected.flipX;
		flipYCheckBox.checked = selected.flipY;
		lowQualityCheckbox.checked = (selected.filters & LOW_QUALITY) == LOW_QUALITY;
		highQualityCheckbox.checked = (selected.filters & HIGH_QUALITY) == HIGH_QUALITY;
	}

	function reloadCharacters() {
		if (stageJson._editorMeta != null) {
			gf.changeCharacter(stageJson._editorMeta.gf);
			dad.changeCharacter(stageJson._editorMeta.dad);
			boyfriend.changeCharacter(stageJson._editorMeta.boyfriend);
		}
		repositionGirlfriend();
		repositionDad();
		repositionBoyfriend();

		setFocus(-1);
		FlxG.camera.target = null;
		var point = focusOnTarget('boyfriend');
		FlxG.camera.scroll.set(point.x - FlxG.width / 2, point.y - FlxG.height / 2);
		FlxG.camera.zoom = stageJson.defaultZoom;
		oppDropdown.select(Std.int(Math.max(0, characterList.indexOf(dad.curCharacter))));
		gfDropdown.select(Std.int(Math.max(0, characterList.indexOf(gf.curCharacter))));
		plDropdown.select(Std.int(Math.max(0, characterList.indexOf(boyfriend.curCharacter))));
	}

	function reloadStageDropDown() {
		stageList = [];
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'stages/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
				if (file.toLowerCase().endsWith('.json')) {
					var stageToCheck:String = file.substr(0, file.length - '.json'.length);
					if (!stageList.contains(stageToCheck))
						stageList.push(stageToCheck);
				}

		if (stageList.length < 1)
			stageList.push('');
		stageDropDown.setItems(stageList.copy());
		stageDropDown.select(Std.int(Math.max(0, stageList.indexOf(lastLoadedStage))));
		directoryDropDown.select(Std.int(Math.max(0, directoryList.indexOf(stageJson.directory))));
	}

	function checkUIOnObject() {
		if (curTabName == 'Object') {
			var selected:Int = spriteListChecked;
			if (selected >= 0) {
				var spr = stageSprites[spriteListLabels.length - selected - 1];
				if (spr != null && StageData.reservedNames.contains(spr.type))
					selectTabByName('Data');
			} else
				selectTabByName('Data');
		}
	}

	var outputTime:Float = 0;

	override function update(elapsed:Float) {
		if (createPopupVisible && (FlxG.mouse.justPressedRight || (FlxG.mouse.justPressed && !FlxSmidr.mouseBlocked)))
			setCreatePopupVisible(false);

		for (basic in stageSprites)
			basic.update(curFilters, elapsed);

		super.update(elapsed);

		outputTime = Math.max(0, outputTime - elapsed);
		outputTxt.alpha = outputTime;

		if (UIFocus.focused != null || UIRoot.overlayOpen)
			return;

		if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
			if (!unsavedProgress) {
				MusicBeatState.switchState(new editors.MasterEditorMenu());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
			} else
				openSubState(new ExitConfirmationPrompt());
			return;
		}

		if (FlxG.keys.justPressed.W) {
			selectSpriteRow(FlxMath.wrap(spriteListChecked - 1, 0, spriteListLabels.length - 1));
		} else if (FlxG.keys.justPressed.S) {
			selectSpriteRow(FlxMath.wrap(spriteListChecked + 1, 0, spriteListLabels.length - 1));
		}

		if (FlxG.keys.justPressed.F1 || (helpBg.visible && FlxG.keys.justPressed.ESCAPE)) {
			helpBg.visible = !helpBg.visible;
			helpTexts.visible = helpBg.visible;
		}

		#if FLX_DEBUG
		if (FlxG.keys.justPressed.F3)
		#else
		if (FlxG.keys.justPressed.F2)
		#end
		{
			mainUI.visible = !mainUI.visible;
		}

		if (FlxG.keys.justPressed.F12)
			showSelectionQuad = !showSelectionQuad;

		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		if (FlxG.keys.pressed.SHIFT)
			shiftMult = 4;
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.25;

		// CAMERA CONTROLS
		var camX:Float = 0;
		var camY:Float = 0;
		var camMove:Float = elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.J)
			camX -= camMove;
		if (FlxG.keys.pressed.K)
			camY += camMove;
		if (FlxG.keys.pressed.L)
			camX += camMove;
		if (FlxG.keys.pressed.I)
			camY -= camMove;

		if (camX != 0 || camY != 0) {
			FlxG.camera.scroll.x += camX;
			FlxG.camera.scroll.y += camY;
			if (FlxG.camera.target != null)
				FlxG.camera.target = null;
			if (focusChecked > -1)
				setFocus(-1);
		}

		var lastZoom = FlxG.camera.zoom;
		if (FlxG.keys.justPressed.R && !FlxG.keys.pressed.CONTROL)
			FlxG.camera.zoom = stageJson.defaultZoom;
		else if (FlxG.keys.pressed.E && FlxG.camera.zoom < maxZoom)
			FlxG.camera.zoom = Math.min(maxZoom, FlxG.camera.zoom + elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);
		else if (FlxG.keys.pressed.Q && FlxG.camera.zoom > minZoom)
			FlxG.camera.zoom = Math.max(minZoom, FlxG.camera.zoom - elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);

		// SPRITE X/Y
		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		if (FlxG.keys.pressed.SHIFT)
			shiftMult = 4;
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.2;

		var moveX:Float = 0;
		var moveY:Float = 0;
		if (FlxG.keys.justPressed.LEFT)
			moveX -= 5 * shiftMult * ctrlMult;
		if (FlxG.keys.justPressed.RIGHT)
			moveX += 5 * shiftMult * ctrlMult;
		if (FlxG.keys.justPressed.UP)
			moveY -= 5 * shiftMult * ctrlMult;
		if (FlxG.keys.justPressed.DOWN)
			moveY += 5 * shiftMult * ctrlMult;

		if (!FlxSmidr.mouseBlocked && FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0)) {
			moveX += FlxG.mouse.deltaScreenX * ctrlMult;
			moveY += FlxG.mouse.deltaScreenY * ctrlMult;
			_updateCamera();
		}

		if (moveX != 0 || moveY != 0) {
			var selected:Int = spriteListChecked;
			if (selected < 0)
				return;

			var spr = stageSprites[spriteListLabels.length - selected - 1];
			if (spr != null) {
				var displayX:Float, displayY:Float;
				spr.x = displayX = Math.round(spr.x + moveX);
				spr.y = displayY = Math.round(spr.y + moveY);
				var char:Character = cast spr.sprite;
				switch (spr.type) {
					case 'boyfriend':
						stageJson.boyfriend[0] = displayX = spr.x - char.positionArray[0];
						stageJson.boyfriend[1] = displayY = spr.y - char.positionArray[1];
					case 'gf':
						stageJson.girlfriend[0] = displayX = spr.x - char.positionArray[0];
						stageJson.girlfriend[1] = displayY = spr.y - char.positionArray[1];
					case 'dad':
						stageJson.opponent[0] = displayX = spr.x - char.positionArray[0];
						stageJson.opponent[1] = displayY = spr.y - char.positionArray[1];
				}
				posTxt.text = 'X: $displayX\nY: $displayY';
				unsavedProgress = true;
			}
		}
	}

	var curFilters:LoadFilters = (LOW_QUALITY) | (HIGH_QUALITY);

	override function draw() {
		if (persistentDraw || subState == null) {
			for (basic in stageSprites)
				if (basic.visible)
					basic.draw(curFilters);

			if (showSelectionQuad && spriteListChecked >= 0) {
				var spr = stageSprites[spriteListLabels.length - spriteListChecked - 1];
				if (spr != null)
					drawDebugOnCamera(spr.sprite);
			}
		}

		super.draw();
	}

	function focusOnTarget(target:String) {
		var focusPoint:FlxPoint = FlxPoint.weak(0, 0);
		switch (target) {
			case 'boyfriend':
				focusPoint.x += boyfriend.getMidpoint().x - boyfriend.cameraPosition[0] - 100;
				focusPoint.y += boyfriend.getMidpoint().y + boyfriend.cameraPosition[1] - 100;
				if (stageJson.camera_boyfriend != null && stageJson.camera_boyfriend.length > 1) {
					focusPoint.x += stageJson.camera_boyfriend[0];
					focusPoint.y += stageJson.camera_boyfriend[1];
				}
			case 'dad':
				focusPoint.x += dad.getMidpoint().x + dad.cameraPosition[0] + 150;
				focusPoint.y += dad.getMidpoint().y + dad.cameraPosition[1] - 100;
				if (stageJson.camera_opponent != null && stageJson.camera_opponent.length > 1) {
					focusPoint.x += stageJson.camera_opponent[0];
					focusPoint.y += stageJson.camera_opponent[1];
				}
			case 'gf':
				if (gf.visible) {
					focusPoint.x += gf.getMidpoint().x + gf.cameraPosition[0];
					focusPoint.y += gf.getMidpoint().y + gf.cameraPosition[1];
				}

				if (stageJson.camera_girlfriend != null && stageJson.camera_girlfriend.length > 1) {
					focusPoint.x += stageJson.camera_girlfriend[0];
					focusPoint.y += stageJson.camera_girlfriend[1];
				}
		}
		return focusPoint;
	}

	function repositionGirlfriend() {
		gf.setPosition(stageJson.girlfriend[0], stageJson.girlfriend[1]);
		gf.x += gf.positionArray[0];
		gf.y += gf.positionArray[1];
	}

	function repositionDad() {
		dad.setPosition(stageJson.opponent[0], stageJson.opponent[1]);
		dad.x += dad.positionArray[0];
		dad.y += dad.positionArray[1];
	}

	function repositionBoyfriend() {
		boyfriend.setPosition(stageJson.boyfriend[0], stageJson.boyfriend[1]);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
	}

	public function drawDebugOnCamera(spr:FlxSprite):Void {
		if (spr == null || !spr.isOnScreen(FlxG.camera))
			return;

		@:privateAccess
		var lineSize:Int = Std.int(Math.max(2, Math.floor(3 / FlxG.camera.zoom)));

		var sprX:Float = spr.x - spr.offset.x;
		var sprY:Float = spr.y - spr.offset.y;
		var sprWidth:Int = Std.int(spr.frameWidth * spr.scale.x);
		var sprHeight:Int = Std.int(spr.frameHeight * spr.scale.y);
		for (num => sel in selectionSprites.members) {
			sel.x = sprX;
			sel.y = sprY;
			switch (num) {
				case 0: // Top
					sel.setGraphicSize(sprWidth, lineSize);
				case 1: // Bottom
					sel.setGraphicSize(sprWidth, lineSize);
					sel.y += sprHeight - lineSize;
				case 2: // Left
					sel.setGraphicSize(lineSize, sprHeight);
				case 3: // Right
					sel.setGraphicSize(lineSize, sprHeight);
					sel.x += sprWidth - lineSize;
			}
			sel.updateHitbox();
			sel.scrollFactor.set(spr.scrollFactor.x, spr.scrollFactor.y);
		}
		selectionSprites.draw();
	}

	// save

	function saveObjectsToJson() {
		stageJson.objects = [];
		for (basic in stageSprites)
			stageJson.objects.push(basic.formatToJson());
	}

	function saveData() {
		if (_file != null)
			return;

		saveObjectsToJson();
		var data = haxe.Json.stringify(stageJson, '\t');
		if (data.length > 0) {
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, '$lastLoadedStage.json');
		}
	}

	var _file:FileReference;

	function onSaveComplete(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice('Successfully saved file.');
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error('Problem saving file');
	}

	var _makeNewSprite = null;

	public function loadImage(onNewSprite:String = null) {
		if (_file != null)
			return;

		_makeNewSprite = onNewSprite;
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		final filters = [
			new FileFilter('PNG (Image)', '*.png'),
			new FileFilter('XML (Sparrow)', '*.xml'),
			new FileFilter('JSON (Aseprite)', '*.json'),
			new FileFilter('TXT (Packer)', '*.txt')
		];
		_file.browse(#if !mac filters #else [] #end);
	}

	private function onLoadComplete(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		#if sys
		var fullPath:String = null;
		@:privateAccess
		if (_file.__path != null)
			fullPath = _file.__path;

		function loadSprite(imageToLoad:String) {
			if (_makeNewSprite != null) {
				if (_makeNewSprite == 'animatedSprite'
					&& !Paths.fileExists('images/$imageToLoad.xml', TEXT)
					&& !Paths.fileExists('images/$imageToLoad.json', TEXT)
					&& !Paths.fileExists('images/$imageToLoad.txt', TEXT)) {
					showOutput('No Animation file found with the same name of the image!', true);
					_makeNewSprite = null;
					_file = null;
					return;
				}
				insertMeta(new StageEditorMetaSprite({type: _makeNewSprite, name: findUnoccupiedName()}, new ModchartSprite()));
			}
			var selected = getSelected();
			tryLoadImage(selected, imageToLoad);

			if (_makeNewSprite != null) {
				selected.sprite.x = Math.round(FlxG.camera.scroll.x + FlxG.width / 2 - selected.sprite.width / 2);
				selected.sprite.y = Math.round(FlxG.camera.scroll.y + FlxG.height / 2 - selected.sprite.height / 2);
				posTxt.visible = true;
				posTxt.text = 'X: ${selected.sprite.x}\nY: ${selected.sprite.y}';
			}
			_makeNewSprite = null;
		}
		_file = null;

		if (fullPath != null) {
			fullPath = fullPath.replace('\\', '/');
			var exePath = Sys.getCwd().replace('\\', '/');
			if (fullPath.startsWith(exePath)) {
				fullPath = fullPath.substr(exePath.length);
				if ((fullPath.startsWith('assets/') #if MODS_ALLOWED || fullPath.startsWith('mods/') #end)
					&& fullPath.contains('/images/')) {
					loadSprite(fullPath.substring(fullPath.indexOf('/images/') + '/images/'.length, fullPath.lastIndexOf('.')));
					return;
				}
			}

			setCreatePopupVisible(false);
			#if MODS_ALLOWED
			var modFolder:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Paths.mods('${Mods.currentModDirectory}/images/') : Paths.mods('images/');
			openSubState(new BasePrompt(480, 160, 'This file is not inside Psych Engine.', function(state:BasePrompt) {
				var txt:FlxText = new FlxText(0, state.bg.y + 60, 460, 'Copy to: "$modFolder"?', 11);
				txt.alignment = CENTER;
				txt.screenCenter(X);
				txt.cameras = state.cameras;
				state.add(txt);

				var btnY = 390;
				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'OK', function() {
					var fileName:String = fullPath.substring(fullPath.lastIndexOf('/') + 1, fullPath.lastIndexOf('.'));
					var pathNoExt:String = fullPath.substring(0, fullPath.lastIndexOf('.'));
					function saveFile(ext:String) {
						var p1:String = '$pathNoExt.$ext';
						var p2:String = modFolder + '$fileName.$ext';
						trace(p1, p2);
						if (FileSystem.exists(p1))
							File.saveBytes(p2, File.getBytes(p1));
					}

					FileSystem.createDirectory(modFolder);
					saveFile('png');
					saveFile('xml');
					saveFile('txt');
					saveFile('json');
					loadSprite(fileName);
					state.close();
				});
				btn.normalStyle.bgColor = FlxColor.GREEN;
				btn.normalStyle.textColor = FlxColor.WHITE;
				btn.screenCenter(X);
				btn.x -= 100;
				btn.cameras = state.cameras;
				state.add(btn);

				var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Cancel', function() {
					_makeNewSprite = null;
					state.close();
				});
				btn.screenCenter(X);
				btn.x += 100;
				btn.cameras = state.cameras;
				state.add(btn);
			}));
			#else
			showOutput('ERROR! File cannot be used, move it to "assets" and recompile.', true);
			#end
		}
		_file = null;
		#else
		trace('File couldn\'t be loaded! You aren\'t on Desktop, are you?');
		#end
	}

	function tryLoadImage(spr:StageEditorMetaSprite, imgPath:String) {
		if (spr == null || StageData.reservedNames.contains(spr.type) || spr.type == 'square' || imgPath == null)
			return;

		spr.image = imgPath;
		updateSelectedUI();
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	private function onLoadCancel(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;

		if (_makeNewSprite != null) {
			setCreatePopupVisible(false);
			_makeNewSprite = null;
		}
		trace('Cancelled file loading.');
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	private function onLoadError(_):Void {
		if (_file == null)
			return;
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;

		if (_makeNewSprite != null) {
			setCreatePopupVisible(false);
			_makeNewSprite = null;
		}
		trace('Problem loading file');
	}

	override function destroy() {
		destroySubStates = true;
		animationEditor.destroy();
		if (uiRoot != null) {
			FlxSmidr.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}

class StageEditorMetaSprite {
	public var sprite:FlxSprite;
	public var visible(get, set):Bool;

	function get_visible()
		return sprite.visible;

	function set_visible(v:Bool)
		return (sprite.visible = v);

	// basic variables for all types
	public var type:String;

	// variables for all types that aren't Character
	public var name:String;
	public var filters:LoadFilters = (LOW_QUALITY) | (HIGH_QUALITY);
	public var x(get, set):Float;
	public var y(get, set):Float;
	public var alpha(get, set):Float;
	public var angle(get, set):Float;

	function get_x()
		return sprite.x;

	function set_x(v:Float)
		return (sprite.x = v);

	function get_y()
		return sprite.y;

	function set_y(v:Float)
		return (sprite.y = v);

	function get_alpha()
		return sprite.alpha;

	function set_alpha(v:Float)
		return (sprite.alpha = v);

	function get_angle()
		return sprite.angle;

	function set_angle(v:Float)
		return (sprite.angle = v);

	public var color(default, set):String = 'FFFFFF';

	function set_color(v:String) {
		sprite.color = CoolUtil.colorFromString(v);
		return (color = v);
	}

	public var image(default, set):String = 'unknown';

	function set_image(v:String) {
		try {
			switch (type) {
				case 'sprite':
					sprite.loadGraphic(Paths.image(v));
				case 'animatedSprite':
					sprite.frames = Paths.getAtlas(v);
			}
		} catch (e:Dynamic) {}
		sprite.updateHitbox();
		return (image = v);
	}

	public var scroll:Array<Float> = [1, 1];

	public function setScrollFactor(scrX:Null<Float> = null, scrY:Null<Float> = null) {
		scroll[0] = (scrX != null ? scrX : scroll[0]);
		scroll[1] = (scrY != null ? scrY : scroll[1]);
		sprite.scrollFactor.set(scroll[0], scroll[1]);
	}

	public var scale:Array<Float> = [1, 1];
	public var antialiasing(default, set):Bool = true;

	function set_antialiasing(v:Bool) {
		sprite.antialiasing = (v && ClientPrefs.data.antialiasing);
		return (antialiasing = v);
	}

	public function setScale(wid:Null<Float> = null, hei:Null<Float> = null) {
		scale[0] = (wid != null ? wid : scale[0]);
		scale[1] = (hei != null ? hei : scale[1]);
		sprite.scale.set(scale[0], scale[1]);
		sprite.updateHitbox();
	}

	public var flipX(get, set):Bool;
	public var flipY(get, set):Bool;

	function get_flipX()
		return sprite.flipX;

	function set_flipX(v:Bool)
		return (sprite.flipX = (v && type != 'square'));

	function get_flipY()
		return sprite.flipY;

	function set_flipY(v:Bool)
		return (sprite.flipY = (v && type != 'square'));

	// "animatedSprite" only variables
	public var firstAnimation:String;
	public var animations:Array<AnimArray>;

	public function new(data:Dynamic, spr:FlxSprite) {
		this.sprite = spr;
		if (data == null)
			return;

		this.type = data.type;
		switch (this.type) {
			case 'sprite', 'square', 'animatedSprite':
				for (v in ['name', 'image', 'scale', 'scroll', 'color', 'filters', 'antialiasing']) {
					var dat:Dynamic = Reflect.field(data, v);
					if (dat != null)
						Reflect.setField(this, v, dat);
				}

				if (this.type == 'animatedSprite') {
					this.animations = data.animations;
					this.firstAnimation = data.firstAnimation;
				}
		}
	}

	public function formatToJson() {
		var obj:Dynamic = {type: type};
		switch (type) {
			case 'square', 'sprite', 'animatedSprite':
				obj.name = name;
				obj.x = x;
				obj.y = y;
				obj.scale = scale;
				obj.scroll = scroll;
				obj.alpha = alpha;
				obj.angle = angle;
				obj.color = color;
				obj.filters = filters;

				if (type != 'square') {
					obj.flipX = flipX;
					obj.flipY = flipY;
					obj.image = image;
					obj.antialiasing = antialiasing;
					if (type == 'animatedSprite') {
						obj.animations = animations;
						obj.firstAnimation = firstAnimation;
					}
				}
		}
		return obj;
	}

	public function update(curFilters:LoadFilters, elapsed:Float) {
		if ((curFilters & filters) != 0 || StageData.reservedNames.contains(type))
			sprite.update(elapsed);
	}

	public function draw(curFilters:LoadFilters) {
		if ((curFilters & filters) != 0 || StageData.reservedNames.contains(type))
			sprite.draw();
	}
}

class StageEditorAnimationSubstate extends MusicBeatSubstate {
	var bg:FlxSprite;
	var originalZoom:Float;
	var originalCamPoint:FlxPoint;
	var originalPosition:FlxPoint;
	var originalCamTarget:FlxObject;
	var originalAlpha:Float = 1;

	public var target:StageEditorMetaSprite;

	var curAnim:Int = 0;
	var animsTxtGroup:FlxTypedGroup<FlxText>;

	var camHUD:FlxCamera = cast(FlxG.state, StageEditorState).camHUD;

	/** The substate's own widget container, parented on the state's shared UI root. **/
	var animUI:Sprite;

	static inline var PAD:Int = 10;
	static inline var BOX_W:Int = 320;

	public function new() {
		super();

		var grid:FlxBackdrop = new FlxBackdrop(FlxGridOverlay.createGrid(50, 50, 100, 100, true, 0xFFAAAAAA, 0xFF666666));
		add(grid);

		animsTxtGroup = new FlxTypedGroup<FlxText>();
		animsTxtGroup.cameras = [camHUD];
		add(animsTxtGroup);

		addAnimationsUI();

		openCallback = function() {
			curAnim = 0;
			originalZoom = FlxG.camera.zoom;
			originalCamPoint = FlxPoint.weak(FlxG.camera.scroll.x, FlxG.camera.scroll.y);
			originalPosition = FlxPoint.weak(target.x, target.y);
			originalCamTarget = FlxG.camera.target;
			originalAlpha = target.alpha;
			FlxG.camera.zoom = 0.5;
			FlxG.camera.scroll.set(0, 0);

			target.alpha = 1;
			target.sprite.screenCenter();
			add(target.sprite);
			animUI.visible = true;
			reloadAnimList();
			trace('Opened substate');
		};

		closeCallback = function() {
			FlxG.camera.zoom = originalZoom;
			FlxG.camera.scroll.set(originalCamPoint.x, originalCamPoint.y);
			FlxG.camera.target = originalCamTarget;

			target.x = originalPosition.x;
			target.y = originalPosition.y;
			target.alpha = originalAlpha;
			remove(target.sprite);
			animUI.visible = false;

			var owner:StageEditorState = cast(FlxG.state, StageEditorState);
			if (owner.mainUI != null)
				owner.mainUI.visible = true;

			if (target.animations.length > 0) {
				if (target.firstAnimation == null)
					target.firstAnimation = target.animations[0].anim;
				playAnim(target.firstAnimation);
			}
		};
	}

	var animationDropDown:UIDropdown;
	var animationInputText:UITextInput;
	var animationNameInputText:UITextInput;
	var animationIndicesInputText:UITextInput;
	var animationFramerate:UIStepper;
	var animationLoopCheckBox:UICheckbox;
	var mainAnimTxt:UILabel;

	function addAnimationsUI() {
		var owner:StageEditorState = cast(FlxG.state, StageEditorState);
		animUI = new Sprite();
		animUI.visible = false;
		owner.uiRoot.content.addChild(animUI);

		var boxX:Float = FlxG.width - BOX_W - 10;
		var boxY:Float = 20;
		var boxH:Float = 300;
		var rowW:Float = BOX_W - PAD * 2;
		var halfW:Float = (rowW - 10) / 2;

		var panel:UIPanel = new UIPanel(BOX_W, boxH, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		animUI.addChild(panel);

		var header:UILabel = new UILabel('Animations', 14, 0);
		header.x = boxX + PAD;
		header.y = boxY + 8;
		animUI.addChild(header);

		var rowY:Float = boxY + 30;

		animationDropDown = new UIDropdown('Animations:', rowW, function(selectedAnimation:Int, pressed:String) {
			var anim:AnimArray = target.animations[selectedAnimation];
			if (anim == null)
				return;

			animationInputText.text = anim.anim;
			animationNameInputText.text = anim.name;
			animationLoopCheckBox.checked = anim.loop;
			animationFramerate.value = anim.fps;

			var indicesStr:String = anim.indices.toString();
			animationIndicesInputText.text = indicesStr.substr(1, indicesStr.length - 2);
		});
		animationDropDown.x = boxX + PAD;
		animationDropDown.y = rowY;
		animUI.addChild(animationDropDown);

		mainAnimTxt = new UILabel('Main Anim.: ', 11, 2);
		mainAnimTxt.x = boxX + PAD;
		mainAnimTxt.y = rowY + 30;
		animUI.addChild(mainAnimTxt);

		var initAnimButton:UIButton = new UIButton('Main Animation', halfW, 24, function() {
			var anim:AnimArray = target.animations[curAnim];
			if (anim == null)
				return;

			mainAnimTxt.text = 'Main Anim.: ${anim.anim}';
			target.firstAnimation = anim.anim;
		});
		initAnimButton.x = boxX + PAD + halfW + 10;
		initAnimButton.y = rowY + 26;
		animUI.addChild(initAnimButton);

		animationInputText = new UITextInput('Animation name:', rowW, '');
		animationInputText.x = boxX + PAD;
		animationInputText.y = rowY + 58;
		animUI.addChild(animationInputText);

		animationNameInputText = new UITextInput('Symbol Name/Tag:', rowW, '');
		animationNameInputText.x = boxX + PAD;
		animationNameInputText.y = rowY + 90;
		animUI.addChild(animationNameInputText);

		animationIndicesInputText = new UITextInput('ADVANCED - Indices:', rowW, '');
		animationIndicesInputText.x = boxX + PAD;
		animationIndicesInputText.y = rowY + 122;
		animUI.addChild(animationIndicesInputText);

		animationFramerate = new UIStepper('Framerate:', halfW, 24, 1);
		animationFramerate.min = 0;
		animationFramerate.max = 240;
		animationFramerate.x = boxX + PAD;
		animationFramerate.y = rowY + 154;
		animUI.addChild(animationFramerate);

		animationLoopCheckBox = new UICheckbox('Should it Loop?', halfW, false);
		animationLoopCheckBox.x = boxX + PAD + halfW + 10;
		animationLoopCheckBox.y = rowY + 154;
		animUI.addChild(animationLoopCheckBox);

		var addUpdateButton:UIButton = new UIButton('Add/Update', halfW, 26, function() {
			if (animationInputText.text == '')
				return;

			var indices:Array<Int> = [];
			var indicesStr:Array<String> = animationIndicesInputText.text.trim().split(',');
			if (indicesStr.length > 1) {
				for (i in 0...indicesStr.length) {
					var index:Null<Int> = Std.parseInt(indicesStr[i]);
					if (index != null && index > -1) {
						indices.push(index);
					}
				}
			}

			var lastAnim:String = (target.animations[curAnim] != null) ? target.animations[curAnim].anim : '';
			var lastOffsets:Array<Int> = null;
			for (anim in target.animations)
				if (animationInputText.text == anim.anim) {
					lastOffsets = anim.offsets;
					cast(target.sprite, ModchartSprite).animOffsets.remove(animationInputText.text);
					target.sprite.animation.remove(animationInputText.text);
					target.animations.remove(anim);
				}

			var addedAnim:AnimArray = {
				anim: animationInputText.text,
				name: animationNameInputText.text,
				fps: Math.round(animationFramerate.value),
				loop: animationLoopCheckBox.checked,
				indices: indices,
				offsets: lastOffsets
			};

			if (addedAnim.indices != null && addedAnim.indices.length > 0)
				target.sprite.animation.addByIndices(addedAnim.anim, addedAnim.name, addedAnim.indices, '', addedAnim.fps, addedAnim.loop);
			else
				target.sprite.animation.addByPrefix(addedAnim.anim, addedAnim.name, addedAnim.fps, addedAnim.loop);

			target.animations.push(addedAnim);
			reloadAnimList();
			playAnim(addedAnim.anim, true);

			curAnim = target.animations.length - 1;
			updateTextColors();
			trace('Added/Updated animation: ' + animationInputText.text);
		}, true);
		addUpdateButton.x = boxX + PAD;
		addUpdateButton.y = rowY + 190;
		animUI.addChild(addUpdateButton);

		var removeButton:UIButton = new UIButton('Remove', halfW, 26, function() {
			for (anim in target.animations) {
				if (animationInputText.text == anim.anim) {
					var targetSprite:ModchartSprite = cast(target.sprite, ModchartSprite);
					var resetAnim:Bool = false;
					if (targetSprite.animation.curAnim != null && anim.anim == targetSprite.animation.curAnim.name)
						resetAnim = true;

					if (targetSprite.animOffsets.exists(anim.anim))
						targetSprite.animOffsets.remove(anim.anim);

					target.animations.remove(anim);
					targetSprite.animation.remove(anim.anim);

					if (resetAnim && target.animations.length > 0) {
						curAnim = FlxMath.wrap(curAnim, 0, target.animations.length - 1);
						playAnim(target.animations[curAnim].anim, true);
						updateTextColors();
					} else if (target.animations.length < 1)
						target.sprite.animation.curAnim = null;

					trace('Removed animation: ' + animationInputText.text);
					reloadAnimList();
					break;
				}
			}
		});
		removeButton.danger = true;
		removeButton.x = boxX + PAD + halfW + 10;
		removeButton.y = rowY + 190;
		animUI.addChild(removeButton);
	}

	function reloadAnimList() {
		if (target.animations == null)
			target.animations = [];
		else if (target.animations.length > 0)
			playAnim(target.animations[0].anim, true);
		curAnim = 0;

		for (text in animsTxtGroup)
			text.kill();

		var spr:ModchartSprite = cast(target.sprite, ModchartSprite);
		if (target.animations.length > 0) {
			if (target.firstAnimation == null || !target.sprite.animation.exists(target.firstAnimation))
				target.firstAnimation = target.animations[0].anim;

			mainAnimTxt.text = 'Main Anim.: ${target.firstAnimation}';
		} else {
			target.firstAnimation = null;
			mainAnimTxt.text = '(No Main Animation)';
		}

		for (num => anim in target.animations) {
			var text:FlxText = animsTxtGroup.recycle(FlxText);
			text.x = 10;
			text.y = 32 + (20 * num);
			text.fieldWidth = 400;
			text.fieldHeight = 20;
			if (anim.offsets != null)
				text.text = '${anim.anim}: ${spr.animOffsets.get(anim.anim)}';
			else
				text.text = '${anim.anim}: No offsets';

			text.setFormat(null, 16, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
			text.scrollFactor.set();
			text.borderSize = 1;
			animsTxtGroup.add(text);
		}
		updateTextColors();
		reloadAnimationDropDown();
	}

	function reloadAnimationDropDown() {
		var animList:Array<String> = [];
		for (anim in target.animations)
			animList.push(anim.anim);
		if (animList.length < 1)
			animList.push('NO ANIMATIONS'); // Prevents crash

		animationDropDown.setItems(animList);
	}

	inline function updateTextColors() {
		for (num => text in animsTxtGroup) {
			text.color = FlxColor.WHITE;
			if (num == curAnim)
				text.color = FlxColor.LIME;
		}
	}

	function playAnim(name:String, force:Bool = false) {
		var spr:ModchartSprite = cast(target.sprite, ModchartSprite);
		spr.playAnim(name, force);
		if (!spr.animOffsets.exists(name))
			spr.updateHitbox();
	}

	final minZoom = 0.25;
	final maxZoom = 2;
	var holdingArrowsTime:Float = 0;
	var holdingArrowsElapsed:Float = 0;
	var holdingFrameTime:Float = 0;
	var holdingFrameElapsed:Float = 0;

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (UIFocus.focused != null || UIRoot.overlayOpen)
			return;

		// ANIMATION SCROLLING
		if (target.animations.length > 1) {
			var changedAnim:Bool = false;
			if (FlxG.keys.justPressed.W && (changedAnim = true))
				curAnim--;
			else if (FlxG.keys.justPressed.S && (changedAnim = true))
				curAnim++;
			else if (FlxG.keys.justPressed.SPACE)
				changedAnim = true;

			if (changedAnim) {
				curAnim = FlxMath.wrap(curAnim, 0, target.animations.length - 1);
				playAnim(target.animations[curAnim].anim, true);
				updateTextColors();
			}
		}

		var shiftMult:Float = 1;
		var ctrlMult:Float = 1;
		var shiftMultBig:Float = 1;
		if (FlxG.keys.pressed.SHIFT) {
			shiftMult = 4;
			shiftMultBig = 10;
		}
		if (FlxG.keys.pressed.CONTROL)
			ctrlMult = 0.25;

		// OFFSET
		if (target.sprite.animation.curAnim != null) {
			var spr:ModchartSprite = cast(target.sprite, ModchartSprite);
			var anim:String = spr.animation.curAnim.name;
			var changedOffset = false;
			var moveKeysP = [
				FlxG.keys.justPressed.LEFT,
				FlxG.keys.justPressed.RIGHT,
				FlxG.keys.justPressed.UP,
				FlxG.keys.justPressed.DOWN
			];
			var moveKeys = [
				FlxG.keys.pressed.LEFT,
				FlxG.keys.pressed.RIGHT,
				FlxG.keys.pressed.UP,
				FlxG.keys.pressed.DOWN
			];
			if (moveKeysP.contains(true)) {
				if (spr.animOffsets.get(anim) != null) {
					spr.offset.x += ((moveKeysP[0] ? 1 : 0) - (moveKeysP[1] ? 1 : 0)) * shiftMultBig;
					spr.offset.y += ((moveKeysP[2] ? 1 : 0) - (moveKeysP[3] ? 1 : 0)) * shiftMultBig;
				} else
					spr.offset.x = spr.offset.y = 0;
				changedOffset = true;
			}

			if (moveKeys.contains(true)) {
				holdingArrowsTime += elapsed;
				if (holdingArrowsTime > 0.6) {
					holdingArrowsElapsed += elapsed;
					while (holdingArrowsElapsed > (1 / 60)) {
						if (spr.animOffsets.get(anim) != null) {
							spr.offset.x += ((moveKeys[0] ? 1 : 0) - (moveKeys[1] ? 1 : 0)) * shiftMultBig;
							spr.offset.y += ((moveKeys[2] ? 1 : 0) - (moveKeys[3] ? 1 : 0)) * shiftMultBig;
						} else
							spr.offset.x = spr.offset.y = 0;
						holdingArrowsElapsed -= (1 / 60);
						changedOffset = true;
					}
				}
			} else
				holdingArrowsTime = 0;

			if (!FlxSmidr.mouseBlocked && FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0)) {
				spr.offset.x -= FlxG.mouse.deltaScreenX;
				spr.offset.y -= FlxG.mouse.deltaScreenY;
				changedOffset = true;
			}

			if (FlxG.keys.justPressed.R && FlxG.keys.pressed.CONTROL) {
				target.animations[curAnim].offsets = null;
				spr.animOffsets.remove(anim);
				spr.updateHitbox();
				animsTxtGroup.members[curAnim].text = '${anim}: No offsets';
			}

			if (changedOffset) {
				var offX = Math.round(spr.offset.x);
				var offY = Math.round(spr.offset.y);

				spr.addOffset(anim, offX, offY);
				target.animations[curAnim].offsets = [offX, offY];
				animsTxtGroup.members[curAnim].text = '${anim}: ${spr.animOffsets.get(anim)}';
			}
		} else {
			holdingArrowsTime = 0;
			holdingArrowsElapsed = 0;
		}

		// CAMERA CONTROLS
		var camX:Float = 0;
		var camY:Float = 0;
		var camMove:Float = elapsed * 500 * shiftMult * ctrlMult;
		if (FlxG.keys.pressed.J)
			camX -= camMove;
		if (FlxG.keys.pressed.K)
			camY += camMove;
		if (FlxG.keys.pressed.L)
			camX += camMove;
		if (FlxG.keys.pressed.I)
			camY -= camMove;

		if (camX != 0 || camY != 0) {
			FlxG.camera.scroll.x += camX;
			FlxG.camera.scroll.y += camY;
		}

		var lastZoom = FlxG.camera.zoom;
		if (FlxG.keys.justPressed.R && !FlxG.keys.pressed.CONTROL)
			FlxG.camera.zoom = 0.5;
		else if (FlxG.keys.pressed.E && FlxG.camera.zoom < maxZoom)
			FlxG.camera.zoom = Math.min(maxZoom, FlxG.camera.zoom + elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);
		else if (FlxG.keys.pressed.Q && FlxG.camera.zoom > minZoom)
			FlxG.camera.zoom = Math.max(minZoom, FlxG.camera.zoom - elapsed * FlxG.camera.zoom * shiftMult * ctrlMult);

		if (FlxG.keys.justPressed.ESCAPE) {
			persistentDraw = true;
			close();
		}
	}
}
