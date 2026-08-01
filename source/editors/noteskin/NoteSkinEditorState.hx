package editors.noteskin;

import backend.skins.Pixel;
import backend.NoteSkinConfig;
import backend.noteskin.NoteSkinService;
import editors.content.DockFlow;
import editors.content.FileDialogHandler;
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
import smidr.widgets.UIRadioGroup;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIStepper;
import smidr.widgets.UITextInput;

using StringTools;

/**
	The note-skin editor: an editor-shaped tool (menu bar, activity rail, docks, transport, status bar)
	wrapped around a LIVE simulated chart.

	The preview is a real `NoteField` autoplaying a generated pattern through real `Receptor`s and
	`NoteSprite`/`SustainSprite` drawables, so it renders on the shipping gameplay path and cannot
	drift from it. Every widget writes into the `NoteSkinDraft` and restyles the running simulation in
	place -- there is no Apply step and the pattern never stops scrolling.

	Handles both skin families first-class: modern individual-image FOLDER skins and classic
	sparrow-ATLAS skins.
**/
class NoteSkinEditorState extends MusicBeatState {
	static inline var TAB_SKIN:Int = 0;
	static inline var TAB_IMAGES:Int = 1;
	static inline var TAB_LOOK:Int = 2;
	static inline var TAB_PIXEL:Int = 3;
	static inline var TAB_OFFSETS:Int = 4;
	static inline var TAB_OSU:Int = 5;

	static final BPM_STEPS:Array<Float> = [90, 120, 150, 180, 210];
	static final SPEED_STEPS:Array<Float> = [1.2, 1.8, 2.4, 3.0, 3.6];
	static final DIRS:Array<String> = ['left', 'down', 'up', 'right', 'square'];
	static final ELEM_LABELS:Array<String> = ['Note', 'Strum', 'Pressed', 'Confirm', 'Hold', 'End', 'Splash'];
	static final ELEM_FIELDS:Array<String> = ['notes', 'strums', 'pressed', 'confirm', 'holds', 'ends', 'splash'];
	static final MODE_LABELS:Array<String> = ['Shared', 'Per direction', 'Per column'];
	static final MAP_ELEMS:Array<String> = ['notes', 'holds', 'ends', 'strums', 'pressed', 'confirm', 'splash'];
	static final OFF_LABELS:Array<String> = ['Note', 'Strum', 'Hold', 'End', 'Splash'];
	static final OFF_FIELDS:Array<String> = ['noteOffsets', 'strumOffsets', 'holdOffsets', 'endOffsets', 'splashOffsets'];

	var draft:NoteSkinDraft = new NoteSkinDraft();
	var sim:NoteSkinSim = new NoteSkinSim();
	final fileDialog:FileDialogHandler = new FileDialogHandler();

	var uiRoot:UIRoot;
	var shell:NoteSkinShell;

	var started:Bool = false;
	var holdsOnTop:Bool = false;
	var restyleQueued:Float = -1;
	var pixelPreview:Bool = false;
	var curTab:Int = TAB_SKIN;

	var curElem:Int = 0;
	var curMode:Int = NoteSkinDraft.MODE_SHARED;
	var elemInputs:Array<UITextInput> = [];
	var elemInherited:Array<Bool> = [];

	var bakeColors:Int = 16;
	var bakeAlphaCut:Int = PixelArtBaker.ALPHA_HALF;

	var curOffElem:Int = 0;
	var curOffTarget:Int = 0;
	var offPerColumn:Bool = false;

