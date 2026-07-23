package editors.mobile;

import flixel.FlxG;
import mobile.backend.SafeArea;
import openfl.display.Sprite;
import smidr.UIComponent;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.flixel.FlxSmidr;
import smidr.widgets.UIButton;
import smidr.widgets.UIDrawer;
import smidr.widgets.UILabel;
import smidr.widgets.UIModal;
import smidr.widgets.UIPanel;
import smidr.widgets.UIScrollPane;

/**
 * Android-first editor chrome, designed for a landscape phone held in two hands:
 *
 * - two THUMB RAILS of big labeled buttons hugging the left/right screen edges (inset so they
 *   don't fight the system back gesture), the canvas filling everything behind them;
 * - a slim translucent STATUS STRIP across the top center (song / section / time / zoom);
 * - a right-edge DRAWER hosting full-height flyout pages (note types, snap, settings) with
 *   large rows -- opened from rail buttons, never by edge swipe (that edge belongs to Android);
 * - a floating bottom ACTION BAR for contextual actions on the current selection;
 * - a GESTURE GUIDE modal (first run + on demand) explaining the touch controls.
 *
 * Pure chrome: the owning editor wires callbacks and fills the drawer pages. Runs under the
 * SmidrUI mobile theme preset so every control is finger-sized.
 */
class MobileEditorShell {
	public final root:UIRoot;

	// Layout constants (logical px on the 1280x720 game surface).
	public static inline var RAIL_W:Float = 168;
	public static inline var RAIL_BTN_H:Float = 60;
	public static inline var STRIP_H:Float = 38;
	public static inline var DRAWER_W:Float = 500;

	final mainUI:Sprite;
	final leftRail:Sprite;
	final rightRail:Sprite;
	var leftY:Float = 8;
	var rightY:Float = 8;

	// Screen edges the chrome must keep clear of (notch / rounded corners); 0 on a plain screen.
	final safeL:Float;
	final safeT:Float;
	final safeR:Float;
	final safeB:Float;

	final statusLabel:UILabel;

	final drawer:UIDrawer;
	final drawerTitle:UILabel;
	final drawerPane:UIScrollPane;

	/** Title of the page last built into the drawer, so an editor can tell which one is on screen. **/
	public var pageTitle(default, null):String = '';

	final actionBar:Sprite;
	var actionBarBg:UIPanel;
	var actionX:Float = 0;

	var guideModal:UIModal = null;
	var promptModal:UIModal = null;

	public function new() {
		UITheme.applyMobilePreset();

		// Chrome is placed against the safe box, not 0/FlxG.width -- the surface spans the whole panel.
		// The rails and bars span a full edge each, so they take the corner radius on top of the cutout.
		SafeArea.refresh();
		final corner:Float = SafeArea.cornerRadius;
		safeL = Math.max(SafeArea.left, corner);
		safeT = Math.max(SafeArea.top, corner);
		safeR = Math.max(SafeArea.right, corner);
		safeB = Math.max(SafeArea.bottom, corner);

		root = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		mainUI = new Sprite();
		root.content.addChild(mainUI);

		// Status strip: translucent, centered between the rails.
		var stripW:Float = FlxG.width - safeL - safeR - RAIL_W * 2 - 20;
		var strip:UIPanel = new UIPanel(stripW, STRIP_H, 0xB4141419);
		strip.x = safeL + RAIL_W + 10;
		strip.y = safeT;
		mainUI.addChild(strip);

		statusLabel = new UILabel('', 16, 0);
		statusLabel.x = strip.x + 14;
		statusLabel.y = safeT + (STRIP_H - 22) / 2;
		mainUI.addChild(statusLabel);

		// Thumb rails (slightly translucent so the grid reads as full-screen).
		var railH:Float = FlxG.height - safeT - safeB;
		leftRail = new Sprite();
		rightRail = new Sprite();
		var lp:UIPanel = new UIPanel(RAIL_W, railH, 0xE0191920);
		leftRail.addChild(lp);
		var rp:UIPanel = new UIPanel(RAIL_W, railH, 0xE0191920);
		rightRail.addChild(rp);
		leftRail.x = safeL;
		leftRail.y = safeT;
		rightRail.x = FlxG.width - safeR - RAIL_W;
		rightRail.y = safeT;
		mainUI.addChild(leftRail);
		mainUI.addChild(rightRail);

		// Drawer: rail-opened flyout pages. Edge swipe stays OFF -- Android's back gesture owns
		// the screen edges, so panels open from explicit buttons only.
		drawer = new UIDrawer(UIDrawerSide.RIGHT, DRAWER_W);
		drawer.edgeSwipeEnabled = false;
		drawer.edgeInset = safeR;
		drawerTitle = new UILabel('', 20, 0);
		drawerTitle.x = 18;
		drawerTitle.y = safeT + 14;
		drawer.content.addChild(drawerTitle);
		drawerPane = new UIScrollPane(DRAWER_W - 28, FlxG.height - safeT - safeB - 60);
		drawerPane.x = 14;
		drawerPane.y = safeT + 48;
		drawer.content.addChild(drawerPane);

		// Floating contextual action bar (bottom center, shown while something is selected).
		actionBar = new Sprite();
		actionBar.visible = false;
		mainUI.addChild(actionBar);
	}

