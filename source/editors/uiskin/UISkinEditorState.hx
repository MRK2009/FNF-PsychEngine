package editors.uiskin;

import backend.UISkinConfig;
import backend.UISkinConfig.UISkinData;
import backend.UISkinConfig.UIJudgement;
import backend.uiskin.UISkinService;
import editors.content.DockFlow;
import flixel.input.keyboard.FlxKey;
import smidr.UIComponent;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.flixel.FlxSmidr;
import smidr.input.UIFocus;
import smidr.overlays.UIToast;
import smidr.overlays.UITooltip;
import smidr.types.UIMenuItem;
import smidr.types.UIRailTabDef;
import smidr.widgets.UIAccordion;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UIDropdown;
import smidr.widgets.UILabel;
import smidr.widgets.UIList;
import smidr.widgets.UIModal;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;

using StringTools;

/**
	The UI-skin editor: an editor-shaped tool (menu bar, activity rail, docks, transport, status bar)
	wrapped around a LIVE popup preview.

	Built to the same shape as `editors.noteskin.NoteSkinEditorState`, and for the same reason: the
	preview runs through `backend.uiskin.UISkinService`, the provider gameplay draws through, so what
	you tune is what you get and a classic or legacy skin previews as it will play. Every widget
	writes into the `UISkinDraft` and re-commits it live -- there is no Apply step.

	Handles all three skin kinds: modern config folders, classic art-only folders/atlases, and the
	base `stageUI` assets.
**/
class UISkinEditorState extends MusicBeatState {
	static inline var TAB_SKIN:Int = 0;
	static inline var TAB_IMAGES:Int = 1;
	static inline var TAB_MOTION:Int = 2;
	static inline var TAB_PLACE:Int = 3;
	static inline var TAB_JUDGE:Int = 4;
	static inline var TAB_PIXEL:Int = 5;

	static final BPM_STEPS:Array<Float> = [90, 120, 150, 180, 210];
	static final COMBO_STEPS:Array<Int> = [7, 42, 123, 456, 789, 1000];
	static final RATING_NAMES:Array<String> = ['sick', 'good', 'bad', 'shit'];
	static final ELEMENTS:Array<String> = ['rating', 'combo', 'numbers'];
	static final EASES:Array<String> = [
		'linear', 'sineIn', 'sineOut', 'sineInOut', 'quadIn', 'quadOut', 'quadInOut', 'cubeOut', 'expoOut', 'backOut', 'elasticOut', 'bounceOut'
	];

	var draft:UISkinDraft = new UISkinDraft();
	var sim:UISkinSim = new UISkinSim();

	var uiRoot:UIRoot;
	var shell:UISkinShell;

	var started:Bool = false;
	var curTab:Int = TAB_SKIN;
	var curElem:Int = 0;
	var pixelPreview:Bool = false;
	var bpm:Float = 150;
	var beatTimer:Float = 0;

	inline function P(v:Float):Float
		return UITheme.px(v);

	override function create() {
		FlxG.mouse.visible = true;
		FlxG.sound.volumeUpKeys = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys = [];

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('UI Skin Editor');
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.scrollFactor.set();
		bg.color = 0xFF15151F;
		add(bg);

		add(sim.group);
		add(sim.handleGroup);
		sim.onPlacementChanged = function(_:String):Void {
			draft.touch();
			commit();
			if (curTab == TAB_PLACE)
				buildLeftDock();
			syncStatus();
		};

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');
		#if mobile
		UITheme.applyMobilePreset();
		#end
		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		UITooltip.install(); // without this every `tooltip` we set is silently inert

		shell = new UISkinShell(uiRoot, FlxG.width, FlxG.height);
		buildMenus();
		bindTransport();
		shell.rail.setTabs(railTabs());
		shell.rail.onSelect = function(i:Int):Void {
			curTab = i;
			buildLeftDock();
			buildRightDock();
		};
		shell.rail.select(TAB_SKIN);

		super.create();
		openEntryModal();
	}

