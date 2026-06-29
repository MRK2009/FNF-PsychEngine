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

using StringTools;

/**
	In-engine editor for UI skins (judgement popups / combo / numbers / countdown). Mirrors
	`NoteSkinEditorState`: a `PsychUIBox` with tabs, a folder-skin dropdown, save/create to
	`mods/images/uiSkins/<name>`, and a LIVE preview driven through `UISkinConfig.editorOverride` +
	`setConfig` so edits show immediately. The preview replays the real popup/countdown using the same
	`UISkinConfig` accessors `PlayState` uses, so what you tune is what you get.
**/
class UISkinEditorState extends MusicBeatState {
	var box:PsychUIBox;
	var config:UISkinData;
	var skinName:String = UISkinConfig.DEFAULT;

	var previewGroup:FlxSpriteGroup = new FlxSpriteGroup();
	var pool:Array<FlxSprite> = [];

	var skinDropDown:PsychUIDropDownMenu;
	var newNameInput:PsychUIInputText;
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
		if (!autoBeat || box == null)
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

	// ---- UI ----

	function addUI() {
		box = new PsychUIBox(FlxG.width - 340, 20, 330, 460, ['Skin', 'Images', 'Motion', 'Judgements']);
		box.canMove = box.canMinimize = true;
		box.scrollFactor.set();
		add(box);
		addSkinTab();
		addImagesTab();
		addMotionTab();
		addJudgementsTab();
	}

	function label(t:FlxSpriteGroup, x:Float, y:Float, text:String, size:Int = 12):FlxText {
		var f = new FlxText(x, y, 0, text, size);
		f.setFormat(font(), size, FlxColor.WHITE);
		t.add(f);
		return f;
	}

	function addSkinTab() {
		var t = box.getTab('Skin').menu;

		label(t, 10, 8, 'Folder skin:');
		var skins = UISkinConfig.list();
		if (skins.length < 1)
			skins.push(skinName);
		skinDropDown = new PsychUIDropDownMenu(10, 28, skins, function(id:Int, name:String) {
			loadSkin(name);
			refreshFields();
		});
		skinDropDown.selectedLabel = skinName;

		var reload = new PsychUIButton(10, 62, 'Reload', function() {
			UISkinConfig.reset();
			loadSkin(skinName);
			refreshFields();
		});
		reload.resize(90, 26);
		t.add(reload);

		var saveBtn = new PsychUIButton(110, 62, 'Save', saveSkin);
		saveBtn.resize(80, 26);
		t.add(saveBtn);

		var saveRootBtn = new PsychUIButton(200, 62, 'Save to game folder', saveToRoot);
		saveRootBtn.resize(120, 26);
		t.add(saveRootBtn);

		label(t, 10, 96, 'New skin name:', 11);
		newNameInput = new PsychUIInputText(115, 93, 120, 'skin', 8);
		t.add(newNameInput);
		var createBtn = new PsychUIButton(240, 91, 'Create', createNewSkin);
		createBtn.resize(70, 26);
		t.add(createBtn);

		// (per-element popup scale lives on the Motion tab; there's no separate "general" scale)
		aaCheck = new PsychUICheckBox(10, 129, 'Antialiasing', 110);
		aaCheck.onClick = function() {
			cfg().antialiasing = aaCheck.checked;
			commit();
		};
		t.add(aaCheck);

		pixelCheck = new PsychUICheckBox(10, 150, 'Pixel', 90);
		pixelCheck.onClick = function() {
			cfg().pixel = pixelCheck.checked;
			commit();
		};
		t.add(pixelCheck);

		pixelVarCheck = new PsychUICheckBox(110, 150, 'Pixel variant', 110);
		pixelVarCheck.onClick = function() {
			cfg().pixelVariant = pixelVarCheck.checked;
			commit();
		};
		t.add(pixelVarCheck);

		var autoBeatCheck = new PsychUICheckBox(10, 198, 'Auto popup on beat', 160);
		autoBeatCheck.checked = autoBeat;
		autoBeatCheck.onClick = function() autoBeat = autoBeatCheck.checked;
		t.add(autoBeatCheck);

		var hitboxCheck = new PsychUICheckBox(180, 198, 'Drag hitboxes', 130);
		hitboxCheck.checked = showHitboxes;
		hitboxCheck.onClick = function() {
			showHitboxes = hitboxCheck.checked;
			positionHandles();
		};
		t.add(hitboxCheck);

		var comboWordCheck = new PsychUICheckBox(10, 174, 'Show combo word', 150);
		comboWordCheck.checked = showComboWord;
		comboWordCheck.onClick = function() {
			showComboWord = comboWordCheck.checked;
			positionHandles();
		};
		t.add(comboWordCheck);

		var previewBtn = new PsychUIButton(10, 226, 'Preview Judgement', function() firePreview(20), 150);
		t.add(previewBtn);
		var previewMissBtn = new PsychUIButton(170, 226, 'Preview (loose)', function() firePreview(120), 130);
		t.add(previewMissBtn);
		var countdownBtn = new PsychUIButton(10, 256, 'Preview Countdown', fireCountdown, 150);
		t.add(countdownBtn);

		label(t, 10, 292, 'Saves to mods/images/uiSkins/<name>/', 11);

		t.add(skinDropDown);
	}

