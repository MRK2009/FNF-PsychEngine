package editors.uiskin;

import smidr.UIRoot;
import smidr.UITheme;
import smidr.types.UIGlyph;
import smidr.widgets.UIButton;
import smidr.widgets.UIChip;
import smidr.widgets.UIIcon;
import smidr.widgets.UIIconRail;
import smidr.widgets.UILabel;
import smidr.widgets.UIMenuBar;
import smidr.widgets.UIPanel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UISeparator;

/**
	The UI-skin editor's chrome: menu bar, left icon rail, left dock, a center hole the live popup
	preview renders into, a right dock, a transport band and a status bar -- the same editor language
	as `editors.noteskin.NoteSkinShell` and `editors.charting.EditorShell`, scaled by `UITheme.scale`.

	Pure structure: every control is exposed as a typed field and `editors.uiskin.UISkinEditorState`
	wires the behaviour. The center region carries no blocking UI so the Flixel preview underneath
	still receives pointer input -- the draggable placement handles depend on that.
**/
final class UISkinShell {
	/** The UI root everything is built into. **/
	public final root:UIRoot;

	public final menuH:Float;
	public final railW:Float;
	public final leftW:Float;
	public final rightW:Float;
	public final transportH:Float;
	public final statusH:Float;

	/** The preview hole (UI/game coordinates - same space). **/
	public final fieldX:Float;

	public final fieldY:Float;
	public var fieldW(default, null):Float;
	public final fieldH:Float;

	public final viewW:Float;
	public final viewH:Float;

	/** The top menu bar (menus assigned by the owner). **/
	public final menuBar:UIMenuBar;

	/** Right-aligned "skin - kind" readout in the menu bar. **/
	public final skinLabel:UILabel;

	/** The left activity rail (tabs assigned by the owner). **/
	public final rail:UIIconRail;

	/** The left dock's scrollable content pane. **/
	public final leftPane:UIScrollPane;

	/** The right dock's scrollable content pane (the inspector). **/
	public final rightPane:UIScrollPane;

	final rightEdge:UISeparator;

	/** `true` while the right dock is hidden (the preview absorbs its width). **/
	public var rightHidden(default, null):Bool = false;

	public final transportPanel:UIPanel;

	/** Play/pause the popup loop (drive it through `playing`). **/
	public final playBtn:UIButton;

	/** Replay the popup loop from the top. **/
	public final restartBtn:UIButton;

	final playIcon:UIIcon;

	public var playing(default, set):Bool = true;

	function set_playing(v:Bool):Bool {
		playing = v;
		playBtn.accent = v;
		playIcon.glyph = v ? UIGlyph.PAUSE : UIGlyph.PLAY;
		return v;
	}

	/** Which rating tier the preview shows. **/
	public final judgeChip:UIChip;

	/** The combo number drawn, so every digit can be checked. **/
	public final comboChip:UIChip;

	/** How fast popups fire. **/
	public final bpmChip:UIChip;

	/** Forces the pixel render path on for previewing, without touching the skin. **/
	public final pixelChip:UIChip;

	/** Freezes the popups for still inspection instead of replaying them. **/
	public final staticChip:UIChip;

	/** Shows the draggable placement handles over the preview. **/
	public final handlesChip:UIChip;

	public final statusPanel:UIPanel;

	/** Left status text (skin path + dirty marker). **/
	public final statusLeft:UILabel;

	/** Right status text (resolved kind / element coverage / FPS). **/
	public final statusRight:UILabel;

