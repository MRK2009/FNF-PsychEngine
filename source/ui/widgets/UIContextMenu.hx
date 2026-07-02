package ui.widgets;

import openfl.display.Sprite;
import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UIRoot;
import ui.UITheme;

/**
	A popup menu shown on `UIRoot.popupLayer` behind a click-blocking backdrop. Used by
	`UIMenuBar` dropdowns and directly for right-click context menus. Escape or an outside
	click closes it; selecting an item closes then runs its callback.
**/
final class UIContextMenu {
	/** The open menu, if any (one at a time). **/
	public static var current(default, null):UIContextMenu = null;

	/** Fired when the menu closes (any reason). **/
	public var onClosed:Void->Void = null;

	final container:Sprite;
	final items:Array<UIMenuItem>;

	/** Menu panel width. **/
	public static var menuWidth:Float = 230;

	/**
		Opens a menu, closing any menu already open.
		@param x the menu's left edge in root coordinates (clamped inside the window)
		@param y the menu's top edge in root coordinates (clamped inside the window)
		@param items the entries (separators render as dividers)
		@return the opened menu (assign `onClosed` for close notifications)
	**/
	public static function open(x:Float, y:Float, items:Array<UIMenuItem>):UIContextMenu {
		if (current != null)
			current.close();
		return new UIContextMenu(x, y, items);
	}

	function new(x:Float, y:Float, items:Array<UIMenuItem>) {
		this.items = items;
		current = this;
		var root:UIRoot = UIRoot.current;

		container = new Sprite();
		var blocker:UIComponent = new UIComponent(true, true);
		blocker.hoverCursor = null;
		blocker.onClick = close;
		blocker.graphics.beginFill(0, 0);
		blocker.graphics.drawRect(-16000, -16000, 32000, 32000);
		blocker.graphics.endFill();
		container.addChild(blocker);

		var rowH:Float = UITheme.px(24);
		var sepH:Float = UITheme.px(8);
		var pad:Float = UITheme.px(5);
		var mw:Float = UITheme.px(menuWidth);
		var totalH:Float = pad * 2;
		for (it in items)
			totalH += (it.separator == true) ? sepH : rowH;

		var panel:Sprite = new Sprite();
		var g = panel.graphics;
		var r:Float = UITheme.px(8);
		g.beginFill(UIColor.rgb(UITheme.panel2));
		g.drawRoundRect(0, 0, mw, totalH, r, r);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(UITheme.border2));
		g.drawRoundRect(0.5, 0.5, mw - 1, totalH - 1, r, r);
		g.lineStyle();
		// clamp inside the window so long menus never clip offscreen
		if (root != null && root.stage != null) {
			var vw:Float = (root.scaleX > 0) ? root.stage.stageWidth / root.scaleX : 1280;
			var vh:Float = (root.scaleY > 0) ? root.stage.stageHeight / root.scaleY : 720;
			if (x + mw > vw - 4)
				x = vw - mw - 4;
			if (y + totalH > vh - 4)
				y = vh - totalH - 4;
			if (x < 4)
				x = 4;
			if (y < 4)
				y = 4;
		}
		panel.x = x;
		panel.y = y;
		container.addChild(panel);

		var cy:Float = pad;
		var i:Int = 0;
		var n:Int = items.length;
		while (i < n) {
			var it:UIMenuItem = items[i];
			if (it.separator == true) {
				g.beginFill(UIColor.rgb(UITheme.border));
				g.drawRect(UITheme.px(10), cy + sepH / 2, mw - UITheme.px(20), 1);
				g.endFill();
				cy += sepH;
			} else {
				var row:UIMenuRow = new UIMenuRow(this, it, mw - 4, rowH);
				row.x = 2;
				row.y = cy;
				panel.addChild(row);
				cy += rowH;
			}
			i++;
		}

		root.popupLayer.addChild(container);
		UIRoot.pushOverlayCloser(close);

		panel.alpha = 0;
		ui.UITween.to(function(p:Float):Void {
			panel.alpha = p;
			panel.scaleY = 0.96 + 0.04 * p;
		}, 0, 1, 145, ui.UITween.OUT_QUAD);
	}

	/** Closes and disposes the menu. **/
	public function close():Void {
		if (current != this)
			return;
		current = null;
		UIRoot.removeOverlayCloser(close);
		disposeTree(container);
		if (container.parent != null)
			container.parent.removeChild(container);
		if (onClosed != null)
			onClosed();
	}

	static function disposeTree(container:Sprite):Void {
		var i:Int = container.numChildren;
		while (--i >= 0) {
			var child = container.getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).dispose();
			else if (child is Sprite)
				disposeTree(cast child);
		}
		container.removeChildren();
	}

	@:allow(ui.widgets.UIMenuRow)
	function pick(item:UIMenuItem):Void {
		close();
		if (item.onSelect != null)
			item.onSelect();
	}
}

/** One menu row: label + optional check + right-aligned shortcut, hover highlight. **/
private final class UIMenuRow extends UIComponent {
	final owner:UIContextMenu;
	final item:UIMenuItem;
	final tf:TextField;
	var shortcutTf:TextField = null;

	public function new(owner:UIContextMenu, item:UIMenuItem, width:Float, height:Float) {
		super(true, true);
		this.owner = owner;
		this.item = item;
		enabled = (item.disabled != true);
		tf = UIFonts.make(UITheme.fs(11), UITheme.text);
		addChild(tf);
		if (item.shortcut != null) {
			shortcutTf = UIFonts.make(UITheme.fs(10), UITheme.text3);
			addChild(shortcutTf);
		}
		resize(width, height);
		render();
	}

	override function click():Void {
		owner.pick(item);
		super.click();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		if (hovered && enabled) {
			g.beginFill(UIColor.rgb(UITheme.panel3));
			g.drawRoundRect(2, 1, w - 4, h - 2, UITheme.px(6), UITheme.px(6));
			g.endFill();
		} else {
			g.beginFill(0, 0);
			g.drawRect(0, 0, w, h);
			g.endFill();
		}

		var textX:Float = UITheme.px(12);
		if (item.checked != null) {
			if (item.checked) {
				g.lineStyle(2, UIColor.rgb(UITheme.accent));
				g.moveTo(UITheme.px(9), h * 0.52);
				g.lineTo(UITheme.px(13), h * 0.68);
				g.lineTo(UITheme.px(19), h * 0.32);
				g.lineStyle();
			}
			textX = UITheme.px(26);
		}

		UIFonts.restyle(tf, UITheme.fs(11), enabled ? UITheme.text : UITheme.text3);
		var resolved:String = (item.key != null) ? UILocale.t(item.key, item.fallback != null ? item.fallback : item.label) : item.label;
		if (tf.text != resolved)
			tf.text = resolved;
		tf.x = textX;
		tf.y = (h - tf.height) / 2;

		if (shortcutTf != null) {
			UIFonts.restyle(shortcutTf, UITheme.fs(10), UITheme.text3);
			if (shortcutTf.text != item.shortcut)
				shortcutTf.text = item.shortcut;
			shortcutTf.x = w - shortcutTf.width - UITheme.px(10);
			shortcutTf.y = (h - shortcutTf.height) / 2;
		}
	}
}
