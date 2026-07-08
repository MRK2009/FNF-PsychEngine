package editors;

import backend.UISkinConfig;
import backend.UISkinConfig.UISkinData;
import backend.UISkinConfig.UIJudgement;
import backend.UISkinConfig.UIPlacement;
import flixel.group.FlxSpriteGroup;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import flixel.input.keyboard.FlxKey;
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

/**
	In-engine editor for UI skins (judgement popups / combo / numbers / countdown). Mirrors
	`NoteSkinEditorState`: a SmidrUI tab box, a folder-skin dropdown, save/create to
	`mods/images/uiSkins/<name>`, and a LIVE preview driven through `UISkinConfig.editorOverride` +
	`setConfig` so edits show immediately. The preview replays the real popup/countdown using the same
	`UISkinConfig` accessors `PlayState` uses, so what you tune is what you get.
**/
class UISkinEditorState extends MusicBeatState {
	var config:UISkinData;
	var skinName:String = UISkinConfig.DEFAULT;

	var previewGroup:FlxSpriteGroup = new FlxSpriteGroup();
	var pool:Array<FlxSprite> = [];

	var skinDropDown:UIDropdown;
	var skinItems:Array<String> = [];
	var newNameInput:UITextInput;
	var infoText:FlxText;
	var tipText:FlxText;
	var notifyTimer:Float = 0;
	var sampleCombo:Int = 0;
	var autoBeat:Bool = true;
	var showComboWord:Bool = false; // the "combo" word is hidden by default, like gameplay

	// Draggable position hitboxes for the rating / combo / numbers, writing config.offsets.
	var showHitboxes:Bool = false;
	var handleGroup:FlxSpriteGroup = new FlxSpriteGroup();
	var handleElems:Array<String> = ['rating', 'combo', 'numbers'];
	var handleSpr:Array<FlxSprite> = [];
	var handleLabels:Array<FlxText> = [];
	var dragIndex:Int = -1;
	var grabX:Float = 0;
	var grabY:Float = 0;

	var uiRoot:UIRoot;

	// The motion elements + the rating names the Images tab exposes.
	static final ELEMENTS:Array<String> = ['rating', 'combo', 'numbers'];
	static final RATING_NAMES:Array<String> = ['sick', 'good', 'bad', 'shit'];
	static final EASES:Array<String> = [
		'linear', 'sineIn', 'sineOut', 'sineInOut', 'quadIn', 'quadOut', 'quadInOut', 'cubeOut', 'expoOut', 'backOut', 'elasticOut', 'bounceOut'
	];

	inline function font()
		return Paths.font('vcr.ttf');

