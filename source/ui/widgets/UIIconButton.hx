package ui.widgets;

import ui.UIColor;
import ui.UIComponent;
import ui.UITheme;

/**
	A square button with a vector-drawn glyph (media transport + common actions), so no icon
	assets are needed. `active` renders the accent state (playing, loop enabled). A `PLAY`
	button automatically shows the pause glyph while `active`.
**/
final class UIIconButton extends UIComponent {
	public static inline var PLAY:Int = 0;
	public static inline var PAUSE:Int = 1;
	public static inline var STOP:Int = 2;
	public static inline var PREV:Int = 3;
	public static inline var NEXT:Int = 4;
	public static inline var LOOP:Int = 5;
	public static inline var PLUS:Int = 6;
	public static inline var MINUS:Int = 7;
	public static inline var CHEVRON_LEFT:Int = 8;
	public static inline var CHEVRON_RIGHT:Int = 9;
	public static inline var GEAR:Int = 10;

	public var icon(default, set):Int;

	/** Accent state (playing / toggled on). **/
	public var active(default, set):Bool = false;

	/**
		@param icon one of the glyph constants (`PLAY`, `STOP`, `GEAR`, ...)
		@param size the square edge length
		@param onClick fired on a completed click
	**/
	public function new(icon:Int, size:Float, ?onClick:Void->Void) {
		super(true, true);
		@:bypassAccessor this.icon = icon;
		this.onClick = onClick;
		resize(size, size);
		render();
	}

	override public function render():Void {
		var base:Int = active ? UITheme.accentDark : UITheme.panel2;
		if (pressed)
			base = UIColor.darken(base, 0.18);
		else if (hovered)
			base = UIColor.lighten(base, 0.10);

		var g = graphics;
		g.clear();
		var r:Float = UITheme.px(UITheme.radius);
		g.beginFill(UIColor.rgb(base));
		g.drawRoundRect(0, 0, w, h, r, r);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(active ? UITheme.accent : UITheme.border));
		g.drawRoundRect(0.5, 0.5, w - 1, h - 1, r, r);
		g.lineStyle();

		var c:Int = UIColor.rgb(active ? UITheme.text : UITheme.text2);
		var shown:Int = (icon == PLAY && active) ? PAUSE : icon;
		drawGlyph(shown, c);
	}

	function drawGlyph(kind:Int, c:Int):Void {
		var g = graphics;
		switch (kind) {
			case PLAY:
				g.beginFill(c);
				g.moveTo(w * 0.38, h * 0.28);
				g.lineTo(w * 0.38, h * 0.72);
				g.lineTo(w * 0.74, h * 0.50);
				g.endFill();
			case PAUSE:
				g.beginFill(c);
				g.drawRect(w * 0.34, h * 0.30, w * 0.11, h * 0.40);
				g.drawRect(w * 0.55, h * 0.30, w * 0.11, h * 0.40);
				g.endFill();
			case STOP:
				g.beginFill(c);
				g.drawRect(w * 0.33, h * 0.33, w * 0.34, h * 0.34);
				g.endFill();
			case PREV:
				g.beginFill(c);
				g.drawRect(w * 0.28, h * 0.30, w * 0.08, h * 0.40);
				g.moveTo(w * 0.72, h * 0.30);
				g.lineTo(w * 0.72, h * 0.70);
				g.lineTo(w * 0.42, h * 0.50);
				g.endFill();
			case NEXT:
				g.beginFill(c);
				g.drawRect(w * 0.64, h * 0.30, w * 0.08, h * 0.40);
				g.moveTo(w * 0.28, h * 0.30);
				g.lineTo(w * 0.28, h * 0.70);
				g.lineTo(w * 0.58, h * 0.50);
				g.endFill();
			case LOOP:
				g.lineStyle(2, c);
				g.drawCircle(w * 0.5, h * 0.5, w * 0.19);
				g.lineStyle();
				g.beginFill(c);
				g.moveTo(w * 0.60, h * 0.22);
				g.lineTo(w * 0.78, h * 0.30);
				g.lineTo(w * 0.60, h * 0.42);
				g.endFill();
			case PLUS:
				g.beginFill(c);
				g.drawRect(w * 0.30, h * 0.46, w * 0.40, h * 0.08);
				g.drawRect(w * 0.46, h * 0.30, w * 0.08, h * 0.40);
				g.endFill();
			case MINUS:
				g.beginFill(c);
				g.drawRect(w * 0.30, h * 0.46, w * 0.40, h * 0.08);
				g.endFill();
			case CHEVRON_LEFT:
				g.lineStyle(2, c);
				g.moveTo(w * 0.58, h * 0.30);
				g.lineTo(w * 0.40, h * 0.50);
				g.lineTo(w * 0.58, h * 0.70);
				g.lineStyle();
			case CHEVRON_RIGHT:
				g.lineStyle(2, c);
				g.moveTo(w * 0.42, h * 0.30);
				g.lineTo(w * 0.60, h * 0.50);
				g.lineTo(w * 0.42, h * 0.70);
				g.lineStyle();
			case GEAR:
				g.lineStyle(2, c);
				g.drawCircle(w * 0.5, h * 0.5, w * 0.17);
				g.lineStyle();
				g.beginFill(c);
				var i:Int = 0;
				while (i < 4) {
					var ang:Float = i * 1.5707963;
					var cx:Float = w * 0.5 + Math.cos(ang) * w * 0.26;
					var cy:Float = h * 0.5 + Math.sin(ang) * h * 0.26;
					g.drawRect(cx - w * 0.045, cy - h * 0.045, w * 0.09, h * 0.09);
					i++;
				}
				g.endFill();
		}
	}

	function set_icon(v:Int):Int {
		icon = v;
		invalidate();
		return v;
	}

	function set_active(v:Bool):Bool {
		if (active == v)
			return v;
		active = v;
		invalidate();
		return v;
	}
}