	function railTabs():Array<UIRailTabDef> {
		return [
			{label: 'SKIN', tooltipFallback: 'Skin and files'},
			{label: 'IMG', tooltipFallback: 'Image names'},
			{label: 'MOTION', tooltipFallback: 'Tween duration, ease, velocity'},
			{label: 'PLACE', tooltipFallback: 'Anchor, spacing and offsets'},
			{label: 'JUDGE', tooltipFallback: 'Custom visual rating tiers'},
			{label: 'PIX', tooltipFallback: 'Pixel mode'}
		];
	}

	// ---- menus ----

	function buildMenus():Void {
		shell.menuBar.setMenus([
			{
				title: 'File',
				items: function():Array<UIMenuItem> return [
					{label: 'New skin...', onSelect: function():Void openTypeModal()},
					{label: 'Open skin...', onSelect: function():Void openPickModal()},
					{separator: true},
					{label: 'Save', shortcut: 'Ctrl+S', onSelect: doSave},
					{label: 'Duplicate...', onSelect: openDuplicateModal},
					{label: 'Reload from disk', onSelect: reloadFromDisk},
					{separator: true},
					{label: 'Exit', onSelect: tryLeave}
				]
			},
			{
				title: 'Edit',
				items: function():Array<UIMenuItem> return [
					{
						label: 'Clear this element\'s motion',
						onSelect: function():Void {
							if (!started)
								return;
							if (cfg().tween != null)
								Reflect.deleteField(cfg().tween, ELEMENTS[curElem]);
							draft.touch();
							commit();
							buildLeftDock();
						}
					},
					{
						label: 'Clear placement',
						onSelect: function():Void {
							if (!started)
								return;
							Reflect.setField(cfg(), 'placement', null);
							draft.touch();
							commit();
							sim.positionHandles();
							buildLeftDock();
						}
					}
				]
			},
			{
				title: 'View',
				items: function():Array<UIMenuItem> return [
					{
						label: shell.rightHidden ? 'Show inspector' : 'Hide inspector',
						onSelect: function():Void {
							shell.setRightHidden(!shell.rightHidden);
							buildMenus();
						}
					},
					{
						label: sim.showHandles ? 'Hide placement handles' : 'Show placement handles',
						onSelect: function():Void {
							sim.showHandles = !sim.showHandles;
							shell.handlesChip.on = sim.showHandles;
							buildMenus();
						}
					},
					{
						label: sim.showComboWord ? 'Hide the "combo" word' : 'Show the "combo" word',
						onSelect: function():Void {
							sim.showComboWord = !sim.showComboWord;
							sim.positionHandles();
							buildMenus();
						}
					},
					{
						label: pixelPreview ? 'Stop pixel preview' : 'Preview as pixel stage',
						onSelect: function():Void {
							pixelPreview = !pixelPreview;
							shell.pixelChip.on = pixelPreview;
							applyPixelPreview();
						}
					}
				]
			},
			{title: 'Help', items: function():Array<UIMenuItem> return [{label: 'About UI skins', onSelect: openHelpModal}]}
		]);
	}

	function bindTransport():Void {
		shell.playBtn.onClick = function():Void shell.playing = !shell.playing;
		shell.restartBtn.onClick = function():Void {
			sim.clear();
			beatTimer = 0;
			sim.firePopup(previewDiff());
		};
		shell.judgeChip.onClick = function():Void {
			var names:Array<String> = ratingChoices();
			var i:Int = names.indexOf(sim.ratingName) + 1;
			sim.ratingName = names[i % names.length];
			syncTransport();
		};
		shell.comboChip.onClick = function():Void {
			var i:Int = COMBO_STEPS.indexOf(sim.comboCount) + 1;
			sim.comboCount = COMBO_STEPS[i % COMBO_STEPS.length];
			syncTransport();
		};
		shell.bpmChip.onClick = function():Void {
			var i:Int = BPM_STEPS.indexOf(bpm) + 1;
			bpm = BPM_STEPS[i % BPM_STEPS.length];
			Conductor.bpm = bpm;
			syncTransport();
		};
		shell.handlesChip.onToggle = function(v:Bool):Void {
			sim.showHandles = v;
			buildMenus();
		};
		shell.pixelChip.onToggle = function(v:Bool):Void {
			pixelPreview = v;
			applyPixelPreview();
		};
		shell.staticChip.onToggle = function(v:Bool):Void {
			sim.staticHold = v;
			shell.playing = !v;
			if (v) {
				sim.clear();
				sim.firePopup(previewDiff());
			}
			syncTransport();
		};
	}