	override function create() {
		Conductor.bpm = 128.0;
		Conductor.songPosition = 0;
		FlxG.mouse.visible = true;
		FlxG.sound.volumeUpKeys = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys = [];

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('UI Skin Editor');
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF1B1B26;
		add(bg);
		add(previewGroup);
		add(handleGroup);

		var available = UISkinConfig.list();
		if (!UISkinConfig.isFolderSkin(skinName) && available.length > 0)
			skinName = available[0];
		loadSkin(skinName);

		addUI();
		buildHandles();

		infoText = new FlxText(8, FlxG.height - 44, 0, '', 14);
		infoText.setFormat(font(), 14, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		infoText.scrollFactor.set();
		add(infoText);

		tipText = new FlxText(8, FlxG.height - 64, 0, 'Use the Preview buttons to test judgements + countdown.', 13);
		tipText.setFormat(font(), 13, FlxColor.YELLOW, LEFT, OUTLINE, FlxColor.BLACK);
		tipText.scrollFactor.set();
		add(tipText);

		refreshFields();

		// Play a steady beat track and auto-fire a judgement popup + combo increment on each beat
		// (like the Audio Offset menu), so authors see their skin react live.
		FlxG.sound.playMusic(Paths.music('offsetSong'), 1, true);

		super.create();
	}

	override function beatHit() {
		super.beatHit();
		if (!autoBeat || uiRoot == null)
			return;
		sampleCombo = (sampleCombo + 1) % 1000;
		var diff:Float = FlxG.random.float(0, 90);
		firePreview(diff, ratingForDiff(diff));
	}

	inline function ratingForDiff(d:Float):String {
		if (d <= ClientPrefs.data.sickWindow)
			return 'sick';
		if (d <= ClientPrefs.data.goodWindow)
			return 'good';
		if (d <= ClientPrefs.data.badWindow)
			return 'bad';
		return 'shit';
	}

	function loadSkin(name:String) {
		skinName = name;
		UISkinConfig.editorOverride = name;
		var loaded = UISkinConfig.isFolderSkin(name) ? UISkinConfig.get(name) : null;
		config = (loaded != null) ? loaded : defaultConfig();
		UISkinConfig.setConfig(name, config);
	}

	function defaultConfig():UISkinData {
		return {
			combo: 'combo',
			num: 'num',
			ready: 'ready',
			set: 'set',
			go: 'go',
			antialiasing: true,
			ratings: {sick: 'sick', good: 'good', bad: 'bad', shit: 'shit'},
			tween: {duration: 0.2, ease: 'linear'},
			judgements: {}
		};
	}

	// Re-publish the in-edit config so the live preview / accessors read the latest values.
	inline function commit()
		UISkinConfig.setConfig(skinName, config);

	inline function cfg():Dynamic
		return cast config;

	// ---- UI (SmidrUI) ----

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
	var boxX:Float = 0;

	function addUI() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		boxX = FlxG.width - BOX_W - 10;
		var boxY:Float = 20;

		boxTabs = new UITabs(BOX_W, [{label: 'Skin'}, {label: 'Images'}, {label: 'Motion'}, {label: 'Judgements'}], function(i:Int):Void {
			for (n in 0...tabPanes.length)
				tabPanes[n].visible = (n == i);
		});

		var paneH:Float = 370;
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

		addSkinTab(tabPanes[0]);
		addImagesTab(tabPanes[1]);
		addMotionTab(tabPanes[2]);
		addJudgementsTab(tabPanes[3]);

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

	function addSkinTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		skinItems = UISkinConfig.list();
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
			UISkinConfig.reset();
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

		// (per-element popup scale lives on the Motion tab; there's no separate "general" scale)
		aaCheck = new UICheckbox('Antialiasing', halfW, false, function(v:Bool) {
			cfg().antialiasing = v;
			commit();
		});
		aaCheck.y = 104;
		pane.content.addChild(aaCheck);

		pixelCheck = new UICheckbox('Pixel', halfW, false, function(v:Bool) {
			cfg().pixel = v;
			commit();
		});
		pixelCheck.x = halfW + 10;
		pixelCheck.y = 104;
		pane.content.addChild(pixelCheck);

		pixelVarCheck = new UICheckbox('Pixel variant', halfW, false, function(v:Bool) {
			cfg().pixelVariant = v;
			commit();
		});
		pixelVarCheck.y = 132;
		pane.content.addChild(pixelVarCheck);

		var comboWordCheck:UICheckbox = new UICheckbox('Show combo word', halfW, showComboWord, function(v:Bool) {
			showComboWord = v;
			positionHandles();
		});
		comboWordCheck.x = halfW + 10;
		comboWordCheck.y = 132;
		pane.content.addChild(comboWordCheck);

		var autoBeatCheck:UICheckbox = new UICheckbox('Auto popup on beat', halfW, autoBeat, function(v:Bool) autoBeat = v);
		autoBeatCheck.y = 160;
		pane.content.addChild(autoBeatCheck);

		var hitboxCheck:UICheckbox = new UICheckbox('Drag hitboxes', halfW, showHitboxes, function(v:Bool) {
			showHitboxes = v;
			positionHandles();
		});
		hitboxCheck.x = halfW + 10;
		hitboxCheck.y = 160;
		pane.content.addChild(hitboxCheck);

		var previewBtn:UIButton = new UIButton('Preview Judgement', halfW, 26, function() firePreview(20));
		previewBtn.y = 194;
		pane.content.addChild(previewBtn);

		var previewMissBtn:UIButton = new UIButton('Preview (loose)', halfW, 26, function() firePreview(120));
		previewMissBtn.x = halfW + 10;
		previewMissBtn.y = 194;
		pane.content.addChild(previewMissBtn);

		var countdownBtn:UIButton = new UIButton('Preview Countdown', rowW, 26, fireCountdown);
		countdownBtn.y = 226;
		pane.content.addChild(countdownBtn);

		paneLabel(pane, 0, 262, 'Saves to mods/images/uiSkins/<name>/');

		pane.refreshContent(286);
	}

