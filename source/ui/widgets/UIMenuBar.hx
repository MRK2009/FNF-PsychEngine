package ui.widgets;

import openfl.geom.Point;
import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/** One top-level menu: a title plus an item factory (evaluated on open, so checkmarks and
	shortcut labels are always current). **/
typedef UIMenuDef = {
	var title:String;
	@:optional var key:String;
	@:optional var fallback:String;
	var items:Void->Array<UIMenuItem>;
}

/**
	A desktop menu bar. Clicking a title opens its dropdown (`UIContextMenu`); while one is open,
	hovering another title switches to it. An optional brand label renders before the menus and
	arbitrary widgets can be laid over the right side by the owner.
**/
final class UIMenuBar extends UIComponent {
	/** Bold leading label rendered before the menu titles (the application name). **/
	public var brand(default, set):String = "";

	public var fontSize(default, set):Int = 12;

	var menus:Array<UIMenuDef> = [];
	var titleTfs:Array<TextField> = [];
	var titleX:Array<Float> = [];
	var titleW:Array<Float> = [];
	var brandTf:TextField = null;
	var openIndex:Int = -1;
	var openMenu:UIContextMenu = null;

	/**
		@param width layout width (typically spans the window)
		@param height the bar height
	**/
	public function new(width:Float, height:Float) {
		super(true, true);
		resize(width, height);
		render();
	}

	/**
		Replaces the menu set.
		@param menus the top-level menus; each `items` factory runs on every open
	**/
	public function setMenus(menus:Array<UIMenuDef>):Void {
		this.menus = menus;
		var i:Int = titleTfs.length;
		while (--i >= 0)
			removeChild(titleTfs[i]);
		titleTfs.resize(0);
		i = 0;
		while (i < menus.length) {
			var tf:TextField = UIFonts.make(UITheme.fs(fontSize), UITheme.text2);
			addChild(tf);
			titleTfs.push(tf);
			i++;
		}
		invalidate();
	}

	override function onPress(localX:Float, localY:Float):Void {
		var idx:Int = titleAt(localX);
		if (idx < 0) {
			return;
		}
		if (openIndex == idx)
			closeDropdown();
		else
			openDropdown(idx);
	}

	override function onStateChanged():Void {
		super.onStateChanged();
	}

	function __hoverSwitch():Void {
		// while a menu is open, hovering another title switches to it
		if (openIndex < 0)
			return;
		var local:Point = globalToLocal(new Point(stage != null ? stage.mouseX : 0, stage != null ? stage.mouseY : 0));
		if (local.y < 0 || local.y > h)
			return;
		var idx:Int = titleAt(local.x);
		if (idx >= 0 && idx != openIndex)
			openDropdown(idx);
	}

	function titleAt(localX:Float):Int {
		var i:Int = 0;
		var n:Int = menus.length;
		while (i < n) {
			if (localX >= titleX[i] && localX < titleX[i] + titleW[i])
				return i;
			i++;
		}
		return -1;
	}

	function openDropdown(idx:Int):Void {
		closeDropdown();
		openIndex = idx;
		var origin:Point = localToGlobal(new Point(titleX[idx] - UITheme.px(6), h));
		var root = ui.UIRoot.current;
		var local:Point = root.popupLayer.globalToLocal(origin);
		openMenu = UIContextMenu.open(local.x, local.y + 1, menus[idx].items());
		openMenu.onClosed = onDropdownClosed;
		if (stage != null)
			stage.addEventListener(openfl.events.MouseEvent.MOUSE_MOVE, __onStageMove);
		invalidate();
	}

	function __onStageMove(_:openfl.events.MouseEvent):Void {
		__hoverSwitch();
	}

	function onDropdownClosed():Void {
		if (stage != null)
			stage.removeEventListener(openfl.events.MouseEvent.MOUSE_MOVE, __onStageMove);
		openIndex = -1;
		openMenu = null;
		invalidate();
	}

	/** Closes the open dropdown, if any. **/
	public function closeDropdown():Void {
		if (openMenu != null)
			openMenu.close();
	}

	/** `true` while a dropdown is open. **/
	public var isOpen(get, never):Bool;

	inline function get_isOpen():Bool {
		return openIndex >= 0;
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(UIColor.rgb(UITheme.panel2));
		g.drawRect(0, 0, w, h);
		g.endFill();
		g.beginFill(UIColor.rgb(UITheme.border));
		g.drawRect(0, h - 1, w, 1);
		g.endFill();

		var x:Float = UITheme.px(12);
		if (brand != "") {
			if (brandTf == null) {
				brandTf = UIFonts.make(UITheme.fs(fontSize), UITheme.text);
				addChild(brandTf);
			}
			UIFonts.restyle(brandTf, UITheme.fs(fontSize), UITheme.text);
			if (brandTf.text != brand)
				brandTf.text = brand;
			brandTf.x = x;
			brandTf.y = (h - brandTf.height) / 2;
			x += brandTf.width + UITheme.px(20);
		}

		titleX.resize(0);
		titleW.resize(0);
		var mouseLocalX:Float = (stage != null) ? globalToLocal(new Point(stage.mouseX, stage.mouseY)).x : -1;
		var i:Int = 0;
		var n:Int = menus.length;
		while (i < n) {
			var tf:TextField = titleTfs[i];
			var m:UIMenuDef = menus[i];
			var resolved:String = (m.key != null) ? UILocale.t(m.key, m.fallback != null ? m.fallback : m.title) : m.title;
			var active:Bool = (i == openIndex);
			UIFonts.restyle(tf, UITheme.fs(fontSize), active ? UITheme.text : UITheme.text2);
			if (tf.text != resolved)
				tf.text = resolved;
			var cellW:Float = tf.width + UITheme.px(16);
			titleX.push(x - UITheme.px(8));
			titleW.push(cellW);
			if (active) {
				g.beginFill(UIColor.rgb(UITheme.panel3));
				g.drawRoundRect(x - UITheme.px(8), UITheme.px(3), cellW, h - UITheme.px(6), UITheme.px(6), UITheme.px(6));
				g.endFill();
			}
			tf.x = x;
			tf.y = (h - tf.height) / 2;
			x += cellW + UITheme.px(6);
			i++;
		}
	}

	override public function dispose():Void {
		closeDropdown();
		super.dispose();
	}

	function set_brand(v:String):String {
		brand = v;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