	/**
		Pixel preview borrows `PlayState.stageUI`, which is what every tier reads to decide between the
		normal and pixel asset paths. Restored on exit.
	**/
	function applyPixelPreview():Void {
		PlayState.stageUI = pixelPreview ? 'pixel' : 'normal';
		UISkinService.reset();
		sim.clear();
		syncTransport();
	}

	/**
		The hit offset that makes `pickVisual` return the tier the JUDGE chip names.

		`pickVisual` selects by WINDOW, not by name -- it returns the first tier whose window contains
		the offset -- so asking for a tier means handing it an offset only that tier contains: its own
		window exactly, since every tighter tier's window is smaller and fails. For a plain rating with
		no tier of its own, anything past the widest window falls through to the rating itself.
	**/
	function previewDiff():Float {
		var tiers:Array<UIJudgement> = draft.judgementList();
		var widest:Float = 0;
		for (t in tiers) {
			if (t.name == sim.ratingName)
				return t.window;
			if (t.window > widest)
				widest = t.window;
		}
		return widest + 1;
	}

	function ratingChoices():Array<String> {
		var out:Array<String> = RATING_NAMES.copy();
		for (j in draft.judgementList())
			if (!out.contains(j.name))
				out.push(j.name);
		return out;
	}

	function syncTransport():Void {
		shell.judgeChip.label = sim.ratingName;
		shell.comboChip.label = 'Combo ${sim.comboCount}';
		shell.bpmChip.label = 'BPM ${Std.int(bpm)}';
		syncStatus();
	}

	// ---- live commit ----

	inline function cfg():Dynamic
		return cast draft.config;

	/** Pushes the draft into the config cache so the preview picks it up with no Apply step. **/
	function commit():Void {
		if (draft.name == null)
			return;
		UISkinConfig.setConfig(draft.name, draft.config);
		UISkinConfig.editorOverride = draft.name;
		UISkinService.reset();
	}

	function beginEditing(name:String):Void {
		draft.load(name);
		started = true;
		commit();
		sim.clear();
		sim.positionHandles();
		buildLeftDock();
		buildRightDock();
		shell.rail.setTabs(railTabs());
		syncTransport();
	}

	// ---- docks ----

	function clearPane(pane:UIScrollPane):Void {
		var i:Int = pane.content.numChildren;
		while (--i >= 0) {
			var c = pane.content.getChildAt(i);
			if (c is UIComponent)
				(cast c : UIComponent).dispose();
		}
		pane.content.removeChildren();
	}

	function buildLeftDock():Void {
		if (shell == null)
			return;
		clearPane(shell.leftPane);
		if (!started)
			return;

		var flow:DockFlow = new DockFlow(shell.leftPane, P(12), P(8));
		switch (curTab) {
			case TAB_IMAGES:
				buildImagesPanel(flow);
			case TAB_MOTION:
				buildMotionPanel(flow);
			case TAB_PLACE:
				buildPlacePanel(flow);
			case TAB_JUDGE:
				buildJudgePanel(flow);
			case TAB_PIXEL:
				buildPixelPanel(flow);
			default:
				buildSkinPanel(flow);
		}
		flow.reflow();
	}

	inline function rowW():Float
		return shell.leftW - P(24);

	function label(flow:DockFlow, text:String, size:Int = 11, tone:Int = 2):Void {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = rowW();
		flow.add(l);
	}

	function textRow(flow:DockFlow, caption:String, value:String, onSet:String->Void):UITextInput {
		var input:UITextInput = new UITextInput(caption, rowW(), value != null ? value : '');
		input.controlWidth = rowW() - P(110);
		input.onChange = function(v:String):Void {
			onSet(v);
			draft.touch();
			commit();
			syncStatus();
		};
		flow.add(input);
		return input;
	}