	var aaCheck:PsychUICheckBox;
	var pixelCheck:PsychUICheckBox;
	var pixelVarCheck:PsychUICheckBox;

	var comboInput:PsychUIInputText;
	var numInput:PsychUIInputText;
	var readyInput:PsychUIInputText;
	var setInput:PsychUIInputText;
	var goInput:PsychUIInputText;
	var ratingInputs:Map<String, PsychUIInputText> = new Map();

	function addImagesTab() {
		var t = box.getTab('Images').menu;

		comboInput = imageField(t, 10, 12, 'combo word:', function(v) {
			cfg().combo = v;
		});
		numInput = imageField(t, 10, 44, 'number prefix:', function(v) {
			cfg().num = v;
		});
		readyInput = imageField(t, 10, 76, 'ready:', function(v) {
			cfg().ready = v;
		});
		setInput = imageField(t, 10, 108, 'set:', function(v) {
			cfg().set = v;
		});
		goInput = imageField(t, 10, 140, 'go:', function(v) {
			cfg().go = v;
		});

		label(t, 10, 176, 'Rating images:', 12);
		var y:Float = 196;
		for (name in RATING_NAMES) {
			ratingInputs.set(name, imageField(t, 10, y, name + ':', function(v) {
				if (cfg().ratings == null)
					cfg().ratings = {};
				Reflect.setField(cfg().ratings, name, v);
				commit();
			}));
			y += 30;
		}
	}

	function imageField(t:FlxSpriteGroup, x:Float, y:Float, name:String, onSet:String->Void):PsychUIInputText {
		label(t, x, y, name, 11);
		var input = new PsychUIInputText(x + 110, y - 3, 160, '', 8);
		input.onChange = function(old:String, cur:String) {
			onSet(cur.trim());
			commit();
		};
		t.add(input);
		return input;
	}

	var motionElemDrop:PsychUIDropDownMenu;
	var mDuration:PsychUINumericStepper;
	var mStartDelay:PsychUINumericStepper;
	var mScale:PsychUINumericStepper;
	var mEaseDrop:PsychUIDropDownMenu;
	var mVelYMin:PsychUINumericStepper;
	var mVelYMax:PsychUINumericStepper;
	var mAccYMin:PsychUINumericStepper;
	var mAccYMax:PsychUINumericStepper;

	function addMotionTab() {
		var t = box.getTab('Motion').menu;

		label(t, 10, 10, 'Element:');
		motionElemDrop = new PsychUIDropDownMenu(80, 6, ELEMENTS.copy(), function(id, name) loadMotion());
		label(t, 10, 44, 'Duration (s):', 11);
		mDuration = new PsychUINumericStepper(110, 41, 0.05, 0.2, 0, 5, 2, 70);
		mDuration.onValueChange = function() applyMotion();
		t.add(mDuration);

		label(t, 10, 76, 'Start delay (0=auto):', 11);
		mStartDelay = new PsychUINumericStepper(120, 73, 0.01, 0, 0, 5, 3, 70);
		mStartDelay.onValueChange = function() applyMotion();
		t.add(mStartDelay);

		label(t, 10, 108, 'Scale:', 11);
		mScale = new PsychUINumericStepper(70, 105, 0.05, 0.7, 0.05, 8, 2, 70);
		mScale.onValueChange = function() applyMotion();
		t.add(mScale);

		label(t, 10, 140, 'Ease:');
		mEaseDrop = new PsychUIDropDownMenu(70, 136, EASES.copy(), function(id, name) applyMotion());

		label(t, 10, 176, 'Up velocity min/max:', 11);
		mVelYMin = new PsychUINumericStepper(10, 196, 5, 140, 0, 2000, 0, 70);
		mVelYMin.onValueChange = function() applyMotion();
		t.add(mVelYMin);
		mVelYMax = new PsychUINumericStepper(90, 196, 5, 160, 0, 2000, 0, 70);
		mVelYMax.onValueChange = function() applyMotion();
		t.add(mVelYMax);

		label(t, 10, 226, 'Gravity (accelY) min/max:', 11);
		mAccYMin = new PsychUINumericStepper(10, 246, 10, 200, 0, 4000, 0, 70);
		mAccYMin.onValueChange = function() applyMotion();
		t.add(mAccYMin);
		mAccYMax = new PsychUINumericStepper(90, 246, 10, 300, 0, 4000, 0, 70);
		mAccYMax.onValueChange = function() applyMotion();
		t.add(mAccYMax);

		t.add(motionElemDrop);
		t.add(mEaseDrop);
		motionElemDrop.selectedLabel = 'rating';
		loadMotion();
	}

