package editors.charting;

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
	The editor chrome: slim menu bar, left icon rail, left dock, center notefield hole,
	right dock (hideable - `setCombined` folds it into the left dock's rail), transport and
	status bar - all scaled by `UITheme.scale`. Builds pure structure and exposes every control
	as a typed public field; `editors.ChartingState` wires behavior and the
	panel builders fill the dock scroll panes. The center region stays free of blocking UI so
	the Flixel notefield underneath receives pointer input.
**/
final class EditorShell {
	/** The UI root everything is built into. **/
	public final root:UIRoot;

	/** Menu bar height (scaled). **/
	public final menuH:Float;

	/** Icon rail width (scaled). **/
	public final railW:Float;

	/** Left dock width (scaled). **/
	public final leftW:Float;

	/** Right dock width (scaled). **/
	public final rightW:Float;

	/** Transport bar height (scaled). **/
	public final transportH:Float;

	/** Status bar height (scaled). **/
	public final statusH:Float;

	/** The notefield hole's left edge (UI/game coordinates - same space). **/
	public final fieldX:Float;

	/** The notefield hole's top edge. **/
	public final fieldY:Float;

	/** The notefield hole's width (grows in combined mode). **/
	public var fieldW(default, null):Float;

	/** The notefield hole's height. **/
	public final fieldH:Float;

	/** Viewport width the chrome was built for. **/
	public final viewW:Float;

	/** Viewport height the chrome was built for. **/
	public final viewH:Float;

	/** `true` while the right dock is folded into the left dock (extra rail tabs). **/
	public var combined(default, null):Bool = false;

	/** The top menu bar (menus assigned by the owner). **/
	public final menuBar:UIMenuBar;

	/** Right-aligned "song - difficulty - keys" readout in the menu bar. **/
	public final songLabel:UILabel;

	/** Menu-bar search button. **/
	public final searchBtn:UIButton;

	/** Menu-bar gear button (jumps to the Options tab). **/
	public final optionsBtn:UIButton;

	/** The left activity rail (tabs assigned by the owner). **/
	public final rail:UIIconRail;

	/** The left dock's scrollable content pane. **/
	public final leftPane:UIScrollPane;

	/** The right dock's scrollable content pane (hidden in combined mode). **/
	public final rightPane:UIScrollPane;

	final rightEdge:UISeparator;

	/** The transport band background. **/
	public final transportPanel:UIPanel;

	/** Previous-section transport button. **/
	public final prevBtn:UIButton;

	/** Play/pause transport button (drive it through `playing`). **/
	public final playBtn:UIButton;

	/** Next-section transport button. **/
	public final nextBtn:UIButton;

	/** Stop transport button. **/
	public final stopBtn:UIButton;

	/** Section-loop toggle button (drive it through `looping`). **/
	public final loopBtn:UIButton;

	final playIcon:UIIcon;

	/** Playback state shown on the play button (accent + play/pause glyph swap). **/
	public var playing(default, set):Bool = false;

	/** Section-loop state shown on the loop button. **/
	public var looping(default, set):Bool = false;

	function set_playing(v:Bool):Bool {
		playing = v;
		playBtn.accent = v;
		playIcon.glyph = v ? UIGlyph.PAUSE : UIGlyph.PLAY;
		return v;
	}

	function set_looping(v:Bool):Bool {
		looping = v;
		loopBtn.accent = v;
		return v;
	}

	/** Playhead-BPM readout chip. **/
	public final bpmChip:UIChip;

	/** Grid snap cycling chip. **/
	public final snapChip:UIChip;

	/** Grid zoom cycling chip. **/
	public final zoomChip:UIChip;

	/** Playback rate cycling chip. **/
	public final rateChip:UIChip;

	/** The scrubbable song strip. **/
	public final timeline:TransportTimeline;

	/** Right-aligned "position / length" readout. **/
	public final timeLabel:UILabel;

	/** The status band background. **/
	public final statusPanel:UIPanel;

	/** Left status text (section/step/selection). **/
	public final statusLeft:UILabel;

	/** Right status text (autosave/backups/FPS). **/
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
		leftW = UITheme.px(250);
		rightW = UITheme.px(280);
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

		prevBtn = UIButton.icon(UIIcon.fromGlyph(UIGlyph.PREV, 16), iconS);
		prevBtn.tooltip = "Previous section";
		playIcon = UIIcon.fromGlyph(UIGlyph.PLAY, 16);
		playBtn = UIButton.icon(playIcon, iconS);
		playBtn.tooltip = "Play / pause";
		playBtn.tooltipShortcut = "Space";
		nextBtn = UIButton.icon(UIIcon.fromGlyph(UIGlyph.NEXT, 16), iconS);
		nextBtn.tooltip = "Next section";
		stopBtn = UIButton.icon(UIIcon.fromGlyph(UIGlyph.STOP, 16), iconS);
		stopBtn.tooltip = "Stop and return";
		loopBtn = UIButton.icon(UIIcon.fromGlyph(UIGlyph.LOOP, 16), iconS);
		loopBtn.tooltip = "Loop section";
		for (b in [prevBtn, playBtn, nextBtn, stopBtn, loopBtn]) {
			b.x = tx;
			b.y = iconY;
			c.addChild(b);
			tx += iconS + UITheme.px(6);
		}
		tx += UITheme.px(6);

		bpmChip = new UIChip("BPM 150");
		bpmChip.tooltip = "Song BPM at the playhead";
		bpmChip.x = tx;
		bpmChip.y = transportPanel.y + (transportH - bpmChip.h) / 2;
		c.addChild(bpmChip);
		tx += bpmChip.w + UITheme.px(12);

		snapChip = new UIChip("Snap 1/16");
		snapChip.tooltip = "Grid snap";
		snapChip.x = tx;
		snapChip.y = transportPanel.y + (transportH - snapChip.h) / 2;
		c.addChild(snapChip);
		tx += UITheme.px(108);

		zoomChip = new UIChip("Zoom 1x");
		zoomChip.tooltip = "Grid zoom";
		zoomChip.x = tx;
		zoomChip.y = snapChip.y;
		c.addChild(zoomChip);
		tx += UITheme.px(96);

		rateChip = new UIChip("Rate 1.00x");
		rateChip.tooltip = "Playback rate";
		rateChip.x = tx;
		rateChip.y = snapChip.y;
		c.addChild(rateChip);
		tx += UITheme.px(104) + UITheme.px(6);

		timeLabel = new UILabel("00:00.000 / 00:00.000", 12, 1);
		timeLabel.render();
		timeLabel.x = viewW - UITheme.px(12) - timeLabel.width;
		timeLabel.y = transportPanel.y + (transportH - timeLabel.height) / 2;
		c.addChild(timeLabel);

		var stripH:Float = UITheme.px(16);
		timeline = new TransportTimeline(timeLabel.x - UITheme.px(14) - tx, stripH);
		timeline.x = tx;
		timeline.y = transportPanel.y + (transportH - stripH) / 2;
		c.addChild(timeline);

		statusPanel = new UIPanel(viewW, statusH, PANEL2);
		statusPanel.y = viewH - statusH;
		statusPanel.borderTop = true;
		c.addChild(statusPanel);

		statusLeft = new UILabel("Beat 0 - Step 0 - Selected: 0", 10, 2);
		statusLeft.render();
		statusLeft.x = UITheme.px(10);
		statusLeft.y = statusPanel.y + (statusH - statusLeft.height) / 2;
		c.addChild(statusLeft);

		statusRight = new UILabel("autosave: off - backups: 0 - 60 FPS", 10, 2);
		statusRight.render();
		statusRight.x = viewW - UITheme.px(10) - statusRight.width;
		statusRight.y = statusPanel.y + (statusH - statusRight.height) / 2;
		c.addChild(statusRight);

		menuBar = new UIMenuBar(viewW, menuH);
		menuBar.brand = "CHART EDITOR";
		c.addChild(menuBar);

		songLabel = new UILabel("no song loaded", 11, 1);
		c.addChild(songLabel);

		searchBtn = new UIButton("Search", UITheme.px(64), menuH);
		searchBtn.fontSize = 10;
		searchBtn.tooltipShortcut = "Ctrl+K";
		c.addChild(searchBtn);

		optionsBtn = UIButton.icon(UIIcon.fromGlyph(UIGlyph.GEAR, 10), menuH);
		optionsBtn.tooltip = "Editor options";
		c.addChild(optionsBtn);

		layoutMenuExtras();
	}

	/**
		Hides/shows the right dock; the notefield hole absorbs the freed width.
		@param on `true` = combined mode (right dock folded into the left rail)
	**/
	public function setCombined(on:Bool):Void {
		combined = on;
		rightPane.visible = !on;
		rightEdge.visible = !on;
		fieldW = viewW - fieldX - (on ? 0 : rightW);
	}

	/** Re-anchors the right side of the menu bar (call after changing `songLabel.text`). **/
	public function layoutMenuExtras():Void {
		songLabel.render();
		var rx:Float = viewW - UITheme.px(8);
		rx -= optionsBtn.w;
		optionsBtn.x = rx;
		optionsBtn.y = (menuH - optionsBtn.h) / 2;
		rx -= UITheme.px(6) + searchBtn.w;
		searchBtn.x = rx;
		searchBtn.y = (menuH - searchBtn.h) / 2;
		rx -= UITheme.px(12) + songLabel.width;
		songLabel.x = rx;
		songLabel.y = (menuH - songLabel.height) / 2;
	}

	/** Re-anchors the transport time readout (call after changing `timeLabel.text`). **/
	public function layoutTime():Void {
		timeLabel.render();
		timeLabel.x = viewW - UITheme.px(12) - timeLabel.width;
	}

	/** Re-anchors the right status text (call after changing `statusRight.text`). **/
	public function layoutStatus():Void {
		statusRight.render();
		statusRight.x = viewW - UITheme.px(10) - statusRight.width;
	}
}