	function numRow(flow:DockFlow, caption:String, value:Float, step:Float, onSet:Float->Void):UIStepper {
		var st:UIStepper = new UIStepper(caption, rowW(), value, step);
		st.onChange = function(v:Float):Void {
			onSet(v);
			draft.touch();
			commit();
			syncStatus();
		};
		flow.add(st);
		return st;
	}

	function buildSkinPanel(flow:DockFlow):Void {
		flow.header(new UIAccordion('Skin', rowW()));
		label(flow, draft.name, 12, 0);
		label(flow, draft.fromBase ? 'Base game skin -- Duplicate before editing.' : 'Folder: ${draft.dir}');

		var list:Array<String> = UISkinConfig.list();
		var drop:UIDropdown = new UIDropdown('Skin', rowW(), function(i:Int, v:String):Void {
			if (v != draft.name)
				confirmDiscard(function():Void beginEditing(v));
		});
		drop.setItems(list.copy());
		drop.select(Std.int(Math.max(0, list.indexOf(draft.name))));
		flow.add(drop);

		flow.add(new UIButton('New skin...', rowW(), P(28), function():Void openTypeModal()));
		flow.add(new UIButton('Duplicate...', rowW(), P(28), openDuplicateModal));
		flow.add(new UIButton('Save', rowW(), P(30), doSave, true));
	}

	function buildImagesPanel(flow:DockFlow):Void {
		flow.header(new UIAccordion('Elements', rowW()));
		label(flow, 'Image file names, without the extension.');

		textRow(flow, 'combo', cfg().combo, function(v) cfg().combo = v);
		textRow(flow, 'num prefix', cfg().num, function(v) cfg().num = v);
		textRow(flow, 'ready', cfg().ready, function(v) cfg().ready = v);
		textRow(flow, 'set', cfg().set, function(v) cfg().set = v);
		textRow(flow, 'go', cfg().go, function(v) cfg().go = v);

		flow.header(new UIAccordion('Ratings', rowW()));
		label(flow, 'Which image each rating draws.');
		for (name in RATING_NAMES) {
			var key:String = name;
			var cur:String = name;
			if (cfg().ratings != null && Reflect.hasField(cfg().ratings, key))
				cur = Std.string(Reflect.field(cfg().ratings, key));
			textRow(flow, name, cur, function(v) {
				if (cfg().ratings == null)
					cfg().ratings = {};
				Reflect.setField(cfg().ratings, key, v);
			});
		}
	}

	function buildMotionPanel(flow:DockFlow):Void {
		flow.header(new UIAccordion('Element', rowW()));
		var drop:UIDropdown = new UIDropdown('Element', rowW(), function(i:Int, _:String):Void {
			curElem = i;
			buildLeftDock();
		});
		drop.setItems(ELEMENTS.copy());
		drop.select(curElem);
		flow.add(drop);

		var elem:String = ELEMENTS[curElem];
		var node:Dynamic = motionNode(elem);

		flow.header(new UIAccordion('Motion', rowW()));
		label(flow, 'Blank uses the engine default for this element.');
		numRow(flow, 'duration', numOf(node, 'duration', 0.2), 0.05, function(v) setMotion(elem, 'duration', v));
		numRow(flow, 'scale', numOf(node, 'scale', curElem == 2 ? 0.5 : 0.7), 0.05, function(v) setMotion(elem, 'scale', v));
		numRow(flow, 'velocityY', numOf(node, 'velocityY', 140), 5, function(v) setMotion(elem, 'velocityY', v));
		numRow(flow, 'velocityX', numOf(node, 'velocityX', 0), 1, function(v) setMotion(elem, 'velocityX', v));
		numRow(flow, 'accelY', numOf(node, 'accelY', 300), 10, function(v) setMotion(elem, 'accelY', v));
		numRow(flow, 'startDelay', numOf(node, 'startDelay', 0), 0.01, function(v) setMotion(elem, 'startDelay', v));

		var easeDrop:UIDropdown = new UIDropdown('ease', rowW(), function(i:Int, v:String):Void {
			setMotion(elem, 'ease', v);
			draft.touch();
			commit();
		});
		easeDrop.setItems(EASES.copy());
		var curEase:String = (node != null && Reflect.hasField(node, 'ease')) ? Std.string(Reflect.field(node, 'ease')) : 'linear';
		easeDrop.select(Std.int(Math.max(0, EASES.indexOf(curEase))));
		flow.add(easeDrop);
	}