	// ---- Rails ----

	/** Adds the next big button to the left thumb rail. **/
	public function addLeft(label:String, cb:Void->Void, accent:Bool = false):UIButton {
		return railButton(leftRail, label, cb, accent, true);
	}

	/** Adds the next big button to the right thumb rail. **/
	public function addRight(label:String, cb:Void->Void, accent:Bool = false):UIButton {
		return railButton(rightRail, label, cb, accent, false);
	}

	/** Vertical breathing room before the next rail button (visual grouping). **/
	public function railGap(left:Bool, h:Float = 12):Void {
		if (left)
			leftY += h;
		else
			rightY += h;
	}

	function railButton(rail:Sprite, label:String, cb:Void->Void, accent:Bool, left:Bool):UIButton {
		var b:UIButton = new UIButton(label, RAIL_W - 16, RAIL_BTN_H, cb, accent);
		// The mobile preset scales button fonts ~1.4x; 13 lands at ~18 effective, which still fits the
		// longest labels ("SETTINGS", "MULTI: OFF") on the wider rail.
		b.fontSize = 13;
		b.x = 8;
		if (left) {
			b.y = leftY;
			leftY += RAIL_BTN_H + 6;
		} else {
			b.y = rightY;
			rightY += RAIL_BTN_H + 6;
		}
		rail.addChild(b);
		return b;
	}

	// ---- Status ----

	public function setStatus(text:String):Void {
		statusLabel.text = text;
	}

	// ---- Drawer pages ----

	/**
		Opens the drawer showing one page. `build` fills the pane's content (children positioned
		from y=0, width `pageWidth()`) and returns the content height for the scroll range.
	**/
	public function openPage(title:String, build:UIScrollPane->Float):Void {
		drawerTitle.text = title;
		pageTitle = title;
		var i:Int = drawerPane.content.numChildren;
		while (--i >= 0) {
			var c = drawerPane.content.getChildAt(i);
			if (c is UIComponent)
				(cast c : UIComponent).dispose();
		}
		drawerPane.content.removeChildren();
		var h:Float = build(drawerPane);
		drawerPane.refreshContent(h);
		drawerPane.setScroll(0);
		drawer.open();
	}

	/** Width available to widgets inside a drawer page. **/
	public inline function pageWidth():Float {
		return drawerPane.w - 18;
	}

	public function closeDrawer():Void {
		drawer.close();
	}

	public var drawerOpen(get, never):Bool;

	inline function get_drawerOpen():Bool {
		return drawer.isOpen;
	}

	// ---- Contextual action bar ----

