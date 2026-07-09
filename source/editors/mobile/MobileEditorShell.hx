package editors.mobile;

import flixel.FlxG;
import openfl.display.Sprite;
import smidr.UIComponent;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.flixel.FlxSmidr;
import smidr.types.UISurface;
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
	public static inline var RAIL_W:Float = 150;
	public static inline var RAIL_BTN_H:Float = 62;
	public static inline var STRIP_H:Float = 36;

	final mainUI:Sprite;
	final leftRail:Sprite;
	final rightRail:Sprite;
	var leftY:Float = 8;
	var rightY:Float = 8;

	final statusLabel:UILabel;

	final drawer:UIDrawer;
	final drawerTitle:UILabel;
	final drawerPane:UIScrollPane;

	final actionBar:Sprite;
	var actionBarBg:UIPanel;
	var actionX:Float = 0;

	var guideModal:UIModal = null;

	public function new() {
		UITheme.applyMobilePreset();

		root = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		mainUI = new Sprite();
		root.content.addChild(mainUI);

		// Status strip: translucent, centered between the rails.
		var stripW:Float = FlxG.width - RAIL_W * 2 - 20;
		var strip:UIPanel = UIPanel.solid(stripW, STRIP_H, 0xB4141419);
		strip.x = RAIL_W + 10;
		strip.y = 0;
		mainUI.addChild(strip);

		statusLabel = new UILabel('', 15, 0);
		statusLabel.x = strip.x + 14;
		statusLabel.y = (STRIP_H - 20) / 2;
		mainUI.addChild(statusLabel);

		// Thumb rails (slightly translucent so the grid reads as full-screen).
		leftRail = new Sprite();
		rightRail = new Sprite();
		var lp:UIPanel = UIPanel.solid(RAIL_W, FlxG.height, 0xE0191920);
		leftRail.addChild(lp);
		var rp:UIPanel = UIPanel.solid(RAIL_W, FlxG.height, 0xE0191920);
		rightRail.addChild(rp);
		rightRail.x = FlxG.width - RAIL_W;
		mainUI.addChild(leftRail);
		mainUI.addChild(rightRail);

		// Drawer: rail-opened flyout pages. Edge swipe stays OFF -- Android's back gesture owns
		// the screen edges, so panels open from explicit buttons only.
		drawer = new UIDrawer(UIDrawerSide.RIGHT, 460);
		drawer.edgeSwipeEnabled = false;
		drawerTitle = new UILabel('', 18, 0);
		drawerTitle.x = 18;
		drawerTitle.y = 14;
		drawer.content.addChild(drawerTitle);
		drawerPane = new UIScrollPane(460 - 28, FlxG.height - 60);
		drawerPane.x = 14;
		drawerPane.y = 48;
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
	public function railGap(left:Bool, h:Float = 18):Void {
		if (left)
			leftY += h;
		else
			rightY += h;
	}

	function railButton(rail:Sprite, label:String, cb:Void->Void, accent:Bool, left:Bool):UIButton {
		var b:UIButton = new UIButton(label, RAIL_W - 16, RAIL_BTN_H, cb, accent);
		b.fontSize = 15;
		b.x = 8;
		if (left) {
			b.y = leftY;
			leftY += RAIL_BTN_H + 10;
		} else {
			b.y = rightY;
			rightY += RAIL_BTN_H + 10;
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

		var btnW:Float = 128;
		var btnH:Float = 58;
		var pad:Float = 10;
		var totalW:Float = items.length * (btnW + pad) + pad;

		actionBarBg = UIPanel.solid(totalW, btnH + pad * 2, 0xE61E1E26);
		actionBar.addChild(actionBarBg);

		actionX = pad;
		for (item in items) {
			var danger:Bool = (item.danger == true);
			var b:UIButton = new UIButton(item.label, btnW, btnH, item.cb, !danger);
			if (danger)
				b.danger = true;
			b.fontSize = 15;
			b.x = actionX;
			b.y = pad;
			actionBar.addChild(b);
			actionX += btnW + pad;
		}

		actionBar.x = (FlxG.width - totalW) / 2;
		actionBar.y = FlxG.height - (btnH + pad * 2) - 14;
	}

	public function showActionBar(show:Bool):Void {
		actionBar.visible = show;
	}

	// ---- Gesture guide ----

	/** Shows the touch-controls guide modal. `onDismiss` fires when it closes. **/
	public function showGuide(lines:Array<String>, ?onDismiss:Void->Void):Void {
		if (guideModal != null)
			return;
		var m:UIModal = new UIModal('TOUCH CONTROLS', 660, 130 + lines.length * 44);
		var y:Float = 8;
		for (line in lines) {
			var l:UILabel = new UILabel(line, 17, 0);
			l.x = 26;
			l.y = y;
			m.body.addChild(l);
			y += 44;
		}
		var ok:UIButton = new UIButton('GOT IT', 240, 56, function() m.close(), true);
		ok.fontSize = 17;
		ok.x = (660 - 240) / 2;
		ok.y = y + 8;
		m.body.addChild(ok);
		m.onClosed = function() {
			guideModal = null;
			if (onDismiss != null)
				onDismiss();
		};
		guideModal = m;
		m.open();
	}

	public var guideOpen(get, never):Bool;

	inline function get_guideOpen():Bool {
		return guideModal != null;
	}

	public function closeGuide():Void {
		if (guideModal != null)
			guideModal.close();
	}

	public function dispose():Void {
		if (guideModal != null)
			guideModal.close();
		FlxSmidr.dispose();
		UITheme.clearMobilePreset();
	}
}