	function motionNode(elem:String):Dynamic {
		if (cfg().tween == null)
			return null;
		return Reflect.hasField(cfg().tween, elem) ? Reflect.field(cfg().tween, elem) : cfg().tween;
	}

	function numOf(node:Dynamic, key:String, def:Float):Float {
		if (node == null || !Reflect.hasField(node, key))
			return def;
		var v:Float = Std.parseFloat(Std.string(Reflect.field(node, key)));
		return Math.isNaN(v) ? def : v;
	}

	function setMotion(elem:String, key:String, value:Dynamic):Void {
		if (cfg().tween == null)
			cfg().tween = {};
		if (!Reflect.hasField(cfg().tween, elem))
			Reflect.setField(cfg().tween, elem, {});
		Reflect.setField(Reflect.field(cfg().tween, elem), key, value);
	}

	function buildPlacePanel(flow:DockFlow):Void {
		flow.header(new UIAccordion('Anchor', rowW()));
		var pl = UISkinConfig.placement();
		numRow(flow, 'anchorX', pl.anchorX, 0.01, function(v) setPlace('anchorX', v));
		numRow(flow, 'numSpacing', pl.numSpacing, 1, function(v) setPlace('numSpacing', v));

		flow.header(new UIAccordion('Offsets', rowW()));
		label(flow, 'Or drag them on screen with Handles on.');
		for (elem in ELEMENTS) {
			var e:String = elem;
			var xy:Array<Float> = switch (e) {
				case 'combo': pl.combo;
				case 'numbers': pl.numbers;
				default: pl.rating;
			}
			numRow(flow, '$e x', xy[0], 1, function(v) setPlaceXY(e, 0, v));
			numRow(flow, '$e y', xy[1], 1, function(v) setPlaceXY(e, 1, v));
		}
	}

	function setPlace(key:String, v:Float):Void {
		if (cfg().placement == null)
			cfg().placement = {};
		Reflect.setField(cfg().placement, key, v);
		sim.positionHandles();
	}

	function setPlaceXY(elem:String, index:Int, v:Float):Void {
		if (cfg().placement == null)
			cfg().placement = {};
		var cur:Dynamic = Reflect.field(cfg().placement, elem);
		var arr:Array<Float> = (cur != null && (cur is Array)) ? cast cur : [0, 0];
		arr[index] = v;
		Reflect.setField(cfg().placement, elem, arr);
		sim.positionHandles();
	}

	function buildJudgePanel(flow:DockFlow):Void {
		flow.header(new UIAccordion('Visual tiers', rowW()));
		label(flow, 'A display-only swap: shown when the hit is inside its window. Scoring is unchanged.');

		var tiers:Array<UIJudgement> = draft.judgementList();
		if (tiers.length == 0)
			label(flow, 'None yet.', 11, 2);

		for (t in tiers) {
			var tier:UIJudgement = t;
			flow.header(new UIAccordion(tier.name, rowW()));
			textRow(flow, 'image', tier.image, function(v) setTier(tier.name, 'image', v));
			numRow(flow, 'window (ms)', tier.window, 1, function(v) setTier(tier.name, 'window', v));
			flow.add(new UIButton('Remove ${tier.name}', rowW(), P(26), function():Void {
				if (cfg().judgements != null)
					Reflect.deleteField(cfg().judgements, tier.name);
				draft.touch();
				commit();
				buildLeftDock();
				syncTransport();
			}));
		}

		var nameIn:UITextInput = new UITextInput('New tier', rowW(), '');
		nameIn.controlWidth = rowW() - P(110);
		flow.add(nameIn);
		flow.add(new UIButton('Add tier', rowW(), P(28), function():Void {
			var n:String = nameIn.text.trim();
			if (n.length < 1) {
				UIToast.show('Enter a tier name first');
				return;
			}
			if (cfg().judgements == null)
				cfg().judgements = {};
			Reflect.setField(cfg().judgements, n, {image: n, window: 20});
			draft.touch();
			commit();
			buildLeftDock();
			syncTransport();
		}));
	}