	/**
		Builds the full chrome into `root.content`.
		@param root the attached UI root
		@param viewW the game viewport width in UI units
		@param viewH the game viewport height in UI units
	**/
	public function new(root:UIRoot, viewW:Float, viewH:Float) {
		this.root = root;
		this.viewW = viewW;
		this.viewH = viewH;

		menuH = UITheme.px(15);
		railW = UITheme.px(46);
		leftW = UITheme.px(260);
		rightW = UITheme.px(250);
		transportH = UITheme.px(40);
		statusH = UITheme.px(22);

		var mainY:Float = menuH;
		var mainH:Float = viewH - mainY - transportH - statusH;
		fieldX = railW + leftW;
		fieldY = mainY;
		fieldW = viewW - fieldX - rightW;
		fieldH = mainH;

		var c = root.content;

		rail = new UIIconRail(railW, mainH, []);
		rail.y = mainY;
		c.addChild(rail);

		leftPane = new UIScrollPane(leftW, mainH);
		leftPane.x = railW;
		leftPane.y = mainY;
		c.addChild(leftPane);

		var leftEdge:UISeparator = new UISeparator(mainH, true);
		leftEdge.x = fieldX - 1;
		leftEdge.y = mainY;
		c.addChild(leftEdge);

		rightPane = new UIScrollPane(rightW, mainH);
		rightPane.x = viewW - rightW;
		rightPane.y = mainY;
		c.addChild(rightPane);

		rightEdge = new UISeparator(mainH, true);
		rightEdge.x = viewW - rightW;
		rightEdge.y = mainY;
		c.addChild(rightEdge);

		transportPanel = new UIPanel(viewW, transportH, PANEL);
		transportPanel.y = mainY + mainH;
		transportPanel.borderTop = true;
		c.addChild(transportPanel);

		var iconS:Float = UITheme.px(28);
		var iconY:Float = transportPanel.y + (transportH - iconS) / 2;
		var tx:Float = UITheme.px(8);

		playIcon = UIIcon.fromGlyph(UIGlyph.PAUSE, 16);
		playBtn = UIButton.icon(playIcon, iconS);
		playBtn.tooltip = 'Play / pause the preview';
		playBtn.accent = true;
		restartBtn = UIButton.icon(UIIcon.fromGlyph(UIGlyph.PREV, 16), iconS);
		restartBtn.tooltip = 'Replay the popups from the top';
		for (b in [playBtn, restartBtn]) {
			b.x = tx;
			b.y = iconY;
			c.addChild(b);
			tx += iconS + UITheme.px(6);
		}
		tx += UITheme.px(8);

		// Value chips (no dot) cycle on click; dot chips own their on/off state and fire `onToggle`.
		var chipY:Float = transportPanel.y + (transportH - UITheme.px(22)) / 2;
		judgeChip = addChip(c, 'sick', 'Which rating the preview shows', tx, chipY, false);
		tx += UITheme.px(78);
		comboChip = addChip(c, 'Combo 123', 'Combo number drawn, for checking every digit', tx, chipY, false);
		tx += UITheme.px(118);
		bpmChip = addChip(c, 'BPM 150', 'How fast popups fire', tx, chipY, false);
		tx += UITheme.px(92);
		handlesChip = addChip(c, 'Handles', 'Drag the rating / combo / numbers to place them', tx, chipY, true);
		tx += UITheme.px(96);
		pixelChip = addChip(c, 'Pixel preview', 'Force the pixel render path for previewing', tx, chipY, true);
		tx += UITheme.px(150);
		staticChip = addChip(c, 'Static', 'Hold the popups on screen instead of replaying them', tx, chipY, true);

		statusPanel = new UIPanel(viewW, statusH, PANEL2);
		statusPanel.y = viewH - statusH;
		statusPanel.borderTop = true;
		c.addChild(statusPanel);

		statusLeft = new UILabel('no skin loaded', 10, 2);
		statusLeft.render();
		statusLeft.x = UITheme.px(10);
		statusLeft.y = statusPanel.y + (statusH - statusLeft.height) / 2;
		c.addChild(statusLeft);

		statusRight = new UILabel('', 10, 2);
		statusRight.render();
		statusRight.x = viewW - UITheme.px(10);
		statusRight.y = statusLeft.y;
		c.addChild(statusRight);

		menuBar = new UIMenuBar(viewW, menuH);
		menuBar.brand = 'UI SKIN EDITOR';
		c.addChild(menuBar);

		skinLabel = new UILabel('no skin loaded', 11, 1);
		c.addChild(skinLabel);

		layoutMenuExtras();
		layoutStatus();
	}

	function addChip(c:openfl.display.Sprite, text:String, tip:String, x:Float, y:Float, dot:Bool):UIChip {
		var chip:UIChip = new UIChip(text, dot);
		chip.tooltip = tip;
		chip.x = x;
		chip.y = y;
		c.addChild(chip);
		return chip;
	}

	/**
		Hides/shows the right dock; the preview hole absorbs the freed width.
		@param hidden `true` to hide the right dock
	**/
	public function setRightHidden(hidden:Bool):Void {
		rightHidden = hidden;
		rightPane.visible = !hidden;
		rightEdge.visible = !hidden;
		fieldW = viewW - fieldX - (hidden ? 0 : rightW);
	}

	/** Re-anchors the right side of the menu bar (call after changing `skinLabel.text`). **/
	public function layoutMenuExtras():Void {
		skinLabel.render();
		skinLabel.x = viewW - UITheme.px(12) - skinLabel.width;
		skinLabel.y = (menuH - skinLabel.height) / 2;
	}

	/** Re-anchors the right status text (call after changing `statusRight.text`). **/
	public function layoutStatus():Void {
		statusRight.render();
		statusRight.x = viewW - UITheme.px(10) - statusRight.width;
	}
}