	/** Replaces the action bar's buttons: an array of label / accent-or-danger / callback rows. **/
	public function setActionBar(items:Array<{label:String, cb:Void->Void, ?danger:Bool}>):Void {
		var i:Int = actionBar.numChildren;
		while (--i >= 0) {
			var c = actionBar.getChildAt(i);
			if (c is UIComponent)
				(cast c : UIComponent).dispose();
		}
		actionBar.removeChildren();

		var btnH:Float = 66;
		var pad:Float = 10;
		// The bar must stay between the thumb rails: with many actions the buttons shrink to fit
		// instead of sliding under (and behind) the right rail, where they can't be tapped.
		var avail:Float = FlxG.width - safeL - safeR - RAIL_W * 2 - 16;
		var btnW:Float = 140;
		var maxBtnW:Float = (avail - pad) / items.length - pad;
		if (items.length > 0 && maxBtnW < btnW)
			btnW = Math.max(64, maxBtnW);
		var totalW:Float = items.length * (btnW + pad) + pad;

		actionBarBg = new UIPanel(totalW, btnH + pad * 2, 0xE61E1E26);
		actionBar.addChild(actionBarBg);

		actionX = pad;
		for (item in items) {
			var danger:Bool = (item.danger == true);
			var b:UIButton = new UIButton(item.label, btnW, btnH, item.cb, !danger);
			if (danger)
				b.danger = true;
			b.fontSize = 13;
			b.x = actionX;
			b.y = pad;
			actionBar.addChild(b);
			actionX += btnW + pad;
		}

		actionBar.x = safeL + (FlxG.width - safeL - safeR - totalW) / 2;
		actionBar.y = FlxG.height - safeB - (btnH + pad * 2) - 14;
	}

	public function showActionBar(show:Bool):Void {
		actionBar.visible = show;
	}

	// ---- Gesture guide ----

	/**
		Shows the touch-controls guide modal. Each line is split at its first run of two-or-more
		spaces into a gesture column and a description column, both word-wrapped, so long entries
		stay inside the panel instead of running off it. `onDismiss` fires when it closes.
	**/
	public function showGuide(lines:Array<String>, ?onDismiss:Void->Void):Void {
		if (guideModal != null)
			return;

		final pad:Float = UITheme.px(20);
		final gap:Float = UITheme.px(14);
		final titleH:Float = UITheme.px(40);
		final btnH:Float = UITheme.px(46);

		var panelW:Float = Math.min(920, FlxG.width - safeL - safeR - 80);
		var innerW:Float = panelW - pad * 2;
		var keyW:Float = innerW * 0.34;
		var descW:Float = innerW - keyW - gap;

		var m:UIModal = new UIModal('TOUCH CONTROLS', panelW, titleH + btnH + pad * 3);

		var pane:UIScrollPane = new UIScrollPane(innerW, btnH);
		pane.x = pad;
		pane.y = 0;

		var y:Float = 0;
		for (line in lines) {
			var key:String = line;
			var desc:String = '';
			var cut:Int = columnSplit(line);
			if (cut > 0) {
				key = StringTools.rtrim(line.substr(0, cut));
				desc = StringTools.ltrim(line.substr(cut));
			}

			var keyLbl:UILabel = new UILabel(key, 15, 0);
			keyLbl.wrapWidth = keyW;
			var rowH:Float = keyLbl.measure();
			keyLbl.y = y;
			pane.content.addChild(keyLbl);

			if (desc.length > 0) {
				var descLbl:UILabel = new UILabel(desc, 15, 2);
				descLbl.wrapWidth = descW;
				var descH:Float = descLbl.measure();
				descLbl.x = keyW + gap;
				descLbl.y = y;
				pane.content.addChild(descLbl);
				if (descH > rowH)
					rowH = descH;
			}

			y += rowH + UITheme.px(10);
		}

		var maxPaneH:Float = FlxG.height - safeT - safeB - titleH - btnH - pad * 4;
		var paneH:Float = Math.min(y, maxPaneH);
		pane.resize(innerW, paneH);
		pane.refreshContent(y);
		m.body.addChild(pane);

		var okW:Float = UITheme.px(200);
		var ok:UIButton = new UIButton('GOT IT', okW, btnH, function() m.close(), true);
		ok.fontSize = 15;
		ok.x = (panelW - okW) / 2;
		ok.y = paneH + pad;
		m.body.addChild(ok);

		m.resize(panelW, titleH + paneH + pad * 2 + btnH);
		m.onClosed = function() {
			guideModal = null;
			if (onDismiss != null)
				onDismiss();
		};
		guideModal = m;
		m.open();
	}

