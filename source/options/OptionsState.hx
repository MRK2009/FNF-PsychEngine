package options;

import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSpriteUtil;
import flixel.graphics.FlxGraphic;
import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import options.Option;
import options.OptionsCatalog;
import options.OptionsCatalog.Sidebar;
import options.OptionsCatalog.OptionRow;
import states.MainMenuState;
import backend.StageData;

using StringTools;

/**
	Rewritten Options menu: 
	A category sidebar + the selected category's settings edited inline
	(toggle / stepper / dropdown), a live description, and search.

	Specialized editors (Controls, Note Colors, etc.) are launches their substates as usual. 
	Data comes from OptionsCatalog.
**/
class OptionsState extends MusicBeatState {
	public static var onPlayState:Bool = false;

	static inline var PANEL_Y:Int = 104;
	static inline var PANEL_H:Int = 558;

	static inline var SIDEBAR_PANEL_X:Int = 24;
	static inline var SIDEBAR_PANEL_WIDTH:Int = 278;
	static inline var SIDEBAR_TEXT_X:Int = 42;
	static inline var SIDEBAR_TOPTIONS_TOP_Y:Int = 122;
	static inline var SIDEBAR_ROW_HEIGHT:Int = 42;
	static inline var SIDEBAR_VISIBLE_ROWS:Int = 12;

	static inline var OPTIONS_PANEL_X:Int = 314;
	static inline var OPTIONS_PANEL_WIDTH:Int = 942;
	static inline var OPTIONS_TEXT_X:Int = 340;
	static inline var OPTIONS_TOP_Y:Int = 128;
	static inline var OPTIONS_ROW_HEIGHT:Int = 46;
	static inline var OPTIONS_VISIBLE_ROWS:Int = 8;
	static inline var VALUE_COLUMN_RIGHT:Int = 1232;

	var sidebar:Array<Sidebar> = [];
	var curCat:Int = 0;
	var catScroll:Int = 0;

	var curRows:Array<OptionRow> = [];
	var curRow:Int = 0;
	var rowScroll:Int = 0;

	var searching:Bool = false;
	var query:String = '';

	var bg:FlxSprite;
	var headerAlpha:Alphabet;
	var searchText:FlxText;
	var hintText:FlxText;
	var descText:FlxText;

	var sbBgs:Array<FlxSprite> = [];
	var sbTexts:Array<FlxText> = [];
	var sbSlotCat:Array<Int> = [];
	var sbHint:FlxText;