	var aaCheck:UICheckbox;
	var pixelCheck:UICheckbox;
	var pixelVarCheck:UICheckbox;

	var comboInput:UITextInput;
	var numInput:UITextInput;
	var readyInput:UITextInput;
	var setInput:UITextInput;
	var goInput:UITextInput;
	var ratingInputs:Map<String, UITextInput> = new Map();

	function addImagesTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);

		comboInput = imageField(pane, rowW, 0, 'combo word:', function(v) {
			cfg().combo = v;
		});
		numInput = imageField(pane, rowW, 32, 'number prefix:', function(v) {
			cfg().num = v;
		});
		readyInput = imageField(pane, rowW, 64, 'ready:', function(v) {
			cfg().ready = v;
		});
		setInput = imageField(pane, rowW, 96, 'set:', function(v) {
			cfg().set = v;
		});
		goInput = imageField(pane, rowW, 128, 'go:', function(v) {
			cfg().go = v;
		});

		paneLabel(pane, 0, 164, 'Rating images:', 12);
		var y:Float = 184;
		for (name in RATING_NAMES) {
			ratingInputs.set(name, imageField(pane, rowW, y, name + ':', function(v) {
				if (cfg().ratings == null)
					cfg().ratings = {};
				Reflect.setField(cfg().ratings, name, v);
				commit();
			}));
			y += 32;
		}

		pane.refreshContent(y + 8);
	}

	function imageField(pane:UIScrollPane, rowW:Float, y:Float, name:String, onSet:String->Void):UITextInput {
		var input:UITextInput = new UITextInput(name, rowW, '', function(v:String) {
			onSet(v.trim());
			commit();
		});
		input.y = y;
		pane.content.addChild(input);
		return input;
	}

	var motionElemDrop:UIDropdown;
	var mDuration:UIStepper;
	var mStartDelay:UIStepper;
	var mScale:UIStepper;
	var mEaseDrop:UIDropdown;
	var mVelYMin:UIStepper;
	var mVelYMax:UIStepper;
	var mAccYMin:UIStepper;
	var mAccYMax:UIStepper;
	var curMotionElem:String = 'rating';
	var curEase:String = 'linear';

	function addMotionTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);
		var halfW:Float = (rowW - 10) / 2;

		motionElemDrop = new UIDropdown('Element:', rowW, function(id, name) {
			curMotionElem = name;
			loadMotion();
		});
		motionElemDrop.setItems(ELEMENTS.copy());
		motionElemDrop.select(0);
		pane.content.addChild(motionElemDrop);

		mDuration = new UIStepper('Duration (s):', halfW, 0.2, 0.05, function(_) applyMotion());
		mDuration.min = 0;
		mDuration.max = 5;
		mDuration.decimals = 2;
		mDuration.y = 32;
		pane.content.addChild(mDuration);

		mStartDelay = new UIStepper('Delay (0=auto):', halfW, 0, 0.01, function(_) applyMotion());
		mStartDelay.min = 0;
		mStartDelay.max = 5;
		mStartDelay.decimals = 3;
		mStartDelay.x = halfW + 10;
		mStartDelay.y = 32;
		pane.content.addChild(mStartDelay);

		mScale = new UIStepper('Scale:', halfW, 0.7, 0.05, function(_) applyMotion());
		mScale.min = 0.05;
		mScale.max = 8;
		mScale.decimals = 2;
		mScale.y = 64;
		pane.content.addChild(mScale);

		mEaseDrop = new UIDropdown('Ease:', rowW, function(id, name) {
			curEase = name;
			applyMotion();
		});
		mEaseDrop.setItems(EASES.copy());
		mEaseDrop.select(0);
		mEaseDrop.y = 96;
		pane.content.addChild(mEaseDrop);

		paneLabel(pane, 0, 130, 'Up velocity min/max:');
		mVelYMin = new UIStepper('Min:', halfW, 140, 5, function(_) applyMotion());
		mVelYMin.min = 0;
		mVelYMin.max = 2000;
		mVelYMin.y = 148;
		pane.content.addChild(mVelYMin);

		mVelYMax = new UIStepper('Max:', halfW, 160, 5, function(_) applyMotion());
		mVelYMax.min = 0;
		mVelYMax.max = 2000;
		mVelYMax.x = halfW + 10;
		mVelYMax.y = 148;
		pane.content.addChild(mVelYMax);

		paneLabel(pane, 0, 182, 'Gravity (accelY) min/max:');
		mAccYMin = new UIStepper('Min:', halfW, 200, 10, function(_) applyMotion());
		mAccYMin.min = 0;
		mAccYMin.max = 4000;
		mAccYMin.y = 200;
		pane.content.addChild(mAccYMin);

		mAccYMax = new UIStepper('Max:', halfW, 300, 10, function(_) applyMotion());
		mAccYMax.min = 0;
		mAccYMax.max = 4000;
		mAccYMax.x = halfW + 10;
		mAccYMax.y = 200;
		pane.content.addChild(mAccYMax);

		pane.refreshContent(236);

		loadMotion();
	}

	// The per-element block under config.tween, created on demand.
	function elemNode():Dynamic {
		if (cfg().tween == null)
			cfg().tween = {};
		var el:String = curMotionElem;
		var node:Dynamic = Reflect.field(cfg().tween, el);
		if (node == null) {
			node = {};
			Reflect.setField(cfg().tween, el, node);
		}
		return node;
	}

	function loadMotion() {
		if (mDuration == null)
			return;
		var node:Dynamic = (cfg().tween != null) ? Reflect.field(cfg().tween, curMotionElem) : null;
		mDuration.value = numOr(node, 'duration', 0.2);
		mStartDelay.value = numOr(node, 'startDelay', 0);
		mScale.value = numOr(node, 'scale', 0.7);
		curEase = strOr(node, 'ease', 'linear');
		mEaseDrop.select(Std.int(Math.max(0, EASES.indexOf(curEase))));
		var vy:Array<Float> = rangeOr(node, 'velocityY', 140, 160);
		mVelYMin.value = vy[0];
		mVelYMax.value = vy[1];
		var ay:Array<Float> = rangeOr(node, 'accelY', 200, 300);
		mAccYMin.value = ay[0];
		mAccYMax.value = ay[1];
	}

	function applyMotion() {
		var node:Dynamic = elemNode();
		Reflect.setField(node, 'duration', mDuration.value);
		Reflect.setField(node, 'startDelay', mStartDelay.value);
		Reflect.setField(node, 'scale', mScale.value);
		Reflect.setField(node, 'ease', curEase);
		Reflect.setField(node, 'velocityY', [mVelYMin.value, mVelYMax.value]);
		Reflect.setField(node, 'accelY', [mAccYMin.value, mAccYMax.value]);
		commit();
	}

	var judgeNameInput:UITextInput;
	var judgeImageInput:UITextInput;
	var judgeWindowStep:UIStepper;
	var judgeListDrop:UIDropdown;
	var judgeItems:Array<String> = [];
	var curJudge:String = '---';

	function addJudgementsTab(pane:UIScrollPane) {
		var rowW:Float = paneRowW(pane);

		paneLabel(pane, 0, 0, 'Custom visual rating tiers (image swap by hit ms).');
		paneLabel(pane, 0, 14, 'They do NOT change scoring/combo.');

		judgeNameInput = new UITextInput('Name:', rowW, 'perfect');
		judgeNameInput.y = 36;
		pane.content.addChild(judgeNameInput);

		judgeImageInput = new UITextInput('Image:', rowW, 'perfect');
		judgeImageInput.y = 68;
		pane.content.addChild(judgeImageInput);

		judgeWindowStep = new UIStepper('Window (ms):', rowW, 22.5, 1);
		judgeWindowStep.min = 0;
		judgeWindowStep.max = 500;
		judgeWindowStep.decimals = 2;
		judgeWindowStep.y = 100;
		pane.content.addChild(judgeWindowStep);

		var addBtn:UIButton = new UIButton('Add / Update', 130, 26, function() {
			var nm:String = judgeNameInput.text.trim();
			if (nm.length < 1) {
				notify('Enter a tier name', false);
				return;
			}
			if (cfg().judgements == null)
				cfg().judgements = {};
			Reflect.setField(cfg().judgements, nm, {image: judgeImageInput.text.trim(), window: judgeWindowStep.value});
			commit();
			refreshJudgeList();
			notify('Tier "$nm" set @ ${judgeWindowStep.value}ms');
		}, true);
		addBtn.y = 134;
		pane.content.addChild(addBtn);

		judgeListDrop = new UIDropdown('Existing:', rowW, function(id, name) {
			curJudge = name;
			if (name == '---')
				return;
			var node:Dynamic = Reflect.field(cfg().judgements, name);
			judgeNameInput.text = name;
			judgeImageInput.text = (node != null && Reflect.field(node, 'image') != null) ? Std.string(Reflect.field(node, 'image')) : name;
			judgeWindowStep.value = (node != null && Reflect.field(node, 'window') != null) ? Std.parseFloat(Std.string(Reflect.field(node, 'window'))) : 0;
		});
		judgeListDrop.y = 172;
		pane.content.addChild(judgeListDrop);

		var removeBtn:UIButton = new UIButton('Remove selected', 150, 26, function() {
			var nm:String = curJudge;
			if (nm == null || nm == '---' || cfg().judgements == null)
				return;
			Reflect.deleteField(cfg().judgements, nm);
			commit();
			refreshJudgeList();
			notify('Removed "$nm"');
		});
		removeBtn.danger = true;
		removeBtn.y = 206;
		pane.content.addChild(removeBtn);

		pane.refreshContent(242);

		refreshJudgeList();
	}

	function refreshJudgeList() {
		if (judgeListDrop == null)
			return;
		var names:Array<String> = (cfg().judgements != null) ? Reflect.fields(cfg().judgements) : [];
		if (names.length < 1)
			names = ['---'];
		judgeItems = names;
		judgeListDrop.setItems(names.copy());
		judgeListDrop.select(0);
		curJudge = names[0];
	}

	function refreshFields() {
		var c = cfg();
		if (aaCheck != null)
			aaCheck.checked = (c.antialiasing != false);
		if (pixelCheck != null)
			pixelCheck.checked = (c.pixel == true);
		if (pixelVarCheck != null)
			pixelVarCheck.checked = (c.pixelVariant == true);

		if (comboInput != null)
			comboInput.text = strOr(c, 'combo', '');
		if (numInput != null)
			numInput.text = strOr(c, 'num', '');
		if (readyInput != null)
			readyInput.text = strOr(c, 'ready', '');
		if (setInput != null)
			setInput.text = strOr(c, 'set', '');
		if (goInput != null)
			goInput.text = strOr(c, 'go', '');
		for (name in RATING_NAMES) {
			var inp = ratingInputs.get(name);
			if (inp != null)
				inp.text = (c.ratings != null && Reflect.field(c.ratings, name) != null) ? Std.string(Reflect.field(c.ratings, name)) : '';
		}
		loadMotion();
		refreshJudgeList();
		if (handleSpr.length > 0)
			positionHandles();
	}

	// ---- live preview ----

	inline function acquire():FlxSprite {
		var s:FlxSprite = (pool.length > 0) ? pool.pop() : new FlxSprite();
		s.revive();
		s.alpha = 1;
		s.scale.set(1, 1);
		s.angle = 0;
		s.velocity.set(0, 0);
		s.acceleration.set(0, 0);
		s.moves = true;
		previewGroup.add(s);
		return s;
	}

	function release(s:FlxSprite) {
		FlxTween.cancelTweensOf(s);
		previewGroup.remove(s, true);
		s.kill();
		pool.push(s);
	}

	// Replays the real judgement popup (rating + combo word + digits) with the in-edit config, so the
	// chosen images / tweens / velocities / custom tiers can be checked without launching a song.
	function firePreview(diffMs:Float, realName:String = 'sick') {
		commit();
		var twR = UISkinConfig.tweenFor('rating');
		var twC = UISkinConfig.tweenFor('combo');
		var twN = UISkinConfig.tweenFor('numbers');
		var vis:UIJudgement = UISkinConfig.pickVisual(diffMs, realName);
		var pl:UIPlacement = UISkinConfig.placement();
		var placement:Float = FlxG.width * pl.anchorX;

		var rating = acquire();
		var ratingFactor:Float = 1;
		var img = UISkinConfig.image(vis.image);
		if (img != null) {
			rating.loadGraphic(img.graphic);
			ratingFactor = img.factor;
		} else
			rating.loadGraphic(Paths.image(vis.image));
		rating.screenCenter();
		rating.x = placement + pl.rating[0];
		rating.y += pl.rating[1];
		rating.acceleration.y = UISkinConfig.tRange(twR, 'accelY', 550, 550);
		rating.velocity.y -= UISkinConfig.tRange(twR, 'velocityY', 140, 175);
		rating.velocity.x -= UISkinConfig.tRange(twR, 'velocityX', 0, 10);
		rating.setGraphicSize(Std.int(rating.width * UISkinConfig.tFloat(twR, 'scale', 0.7) * (vis.scale != null ? vis.scale : 1) * ratingFactor));
		rating.updateHitbox();
		FlxTween.tween(rating, {alpha: 0}, UISkinConfig.tFloat(twR, 'duration', 0.2), {
			ease: UISkinConfig.tEase(twR),
			startDelay: UISkinConfig.tStartDelay(twR, Conductor.crochet * 0.001),
			onComplete: function(_) release(rating)
		});

		// The "combo" word is hidden by default (matches gameplay, where showCombo is off). Toggle it on.
		var combo:FlxSprite = null;
		if (showComboWord) {
			combo = acquire();
			var comboFactor:Float = 1;
			var cimg = UISkinConfig.image('combo');
			if (cimg != null) {
				combo.loadGraphic(cimg.graphic);
				comboFactor = cimg.factor;
			} else
				combo.loadGraphic(Paths.image('combo'));
			combo.screenCenter();
			combo.acceleration.y = UISkinConfig.tRange(twC, 'accelY', 200, 300);
			combo.velocity.y -= UISkinConfig.tRange(twC, 'velocityY', 140, 160);
			combo.velocity.x += UISkinConfig.tRange(twC, 'velocityX', 1, 10);
			combo.setGraphicSize(Std.int(combo.width * UISkinConfig.tFloat(twC, 'scale', 0.7) * comboFactor));
			combo.updateHitbox();
			combo.y += pl.combo[1];
		}

		var sep:String = Std.string(sampleCombo).lpad('0', 3);
		var xThing:Float = 0;
		for (i in 0...sep.length) {
			var num = acquire();
			var nFactor:Float = 1;
			var nimg = UISkinConfig.image('num' + Std.parseInt(sep.charAt(i)));
			if (nimg != null) {
				num.loadGraphic(nimg.graphic);
				nFactor = nimg.factor;
			} else
				num.loadGraphic(Paths.image('num' + Std.parseInt(sep.charAt(i))));
			num.screenCenter();
			num.x = placement + (pl.numSpacing * i) + pl.numbers[0];
			num.y += pl.numbers[1];
			num.setGraphicSize(Std.int(num.width * UISkinConfig.tFloat(twN, 'scale', 0.5) * nFactor));
			num.updateHitbox();
			num.acceleration.y = UISkinConfig.tRange(twN, 'accelY', 200, 300);
			num.velocity.y -= UISkinConfig.tRange(twN, 'velocityY', 140, 160);
			num.velocity.x = UISkinConfig.tRange(twN, 'velocityX', -5, 5);
			FlxTween.tween(num, {alpha: 0}, UISkinConfig.tFloat(twN, 'duration', 0.2), {
				ease: UISkinConfig.tEase(twN),
				startDelay: UISkinConfig.tStartDelay(twN, Conductor.crochet * 0.002),
				onComplete: function(_) release(num)
			});
			if (num.x > xThing)
				xThing = num.x;
		}
		if (combo != null) {
			combo.x = xThing + pl.combo[0];
			FlxTween.tween(combo, {alpha: 0}, UISkinConfig.tFloat(twC, 'duration', 0.2), {
				ease: UISkinConfig.tEase(twC),
				startDelay: UISkinConfig.tStartDelay(twC, Conductor.crochet * 0.002),
				onComplete: function(_) release(combo)
			});
		}
	}

	function fireCountdown() {
		commit();
		var names:Array<String> = ['ready', 'set', 'go'];
		var step:Int = 0;
		new FlxTimer().start(Conductor.crochet / 1000, function(tmr:FlxTimer) {
			if (step < names.length)
				spawnCountdown(names[step]);
			step++;
		}, names.length);
	}

	function spawnCountdown(logical:String) {
		var spr = acquire();
		var img = UISkinConfig.image(logical);
		if (img != null)
			spr.loadGraphic(img.graphic);
		else
			spr.loadGraphic(Paths.image(logical));
		spr.updateHitbox();
		if (img != null && img.factor != 1)
			spr.setGraphicSize(Std.int(spr.width * img.factor));
		spr.screenCenter();
		FlxTween.tween(spr, {alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(_) release(spr)
		});
	}

	// ---- position hitboxes ----

	function buildHandles() {
		var sizes:Array<Array<Int>> = [[150, 64], [120, 50], [140, 50]];
		var cols:Array<Int> = [0x5500FF00, 0x5500CCFF, 0x55FFCC00];
		for (i in 0...handleElems.length) {
			var spr = new FlxSprite().makeGraphic(sizes[i][0], sizes[i][1], cols[i]);
			spr.scrollFactor.set();
			handleGroup.add(spr);
			handleSpr.push(spr);

			var lbl = new FlxText(0, 0, sizes[i][0], handleElems[i], 12);
			lbl.setFormat(font(), 12, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
			lbl.scrollFactor.set();
			handleGroup.add(lbl);
			handleLabels.push(lbl);
		}
		positionHandles();
	}

	// Reference frame the placement [x,y] is measured from: the anchor column X and the screen centre Y.
	inline function refX():Float
		return FlxG.width * UISkinConfig.placement().anchorX;

	inline function refY():Float
		return FlxG.height / 2;

	inline function placeOf(elem:String):Array<Float> {
		var pl = UISkinConfig.placement();
		return switch (elem) {
			case 'combo': pl.combo;
			case 'numbers': pl.numbers;
			default: pl.rating;
		}
	}

	function positionHandles() {
		handleGroup.visible = showHitboxes;
		var rx = refX();
		var ry = refY();
		for (i in 0...handleSpr.length) {
			var p = placeOf(handleElems[i]);
			handleSpr[i].x = rx + p[0];
			handleSpr[i].y = ry + p[1];
			handleLabels[i].x = handleSpr[i].x;
			handleLabels[i].y = handleSpr[i].y + handleSpr[i].height / 2 - 8;
			// The "combo" word is hidden by default, so its handle only shows when the word is enabled.
			var vis = showHitboxes && (handleElems[i] != 'combo' || showComboWord);
			handleSpr[i].visible = vis;
			handleLabels[i].visible = vis;
		}
	}

	// Drag result -> the element's placement [x,y] (relative to the anchor/centre), stored on the skin.
	function setHandleOffset(i:Int) {
		if (cfg().placement == null)
			cfg().placement = {};
		var px = Math.round(handleSpr[i].x - refX());
		var py = Math.round(handleSpr[i].y - refY());
		Reflect.setField(cfg().placement, handleElems[i], [px, py]);
		commit();
	}

	function updateHandles() {
		if (!showHitboxes || UIFocus.focused != null) {
			dragIndex = -1;
			return;
		}
		var overUI:Bool = (FlxG.mouse.x > boxX);
		if (dragIndex < 0 && FlxG.mouse.justPressed && !overUI) {
			for (i in 0...handleSpr.length) {
				if (!handleSpr[i].visible)
					continue;
				if (FlxG.mouse.overlaps(handleSpr[i])) {
					dragIndex = i;
					grabX = FlxG.mouse.x - handleSpr[i].x;
					grabY = FlxG.mouse.y - handleSpr[i].y;
					break;
				}
			}
		}
		if (dragIndex >= 0) {
			handleSpr[dragIndex].x = FlxG.mouse.x - grabX;
			handleSpr[dragIndex].y = FlxG.mouse.y - grabY;
			handleLabels[dragIndex].x = handleSpr[dragIndex].x;
			handleLabels[dragIndex].y = handleSpr[dragIndex].y + handleSpr[dragIndex].height / 2 - 8;
			setHandleOffset(dragIndex);
			if (FlxG.mouse.justReleased) {
				notify('${handleElems[dragIndex]} offset set');
				dragIndex = -1;
			}
		}
	}

	// ---- save ----

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
		if (hasShared)
			name += '-modified';
		#end
		return 'mods/images/uiSkins/$name';
	}

	function saveSkin() {
		#if sys
		var dir = saveDir();
		try {
			ensureDir(dir);
			sys.io.File.saveContent('$dir/skin.tcfg', backend.config.UiTcfgWriter.write(config));
			UISkinConfig.reset();
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
			sys.io.File.saveContent(path, backend.config.UiTcfgWriter.write(config));
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
		var dir = 'mods/images/uiSkins/$name';
		try {
			ensureDir(dir);
			config = defaultConfig();
			sys.io.File.saveContent('$dir/skin.tcfg', backend.config.UiTcfgWriter.write(config));
			UISkinConfig.reset();
			skinName = 'uiSkins/$name';
			skinItems = UISkinConfig.list();
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

	function notify(msg:String, good:Bool = true) {
		tipText.color = good ? FlxColor.LIME : FlxColor.RED;
		tipText.text = msg;
		notifyTimer = 4;
	}

	override function update(elapsed:Float) {
		// Drive the beat clock off the looping track so beatHit() fires (auto popup on beat).
		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		super.update(elapsed);
		updateHandles();
		infoText.text = 'UI Skin Editor - $skinName   |   ESC: editor menu';
		if (notifyTimer > 0) {
			notifyTimer -= elapsed;
			if (notifyTimer <= 0)
				tipText.color = FlxColor.YELLOW;
		}

		if (UIFocus.focused == null && !UIRoot.overlayOpen && controls.BACK) {
			UISkinConfig.editorOverride = null;
			UISkinConfig.reset();
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			MusicBeatState.switchState(new MasterEditorMenu());
		}
	}

	override function destroy() {
		UISkinConfig.editorOverride = null;
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

	// ---- small reflect helpers ----

	static function numOr(node:Dynamic, key:String, def:Float):Float {
		if (node == null)
			return def;
		var v:Dynamic = Reflect.field(node, key);
		if (v == null)
			return def;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
			return v;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	static function strOr(node:Dynamic, key:String, def:String):String {
		if (node == null)
			return def;
		var v:Dynamic = Reflect.field(node, key);
		return (v == null) ? def : Std.string(v);
	}

	static function rangeOr(node:Dynamic, key:String, defMin:Float, defMax:Float):Array<Float> {
		var v:Dynamic = (node != null) ? Reflect.field(node, key) : null;
		if (v == null)
			return [defMin, defMax];
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			var lo:Float = a.length > 0 ? Std.parseFloat(Std.string(a[0])) : defMin;
			var hi:Float = a.length > 1 ? Std.parseFloat(Std.string(a[1])) : lo;
			return [lo, hi];
		}
		var f:Float = Std.parseFloat(Std.string(v));
		return [f, f];
	}
}