	function setTier(name:String, key:String, value:Dynamic):Void {
		if (cfg().judgements == null)
			cfg().judgements = {};
		if (!Reflect.hasField(cfg().judgements, name))
			Reflect.setField(cfg().judgements, name, {});
		Reflect.setField(Reflect.field(cfg().judgements, name), key, value);
	}

	function buildPixelPanel(flow:DockFlow):Void {
		flow.header(new UIAccordion('Pixel', rowW()));
		label(flow, 'Pixel art lives in a `pixel/` subfolder or under a `-pixel` suffix.');

		var pixelBox:UICheckbox = new UICheckbox('pixel', rowW(), cfg().pixel == true, function(v:Bool):Void {
			cfg().pixel = v;
			draft.touch();
			commit();
		});
		flow.add(pixelBox);

		var variantBox:UICheckbox = new UICheckbox('pixelVariant', rowW(), cfg().pixelVariant == true, function(v:Bool):Void {
			cfg().pixelVariant = v;
			draft.touch();
			commit();
		});
		variantBox.tooltip = 'Auto-selected on pixel stages when the chosen skin has no pixel art';
		flow.add(variantBox);

		var aaBox:UICheckbox = new UICheckbox('antialiasing', rowW(), cfg().antialiasing != false, function(v:Bool):Void {
			cfg().antialiasing = v;
			draft.touch();
			commit();
		});
		flow.add(aaBox);
	}

	function buildRightDock():Void {
		if (shell == null || shell.rightHidden)
			return;
		clearPane(shell.rightPane);
		if (!started)
			return;

		var flow:DockFlow = new DockFlow(shell.rightPane, P(12), P(6));
		flow.header(new UIAccordion('Resolved', shell.rightW - P(24)));

		var l:UILabel = new UILabel(UISkinConfig.isSkin(draft.name) ? 'skin.tcfg found' : 'no skin.tcfg -- base values in use', 11, 0);
		l.wrapWidth = shell.rightW - P(24);
		flow.add(l);

		// Which elements this skin actually provides, versus which fall through to another tier. This
		// is the thing you cannot see by looking at the popup.
		for (key in ['combo', 'num0', 'ready', 'set', 'go'])
			flow.add(coverageRow(key, UISkinConfig.image(key) != null));
		for (name in RATING_NAMES)
			flow.add(coverageRow(name, UISkinConfig.image(name) != null));

		flow.reflow();
	}

	function coverageRow(key:String, own:Bool):UILabel {
		var l:UILabel = new UILabel((own ? '+ ' : '- ') + key + (own ? '' : '   (falls back)'), 10, own ? 0 : 2);
		l.wrapWidth = shell.rightW - P(24);
		return l;
	}

	function syncStatus():Void {
		if (shell == null)
			return;
		shell.statusLeft.text = (draft.name != null ? draft.name : 'no skin loaded') + (draft.dirty ? ' *' : '');
		shell.statusLeft.render();
		shell.skinLabel.text = (draft.name != null) ? draft.shortName() : '-';
		shell.layoutMenuExtras();
	}

	// ---- files ----

	function doSave():Void {
		if (!started)
			return;
		if (draft.fromBase) {
			UIToast.show('Base game skin - use Duplicate first');
			openDuplicateModal();
			return;
		}
		var err:String = draft.save();
		if (err != null) {
			UIToast.show('Save failed: $err');
			return;
		}
		UISkinConfig.reset();
		commit();
		UIToast.show('Saved ${draft.dir}/skin.tcfg');
		syncStatus();
	}

