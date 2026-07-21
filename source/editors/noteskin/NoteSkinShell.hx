package editors.noteskin;

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
	The note-skin editor's chrome: menu bar, left icon rail, left dock, a center hole the simulated
	notefield renders into, a right dock, a transport band and a status bar -- the same editor
	language as `editors.charting.EditorShell`, scaled by `UITheme.scale`.

	Pure structure: every control is exposed as a typed field and `editors.noteskin.NoteSkinEditorState`
	wires the behaviour. The center region carries no blocking UI so the Flixel notefield underneath
	still receives pointer input.
**/
final class NoteSkinShell {
	/** The UI root everything is built into. **/
	public final root:UIRoot;

	public final menuH:Float;
	public final railW:Float;
	public final leftW:Float;
	public final rightW:Float;
	public final transportH:Float;
	public final statusH:Float;

	/** The notefield hole (UI/game coordinates - same space). **/
	public final fieldX:Float;

	public final fieldY:Float;
	public var fieldW(default, null):Float;
	public final fieldH:Float;

	public final viewW:Float;
	public final viewH:Float;

	/** The top menu bar (menus assigned by the owner). **/
	public final menuBar:UIMenuBar;

	/** Right-aligned "skin - family - keys" readout in the menu bar. **/
	public final skinLabel:UILabel;

	/** The left activity rail (tabs assigned by the owner). **/
	public final rail:UIIconRail;

	/** The left dock's scrollable content pane. **/
	public final leftPane:UIScrollPane;

	/** The right dock's scrollable content pane. **/
	public final rightPane:UIScrollPane;

	final rightEdge:UISeparator;

	/** `true` while the right dock is hidden (the field absorbs its width). **/
	public var rightHidden(default, null):Bool = false;

	public final transportPanel:UIPanel;

	/** Play/pause the simulation (drive it through `playing`). **/
	public final playBtn:UIButton;

	/** Restart the simulated pattern from the top. **/
	public final restartBtn:UIButton;

	final playIcon:UIIcon;

	public var playing(default, set):Bool = true;

	function set_playing(v:Bool):Bool {
		playing = v;
		playBtn.accent = v;
		playIcon.glyph = v ? UIGlyph.PAUSE : UIGlyph.PLAY;
		return v;
	}

	/** BPM readout / cycler for the simulated pattern. **/
	public final bpmChip:UIChip;

	/** Scroll-speed cycler. **/
	public final speedChip:UIChip;

	/** Keycount cycler. **/
	public final keysChip:UIChip;

	/** Scroll-direction toggle. **/
	public final scrollChip:UIChip;

	/** Forces the pixel render path on for previewing, without touching the skin. **/
	public final pixelChip:UIChip;

	/** Freezes the pattern for still inspection instead of scrolling it. **/
	public final staticChip:UIChip;

	public final statusPanel:UIPanel;

	/** Left status text (skin path + dirty marker). **/
	public final statusLeft:UILabel;

	/** Right status text (resolved sheet / element counts / FPS). **/
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
		restartBtn.tooltip = 'Restart the pattern';
		for (b in [playBtn, restartBtn]) {
			b.x = tx;
			b.y = iconY;
			c.addChild(b);
			tx += iconS + UITheme.px(6);
		}
		tx += UITheme.px(8);

		// Value chips (no dot) cycle on click; dot chips own their on/off state and fire `onToggle`.
		var chipY:Float = transportPanel.y + (transportH - UITheme.px(22)) / 2;
		bpmChip = addChip(c, 'BPM 150', 'Pattern tempo', tx, chipY, false);
		tx += UITheme.px(92);
		speedChip = addChip(c, 'Speed 2.4', 'Scroll speed', tx, chipY, false);
		tx += UITheme.px(104);
		keysChip = addChip(c, '4K', 'Column count', tx, chipY, false);
		tx += UITheme.px(62);
		scrollChip = addChip(c, 'Downscroll', 'Scroll downward', tx, chipY, true);
		tx += UITheme.px(112);
		pixelChip = addChip(c, 'Pixel preview', 'Force the pixel render path for previewing', tx, chipY, true);
		tx += UITheme.px(150);
		staticChip = addChip(c, 'Static', 'Freeze the pattern and cycle the receptor states', tx, chipY, true);

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
		menuBar.brand = 'NOTE SKIN EDITOR';
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
		Hides/shows the right dock; the notefield hole absorbs the freed width.
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