/**
	The transport's scrubbable song strip: progress fill + playhead tick; click or drag
	anywhere to seek (`onScrub(progress 0..1)` fires while dragging).
**/
final class TransportTimeline extends smidr.UIComponent {
	/** Playback progress 0..1 (owner-driven). **/
	public var progress(default, set):Float = 0;

	/** Fired with the target progress while clicking/dragging. **/
	public var onScrub:Float->Void = null;

	/**
		@param width the strip width
		@param height the strip height
	**/
	public function new(width:Float, height:Float) {
		super(true, true);
		hoverCursor = null;
		resize(width, height);
		render();
	}

	override function onPress(localX:Float, localY:Float):Void {
		scrubAt(localX);
		beginCapture();
	}

	override function onDragMove(stageX:Float, stageY:Float):Void {
		scrubAt(globalToLocal(new openfl.geom.Point(stageX, stageY)).x);
	}

	function scrubAt(localX:Float):Void {
		var p:Float = localX / w;
		if (p < 0)
			p = 0;
		if (p > 1)
			p = 1;
		if (onScrub != null)
			onScrub(p);
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		var r:Float = UITheme.px(5);
		g.beginFill(smidr.UIColor.rgb(UITheme.inputBg));
		g.drawRoundRect(0, 0, w, h, r, r);
		g.endFill();
		if (progress > 0) {
			g.beginFill(smidr.UIColor.rgb(UITheme.accentDark), 0.55);
			g.drawRoundRect(1, 1, (w - 2) * progress, h - 2, r, r);
			g.endFill();
		}
		g.lineStyle(1, smidr.UIColor.rgb(UITheme.border));
		g.drawRoundRect(0.5, 0.5, w - 1, h - 1, r, r);
		g.lineStyle();
		g.beginFill(smidr.UIColor.rgb(UITheme.accent));
		var px:Float = 1 + (w - 3) * progress;
		g.drawRect(px, 1, 2, h - 2);
		g.endFill();
	}

	function set_progress(v:Float):Float {
		if (v < 0)
			v = 0;
		if (v > 1)
			v = 1;
		if (v != progress) {
			progress = v;
			invalidate();
		}
		return v;
	}
}