	// The per-element block under config.tween, created on demand.
	function elemNode():Dynamic {
		if (cfg().tween == null)
			cfg().tween = {};
		var el:String = motionElemDrop.selectedLabel;
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
		var node:Dynamic = (cfg().tween != null) ? Reflect.field(cfg().tween, motionElemDrop.selectedLabel) : null;
		mDuration.value = numOr(node, 'duration', 0.2);
		mStartDelay.value = numOr(node, 'startDelay', 0);
		mScale.value = numOr(node, 'scale', 0.7);
		mEaseDrop.selectedLabel = strOr(node, 'ease', 'linear');
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
		Reflect.setField(node, 'ease', mEaseDrop.selectedLabel);
		Reflect.setField(node, 'velocityY', [mVelYMin.value, mVelYMax.value]);
		Reflect.setField(node, 'accelY', [mAccYMin.value, mAccYMax.value]);
		commit();
	}

	var judgeNameInput:PsychUIInputText;
	var judgeImageInput:PsychUIInputText;
	var judgeWindowStep:PsychUINumericStepper;
	var judgeListDrop:PsychUIDropDownMenu;

	function addJudgementsTab() {
		var t = box.getTab('Judgements').menu;

		label(t, 10, 8, 'Custom visual rating tiers (image swap by hit ms).', 11);
		label(t, 10, 24, 'They do NOT change scoring/combo.', 11);

		label(t, 10, 52, 'Name:', 11);
		judgeNameInput = new PsychUIInputText(70, 49, 110, 'perfect', 8);
		t.add(judgeNameInput);
		label(t, 10, 84, 'Image:', 11);
		judgeImageInput = new PsychUIInputText(70, 81, 110, 'perfect', 8);
		t.add(judgeImageInput);
		label(t, 10, 116, 'Window (ms):', 11);
		judgeWindowStep = new PsychUINumericStepper(110, 113, 1, 22.5, 0, 500, 2, 80);
		t.add(judgeWindowStep);

		var addBtn = new PsychUIButton(10, 146, 'Add / Update', function() {
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
		}, 110);
		t.add(addBtn);

		label(t, 10, 186, 'Existing:', 11);
		judgeListDrop = new PsychUIDropDownMenu(75, 182, ['---'], function(id, name) {
			if (name == '---')
				return;
			var node:Dynamic = Reflect.field(cfg().judgements, name);
			judgeNameInput.text = name;
			judgeImageInput.text = (node != null && Reflect.field(node, 'image') != null) ? Std.string(Reflect.field(node, 'image')) : name;
			judgeWindowStep.value = (node != null && Reflect.field(node, 'window') != null) ? Std.parseFloat(Std.string(Reflect.field(node, 'window'))) : 0;
		});
		var removeBtn = new PsychUIButton(10, 216, 'Remove selected', function() {
			var nm:String = judgeListDrop.selectedLabel;
			if (nm == null || nm == '---' || cfg().judgements == null)
				return;
			Reflect.deleteField(cfg().judgements, nm);
			commit();
			refreshJudgeList();
			notify('Removed "$nm"');
		}, 130);
		t.add(removeBtn);

		t.add(judgeListDrop);
		refreshJudgeList();
	}

	function refreshJudgeList() {
		if (judgeListDrop == null)
			return;
		var names:Array<String> = (cfg().judgements != null) ? Reflect.fields(cfg().judgements) : [];
		if (names.length < 1)
			names = ['---'];
		judgeListDrop.list = names;
		judgeListDrop.selectedLabel = names[0];
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
		if (!showHitboxes || PsychUIInputText.focusOn != null) {
			dragIndex = -1;
			return;
		}
		var overUI:Bool = (box != null && FlxG.mouse.x > box.x);
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
			skinDropDown.list = UISkinConfig.list();
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

		if (PsychUIInputText.focusOn == null && controls.BACK) {
			UISkinConfig.editorOverride = null;
			UISkinConfig.reset();
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			MusicBeatState.switchState(new MasterEditorMenu());
		}
	}

	override function destroy() {
		UISkinConfig.editorOverride = null;
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
