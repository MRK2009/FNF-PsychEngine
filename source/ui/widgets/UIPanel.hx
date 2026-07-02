package ui.widgets;

import ui.UIColor;
import ui.UIComponent;
import ui.UITheme;

/**
	A filled surface: chrome bands, cards, placeholders. Non-interactive but blocking by default
	(children stay interactive, pointer hits never fall through). `corner` rounds the fill;
	the four `border*` flags draw 1px themed edges and `outline` draws a full 1px frame.
**/
final class UIPanel extends UIComponent {
	/** Fill color (ARGB). **/
	public var fill(default, set):Int;

	/** Corner radius in scaled pixels (0 = square). **/
	public var corner(default, set):Float = 0;

	public var borderTop(default, set):Bool = false;
	public var borderBottom(default, set):Bool = false;
	public var borderLeft(default, set):Bool = false;
	public var borderRight(default, set):Bool = false;

	/** Full 1px frame (cards). **/
	public var outline(default, set):Bool = false;

	/**
		@param width layout width
		@param height layout height
		@param fill the fill color (ARGB)
		@param blocking `true` swallows pointer hits (children stay interactive)
	**/
	public function new(width:Float, height:Float, fill:Int, blocking:Bool = true) {
		super(false, blocking);
		@:bypassAccessor this.fill = fill;
		resize(width, height);
		render();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(UIColor.rgb(fill), UIColor.alphaOf(fill));
		if (corner > 0)
			g.drawRoundRect(0, 0, w, h, corner, corner);
		else
			g.drawRect(0, 0, w, h);
		g.endFill();

		if (outline) {
			g.lineStyle(1, UIColor.rgb(UITheme.border));
			if (corner > 0)
				g.drawRoundRect(0.5, 0.5, w - 1, h - 1, corner, corner);
			else
				g.drawRect(0.5, 0.5, w - 1, h - 1);
			g.lineStyle();
			return;
		}

		g.beginFill(UIColor.rgb(UITheme.border));
		if (borderTop)
			g.drawRect(0, 0, w, 1);
		if (borderBottom)
			g.drawRect(0, h - 1, w, 1);
		if (borderLeft)
			g.drawRect(0, 0, 1, h);
		if (borderRight)
			g.drawRect(w - 1, 0, 1, h);
		g.endFill();
	}

	function set_fill(v:Int):Int {
		fill = v;
		invalidate();
		return v;
	}

	function set_corner(v:Float):Float {
		corner = v;
		invalidate();
		return v;
	}

	function set_borderTop(v:Bool):Bool {
		borderTop = v;
		invalidate();
		return v;
	}

	function set_borderBottom(v:Bool):Bool {
		borderBottom = v;
		invalidate();
		return v;
	}

	function set_borderLeft(v:Bool):Bool {
		borderLeft = v;
		invalidate();
		return v;
	}

	function set_borderRight(v:Bool):Bool {
		borderRight = v;
		invalidate();
		return v;
	}

	function set_outline(v:Bool):Bool {
		outline = v;
		invalidate();
		return v;
	}
}