	var rowBgs:Array<FlxSprite> = [];
	var rowNames:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];
	var rowArrowL:Array<FlxText> = [];
	var rowArrowR:Array<FlxText> = [];
	var rowChecks:Array<FlxSprite> = [];
	var checkOnGfx:FlxGraphic;
	var checkOffGfx:FlxGraphic;

	static inline var CHECKBOX_SIZE:Int = 34;

	var rowSlotIndex:Array<Int> = []; // which curRows index each slot shows (-1 = empty)
	var opHint:FlxText;

	var notes:FlxTypedGroup<StrumNote>;
	var splashes:FlxTypedGroup<NoteSplash>;
	var previewActive:Bool = false;

	var popupOpen:Bool = false;
	var popupOption:Option = null;
	var popupBg:FlxSprite;
	var popupPanel:FlxSprite;
	var popupCursor:FlxSprite;
	var popupTexts:Array<FlxText> = [];
	var popupSel:Int = 0;
	var popupScroll:Int = 0;

	static inline var POPUP_VISIBLE_ROWS:Int = 10;
	static inline var POPUP_ROW_HEIGHT:Int = 36;

	var holdTime:Float = 0;
	var holdValue:Float = 0;
	var nextAccept:Int = 5;
	var quitting:Bool = false;
	var changedMusic:Bool = false;

	override function create() {
		backend.Mods.allowCurrentModAssets = false;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
		persistentUpdate = true;

		sidebar = OptionsCatalog.build();
		wireDynamicOptions();

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF1A1A2E;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		makePanel(SIDEBAR_PANEL_X, PANEL_Y, SIDEBAR_PANEL_WIDTH, PANEL_H);
		makePanel(OPTIONS_PANEL_X, PANEL_Y, OPTIONS_PANEL_WIDTH, PANEL_H);

		headerAlpha = new Alphabet(SIDEBAR_TEXT_X, 30, '', true);
		headerAlpha.scrollFactor.set();
		add(headerAlpha);

		searchText = makeText(FlxG.width - 470, 44, 450, 'SEARCH ( / )', 22, RIGHT);
		add(searchText);

		for (i in 0...SIDEBAR_VISIBLE_ROWS) {
			var rowY:Int = SIDEBAR_TOPTIONS_TOP_Y + i * SIDEBAR_ROW_HEIGHT;
			var bgRow:FlxSprite = new FlxSprite(SIDEBAR_PANEL_X + 4, rowY).makeGraphic(1, 1, FlxColor.WHITE);
			bgRow.scale.set(SIDEBAR_PANEL_WIDTH - 8, SIDEBAR_ROW_HEIGHT - 4);
			bgRow.updateHitbox();
			bgRow.alpha = 0;
			bgRow.scrollFactor.set();
			add(bgRow);
			sbBgs.push(bgRow);

			var t:FlxText = makeText(SIDEBAR_TEXT_X, rowY + 6, SIDEBAR_PANEL_WIDTH - 28, '', 22, LEFT);
			sbTexts.push(t);
			add(t);
			sbSlotCat.push(-1);
		}

		sbHint = makeText(SIDEBAR_PANEL_X, PANEL_Y + PANEL_H - 26, SIDEBAR_PANEL_WIDTH - 12, '', 14, RIGHT);
		sbHint.alpha = 0.7;
		add(sbHint);

		checkOnGfx = makeCheckGraphic(true);
		checkOffGfx = makeCheckGraphic(false);

		for (i in 0...OPTIONS_VISIBLE_ROWS) {
			var rowY:Int = OPTIONS_TOP_Y + i * OPTIONS_ROW_HEIGHT;
			var rb:FlxSprite = new FlxSprite(OPTIONS_PANEL_X + 6, rowY).makeGraphic(1, 1, FlxColor.WHITE);
			rb.scale.set(OPTIONS_PANEL_WIDTH - 12, OPTIONS_ROW_HEIGHT - 4);
			rb.updateHitbox();
			rb.alpha = 0;
			rb.scrollFactor.set();
			add(rb);
			rowBgs.push(rb);

			var nm:FlxText = makeText(OPTIONS_TEXT_X, rowY + 8, 620, '', 24, LEFT);
			rowNames.push(nm);
			add(nm);

			var al:FlxText = makeText(0, rowY + 8, 30, '<', 24, CENTER);
			al.visible = false;
			rowArrowL.push(al);
			add(al);

			var vt:FlxText = makeText(0, rowY + 8, 260, '', 22, CENTER);
			vt.visible = false;
			rowValues.push(vt);
			add(vt);

			var ar:FlxText = makeText(VALUE_COLUMN_RIGHT - 26, rowY + 8, 30, '>', 24, CENTER);
			ar.visible = false;
			rowArrowR.push(ar);
			add(ar);

			var cb:FlxSprite = new FlxSprite(0, 0);
			cb.scrollFactor.set();
			cb.visible = false;
			rowChecks.push(cb);
			add(cb);

			rowSlotIndex.push(-1);
		}

		descText = makeText(OPTIONS_TEXT_X, OPTIONS_TOP_Y + OPTIONS_VISIBLE_ROWS * OPTIONS_ROW_HEIGHT + 16, OPTIONS_PANEL_WIDTH - 52, '', 18, LEFT);
		descText.alpha = 0.9;
		add(descText);

		opHint = makeText(OPTIONS_PANEL_X, PANEL_Y + PANEL_H - 26, OPTIONS_PANEL_WIDTH - 12, '', 14, RIGHT);
		opHint.alpha = 0.7;
		add(opHint);

		hintText = makeText(0, FlxG.height - 30, FlxG.width, 'ARROWS Navigate   Q/E Category   ENTER Toggle/Open   / Search   ESC Back', 16, CENTER);
		add(hintText);

		buildPreview();
		buildPopup();

		selectCategory(0, false);
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end
	}

	override function destroy() {
		if (changedMusic && !onPlayState && FlxG.sound.music != null)
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 1, true);
		ClientPrefs.loadPrefs();
		super.destroy();
	}

	override function update(elapsed:Float) {
		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		if (quitting) {
			super.update(elapsed);
			return;
		}

		if (nextAccept > 0)
			nextAccept--;

		if (popupOpen) {
			updatePopup();
			super.update(elapsed);
			return;
		}

		if (searching) {
			handleSearchInput();
			super.update(elapsed);
			return;
		}

		handleKeyboard(elapsed);
		handleMouse();
		super.update(elapsed);
	}

	/**
	 * Handles keyboard input while browsing options.
	 *
	 * Processes search, category navigation, row movement, action activation,
	 * reset behavior, and back/cancel navigation.
	 *
	 * @param elapsed Frame delta used by option editing logic.
	 */
	function handleKeyboard(elapsed:Float):Void {
		if (FlxG.keys.justPressed.SLASH) {
			beginSearch();
			return;
		}

		if (FlxG.keys.justPressed.E || FlxG.keys.justPressed.TAB)
			cycleCategory(1);
		else if (FlxG.keys.justPressed.Q)
			cycleCategory(-1);

		if (controls.UI_UP_P)
			moveRow(-1);
		if (controls.UI_DOWN_P)
			moveRow(1);

		var o:Option = focusedOption();
		if (o != null)
			editFocused(o, elapsed);
		else if (controls.ACCEPT && nextAccept <= 0)
			activateRow(); // launcher / action

		if (controls.RESET && o != null)
			resetFocused(o);

		if (controls.BACK)
			exitState();
	}

	/**
	 * Processes input for the currently focused option.
	 *
	 * Handles acceptance, popup opening, cycling string choices, and
	 * incremental numeric adjustment for INT/FLOAT/PERCENT options.
	 *
	 * @param o The currently focused option.
	 * @param elapsed Frame time used for accelerated numeric changes.
	 */
	function editFocused(o:Option, elapsed:Float):Void {
		switch (o.type) {
			case BOOL:
				if (controls.ACCEPT && nextAccept <= 0) {
					nextAccept = 5;
					o.setValue((o.getValue() == true) ? false : true);
					o.change();
					FlxG.sound.play(Paths.sound('scrollMenu'));
					refreshVisibleRows();
				}

			case STRING:
				if (controls.ACCEPT && nextAccept <= 0) {
					nextAccept = 5;
					openPopup(o);
				} else if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
					cycleString(o, controls.UI_LEFT_P ? -1 : 1);

			default: // INT / FLOAT / PERCENT
				if (controls.UI_LEFT || controls.UI_RIGHT) {
					var pressed:Bool = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
					if (holdTime > 0.5 || pressed) {
						var dir:Float = controls.UI_LEFT ? -1 : 1;
						if (pressed) {
							holdValue = clampNum(o, o.getValue() + dir * o.changeValue);
							setNum(o, holdValue);
							o.change();
							FlxG.sound.play(Paths.sound('scrollMenu'));
						} else {
							holdValue = clampNum(o, holdValue + o.scrollSpeed * elapsed * dir);
							setNum(o, holdValue);
							o.change();
						}
						refreshVisibleRows();
					}
					holdTime += elapsed;
				} else if (controls.UI_LEFT_R || controls.UI_RIGHT_R) {
					if (holdTime > 0.5)
						FlxG.sound.play(Paths.sound('scrollMenu'));
					holdTime = 0;
				}
		}
	}

	/**
	 * Cycles the current option value for a STRING option.
	 *
	 * Wraps the selection around the available choices and refreshes the UI.
	 *
	 * @param o The option to update.
	 * @param dir Direction to cycle (-1 for previous, 1 for next).
	 */
	function cycleString(o:Option, dir:Int):Void {
		if (o.options == null || o.options.length == 0)
			return;
		var num:Int = o.curOption + dir;
		if (num < 0)
			num = o.options.length - 1;
		else if (num >= o.options.length)
			num = 0;
		o.curOption = num;
		o.setValue(o.options[num]);
		o.change();
		FlxG.sound.play(Paths.sound('scrollMenu'));
		refreshVisibleRows();
	}

	/**
	 * Resets the currently focused option to its default value.
	 *
	 * For STRING options, this also restores the selection index.
	 *
	 * @param o The option to reset.
	 */
	function resetFocused(o:Option):Void {
		o.setValue(o.defaultValue);
		if (o.type == STRING && o.options != null)
			o.curOption = o.options.indexOf(o.getValue());
		o.change();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		refreshVisibleRows();
	}

	/**
	 * Writes a numeric value into an option with the correct rounding.
	 *
	 * @param o The option to update.
	 * @param v The raw numeric value to assign.
	 */
	function setNum(o:Option, v:Float):Void {
		if (o.type == INT)
			o.setValue(Math.round(v));
		else
			o.setValue(FlxMath.roundDecimal(v, o.decimals));
	}

	/**
	 * Clamps a numeric option value inside its allowed min/max range.
	 *
	 * @param o The option whose range to enforce.
	 * @param v The value to clamp.
	 * @return The clamped value.
	 */
	inline function clampNum(o:Option, v:Float):Float {
		if (v < o.minValue)
			v = o.minValue;
		else if (v > o.maxValue)
			v = o.maxValue;
		return v;
	}

	/**
	 * Activates the currently selected row if it is a launcher/action.
	 */
	function activateRow():Void {
		if (curRow < 0 || curRow >= curRows.length)
			return;
		switch (curRows[curRow]) {
			case Action(_, _, which):
				launch(which);
			default:
		}
	}

	/**
	 * Handles mouse interaction for the options menu.
	 *
	 * Supports sidebar clicks, row selection, boolean toggles, string option
	 * selection, and value adjustment via left/right controls.
	 */
	function handleMouse():Void {
		if (FlxG.mouse.wheel != 0)
			moveRow(-(FlxG.mouse.wheel > 0 ? 1 : -1));

		var moved:Bool = (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0);
		if (!moved && !FlxG.mouse.justPressed)
			return;

		// Sidebar
		for (i in 0...sbBgs.length) {
			var cat:Int = sbSlotCat[i];
			if (cat < 0 || !FlxG.mouse.overlaps(sbBgs[i]))
				continue;
			if (FlxG.mouse.justPressed) {
				if (cat != curCat)
					selectCategory(cat, true);
				else
					openIfLauncher();
			}
		}

		// Option rows
		for (i in 0...rowBgs.length) {
			var idx:Int = rowSlotIndex[i];
			if (idx < 0 || !FlxG.mouse.overlaps(rowBgs[i]))
				continue;
			if (idx != curRow && (moved || FlxG.mouse.justPressed))
				selectRow(idx);
			if (!FlxG.mouse.justPressed)
				continue;

			var o:Option = optionOf(curRows[idx]);
			if (o == null) {
				activateRow();
				continue;
			}
			switch (o.type) {
				case BOOL:
					o.setValue((o.getValue() == true) ? false : true);
					o.change();
					FlxG.sound.play(Paths.sound('scrollMenu'));
					refreshVisibleRows();
				case STRING:
					if (FlxG.mouse.overlaps(rowArrowL[i]))
						cycleString(o, -1);
					else if (FlxG.mouse.overlaps(rowArrowR[i]))
						cycleString(o, 1);
					else
						openPopup(o);
				default:
					if (FlxG.mouse.overlaps(rowArrowL[i])) {
						setNum(o, clampNum(o, o.getValue() - o.changeValue));
						o.change();
						FlxG.sound.play(Paths.sound('scrollMenu'));
						refreshVisibleRows();
					} else if (FlxG.mouse.overlaps(rowArrowR[i])) {
						setNum(o, clampNum(o, o.getValue() + o.changeValue));
						o.change();
						FlxG.sound.play(Paths.sound('scrollMenu'));
						refreshVisibleRows();
					}
			}
		}
	}

	/**
	 * Moves the selected sidebar category by the given direction.
	 *
	 * @param dir Direction to move the category selection (positive = next, negative = previous).
	 */
	function cycleCategory(dir:Int):Void {
		selectCategory(FlxMath.wrap(curCat + dir, 0, sidebar.length - 1), true);
	}

	/**
	 * Selects a sidebar category and refreshes the options UI.
	 *
	 * This resets the search query, updates the header, refreshes the sidebar,
	 * rebuilds option rows, and selects the first row in the new category.
	 *
	 * @param idx The category index to select.
	 * @param sound Whether to play the category change sound.
	 */
	function selectCategory(idx:Int, sound:Bool):Void {
		curCat = FlxMath.wrap(idx, 0, sidebar.length - 1);
		query = '';
		searchText.text = 'SEARCH ( / )';
		setHeader(categoryName(sidebar[curCat]));

		curRows = switch (sidebar[curCat]) {
			case Group(_, rows): rows;
			default: [];
		}
		curRow = 0;
		rowScroll = 0;
		holdTime = 0;

		if (sound)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);

		refreshSidebar();
		buildRows();
		selectRow(0);
	}

	/**
	 * Opens the current category if it is a launcher.
	 */
	function openIfLauncher():Void {
		switch (sidebar[curCat]) {
			case Launcher(_, _, which):
				launch(which);
			default:
		}
	}

	/**
	 * Updates the sidebar display and scroll offset for the selected category.
	 */
	function refreshSidebar():Void {
		if (curCat < catScroll)
			catScroll = curCat;
		else if (curCat >= catScroll + SIDEBAR_VISIBLE_ROWS)
			catScroll = curCat - SIDEBAR_VISIBLE_ROWS + 1;
		if (catScroll > sidebar.length - SIDEBAR_VISIBLE_ROWS)
			catScroll = sidebar.length - SIDEBAR_VISIBLE_ROWS;
		if (catScroll < 0)
			catScroll = 0;

		for (i in 0...SIDEBAR_VISIBLE_ROWS) {
			var cat:Int = catScroll + i;
			if (cat >= sidebar.length) {
				sbSlotCat[i] = -1;
				sbTexts[i].text = '';
				sbBgs[i].alpha = 0;
				continue;
			}
			sbSlotCat[i] = cat;

			var selected:Bool = (cat == curCat && !searching);
			sbBgs[i].alpha = selected ? 0.85 : 0;

			var t:FlxText = sbTexts[i];
			t.text = categoryName(sidebar[cat]);
			t.color = selected ? 0xFF20131F : FlxColor.WHITE;
			t.borderColor = selected ? FlxColor.WHITE : FlxColor.BLACK;
			t.alpha = selected ? 1 : 0.85;
		}
		sbHint.text = (sidebar.length > SIDEBAR_VISIBLE_ROWS) ? '${catScroll + 1}-${Std.int(Math.min(catScroll + SIDEBAR_VISIBLE_ROWS, sidebar.length))} / ${sidebar.length}' : '';
	}

	/**
	 * Builds the currently visible option rows for the selected category.
	 *
	 * If the current category is a launcher, it shows the launcher prompt
	 * instead of rendering option rows.
	 */
	function buildRows():Void {
		var launcher:Bool = (curRows.length == 0);
		opHint.visible = !launcher;
		for (i in 0...OPTIONS_VISIBLE_ROWS)
			hideRowSlot(i);

		if (launcher) {
			rowScroll = 0;
			descText.text = launcherDesc(sidebar[curCat]) + '\n\nPress ENTER to open.';
			previewActive = false;
			updatePreviewVisibility();
			return;
		}
		layoutRows();
	}

	/**
	 * Moves the selected option row up or down.
	 *
	 * @param dir The direction to move (positive for down, negative for up).
	 */
	function moveRow(dir:Int):Void {
		if (curRows.length == 0)
			return;
		selectRow(FlxMath.wrap(curRow + dir, 0, curRows.length - 1));
	}

	/**
	 * Selects a specific option row and updates row state.
	 *
	 * @param idx The index of the row to select.
	 */
	function selectRow(idx:Int):Void {
		if (curRows.length == 0) {
			descText.text = launcherDesc(sidebar[curCat]) + '\n\nPress ENTER to open.';
			return;
		}
		curRow = FlxMath.wrap(idx, 0, curRows.length - 1);
		holdTime = 0;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.35);
		descText.text = rowDesc(curRows[curRow]);
		layoutRows();
		updatePreviewVisibility();
	}

	/**
	 * Lays out the visible option rows and updates the row UI state.
	 *
	 * This keeps the selected row in view, renders action/boolean/value rows,
	 * and updates the pagination hint for the current row window.
	 */
	function layoutRows():Void {
		if (curRow < rowScroll)
			rowScroll = curRow;
		else if (curRow >= rowScroll + OPTIONS_VISIBLE_ROWS)
			rowScroll = curRow - OPTIONS_VISIBLE_ROWS + 1;
		if (rowScroll > curRows.length - OPTIONS_VISIBLE_ROWS)
			rowScroll = curRows.length - OPTIONS_VISIBLE_ROWS;
		if (rowScroll < 0)
			rowScroll = 0;

		for (i in 0...OPTIONS_VISIBLE_ROWS) {
			var idx:Int = rowScroll + i;
			if (idx >= curRows.length) {
				hideRowSlot(i);
				continue;
			}
			rowSlotIndex[i] = idx;
			var rowY:Float = OPTIONS_TOP_Y + i * OPTIONS_ROW_HEIGHT;
			var selected:Bool = (idx == curRow);
			rowBgs[i].alpha = selected ? 0.85 : 0;

			var nm:FlxText = rowNames[i];
			nm.text = rowName(curRows[idx]);
			nm.color = selected ? 0xFF20131F : FlxColor.WHITE;
			nm.borderColor = selected ? FlxColor.WHITE : FlxColor.BLACK;
			nm.alpha = selected ? 1 : 0.85;
			nm.y = rowY + 8;

			var o:Option = optionOf(curRows[idx]);
			var cb:FlxSprite = rowChecks[i];
			var vt:FlxText = rowValues[i];
			var al:FlxText = rowArrowL[i];
			var ar:FlxText = rowArrowR[i];

			if (o == null) {
				// Action row: show a ">" opener marker.
				cb.visible = al.visible = false;

				ar.visible = true;
				ar.y = rowY + 8;

				vt.visible = true;
				vt.text = 'OPEN';
				vt.color = selected ? 0xFF20131F : FlxColor.WHITE;
				vt.x = VALUE_COLUMN_RIGHT - 90 - 26;
				vt.fieldWidth = 90;
				vt.y = rowY + 8;
				vt.alpha = selected ? 1 : 0.85;
			} else if (o.type == BOOL) {
				al.visible = ar.visible = vt.visible = false;

				cb.visible = true;
				cb.loadGraphic((o.getValue() == true) ? checkOnGfx : checkOffGfx);
				cb.setGraphicSize(CHECKBOX_SIZE, CHECKBOX_SIZE);
				cb.updateHitbox();
				cb.setPosition(VALUE_COLUMN_RIGHT - CHECKBOX_SIZE, rowY + (OPTIONS_ROW_HEIGHT - 4 - CHECKBOX_SIZE) / 2);
			} else {
				cb.visible = false;

				vt.visible = al.visible = ar.visible = true;
				vt.text = valueString(o);
				vt.color = selected ? 0xFF20131F : FlxColor.WHITE;
				vt.fieldWidth = 230;
				vt.x = VALUE_COLUMN_RIGHT - 26 - 230;
				vt.y = rowY + 8;
				vt.alpha = selected ? 1 : 0.85;

				al.x = vt.x - 30;
				al.y = rowY + 8;
				al.alpha = selected ? 1 : 0.6;

				ar.x = VALUE_COLUMN_RIGHT - 26;
				ar.y = rowY + 8;
				ar.alpha = selected ? 1 : 0.6;
			}
		}

		opHint.text = (curRows.length > OPTIONS_VISIBLE_ROWS) ? '${rowScroll + 1}-${Std.int(Math.min(rowScroll + OPTIONS_VISIBLE_ROWS, curRows.length))} / ${curRows.length}' : '';
	}

	/**
	 * Resets a row slot to its empty state.
	 *
	 * @param i The index of the visible row slot to clear.
	 */
	function hideRowSlot(i:Int):Void {
		rowSlotIndex[i] = -1;
		rowBgs[i].alpha = 0;
		rowNames[i].text = '';
		rowValues[i].visible = false;
		rowArrowL[i].visible = false;
		rowArrowR[i].visible = false;
		rowChecks[i].visible = false;
	}

	/**
	 * Refreshes the on-screen visible row layout.
	 */
	function refreshVisibleRows():Void
		layoutRows();

	/**
	 * Builds the string-selection popup UI used for STRING option fields.
	 *
	 * Initializes the background, panel, cursor, and row labels, but keeps the
	 * popup hidden until a dropdown/choice option is opened.
	 */
	function buildPopup():Void {
		popupBg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		popupBg.scale.set(FlxG.width, FlxG.height);
		popupBg.updateHitbox();
		popupBg.alpha = 0;
		popupBg.scrollFactor.set();
		add(popupBg);

		popupPanel = new FlxSprite(0, 0).makeGraphic(1, 1, 0xFF14161E);
		popupPanel.scrollFactor.set();
		popupPanel.visible = false;
		add(popupPanel);

		popupCursor = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.WHITE);
		popupCursor.alpha = 0.85;
		popupCursor.scrollFactor.set();
		popupCursor.visible = false;
		add(popupCursor);

		for (i in 0...POPUP_VISIBLE_ROWS) {
			var t:FlxText = makeText(0, 0, 420, '', 22, LEFT);
			t.visible = false;
			popupTexts.push(t);
			add(t);
		}
	}

	/**
	 * Opens the option popup for a STRING option and prepares selection state.
	 *
	 * @param o The option whose available choices should be displayed.
	 */
	function openPopup(o:Option):Void {
		if (o.options == null || o.options.length == 0)
			return;

		popupOpen = true;
		popupOption = o;

		popupSel = Std.int(Math.max(0, o.curOption));
		popupScroll = 0;

		FlxG.sound.play(Paths.sound('scrollMenu'));

		var w:Int = 460;
		var rows:Int = Std.int(Math.min(POPUP_VISIBLE_ROWS, o.options.length));
		var h:Int = rows * POPUP_ROW_HEIGHT + 20;
		var px:Float = (FlxG.width - w) / 2;
		var py:Float = (FlxG.height - h) / 2;

		popupBg.alpha = 0.6;

		popupPanel.setPosition(px, py);
		popupPanel.scale.set(w, h);
		popupPanel.updateHitbox();
		popupPanel.visible = true;

		popupCursor.scale.set(w - 16, POPUP_ROW_HEIGHT);
		popupCursor.updateHitbox();
		popupCursor.visible = true;
		layoutPopup();
	}

	/**
	 * Updates popup scrolling, visible rows, and the selection cursor.
	 */
	function layoutPopup():Void {
		var o:Option = popupOption;
		var rows:Int = Std.int(Math.min(POPUP_VISIBLE_ROWS, o.options.length));

		if (popupSel < popupScroll)
			popupScroll = popupSel;
		else if (popupSel >= popupScroll + rows)
			popupScroll = popupSel - rows + 1;

		if (popupScroll > o.options.length - rows)
			popupScroll = o.options.length - rows;

		if (popupScroll < 0)
			popupScroll = 0;

		var px:Float = popupPanel.x + 10;
		var py:Float = popupPanel.y + 10;

		for (i in 0...POPUP_VISIBLE_ROWS) {
			var t:FlxText = popupTexts[i];
			var idx:Int = popupScroll + i;
			if (i >= rows || idx >= o.options.length) {
				t.visible = false;
				continue;
			}

			t.visible = true;
			t.text = o.options[idx];
			t.setPosition(px + 8, py + i * POPUP_ROW_HEIGHT + 4);

			var sel:Bool = (idx == popupSel);
			t.color = sel ? 0xFF20131F : FlxColor.WHITE;
			t.borderColor = sel ? FlxColor.WHITE : FlxColor.BLACK;

			if (sel) {
				popupCursor.setPosition(popupPanel.x + 8, py + i * POPUP_ROW_HEIGHT);
			}
		}
	}

	/**
	 * Handles keyboard, mouse, and wheel input while the popup is open.
	 */
	function updatePopup():Void {
		if (controls.UI_UP_P) {
			popupSel = FlxMath.wrap(popupSel - 1, 0, popupOption.options.length - 1);
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			layoutPopup();
		}

		if (controls.UI_DOWN_P) {
			popupSel = FlxMath.wrap(popupSel + 1, 0, popupOption.options.length - 1);
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			layoutPopup();
		}

		if (FlxG.mouse.wheel != 0) {
			popupSel = FlxMath.wrap(popupSel - (FlxG.mouse.wheel > 0 ? 1 : -1), 0, popupOption.options.length - 1);
			layoutPopup();
		}

		if (FlxG.mouse.justMoved || FlxG.mouse.justPressed) {
			for (i in 0...popupTexts.length) {
				if (popupTexts[i].visible && FlxG.mouse.overlaps(popupTexts[i])) {
					popupSel = popupScroll + i;
					layoutPopup();

					if (FlxG.mouse.justPressed)
						confirmPopup();
					return;
				}
			}
		}

		if (controls.ACCEPT && nextAccept <= 0)
			confirmPopup();
		else if (controls.BACK)
			closePopup();
	}

	/**
	 * Confirms the selected popup choice, applies it to the option, and closes the popup.
	 */
	function confirmPopup():Void {
		nextAccept = 5;
		popupOption.curOption = popupSel;
		popupOption.setValue(popupOption.options[popupSel]);
		popupOption.change();

		FlxG.sound.play(Paths.sound('confirmMenu'));

		closePopup();
		refreshVisibleRows();
	}

	/**
	 * Hides the option popup and clears the visible text rows.
	 */
	function closePopup():Void {
		popupOpen = false;
		popupBg.alpha = 0;
		popupPanel.visible = false;
		popupCursor.visible = false;
		for (t in popupTexts)
			t.visible = false;
	}

	/**
	 * Creates the live previews for note and splash objects used by the options menu.
	 *
	 * Kept hidden until their options are selected.
	 */
	function buildPreview():Void {
		notes = new FlxTypedGroup<StrumNote>();
		splashes = new FlxTypedGroup<NoteSplash>();

		for (i in 0...Note.colArray.length) {
			var note:StrumNote = new StrumNote(420 + (520 / Note.colArray.length) * i, 470, i, 0);
			note.scrollFactor.set();
			changeNoteSkin(note);
			note.setGraphicSize(Std.int(note.width * 0.6));
			note.updateHitbox();
			note.visible = false;
			notes.add(note);

			var splash:NoteSplash = new NoteSplash(0, 0, NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix());
			splash.inEditor = true;
			splash.babyArrow = note;
			splash.ID = i;
			splash.kill();
			splashes.add(splash);
		}

		add(notes);
		add(splashes);
	}

	/**
	 * Shows or hides the preview area based on the currently selected option.
	 */
	function updatePreviewVisibility():Void {
		var o:Option = focusedOption();
		var show:Bool = (o != null && (o.variable == 'noteSkin' || o.variable == 'splashSkin' || o.variable == 'splashAlpha'));

		if (show == previewActive)
			return;
		previewActive = show;

		for (note in notes.members)
			note.visible = show;
		if (show)
			playNoteSplashes();
	}

	/**
	 * OH LORD HAVE MERCY ON ME, INDENTATION HELL (TEMPORARY) PART 1
	 * Binds dynamic option change handlers after the catalog is built.
	 *
	 * This wires live previews and special change behavior for certain options.
	 */
	function wireDynamicOptions():Void {
		for (entry in sidebar) {
			switch (entry) {
				case Group(_, rows):
					for (row in rows)
						switch (row) {
							case Setting(o):
								switch (o.variable) {
									case 'noteSkin': o.onChange = onChangeNoteSkin;
									case 'splashSkin': o.onChange = onChangeSplashSkin;
									case 'splashAlpha': o.onChange = playNoteSplashes;
									case 'pauseMusic': o.onChange = onChangePauseMusic;
									default:
								}
							default:
						}
				default:
			}
		}
	}

	/**
	 * Executes the pause music option change logic.
	 *
	 * This either mutes music or loads the selected pause music track.
	 */
	function onChangePauseMusic():Void {
		if (ClientPrefs.data.pauseMusic == 'None')
			FlxG.sound.music.volume = 0;
		else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
		changedMusic = true;
	}

	/**
	 * Updates all live preview notes to use the currently selected note skin.
	 */
	function onChangeNoteSkin():Void {
		notes.forEachAlive(function(note:StrumNote) {
			changeNoteSkin(note);
			note.setGraphicSize(Std.int(note.width * 0.6));
			note.updateHitbox();
			note.centerOffsets();
			note.centerOrigin();
		});
	}

	/**
	 * Applies a skin texture to a preview StrumNote instance.
	 *
	 * @param note The note instance to update.
	 */
	function changeNoteSkin(note:StrumNote):Void {
		var skin:String = Note.defaultNoteSkin;
		var customSkin:String = skin + Note.getNoteSkinPostfix();
		if (Paths.fileExists('images/$customSkin.png', IMAGE))
			skin = customSkin;
		note.texture = skin;
		note.reloadNote();
		note.playAnim('static');
	}

	/**
	 * Updates all live preview splashes to use the currently selected splash skin.
	 */
	function onChangeSplashSkin():Void {
		var skin:String = NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix();
		for (splash in splashes)
			splash.loadSplash(skin);
		playNoteSplashes();
	}

	/**
	 * Plays the note splash preview effects while preview mode is active.
	 */
	function playNoteSplashes():Void {
		if (!previewActive)
			return;

		var rand:Int = 0;
		if (splashes.members[0] != null && splashes.members[0].maxAnims > 1)
			rand = FlxG.random.int(0, splashes.members[0].maxAnims - 1);

		for (splash in splashes) {
			splash.revive();
			splash.spawnSplashNote(0, 0, splash.ID, null, false);

			if (splash.maxAnims > 1)
				splash.noteData = splash.noteData % Note.colArray.length + (rand * Note.colArray.length);
			splash.playDefaultAnim();
		}
	}

	/**
	 * Begins search mode for the options menu.
	 *
	 * This switches the UI into search mode, updates the prompt text,
	 * applies the current query, and opens the software keyboard on Android.
	 */
	function beginSearch():Void {
		searching = true;
		searchText.text = 'SEARCH: ' + query + '_';
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		applySearch();

		#if android
		mobile.backend.SoftKeyboard.open(searchType, searchBackspace, endSearch);
		#end
	}

	/**
	 * Ends search mode and restores normal options browsing state.
	 *
	 * If the query is empty, this resets to the current category view.
	 */
	function endSearch():Void {
		searching = false;

		#if android
		mobile.backend.SoftKeyboard.close();
		#end

		if (query.length == 0)
			selectCategory(curCat, false);
		else
			searchText.text = 'SEARCH: ' + query;
		refreshSidebar();
	}

	/**
	 * Processes keyboard input while the options search field is active.
	 *
	 * This handles Enter/Escape to end search, backspace and alphanumeric input to
	 * update the query, and navigation input while searching.
	 */
	function handleSearchInput():Void {
		var k:Int = FlxG.keys.firstJustPressed();
		if (k == 13 || k == 27) {
			endSearch();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			return;
		}

		if (k == 8)
			query = query.length > 0 ? query.substr(0, query.length - 1) : '';
		else if (k == 32)
			query += ' ';
		else if ((k >= 65 && k <= 90) || (k >= 48 && k <= 57))
			query += String.fromCharCode(k).toLowerCase();
		else {
			if (controls.UI_UP_P)
				moveRow(-1);
			if (controls.UI_DOWN_P)
				moveRow(1);
			var o:Option = focusedOption();
			if (o != null)
				editFocused(o, FlxG.elapsed);

			handleMouse();
			return;
		}

		searchText.text = 'SEARCH: ' + query + '_';
		applySearch();
	}

	/**
	 * Applies the current search query to the options list and updates the sidebar/rows.
	 *
	 * If the query is empty, the current category rows are shown. Otherwise the list is
	 * filtered to settings whose name or description contains the query text.
	 */
	function applySearch():Void {
		var q:String = query.toLowerCase().trim();
		setHeader(q.length == 0 ? categoryName(sidebar[curCat]) : 'Search Results');

		if (q.length == 0) {
			curRows = switch (sidebar[curCat]) {
				case Group(_, rows): rows;
				default: [];
			}

			// Oh lord have mercy on me, indentation hell (temporary) PART 2
		} else {
			curRows = [];
			for (entry in sidebar)
				switch (entry) {
					case Group(_, rows):
						for (row in rows)
							switch (row) {
								case Setting(o):
									if (o.name.toLowerCase().indexOf(q) >= 0
										|| (o.description != null && o.description.toLowerCase().indexOf(q) >= 0)) curRows.push(row);
								default:
							}
					default:
				}
		}

		curRow = 0;
		rowScroll = 0;

		for (i in 0...sbBgs.length)
			sbBgs[i].alpha = 0;
		buildRows();

		if (curRows.length > 0)
			selectRow(0);
		else {
			descText.text = 'No results.';
			updatePreviewVisibility();
		}
	}

	#if android
	/**
	 * Appends typed input to the active search query and refreshes results.
	 *
	 * @param input The input text to add to the search query.
	 */
	function searchType(input:String):Void {
		query += input.toLowerCase();
		searchText.text = 'SEARCH: ' + query + '_';
		applySearch();
	}

	/**
	 * Removes the last character from the active search query and refreshes results.
	 */
	function searchBackspace():Void {
		if (query.length > 0) {
			query = query.substr(0, query.length - 1);
			searchText.text = 'SEARCH: ' + query + '_';
			applySearch();
		}
	}
	#end

	/**
	 * Launches a specialized options substate or navigation action.
	 *
	 * @param which State to launch.
	 */
	function launch(which:String):Void {
		FlxG.sound.play(Paths.sound('confirmMenu'));
		ClientPrefs.saveSettings();
		switch (which) {
			case 'controls':
				openSubState(new ControlsSubState());
			case 'noteColors':
				openSubState(new NotesColorSubState());
			case 'gameplayChangers':
				openSubState(new GameplayChangersSubstate());
			case 'noteOffset':
				MusicBeatState.switchState(new NoteOffsetState());
			case 'fpsSettings':
				openSubState(new FPSCounterSettingsSubState());
			#if TRANSLATIONS_ALLOWED
			case 'language':
				openSubState(new LanguageSubState());
			#end
			#if MODS_ALLOWED
			case 'modSecurity':
				openSubState(new ModSecurityChecksSubState());
			#end
			#if mobile
			case 'mobile':
				openSubState(new mobile.options.MobileOptionsSubState());
			#end
			default:
		}
	}

	override function closeSubState() {
		super.closeSubState();
		ClientPrefs.saveSettings();
		persistentUpdate = true;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
	}

	/**
	 * Exits the options menu and returns to the appropriate game state.
	 *
	 * If the options menu was opened from gameplay, this returns to PlayState.
	 * Otherwise it returns to the main menu.
	 */
	function exitState():Void {
		quitting = true;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		ClientPrefs.saveSettings();

		if (onPlayState) {
			StageData.loadDirectory(PlayState.SONG);
			LoadingState.loadAndSwitchState(new PlayState());
			if (FlxG.sound.music != null)
				FlxG.sound.music.volume = 0;
		} else
			MusicBeatState.switchState(new MainMenuState());
	}

	/**
	 * Returns the currently focused option object, if any.
	 *
	 * @return The focused Option, or null if no option is selected.
	 */
	function focusedOption():Option {
		if (curRow < 0 || curRow >= curRows.length)
			return null;
		return optionOf(curRows[curRow]);
	}

	/**
	 * Extracts the Option instance from an OptionRow.
	 *
	 * @param row The row to evaluate.
	 * @return The Option if the row is a Setting, otherwise null.
	 */
	inline function optionOf(row:OptionRow):Option {
		return switch (row) {
			case Setting(o): o;
			default: null;
		}
	}

	/**
	 * Gets the display name for an option row.
	 *
	 * @param row The row whose name should be returned.
	 * @return The visible row name.
	 */
	function rowName(row:OptionRow):String {
		return switch (row) {
			case Setting(o): o.name;
			case Action(name, _, _): Language.getPhrase('options_$name', name);
		}
	}

	/**
	 * Gets the description text for an option row.
	 *
	 * @param row The row whose description should be returned.
	 * @return The row description.
	 */
	function rowDesc(row:OptionRow):String {
		return switch (row) {
			case Setting(o): o.description;
			case Action(_, desc, _): desc;
		}
	}

	/**
	 * Returns the display name for a sidebar entry.
	 *
	 * @param s The sidebar entry.
	 * @return The sidebar title.
	 */
	inline function categoryName(s:Sidebar):String {
		return switch (s) {
			case Group(name, _): name;
			case Launcher(name, _, _): name;
		}
	}

	/**
	 * Returns the launcher description for a sidebar entry.
	 *
	 * @param s The sidebar entry.
	 * @return The launcher description, or an empty string if none exists.
	 */
	inline function launcherDesc(s:Sidebar):String {
		return switch (s) {
			case Launcher(_, desc, _): desc;
			default: '';
		}
	}

	/**
	 * Formats an option's display value string.
	 *
	 * @param o The option to format.
	 * @return The formatted display string.
	 */
	function valueString(o:Option):String {
		var text:String = o.displayFormat;
		// Show PERCENT as actual %
		var vs:String = (o.type == PERCENT) ? Std.string(Math.round((o.getValue() : Float) * 100)) : Std.string(o.getValue());
		return text.replace('%v', vs).replace('%d', Std.string(o.defaultValue));
	}
		- /**
		 * Creates a small checkbox graphic for the options menu.
		 *
		 * @param on Whether the checkbox should be rendered in the checked state.
		 * @return A FlxGraphic containing the checkbox sprite.
		 */
		function makeCheckGraphic(on:Bool):FlxGraphic {
			var s:FlxSprite = new FlxSprite();
			s.makeGraphic(CHECKBOX_SIZE, CHECKBOX_SIZE, FlxColor.TRANSPARENT, false, 'optCheck_' + on);
			FlxSpriteUtil.drawRect(s, 1, 1, CHECKBOX_SIZE - 3, CHECKBOX_SIZE - 3, on ? 0xFF1E7A45 : FlxColor.TRANSPARENT,
				{thickness: 3, color: on ? 0xFF2EC46B : 0xFF8A8A8A});
			if (on) {
				FlxSpriteUtil.drawLine(s, 8, 18, 14, 25, {thickness: 4, color: FlxColor.WHITE});
				FlxSpriteUtil.drawLine(s, 14, 25, 27, 9, {thickness: 4, color: FlxColor.WHITE});
			}
			return s.graphic;
		}

	/**
	 * Helper function to make a stylized panel background.
	 *
	 * @param x The x position of the panel.
	 * @param y The y position of the panel.
	 * @param w The width of the panel.
	 * @param h The height of the panel.
	 */
	function makePanel(x:Int, y:Int, w:Int, h:Int):Void {
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

	/**
	 * Sets the options menu header text and constrains its scale so it fits the available width.
	 *
	 * @param text The header string to display.
	 */
	inline function setHeader(text:String):Void {
		headerAlpha.text = text;
		headerAlpha.setScale(1);
		if (headerAlpha.width > 740)
			headerAlpha.setScale(740 / headerAlpha.width);
		if (headerAlpha.scaleX > 0.9)
			headerAlpha.setScale(0.9);
	}

	/**
	 * Helper function to make FlxText instance for use throughout the options menu.
	 *
	 * @param x The x position of the text object.
	 * @param y The y position of the text object.
	 * @param w The width of the text object.
	 * @param text The initial text content.
	 * @param size The font size to use.
	 * @param align The text alignment.
	 * @return A configured FlxText instance.
	 */
	function makeText(x:Float, y:Float, w:Float, text:String, size:Int, align:flixel.text.FlxTextAlign):FlxText {
		var text:FlxText = new FlxText(x, y, w, text, size);
		text.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, align, OUTLINE, FlxColor.BLACK);
		text.borderSize = 1.5;
		text.scrollFactor.set();
		return text;
	}
}