	function reloadFromDisk():Void {
		if (!started)
			return;
		confirmDiscard(function():Void {
			UISkinConfig.reset();
			UISkinService.reset();
			beginEditing(draft.name);
			UIToast.show('Reloaded ${draft.name}');
		});
	}

	function tryLeave():Void {
		confirmDiscard(function():Void {
			PlayState.stageUI = 'normal';
			UISkinConfig.editorOverride = null;
			UISkinConfig.reset();
			UISkinService.reset();
			MusicBeatState.switchState(new editors.MasterEditorMenu());
		});
	}

	/** Runs `onOk`, asking first when there are unsaved changes. **/
	function confirmDiscard(onOk:Void->Void):Void {
		if (!draft.dirty) {
			onOk();
			return;
		}
		var mw:Float = P(460);
		var modal:UIModal = new UIModal('Unsaved changes', mw, P(180));
		var y:Float = P(14);
		y += modalLabel(modal, mw, 'This skin has unsaved changes. Discard them?', y, 12, 0).height + P(10);

		var discard:UIButton = new UIButton('Discard', P(140), P(30), function():Void {
			modal.close();
			onOk();
		}, true);
		var save:UIButton = new UIButton('Save first', P(140), P(30), function():Void {
			modal.close();
			doSave();
			onOk();
		});
		finishModal(modal, mw, y, save, discard);
	}

	// ---- modals ----

	function modalLabel(modal:UIModal, mw:Float, text:String, y:Float, size:Int, tone:Int):UILabel {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = mw - P(32);
		l.x = P(16);
		l.y = y;
		l.render();
		modal.body.addChild(l);
		return l;
	}

	function finishModal(modal:UIModal, mw:Float, y:Float, left:UIButton, right:UIButton):Void {
		left.x = P(16);
		left.y = y + P(10);
		modal.body.addChild(left);
		right.x = mw - P(16) - right.w;
		right.y = left.y;
		modal.body.addChild(right);
		modal.open();
	}

	/** First thing shown: pick a skin to edit, or make one. **/
	function openEntryModal():Void {
		var list:Array<String> = UISkinConfig.list();
		if (list.length == 0) {
			openTypeModal();
			return;
		}
		openPickModal();
	}

	function openPickModal():Void {
		var list:Array<String> = UISkinConfig.list();
		if (list.length == 0) {
			UIToast.show('No UI skins found - make one first');
			openTypeModal();
			return;
		}

		var mw:Float = P(460);
		var modal:UIModal = new UIModal('Open skin', mw, P(360));
		var y:Float = P(14);

		var picked:String = list[0];
		var listBox:UIList = new UIList(mw - P(32), P(220));
		listBox.setItems(list.copy());
		listBox.onSelect = function(i:Int):Void picked = list[i];
		listBox.x = P(16);
		listBox.y = y;
		modal.body.addChild(listBox);
		y += P(228);

		var okBtn:UIButton = new UIButton('Edit', P(140), P(30), function():Void {
			modal.close();
			confirmDiscard(function():Void beginEditing(picked));
		}, true);
		var newBtn:UIButton = new UIButton('New skin...', P(140), P(28), function():Void {
			modal.close();
			openTypeModal();
		});
		finishModal(modal, mw, y, newBtn, okBtn);
	}

	function openTypeModal():Void {
		var mw:Float = P(480);
		var modal:UIModal = new UIModal('New skin', mw, P(220));
		var y:Float = P(14);

		var nameIn:UITextInput = new UITextInput('Name:', mw - P(32), UISkinDraft.suggestName('MyUI'));
		nameIn.controlWidth = mw - P(170);
		nameIn.x = P(16);
		nameIn.y = y;
		modal.body.addChild(nameIn);
		y += nameIn.h + P(10);
		y += modalLabel(modal, mw, 'Created in your current mod, with the vanilla element names.', y, 11, 2).height;

		var okBtn:UIButton = new UIButton('Create', P(150), P(30), function():Void {
			var short:String = nameIn.text.trim();
			if (short.length < 1) {
				UIToast.show('Enter a name first');
				return;
			}
			if (UISkinDraft.nameTaken(short)) {
				UIToast.show('A skin named "$short" already exists');
				return;
			}
			var dir:String = UISkinDraft.targetDir(short);
			UISkinDraft.ensureDir(dir);
			draft.name = 'uiSkins/$short';
			draft.config = UISkinDraft.defaultConfig();
			draft.dir = dir;
			draft.fromBase = false;
			var err:String = draft.save();
			if (err != null) {
				UIToast.show('Create failed: $err');
				return;
			}
			modal.close();
			UISkinConfig.reset();
			beginEditing(draft.name);
			UIToast.show('Created $dir/skin.tcfg');
		}, true);

		var cancelBtn:UIButton = new UIButton('Cancel', P(120), P(28), function():Void modal.close());
		finishModal(modal, mw, y, cancelBtn, okBtn);
	}