	override function create() {
		FlxG.mouse.visible = true;
		FlxG.sound.volumeUpKeys = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys = [];

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Note Skin Editor');
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.scrollFactor.set();
		bg.color = 0xFF15151F;
		add(bg);

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');
		#if mobile
		UITheme.applyMobilePreset();
		#end
		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		UITooltip.install(); // without this every `tooltip` we set is silently inert

		shell = new NoteSkinShell(uiRoot, FlxG.width, FlxG.height);
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

	override function destroy() {
		NoteSkinConfig.editorOverride = null;
		Pixel.render = false;
		NoteSkinConfig.reset();
		NoteSkinService.reset();
		Mania.apply(Mania.DEFAULT);

		if (sim != null)
			sim.destroy();
		if (fileDialog != null)
			fileDialog.destroy();
		if (uiRoot != null) {
			UITooltip.reset();
			UIToast.reset();
			FlxSmidr.dispose();
			#if mobile
			UITheme.clearMobilePreset();
			#end
			uiRoot = null;
		}
		super.destroy();

		FlxG.sound.muteKeys = [FlxKey.ZERO];
		FlxG.sound.volumeDownKeys = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
		FlxG.sound.volumeUpKeys = [FlxKey.NUMPADPLUS, FlxKey.PLUS];
	}

	function leave():Void {
		MusicBeatState.switchState(new editors.MasterEditorMenu());
	}

	function railTabs():Array<UIRailTabDef> {
		return [
			{label: 'SKIN', tooltipFallback: 'Skin, keycount and files'},
			{label: 'IMG', tooltipFallback: draft.atlas ? 'Frame prefixes' : 'Image names'},
			{label: 'LOOK', tooltipFallback: 'Scale, angles, colouring'},
			{label: 'PIX', tooltipFallback: 'Pixel art mode'},
			{label: 'OFFS', tooltipFallback: 'Per-element offsets'},
			{label: 'OSU', tooltipFallback: 'osu!mania sizing & hit position'}
		];
	}

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
					{label: 'Clear this element', onSelect: function():Void {
						draft.setField(ELEM_FIELDS[curElem], null);
						restyle();
						buildLeftDock();
						buildRightDock();
					}},
					{label: 'Clear all offsets', onSelect: function():Void {
						for (f in OFF_FIELDS)
							Reflect.deleteField(draft.config, f);
						draft.touch();
						restyle();
						buildLeftDock();
					}}
				]
			},
			{
				title: 'View',
				items: function():Array<UIMenuItem> return [
					{label: shell.rightHidden ? 'Show inspector' : 'Hide inspector', onSelect: function():Void {
						shell.setRightHidden(!shell.rightHidden);
						relayoutField();
						buildRightDock();
					}},
					{label: sim.downScroll ? 'Upscroll' : 'Downscroll', onSelect: toggleScroll},
					{label: pixelPreview ? 'Stop pixel preview' : 'Preview as pixel stage', onSelect: togglePixelPreview}
				]
			},
			{
				title: 'Help',
				items: function():Array<UIMenuItem> return [
					{label: 'About note skins', onSelect: openHelpModal}
				]
			}
		]);
	}

	function bindTransport():Void {
		shell.playBtn.onClick = function():Void {
			shell.playing = !shell.playing;
			sim.playing = shell.playing;
		};
		shell.restartBtn.onClick = function():Void sim.restart();
		shell.bpmChip.onClick = function():Void {
			sim.bpm = cycle(BPM_STEPS, sim.bpm);
			rebuildSim();
		};
		shell.speedChip.onClick = function():Void {
			sim.speed = cycle(SPEED_STEPS, sim.speed);
			syncTransport();
		};
		shell.keysChip.onClick = function():Void {
			var next:Int = draft.keyCount + 1;
			if (next > Mania.MAX)
				next = Mania.MIN;
			setKeyCount(next);
		};
		shell.scrollChip.onToggle = function(v:Bool):Void setDownScroll(v);
		shell.staticChip.onToggle = function(v:Bool):Void {
			sim.setStatic(v);
			shell.playing = !v;
			sim.playing = !v;
			syncTransport();
		};
		shell.pixelChip.onToggle = function(v:Bool):Void {
			pixelPreview = v;
			restyle();
			syncTransport();
		};
	}

	static function cycle(steps:Array<Float>, current:Float):Float {
		var i:Int = steps.indexOf(current);
		return steps[(i + 1) % steps.length];
	}

	function toggleScroll():Void {
		setDownScroll(!sim.downScroll);
	}

	/** Flips scroll direction and moves the receptor line to the matching end of the field. **/
	function setDownScroll(down:Bool):Void {
		sim.downScroll = down;
		sim.place(fieldCenterX(), fieldLineY());
		syncTransport();
	}

	function togglePixelPreview():Void {
		pixelPreview = !pixelPreview;
		restyle();
		syncTransport();
	}

	function setKeyCount(count:Int):Void {
		draft.keyCount = count;
		draft.overriding = (count != Mania.DEFAULT) && (draft.sectionFor(count) != null);
		sim.keyCount = count;
		rebuildSim();
		buildLeftDock();
		buildRightDock();
	}

	/**
		Modal metrics, all theme-scaled. Every coordinate inside a modal MUST go through these: SmidrUI
		scales widget FONTS by `UITheme.scale` but takes box sizes raw, so hardcoded pixel positions
		overlap and overflow as soon as the theme is scaled up.
	**/
	static inline function P(base:Float):Float
		return UITheme.px(base);

	inline function modalTitleH():Float
		return P(40);

	/**
		Finishes a modal: sizes the panel to the content above, then lays the button row along its
		bottom (`left` anchored left, `right` anchored right). Sizing from content is what keeps the
		buttons from colliding with the last row at any theme scale.
		@param modal the modal being built
		@param mw the panel width
		@param contentBottom the y (body-local) just below the last content row
		@param left the left-anchored button, or null
		@param right the right-anchored button, or null
	**/
	function finishModal(modal:UIModal, mw:Float, contentBottom:Float, ?left:UIButton, ?right:UIButton):Void {
		var pad:Float = P(16);
		var rowY:Float = contentBottom + P(14);
		var btnH:Float = 0;
		if (left != null && left.h > btnH)
			btnH = left.h;
		if (right != null && right.h > btnH)
			btnH = right.h;

		modal.resize(mw, modalTitleH() + rowY + btnH + pad);
		if (left != null) {
			left.x = pad;
			left.y = rowY;
			modal.body.addChild(left);
		}
		if (right != null) {
			right.x = mw - pad - right.w;
			right.y = rowY;
			modal.body.addChild(right);
		}
		modal.open();
	}

	/** A body-local label, wrapped to the panel width so long hints can't spill outside it. **/
	function modalLabel(modal:UIModal, mw:Float, text:String, y:Float, size:Int = 12, tone:Int = 0):UILabel {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = mw - P(32);
		l.x = P(16);
		l.y = y;
		modal.body.addChild(l);
		l.render();
		return l;
	}

	function openEntryModal():Void {
		var mw:Float = P(420);
		var btnH:Float = P(34);
		var modal:UIModal = new UIModal('Note Skin Editor', mw, P(240));
		modal.dismissable = started;

		var y:Float = P(12);
		y += modalLabel(modal, mw, 'What would you like to do?', y).height + P(12);

		var newBtn:UIButton = new UIButton('Make new skin', mw - P(32), btnH, function():Void {
			modal.close();
			openTypeModal();
		}, true);
		newBtn.tooltip = 'Create a skin from a template';
		newBtn.x = P(16);
		newBtn.y = y;
		modal.body.addChild(newBtn);
		y += btnH + P(8);

		var editBtn:UIButton = new UIButton('Edit existing skin', mw - P(32), btnH, function():Void {
			modal.close();
			openPickModal();
		});
		editBtn.tooltip = 'Open one of your installed note skins';
		editBtn.x = P(16);
		editBtn.y = y;
		modal.body.addChild(editBtn);
		y += btnH;

		var backBtn:UIButton = new UIButton(started ? 'Cancel' : 'Back to editors', P(150), P(28), function():Void {
			modal.close();
			if (!started)
				leave();
		});
		finishModal(modal, mw, y, backBtn, null);
	}

	function openTypeModal():Void {
		var mw:Float = P(470);
		var btnH:Float = P(32);
		var modal:UIModal = new UIModal('New skin', mw, P(280));
		modal.dismissable = started;

		var y:Float = P(10);
		y += modalLabel(modal, mw, 'Which kind of skin?', y).height + P(10);

		var folderBtn:UIButton = new UIButton('Folder skin', mw - P(32), btnH, function():Void {
			modal.close();
			openCreateModal(false);
		}, true);
		folderBtn.tooltip = 'One image per element, named by you';
		folderBtn.x = P(16);
		folderBtn.y = y;
		modal.body.addChild(folderBtn);
		y += btnH + P(4);
		y += modalLabel(modal, mw, 'Individual image files per element (note.png, holdBody.png...). Cloned from the Default skin.', y, 11,
			2).height + P(10);

		var atlasBtn:UIButton = new UIButton('Atlas skin', mw - P(32), btnH, function():Void {
			modal.close();
			openCreateModal(true);
		});
		atlasBtn.tooltip = 'One sparrow sheet, routed by frame prefix';
		atlasBtn.x = P(16);
		atlasBtn.y = y;
		modal.body.addChild(atlasBtn);
		y += btnH + P(4);
		y += modalLabel(modal, mw, 'One sparrow sheet (.png + .xml) with frame prefixes. Cloned from the Legacy NOTE_assets template.', y, 11,
			2).height;

		var backBtn:UIButton = new UIButton('Back', P(120), P(28), function():Void {
			modal.close();
			openEntryModal();
		});
		finishModal(modal, mw, y, backBtn, null);
	}

	function openCreateModal(isAtlas:Bool):Void {
		var mw:Float = P(540);
		var modal:UIModal = new UIModal(isAtlas ? 'New atlas skin' : 'New folder skin', mw, P(300));
		modal.dismissable = started;

		var y:Float = P(12);
		var nameIn:UITextInput = new UITextInput('Name:', mw - P(32), NoteSkinDraft.suggestName('MySkin'));
		nameIn.controlWidth = mw - P(140);
		nameIn.tooltip = 'Folder name under images/noteSkins/';
		nameIn.x = P(16);
		nameIn.y = y;
		modal.body.addChild(nameIn);
		y += nameIn.h + P(10);

		var sheetDrop:UIDropdown = null;
		var browsed:String = null;
		var browseLabel:UILabel = null;

		if (isAtlas) {
			var sheets:Array<String> = NoteSkinDraft.listSheets();
			// The Legacy template leads the list and is preselected -- keeping it clones the whole
			// template folder (sheet + fully-routed config); anything else copies just that sheet in.
			if (!sheets.contains(NoteSkinDraft.LEGACY_SHEET))
				sheets.unshift(NoteSkinDraft.LEGACY_SHEET);
			sheetDrop = new UIDropdown('Sheet:', mw - P(32), null);
			sheetDrop.controlWidth = mw - P(140);
			sheetDrop.tooltip = 'The sparrow sheet copied into the new skin';
			sheetDrop.setItems(sheets.copy());
			var pref:Int = sheets.indexOf(NoteSkinDraft.LEGACY_SHEET);
			sheetDrop.select(pref < 0 ? 0 : pref);
			sheetDrop.x = P(16);
			sheetDrop.y = y;
			modal.body.addChild(sheetDrop);
			y += sheetDrop.h + P(8);

			browseLabel = modalLabel(modal, mw, 'Default = the Legacy NOTE_assets template.', y, 11, 2);
			y += browseLabel.height + P(6);

			var browseBtn:UIButton = new UIButton('Browse for .png...', P(210), P(28), function():Void {
				if (!fileDialog.completed)
					return;
				fileDialog.open('sheet.png', 'Pick a sparrow sheet', [new openfl.net.FileFilter('Sparrow sheet', '*.png')], function():Void {
					browsed = fileDialog.path.replace('\\', '/');
					browseLabel.text = 'Copying: ' + browsed.substr(browsed.lastIndexOf('/') + 1);
				});
			});
			browseBtn.tooltip = 'Copy an external sheet in instead';
			browseBtn.x = P(16);
			browseBtn.y = y;
			modal.body.addChild(browseBtn);
			y += browseBtn.h + P(8);
		}

		// Failures are reported INSIDE the modal. A toast alone reads as "the button did nothing",
		// because the modal stays open on the early-return paths below.
		var errLabel:UILabel = modalLabel(modal, mw, '', y, 11, 0);
		y += P(18);

		// Validate WHILE typing: a name clash is the one rejection that used to look like the Create
		// button doing nothing, so it has to be visible before the button is ever pressed.
		nameIn.onChange = function(v:String):Void {
			var short:String = v.trim();
			if (short.length > 0 && NoteSkinDraft.nameTaken(short))
				errLabel.text = '"$short" already exists - pick another name.';
			else
				errLabel.text = '';
		};

		var createBtn:UIButton = new UIButton('Create', P(140), P(30), function():Void {
			errLabel.text = '';
			var short:String = nameIn.text.trim();
			if (short.length < 1) {
				errLabel.text = 'Enter a skin name first.';
				return;
			}
			if (NoteSkinDraft.nameTaken(short)) {
				errLabel.text = '"$short" already exists - pick another name.';
				return;
			}
			var err:String = isAtlas ? NoteSkinDraft.scaffoldAtlas(short, sheetDrop == null ? null : sheetDrop.selectedValue,
				browsed) : NoteSkinDraft.scaffoldFolder(short);
			if (err != null) {
				errLabel.text = err;
				return;
			}
			modal.close();
			NoteSkinConfig.reset();
			beginEditing('noteSkins/$short');
			var notice:String = NoteSkinDraft.lastNotice;
			NoteSkinDraft.lastNotice = null;
			UIToast.show(notice != null ? notice : 'Created ${NoteSkinDraft.targetDir(short)}');
		}, true);

		var backBtn:UIButton = new UIButton('Back', P(120), P(28), function():Void {
			modal.close();
			openTypeModal();
		});
		finishModal(modal, mw, y, backBtn, createBtn);
	}

	function openPickModal():Void {
		var mw:Float = P(500);
		var mh:Float = P(440);
		var modal:UIModal = new UIModal('Open skin', mw, mh);
		modal.dismissable = started;

		var skins:Array<String> = NoteSkinConfig.list();
		if (skins.length < 1)
			modalLabel(modal, mw, 'No note skins found. Make a new one instead.', P(16));

		var labels:Array<String> = [
			for (s in skins)
				s + (NoteSkinConfig.isClassicSkin(s) ? '   [Atlas]' : '   [Folder]')
		];

		var list:UIList = new UIList(mw - P(32), mh - modalTitleH() - P(100));
		list.tooltip = 'Double-click a skin to open it';
		list.x = P(16);
		list.y = P(8);
		list.setItems(labels);
		if (skins.length > 0)
			list.select(0);
		list.onActivate = function(i:Int):Void {
			modal.close();
			beginEditing(skins[i]);
		};
		modal.body.addChild(list);

		var openBtn:UIButton = new UIButton('Open', P(140), P(30), function():Void {
			var i:Int = list.selectedIndex;
			if (i < 0 || i >= skins.length) {
				UIToast.show('Pick a skin first');
				return;
			}
			modal.close();
			beginEditing(skins[i]);
		}, true);

		var backBtn:UIButton = new UIButton('Back', P(120), P(28), function():Void {
			modal.close();
			openEntryModal();
		});
		finishModal(modal, mw, list.y + list.h, backBtn, openBtn);
	}

	/** Loads a skin, binds it as the live preview override and (re)builds the simulation and docks. **/
	function beginEditing(skinName:String):Void {
		NoteSkinConfig.reset();
		draft.load(skinName);
		NoteSkinConfig.editorOverride = skinName;
		started = true;

		sim.keyCount = draft.keyCount;
		rebuildSim();
		shell.rail.setTabs(railTabs());
		buildLeftDock();
		buildRightDock();
		syncTransport();
	}

	/** Rebuilds the simulation from scratch (keycount / BPM changed, so the note set changed). **/
	function rebuildSim():Void {
		sim.removeLayers(this);
		commitConfig();
		sim.build(fieldCenterX(), fieldLineY());
		holdsOnTop = (draft.config.holdsOverHeads == true);
		sim.addLayers(this, holdsOnTop);
		syncTransport();
	}

	inline function fieldCenterX():Float
		return shell.fieldX + shell.fieldW / 2;

	inline function fieldLineY():Float
		return sim.downScroll ? (shell.fieldY + shell.fieldH - UITheme.px(110)) : (shell.fieldY + UITheme.px(90));

	function relayoutField():Void {
		sim.place(fieldCenterX(), fieldLineY());
	}

	/** Pushes the draft into the config caches so the skin providers see the edit. **/
	function commitConfig():Void {
		NoteSkinConfig.setConfig(draft.name, draft.config);
		NoteSkinConfig.invalidate(draft.name);
		NoteSkinService.reset();
		Pixel.render = pixelPreview || NoteSkinConfig.pixelModeOf(draft.config) == NoteSkinConfig.PIXEL_ALWAYS;
	}

	/**
		The live-edit path: re-applies the skin to every drawable already on screen. The pattern keeps
		scrolling, nothing is respawned, so edits read as instant.
	**/
	function restyle():Void {
		if (!started)
			return;
		commitConfig();
		sim.restyle();

		var over:Bool = (draft.config.holdsOverHeads == true);
		if (over != holdsOnTop) {
			holdsOnTop = over;
			sim.removeLayers(this);
			sim.addLayers(this, holdsOnTop);
		}
	}

	/** Debounced restyle, for text fields that fire per keystroke. **/
	inline function queueRestyle():Void
		restyleQueued = 0.12;

	function syncTransport():Void {
		shell.bpmChip.label = 'BPM ' + Std.int(sim.bpm);
		shell.speedChip.label = 'Speed ' + sim.speed;
		shell.keysChip.label = draft.keyCount + 'K';
		shell.scrollChip.on = sim.downScroll;
		shell.pixelChip.on = pixelPreview;
		shell.staticChip.on = sim.staticMode;

		shell.skinLabel.text = started ? (draft.name + (draft.atlas ? '  [Atlas]' : '  [Folder]')) : 'no skin loaded';
		shell.layoutMenuExtras();
	}

	static function clearPane(pane:UIScrollPane):Void {
		var i:Int = pane.content.numChildren;
		while (--i >= 0) {
			var child = pane.content.getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).dispose();
		}
		pane.content.removeChildren();
		pane.setScroll(0);
	}

	function buildLeftDock():Void {
		if (shell == null)
			return;
		clearPane(shell.leftPane);
		if (!started)
			return;

		var flow:DockFlow = new DockFlow(shell.leftPane, UITheme.px(12), UITheme.px(8));
		switch (curTab) {
			case TAB_IMAGES:
				buildImagesPanel(flow);
			case TAB_LOOK:
				buildLookPanel(flow);
			case TAB_PIXEL:
				buildPixelPanel(flow);
			case TAB_OFFSETS:
				buildOffsetsPanel(flow);
			case TAB_OSU:
				buildOsuPanel(flow);
			default:
				buildSkinPanel(flow);
		}
		flow.reflow();
	}

	inline function dockW():Float
		return shell.leftW - UITheme.px(28);

	/**
		A dock label wrapped to the pane width. `UILabel` does not wrap unless `wrapWidth` is set, so a
		bare one renders as a single long line that spills out past the dock and over the notefield.
		@param text the label text
		@param w the wrap width (the dock content width)
		@param size the font size
		@param tone the text tone
	**/
	/** Attaches a tooltip and returns the widget, so it reads inline inside a `flow.add(...)`. **/
	inline function tip<T:UIComponent>(c:T, text:String):T {
		c.tooltip = text;
		return c;
	}

	function dockLabel(text:String, w:Float, size:Int = 11, tone:Int = 2):UILabel {
		var l:UILabel = new UILabel(text, size, tone);
		l.wrapWidth = w;
		l.render();
		return l;
	}

	function buildSkinPanel(flow:DockFlow):Void {
		var w:Float = dockW();
		var half:Float = (w - UITheme.px(8)) / 2;

		flow.header(new UIAccordion('Skin', w, true));
		flow.add(dockLabel(draft.name, w, 12, 0));
		flow.add(dockLabel(draft.atlas ? 'Classic sparrow atlas' : 'Modern image folder', w));
		flow.add(dockLabel(draft.fromBase ? 'Base game - Duplicate to edit' : (draft.dir == null ? '' : draft.dir), w, 10));

		if (draft.atlas) {
			var sheetIn:UITextInput = new UITextInput('Sheet:', w, draft.config.sheet == null ? '' : draft.config.sheet, function(v:String):Void {
				draft.config.sheet = (v.trim().length < 1) ? null : v.trim();
				draft.touch();
				queueRestyle();
			});
			sheetIn.controlWidth = w - UITheme.px(64);
			flow.add(sheetIn);

			var squareIn:UITextInput = new UITextInput('Square:', w, draft.config.squareSheet == null ? '' : draft.config.squareSheet,
				function(v:String):Void {
					draft.config.squareSheet = (v.trim().length < 1) ? null : v.trim();
					draft.touch();
					queueRestyle();
				});
			squareIn.controlWidth = w - UITheme.px(64);
			flow.add(squareIn);
			flow.add(dockLabel('Centre-lane atlas for multikey. Blank uses the shared one; ignored when the sheet already bakes square frames in.', w, 10));
		}

		flow.header(new UIAccordion('Keycount', w, true));
		var keysStep:UIStepper = new UIStepper('Keys:', w, draft.keyCount, 1, function(v:Float):Void {
			var n:Int = Std.int(v);
			if (n != draft.keyCount)
				setKeyCount(n);
		});
		keysStep.tooltip = 'Column count the preview runs at';
		keysStep.min = Mania.MIN;
		keysStep.max = Mania.MAX;
		flow.add(keysStep);

		var overrideCheck:UICheckbox = new UICheckbox('Override this keycount', w, draft.overriding, function(v:Bool):Void {
			if (v) {
				draft.overriding = true;
				draft.ensureSection();
			} else {
				draft.overriding = false;
				draft.clearSection();
			}
			restyle();
			buildLeftDock();
		});
		overrideCheck.tooltip = 'Give this keycount its own image set instead of inheriting the base config';
		flow.add(overrideCheck);
		flow.add(dockLabel(overrideHint(), w, 10));

		flow.header(new UIAccordion('File', w, true));
		var saveBtn:UIButton = new UIButton('Save', half, UITheme.px(28), doSave, true);
		saveBtn.tooltip = 'Write skin.tcfg (Ctrl+S)';
		flow.add(saveBtn);
		flow.add(tip(new UIButton('Duplicate...', half, UITheme.px(28), openDuplicateModal), 'Copy this skin into your mod under a new name'));
		flow.add(tip(new UIButton('Reload from disk', w, UITheme.px(28), reloadFromDisk), 'Discard unsaved edits and re-read the files'));
		flow.add(tip(new UIButton('Open another...', w, UITheme.px(28), function():Void openPickModal()), 'Switch to a different skin'));
	}

	function overrideHint():String {
		if (draft.keyCount == Mania.DEFAULT && !draft.overriding)
			return 'Editing the base config.';
		if (draft.overriding)
			return 'Editing the ${draft.keyCount}K section.';
		return '${draft.keyCount}K inherits the base config.';
	}

	function buildImagesPanel(flow:DockFlow):Void {
		var w:Float = dockW();

		flow.header(new UIAccordion(draft.atlas ? 'Frame prefixes' : 'Image names', w, true));
		flow.add(dockLabel(draft.atlas ? 'Prefixes matched against the sheet XML.' : 'File names inside the skin folder.', w, 10));

		var elemDrop:UIDropdown = new UIDropdown('Element:', w, function(id:Int, _):Void {
			curElem = id;
			curMode = NoteSkinDraft.detectMode(draft.effective(ELEM_FIELDS[curElem]));
			buildLeftDock();
			buildRightDock();
		});
		elemDrop.setItems(ELEM_LABELS.slice(0, elemCount()));
		elemDrop.tooltip = 'Which part of the note this panel edits';
		elemDrop.select(curElem);
		flow.add(elemDrop);

		var modeDrop:UIDropdown = new UIDropdown('Layout:', w, function(id:Int, _):Void {
			curMode = id;
			buildLeftDock();
		});
		modeDrop.setItems(MODE_LABELS.copy());
		modeDrop.tooltip = 'One shared value, one per direction, or one per column';
		modeDrop.select(curMode);
		flow.add(modeDrop);

		var field:String = ELEM_FIELDS[curElem];
		flow.add(tip(new UICheckbox('Colorable', w, NoteSkinConfig.colorableFor(draft.config, field), function(v:Bool):Void {
			setElemMap('colorable', field, v);
		}), 'Let the note colour tint this element'));
		flow.add(tip(new UICheckbox('Animated', w, NoteSkinConfig.animatedFor(draft.config, field), function(v:Bool):Void {
			setElemMap('animated', field, v);
		}), 'Play every frame; off uses only the first'));

		flow.header(new UIAccordion('Values', w, true));
		elemInputs = [];
		elemInherited = [];
		var raw:Dynamic = draft.effective(field);
		var slots:Int = modeSlots();
		for (i in 0...slots) {
			var key:String = modeKey(i);
			var set:String = readElemKey(raw, key);
			var inherited:Bool = (set.length < 1);
			var shown:String = inherited ? draft.defaultFor(field, curMode, i) : set;

			var inp:UITextInput = new UITextInput(slotLabel(i), w, shown);
			inp.controlWidth = w - UITheme.px(76);
			inp.tooltip = inherited ? 'Inherited: $shown. Type to override.' : (draft.atlas ? 'XML frame prefix' : 'Image file name');
			var idx:Int = i;
			inp.onChange = function(_):Void {
				elemInherited[idx] = false;
				applyElementInputs();
			};
			elemInputs.push(inp);
			elemInherited.push(inherited);
			flow.add(inp);
		}
		if (elemInherited.contains(true))
			flow.add(dockLabel('Greyed values are engine defaults; edit one to make it explicit.', w, 10));
	}

	inline function elemCount():Int
		return draft.atlas ? 6 : 7;

	inline function modeSlots():Int
		return switch (curMode) {
			case NoteSkinDraft.MODE_DIRECTION: DIRS.length;
			case NoteSkinDraft.MODE_COLUMN: draft.keyCount;
			// Shared: `arrow` + `square` for directional art, a single image for holds/ends/splash.
			default: NoteSkinDraft.isDirectional(ELEM_FIELDS[curElem]) ? 2 : 1;
		}

	inline function modeKey(i:Int):String
		return switch (curMode) {
			case NoteSkinDraft.MODE_DIRECTION: DIRS[i];
			case NoteSkinDraft.MODE_COLUMN: Std.string(i);
			default: (i == 0) ? 'arrow' : 'square';
		}

	inline function slotLabel(i:Int):String
		return switch (curMode) {
			case NoteSkinDraft.MODE_COLUMN: 'Col ${i + 1}:';
			case NoteSkinDraft.MODE_DIRECTION: modeKey(i) + ':';
			default: NoteSkinDraft.isDirectional(ELEM_FIELDS[curElem]) ? (modeKey(i) + ':') : 'Image:';
		}

	/** Reads one slot of an element field, tolerating the String / Array / object forms it can take. **/
	function readElemKey(field:Dynamic, key:String):String {
		if (field == null)
			return '';
		if (Std.isOfType(field, String))
			return (key == 'arrow') ? cast field : '';
		if (Std.isOfType(field, Array)) {
			var a:Array<Dynamic> = field;
			var n:Null<Int> = Std.parseInt(key);
			return (n != null && n >= 0 && n < a.length && a[n] != null) ? Std.string(a[n]) : '';
		}
		var v:Dynamic = Reflect.field(field, key);
		return v == null ? '' : Std.string(v);
	}

	/**
		Writes the visible slots back. Slots still showing an inherited default are skipped, so browsing
		the panel never bakes the engine's fallbacks into the file -- only edited slots become explicit.
	**/
	function applyElementInputs():Void {
		var slots:Int = modeSlots();
		var value:Dynamic = null;

		if (curMode == NoteSkinDraft.MODE_SHARED) {
			var arrow:String = explicitAt(0);
			if (!NoteSkinDraft.isDirectional(ELEM_FIELDS[curElem]))
				value = arrow; // one image, one plain string
			else {
				var square:String = explicitAt(1);
				value = (arrow == null && square == null) ? null : (square == null ? cast arrow : {arrow: arrow, square: square});
			}
		} else {
			var obj:Dynamic = {};
			var any:Bool = false;
			for (i in 0...slots) {
				var v:String = explicitAt(i);
				if (v != null) {
					Reflect.setField(obj, modeKey(i), v);
					any = true;
				}
			}
			value = any ? obj : null;
		}

		draft.setField(ELEM_FIELDS[curElem], value);
		queueRestyle();
	}

	inline function explicitAt(i:Int):String {
		if (i >= elemInputs.length || elemInherited[i])
			return null;
		var v:String = elemInputs[i].text.trim();
		return v.length < 1 ? null : v;
	}

	/** Rewrites a whole `colorable`/`animated` map with one element changed (flat bool maps). **/
	function setElemMap(group:String, element:String, value:Bool):Void {
		var obj:Dynamic = {};
		for (e in MAP_ELEMS) {
			var cur:Bool = (group == 'colorable') ? NoteSkinConfig.colorableFor(draft.config, e) : NoteSkinConfig.animatedFor(draft.config, e);
			Reflect.setField(obj, e, cur);
		}
		Reflect.setField(obj, element, value);
		Reflect.setField(draft.config, group, obj);
		draft.touch();
		restyle();
	}

	function buildLookPanel(flow:DockFlow):Void {
		var w:Float = dockW();

		flow.header(new UIAccordion('Size', w, true));
		flow.add(numRow('Scale:', w, num(draft.config.scale, 0.7), 0.05, 2, 0.05, 8, function(v:Float):Void {
			draft.config.scale = v;
			draft.touch();
			restyle();
		}));
		flow.add(tip(numRow('Column gap:', w, num(draft.config.columnGap, 0), 1, 0, -80, 200, function(v:Float):Void {
			draft.config.columnGap = (v == 0) ? null : v;
			draft.touch();
			rebuildSim();
		}), 'Extra px between lanes, added on top of the engine spacing'));
		if (!draft.atlas)
			flow.add(dockLabel('osu!mania sizing & hit position live in the OSU tab.', w, 10));

		flow.header(new UIAccordion('Animation', w, true));
		flow.add(numRow('Anim FPS:', w, num(draft.config.fps, 24), 1, 0, 0, 60, function(v:Float):Void {
			draft.config.fps = Std.int(v);
			draft.touch();
			restyle();
		}));

		flow.header(new UIAccordion('Holds', w, true));
		flow.add(numRow('Hold alpha:', w, num(draft.config.holdAlpha, 1), 0.05, 2, 0, 1, function(v:Float):Void {
			draft.config.holdAlpha = v;
			draft.touch();
			restyle();
		}));
		flow.add(numRow('Head overlap:', w, num(draft.config.headOverlap, 0), 0.02, 2, -1, 1, function(v:Float):Void {
			draft.config.headOverlap = v;
			draft.touch();
			restyle();
		}));
		flow.add(new UICheckbox('Holds over heads', w, draft.config.holdsOverHeads == true, function(v:Bool):Void {
			draft.config.holdsOverHeads = v;
			draft.touch();
			restyle();
		}));
		flow.add(tip(new UICheckbox('Hold antialiasing', w, draft.config.holdAntialiasing == true, function(v:Bool):Void {
			draft.config.holdAntialiasing = v;
			draft.touch();
			restyle();
		}), 'Antialias the trail independently of the notes'));
		flow.add(tip(new UICheckbox('Has hold end (tail cap)', w, draft.config.hasHoldEnd != false, function(v:Bool):Void {
			draft.config.hasHoldEnd = v;
			draft.touch();
			restyle();
		}), 'Off: the body runs the full length with no end cap'));

		flow.header(new UIAccordion('Rendering', w, true));
		flow.add(new UICheckbox('Antialiasing', w, draft.config.antialiasing != false, function(v:Bool):Void {
			draft.config.antialiasing = v;
			draft.touch();
			restyle();
		}));
		flow.add(new UICheckbox('Colorable (all elements)', w, anyColorable(), function(v:Bool):Void {
			draft.config.colorable = v;
			draft.touch();
			restyle();
		}));
		flow.add(new UICheckbox('Ships @2x art', w, draft.config.hiRes == true, function(v:Bool):Void {
			draft.config.hiRes = v;
			draft.touch();
			restyle();
		}));

		flow.header(new UIAccordion('Colours', w, draft.hasColors()));
		flow.add(dockLabel(draft.hasColors() ? 'This skin ships its own note colours.' : 'Using the engine/player colours. Edit one to make this skin ship its own.',
			w, 10));
		var chanNames:Array<String> = ['R', 'G', 'B'];
		for (col in 0...draft.keyCount) {
			var rgb:Array<FlxColor> = draft.colorsFor(col);
			flow.add(dockLabel('Column ${col + 1}', w, 11, 1));
			for (ch in 0...3) {
				var c:Int = col;
				var k:Int = ch;
				flow.add(tip(new UITextInput(chanNames[ch] + ':', w, StringTools.hex(rgb[ch], 8), function(v:String):Void {
					var cur:Array<FlxColor> = draft.colorsFor(c);
					var n:Null<Int> = Std.parseInt('0x' + v.trim().replace('0x', ''));
					if (n == null)
						return;
					cur[k] = n;
					draft.setColors(c, cur);
					queueRestyle();
				}), 'AARRGGBB hex for this palette slot'));
			}
		}
		if (draft.hasColors())
			flow.add(tip(new UIButton('Reset to engine colours', w, UITheme.px(26), function():Void {
				draft.clearColors();
				restyle();
				buildLeftDock();
			}), 'Drop this palette entirely'));

		if (!draft.atlas) {
			flow.header(new UIAccordion('Rotation', w, true));
			flow.add(new UICheckbox('Rotate shared art per lane', w, draft.config.rotate != false, function(v:Bool):Void {
				draft.config.rotate = v;
				draft.touch();
				restyle();
			}));
			var angles:Array<Float> = (draft.config.directionAngles == null) ? [-90, 180, 0, 90] : draft.config.directionAngles;
			for (i in 0...4) {
				var idx:Int = i;
				flow.add(numRow(['Left:', 'Down:', 'Up:', 'Right:'][i], w, (i < angles.length) ? angles[i] : 0, 15, 0, -360, 360,
					function(v:Float):Void {
						if (draft.config.directionAngles == null)
							draft.config.directionAngles = [-90, 180, 0, 90];
						draft.config.directionAngles[idx] = v;
						draft.touch();
						restyle();
					}));
			}

			flow.header(new UIAccordion('Splash', w, true));
			flow.add(tip(numRow('Splash scale:', w, num(draft.config.splashScale, 1), 0.05, 2, 0.05, 8, function(v:Float):Void {
				draft.config.splashScale = v;
				draft.touch();
				restyle();
			}), 'Size of the splash art this skin ships'));
			flow.add(tip(new UICheckbox('Sync splash to note colour', w, draft.config.splashSyncColor == true, function(v:Bool):Void {
				draft.config.splashSyncColor = v ? true : null;
				draft.touch();
				restyle();
			}), 'Tint the splash with the lane colour even if the player has splash linking off'));
		}
	}

	/**
		The OSU rail tab: osu!mania-style column sizing (`Fit column`, `Column width`) and hit placement
		(`Hit position`, `Flip receptor Y`). Folder skins only -- classic atlas skins route through
		`ClassicNoteSkin`, which reads none of these.
	**/
	function buildOsuPanel(flow:DockFlow):Void {
		var w:Float = dockW();

		if (draft.atlas) {
			flow.add(dockLabel('osu!mania options apply to folder skins only (individual image files), not classic atlas skins.',
				w, 11));
			return;
		}

		flow.header(new UIAccordion('Sizing', w, true));
		flow.add(tip(numRow('Fit column:', w, num(draft.config.fitColumnWidth, 0), 0.05, 2, 0, 2, function(v:Float):Void {
			draft.config.fitColumnWidth = (v <= 0) ? null : v;
			draft.touch();
			restyle();
		}), 'osu!mania column fill: each element fills the lane width instead of scaling by native pixels'));
		flow.add(dockLabel('0 = off; otherwise the fraction of the lane each element fills (1 = whole column).', w, 10));
		flow.add(tip(numRow('Column width (osu):', w, num(draft.config.columnWidth, 0), 1, 0, 0, 512, function(v:Float):Void {
			draft.config.columnWidth = (v <= 0) ? null : v;
			draft.touch();
			restyle();
		}), 'osu ColumnWidth (osu!px). With Fit column on, sizes the receptor HEIGHT off this instead of stretching to its own aspect. 0 = off'));
		flow.add(dockLabel('Only affects receptors under Fit column: they fill the lane width but scale height off this, so a tall column key isn\'t stretched.',
			w, 10));

		flow.header(new UIAccordion('Hit position', w, true));
		flow.add(tip(new UICheckbox('Hit position (osu HitPosition)', w, draft.config.hitAlign != null, function(v:Bool):Void {
			draft.config.hitAlign = v ? num(draft.config.hitAlign, 0.5) : null;
			draft.touch();
			buildLeftDock(); // show/hide the value row
		}), 'Where on the receptor a note should be for a perfect hit (moves the note, not the receptor art)'));
		if (draft.config.hitAlign != null) {
			flow.add(numRow('  Hit point (0 top - 1 bottom):', w, num(draft.config.hitAlign, 0.5), 0.02, 2, 0, 1, function(v:Float):Void {
				draft.config.hitAlign = v;
				draft.touch();
				restyle();
			}));
			flow.add(dockLabel('Where notes converge for a perfect hit: 0 = top of the receptor art, 0.5 = centre, 1 = bottom. The receptor art stays put; the note press point moves onto this spot.',
				w, 10));
		}
		var flipMode:String = NoteSkinConfig.receptorFlipMode(draft.config);
		var flipIdx:Int = switch (flipMode) {
			case 'upscroll': 1;
			case 'downscroll': 2;
			case 'always': 3;
			default: 0;
		};
		var flipDrop:UIDropdown = new UIDropdown('Flip receptor Y:', w, function(id:Int, _):Void {
			draft.config.receptorFlipY = switch (id) {
				case 1: 'upscroll';
				case 2: 'downscroll';
				case 3: 'always';
				default: null;
			};
			draft.touch();
			restyle();
		});
		flipDrop.setItems(['Off', 'On upscroll', 'On downscroll', 'Always']);
		flipDrop.select(flipIdx);
		flipDrop.tooltip = 'Vertically flip the receptor art, like osu flips its key art per scroll direction (hit position is auto-mirrored)';
		flow.add(flipDrop);
	}

	function buildPixelPanel(flow:DockFlow):Void {
		var w:Float = dockW();
		var mode:String = draft.pixelMode();

		flow.header(new UIAccordion('Pixel mode', w, true));
		var modes:Array<String> = [NoteSkinConfig.PIXEL_NONE, NoteSkinConfig.PIXEL_ALWAYS, NoteSkinConfig.PIXEL_VARIANT];
		var radio:UIRadioGroup = new UIRadioGroup(['Not a pixel skin', 'Always pixel art', 'HD + pixel variant'], w, modes.indexOf(mode),
			function(i:Int):Void {
				draft.setPixelMode(modes[i]);
				restyle();
				buildLeftDock();
				buildRightDock();
			});
		radio.tooltip = 'How this skin uses pixel art';
		flow.add(radio);
		flow.add(dockLabel(pixelModeHint(mode), w, 10));

		if (mode != NoteSkinConfig.PIXEL_NONE) {
			flow.header(new UIAccordion('Pixel sizing', w, true));
			flow.add(numRow('Pixel scale:', w, num(draft.config.pixelScale, 6), 1, 0, 1, 24, function(v:Float):Void {
				draft.config.pixelScale = v;
				draft.touch();
				restyle();
			}));
			flow.add(dockLabel('Used instead of Scale while pixel art is rendering.', w, 10));

			flow.header(new UIAccordion('Pixel art', w, true));
			flow.add(dockLabel('Looked up as pixel/<name>, then <name>-pixel.', w, 10));
			for (element in NoteSkinDraft.PIXEL_ELEMENTS) {
				var info = draft.pixelArtFor(element);
				flow.add(dockLabel(element + ': ' + (info.found ? 'found' : 'MISSING'), w, 11, info.found ? 1 : 0));
				flow.add(dockLabel('   ' + info.path, w, 10));
			}
			if (!draft.atlas) {
				flow.add(dockLabel('splash: ' + draft.splashPixelMode(), w, 11, 1));
				flow.add(dockLabel('   Splashes are pixelated by a shader, so pixel/splash art is optional.', w, 10));
				flow.add(tip(new UIButton('Bake pixel splash', w, UITheme.px(26), bakePixelSplash),
					'Write the shader pixel look out as real frames the skin then uses instead'));
			}
			if (!draft.atlas) {
				flow.add(tip(numRow('Palette:', w, bakeColors, 1, 0, 0, 256, function(v:Float):Void {
					bakeColors = Std.int(v);
				}), 'Colours to reduce baked art to; 0 leaves colour untouched'));
				flow.add(tip(numRow('Alpha cutoff:', w, bakeAlphaCut, 8, 0, 0, 255, function(v:Float):Void {
					bakeAlphaCut = Std.int(v);
				}), 'Pixels below this opacity are discarded (128 = 50%); the rest become fully opaque'));
				flow.add(tip(new UIButton('Bake pixel art (all elements)', w, UITheme.px(26), bakePixelElements),
					'Generate low-res pixel/ variants from the HD art as a starting point'));
				flow.add(dockLabel('Downscaled by Scale / Pixel scale so they render at the same size, then quantised. Meant as a base to tidy up by hand.',
					w, 10));
			}
		}

		flow.header(new UIAccordion('Preview', w, true));
		flow.add(new UICheckbox('Preview as pixel stage', w, pixelPreview, function(v:Bool):Void {
			pixelPreview = v;
			restyle();
			syncTransport();
		}));
		flow.add(dockLabel('Forces the pixel render path without changing the skin.', w, 10));
	}

	/**
		Renders the splash's shader look out to real `pixel/` frames. Once they exist `applySplash`
		prefers them and drops the shader, so the art becomes editable at no visual cost.
	**/
	function bakePixelSplash():Void {
		if (!started)
			return;
		var res = PixelArtBaker.bake(draft, num(draft.config.pixelScale, PlayState.daPixelZoom), bakeColors, bakeAlphaCut);
		if (res.error != null && res.frames < 1) {
			UIToast.show('Bake failed: ' + res.error);
			return;
		}
		restyle();
		buildLeftDock();
		UIToast.show('Baked ${res.frames} splash frame(s) to ${res.path}');
	}

	/**
		Generates low-res `pixel/` variants for every non-splash element from the HD art. Unlike the
		splash there is no shader to reproduce -- pixel notes are a genuine art swap -- so this is a
		bootstrap for hand-tidying rather than an exact reproduction.
	**/
	function bakePixelElements():Void {
		if (!started)
			return;
		var res = PixelArtBaker.bakeElements(draft, NoteSkinDraft.PIXEL_ELEMENTS, bakeColors, bakeAlphaCut);
		if (res.error != null && res.frames < 1) {
			UIToast.show('Bake failed: ' + res.error);
			return;
		}
		restyle();
		buildLeftDock();
		UIToast.show('Baked ${res.frames} frame(s) to ${res.path}');
	}

	static function pixelModeHint(mode:String):String {
		return switch (mode) {
			case NoteSkinConfig.PIXEL_ALWAYS: 'This skin is pixel art and always renders that way.';
			case NoteSkinConfig.PIXEL_VARIANT: 'HD normally; the pixel art takes over on pixel stages.';
			default: 'No pixel art. Pixel stages fall back to another skin.';
		}
	}

	function buildOffsetsPanel(flow:DockFlow):Void {
		var w:Float = dockW();

		flow.header(new UIAccordion('Offsets', w, true));
		flow.add(dockLabel('Nudge each element to centre it in its lane.', w, 10));

		var elemDrop:UIDropdown = new UIDropdown('Element:', w, function(id:Int, _):Void {
			curOffElem = id;
			buildLeftDock();
		});
		elemDrop.tooltip = 'Which element the offset below moves';
		elemDrop.setItems(OFF_LABELS.copy());
		elemDrop.select(curOffElem);
		flow.add(elemDrop);

		flow.add(new UICheckbox('Per column (not direction)', w, offPerColumn, function(v:Bool):Void {
			offPerColumn = v;
			curOffTarget = 0;
			buildLeftDock();
		}));

		var targets:Array<String> = offPerColumn ? [for (i in 0...draft.keyCount) 'Column ${i + 1}'] : DIRS.copy();
		if (curOffTarget >= targets.length)
			curOffTarget = 0;
		var targetDrop:UIDropdown = new UIDropdown('Target:', w, function(id:Int, _):Void {
			curOffTarget = id;
			buildLeftDock();
		});
		targetDrop.setItems(targets);
		targetDrop.tooltip = 'Which lane the offset applies to';
		targetDrop.select(curOffTarget);
		flow.add(targetDrop);

		var cur:Array<Float> = readOffset();
		flow.add(numRow('X:', w, cur[0], 1, 0, -400, 400, function(v:Float):Void writeOffset(v, readOffset()[1])));
		flow.add(numRow('Y:', w, cur[1], 1, 0, -400, 400, function(v:Float):Void writeOffset(readOffset()[0], v)));
		// The strum's Y is measured along the scroll direction, so one tuned position fits both; the note /
		// hold / splash offsets centre art on the strum and are the same either way.
		if (OFF_FIELDS[curOffElem] == 'strumOffsets')
			flow.add(dockLabel('Y follows the scroll direction: tune it once, it fits up and down.', w, 10));
		flow.add(new UIButton('Reset this target', w, UITheme.px(26), function():Void {
			writeOffset(0, 0);
			buildLeftDock();
		}));
	}

	inline function offTargetKey():String
		return offPerColumn ? Std.string(curOffTarget) : DIRS[curOffTarget];

	function readOffset():Array<Float> {
		var f:Dynamic = Reflect.field(draft.config, OFF_FIELDS[curOffElem]);
		var v:Dynamic = (f == null) ? null : Reflect.field(f, offTargetKey());
		if (v != null && Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			return [a.length > 0 ? num(a[0], 0) : 0, a.length > 1 ? num(a[1], 0) : 0];
		}
		return [0, 0];
	}

	function writeOffset(x:Float, y:Float):Void {
		var fieldName:String = OFF_FIELDS[curOffElem];
		var f:Dynamic = Reflect.field(draft.config, fieldName);
		if (f == null) {
			f = {};
			Reflect.setField(draft.config, fieldName, f);
		}
		// Both zero -> drop the entry so the config doesn't accumulate [0, 0] noise.
		if (x == 0 && y == 0) {
			Reflect.deleteField(f, offTargetKey());
			if (Reflect.fields(f).length < 1)
				Reflect.setField(draft.config, fieldName, null);
		} else
			Reflect.setField(f, offTargetKey(), [x, y]);
		draft.touch();
		restyle();
	}

	/** The right dock: a read-only inspector for what the active element currently resolves to. **/
	function buildRightDock():Void {
		if (shell == null || shell.rightHidden)
			return;
		clearPane(shell.rightPane);
		if (!started)
			return;

		var w:Float = shell.rightW - UITheme.px(28);
		var flow:DockFlow = new DockFlow(shell.rightPane, UITheme.px(12), UITheme.px(6));

		flow.header(new UIAccordion('Resolved', w, true));
		flow.add(dockLabel('What the engine builds right now:', w, 10));

		for (i in 0...elemCount()) {
			var field:String = ELEM_FIELDS[i];
			var raw:Dynamic = draft.effective(field);
			var key:String = NoteSkinConfig.columnKey(raw, 0);
			var shown:String = (key != null && key.length > 0) ? key : draft.defaultFor(field, NoteSkinDraft.MODE_SHARED, 0);
			if (shown.length < 1)
				shown = '(unset)';
			flow.add(dockLabel(ELEM_LABELS[i] + ':', w, 11, 1));
			flow.add(dockLabel('   ' + shown, w, 10));
		}

		flow.header(new UIAccordion('Skin', w, true));
		flow.add(dockLabel('Family: ' + (draft.atlas ? 'Atlas' : 'Folder'), w, 10));
		flow.add(dockLabel('Pixel: ' + draft.pixelMode(), w, 10));
		flow.add(dockLabel('Keys: ' + draft.keyCount + 'K' + (draft.overriding ? ' (override)' : ''), w, 10));
		if (draft.atlas)
			flow.add(dockLabel('Sheet: ' + (draft.config.sheet == null ? '(auto)' : draft.config.sheet), w, 10));

		flow.reflow();
	}

	function numRow(label:String, w:Float, value:Float, step:Float, decimals:Int, lo:Float, hi:Float, cb:Float->Void):UIStepper {
		var s:UIStepper = new UIStepper(label, w, value, step, cb);
		s.min = lo;
		s.max = hi;
		s.decimals = decimals;
		s.controlWidth = UITheme.px(70);
		return s;
	}

	function anyColorable():Bool {
		var c:Dynamic = draft.config.colorable;
		if (c == null)
			return false;
		if (Std.isOfType(c, Bool))
			return c == true;
		for (e in MAP_ELEMS)
			if (NoteSkinConfig.colorableFor(draft.config, e))
				return true;
		return false;
	}

	static function num(v:Dynamic, fallback:Float):Float {
		if (v == null)
			return fallback;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
			return v;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? fallback : f;
	}

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
		NoteSkinConfig.reset();
		commitConfig();
		NoteSkinConfig.editorOverride = draft.name;
		UIToast.show('Saved ${draft.dir}/skin.tcfg');
	}

	function reloadFromDisk():Void {
		if (!started)
			return;
		NoteSkinConfig.reset();
		draft.load(draft.name);
		NoteSkinConfig.editorOverride = draft.name;
		rebuildSim();
		buildLeftDock();
		buildRightDock();
		UIToast.show('Reloaded ${draft.name}');
	}

	function openDuplicateModal():Void {
		if (!started)
			return;
		var mw:Float = P(480);
		var modal:UIModal = new UIModal('Duplicate skin', mw, P(220));

		var y:Float = P(14);
		var nameIn:UITextInput = new UITextInput('New name:', mw - P(32), NoteSkinDraft.suggestName(draft.shortName() + 'Copy'));
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
			if (NoteSkinDraft.nameTaken(short)) {
				UIToast.show('A skin named "$short" already exists');
				return;
			}
			var err:String = draft.duplicate(short);
			if (err != null) {
				UIToast.show('Duplicate failed: $err');
				return;
			}
			modal.close();
			NoteSkinConfig.reset();
			beginEditing(draft.name);
			UIToast.show('Now editing ${draft.name}');
		}, true);

		var cancelBtn:UIButton = new UIButton('Cancel', P(120), P(28), function():Void modal.close());
		finishModal(modal, mw, y, cancelBtn, okBtn);
	}

	function openHelpModal():Void {
		var mw:Float = P(560);
		var modal:UIModal = new UIModal('About note skins', mw, P(340));

		var y:Float = P(12);
		for (para in [
			'FOLDER skins ship one image per element (note.png, holdBody.png...) and you name them in the Images tab.',
			'ATLAS skins ship one sparrow sheet (.png + .xml) and name FRAME PREFIXES instead. Prefixes must be specific: "purple0" matches purple0001 but not "purple hold piece0001".',
			'Multikey centre lane: bake square frames into your sheet, or point Square at your own atlas. Baked-in frames always win.',
			'Pixel art lives at pixel/<name> or <name>-pixel next to the base art.'
		])
			y += modalLabel(modal, mw, para, y, 11, 1).height + P(10);

		var closeBtn:UIButton = new UIButton('Close', P(130), P(28), function():Void modal.close(), true);
		finishModal(modal, mw, y, null, closeBtn);
	}

	function tryLeave():Void {
		if (draft.dirty)
			openExitModal();
		else
			leave();
	}

	function openExitModal():Void {
		var mw:Float = P(460);
		var btnH:Float = P(28);
		var modal:UIModal = new UIModal('Leave Note Skin Editor?', mw, P(200));

		var y:Float = P(14);
		y += modalLabel(modal, mw, 'This skin has unsaved changes.', y).height + P(6);

		// Three buttons: the middle one is placed by hand, the outer pair by `finishModal`.
		var save:UIButton = new UIButton('Save & leave', P(140), btnH, function():Void {
			modal.close();
			doSave();
			leave();
		}, true);
		save.x = mw - P(16) - P(120) - P(8) - P(140);
		save.y = y + P(14);
		modal.body.addChild(save);

		var cancel:UIButton = new UIButton('Cancel', P(120), btnH, function():Void modal.close());
		var discard:UIButton = new UIButton('Discard', P(120), btnH, function():Void {
			modal.close();
			leave();
		});
		discard.danger = true;
		finishModal(modal, mw, y, cancel, discard);
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (restyleQueued > 0) {
			restyleQueued -= elapsed;
			if (restyleQueued <= 0) {
				restyleQueued = -1;
				restyle();
			}
		}

		if (!started)
			return;

		sim.update(elapsed);

		shell.statusLeft.text = (draft.dir == null ? draft.name : draft.dir) + (draft.dirty ? '   *unsaved*' : '');
		shell.statusRight.text = (draft.atlas ? 'sheet: ' + (draft.config.sheet == null ? '(auto)' : draft.config.sheet) : 'folder skin')
			+ '   pixel: '
			+ draft.pixelMode()
			+ '   '
			+ Std.int(FlxG.drawFramerate)
			+ ' FPS';
		shell.layoutStatus();

		var blockInput:Bool = (UIFocus.focused != null) || UIRoot.overlayOpen;
		if (blockInput)
			return;

		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S) {
			doSave();
			return;
		}
		if (FlxG.keys.justPressed.SPACE) {
			shell.playing = !shell.playing;
			sim.playing = shell.playing;
			return;
		}
		if (controls.BACK) {
			tryLeave();
			return;
		}
	}
}