	/** Index of the first run of two-or-more spaces (the gesture/description column break), or -1. **/
	static function columnSplit(line:String):Int {
		var i:Int = line.indexOf('  ');
		return (i > 0) ? i : -1;
	}

	public var guideOpen(get, never):Bool;

	inline function get_guideOpen():Bool {
		return guideModal != null;
	}

	public function closeGuide():Void {
		if (guideModal != null)
			guideModal.close();
	}

	// ---- Prompt ----

	/**
		Shows a finger-sized question modal: a wrapped message over one big button per choice
		(laid out in a row, or stacked when they would not fit). The picked callback fires after
		the modal closes so the caller may switch state from it. `onCancel` fires when the modal
		is dismissed by the backdrop / Escape / Android back instead.
		@param title the header text
		@param message the question body
		@param choices the buttons, left to right
		@param onCancel fired on dismissal without a choice
	**/
	public function showPrompt(title:String, message:String, choices:Array<{label:String, cb:Void->Void, ?danger:Bool, ?accent:Bool}>,
			?onCancel:Void->Void):Void {
		if (promptModal != null)
			return;

		final pad:Float = UITheme.px(20);
		final gap:Float = UITheme.px(10);
		final titleH:Float = UITheme.px(40);
		final btnH:Float = UITheme.px(56);

		var panelW:Float = Math.min(760, FlxG.width - safeL - safeR - 80);
		var innerW:Float = panelW - pad * 2;

		var m:UIModal = new UIModal(title, panelW, titleH + btnH + pad * 3);

		var msg:UILabel = new UILabel(message, 15, 0);
		msg.wrapWidth = innerW;
		var msgH:Float = msg.measure();
		msg.x = pad;
		msg.y = 0;
		m.body.addChild(msg);

		// One row while every button keeps a usable width; otherwise a stack.
		var count:Int = choices.length;
		var rowW:Float = (count > 0) ? (innerW - gap * (count - 1)) / count : innerW;
		var stacked:Bool = rowW < UITheme.px(150);

		var y:Float = msgH + pad;
		var x:Float = pad;
		var picked:Void->Void = null;

		for (choice in choices) {
			var cb:Void->Void = choice.cb;
			var b:UIButton = new UIButton(choice.label, stacked ? innerW : rowW, btnH, function():Void {
				picked = cb;
				m.close();
			}, choice.accent == true);
			if (choice.danger == true)
				b.danger = true;
			b.fontSize = 14;
			b.x = stacked ? pad : x;
			b.y = y;
			m.body.addChild(b);
			if (stacked)
				y += btnH + gap;
			else
				x += rowW + gap;
		}

		var buttonsH:Float = stacked ? (count * (btnH + gap) - gap) : btnH;
		m.resize(panelW, titleH + msgH + pad * 2 + buttonsH);
		m.onClosed = function():Void {
			promptModal = null;
			if (picked != null)
				picked();
			else if (onCancel != null)
				onCancel();
		};
		promptModal = m;
		m.open();
	}

	public var promptOpen(get, never):Bool;

	inline function get_promptOpen():Bool {
		return promptModal != null;
	}

	public function closePrompt():Void {
		if (promptModal != null)
			promptModal.close();
	}

	public function dispose():Void {
		if (guideModal != null)
			guideModal.close();
		if (promptModal != null) {
			promptModal.onClosed = null;
			promptModal.close();
			promptModal = null;
		}
		FlxSmidr.dispose();
		UITheme.clearMobilePreset();
	}
}