	function openDuplicateModal():Void {
		if (!started)
			return;
		var mw:Float = P(480);
		var modal:UIModal = new UIModal('Duplicate skin', mw, P(220));

		var y:Float = P(14);
		var nameIn:UITextInput = new UITextInput('New name:', mw - P(32), UISkinDraft.suggestName(draft.shortName() + 'Copy'));
		nameIn.controlWidth = mw - P(170);
		nameIn.x = P(16);
		nameIn.y = y;
		modal.body.addChild(nameIn);
		y += nameIn.h + P(10);
		y += modalLabel(modal, mw, 'Copies every file into your mod, then edits the copy.', y, 11, 2).height;

		var okBtn:UIButton = new UIButton('Duplicate', P(150), P(30), function():Void {
			var short:String = nameIn.text.trim();
			if (short.length < 1) {
				UIToast.show('Enter a name first');
				return;
			}
			if (UISkinDraft.nameTaken(short)) {
				UIToast.show('A skin named "$short" already exists');
				return;
			}
			var err:String = draft.duplicate(short);
			if (err != null) {
				UIToast.show('Duplicate failed: $err');
				return;
			}
			modal.close();
			UISkinConfig.reset();
			beginEditing(draft.name);
			UIToast.show('Now editing ${draft.name}');
		}, true);

		var cancelBtn:UIButton = new UIButton('Cancel', P(120), P(28), function():Void modal.close());
		finishModal(modal, mw, y, cancelBtn, okBtn);
	}

	function openHelpModal():Void {
		var mw:Float = P(560);
		var modal:UIModal = new UIModal('About UI skins', mw, P(340));
		var y:Float = P(14);
		var lines:Array<String> = [
			'A UI skin covers the judgement popups, the combo word and digits, and the ready/set/go countdown.',
			'',
			'A skin is a folder under uiSkins/ with a skin.tcfg. Without that config it is not a skin,',
			'and the base stageUI values are used instead.',
			'',
			'Anything your skin does not ship falls back: first to the engine Default skin, then to the',
			'base values. The inspector on the right shows which elements are yours and which fall back.'
		];
		for (line in lines)
			y += modalLabel(modal, mw, line, y, 11, line.startsWith('  ') ? 2 : 1).height + P(2);

		var okBtn:UIButton = new UIButton('Close', P(140), P(30), function():Void modal.close(), true);
		var docsBtn:UIButton = new UIButton('', P(1), P(1), function():Void {});
		docsBtn.visible = false;
		finishModal(modal, mw, y, docsBtn, okBtn);
	}

	// ---- loop ----

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (started) {
			sim.updateHandles(cfg());

			if (shell.playing && !sim.staticHold) {
				beatTimer += elapsed;
				var period:Float = 60 / bpm;
				if (beatTimer >= period) {
					beatTimer -= period;
					sim.firePopup(previewDiff());
				}
			}
		}

		if (UIFocus.focused == null) {
			if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S)
				doSave();
			if (FlxG.keys.justPressed.ESCAPE)
				tryLeave();
		}

		shell.statusRight.text = '${Std.int(FlxG.drawFramerate)} fps';
		shell.layoutStatus();
	}

	override function destroy() {
		PlayState.stageUI = 'normal';
		UISkinConfig.editorOverride = null;
		UISkinService.reset();
		sim.destroy();
		UITooltip.reset();
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
