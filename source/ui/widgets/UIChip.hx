package ui.widgets;

import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/**
	A compact pill chip. With `hasDot = true` it's a stateful toggle showing a status dot
	(`on` flips on click, then `onToggle(on)` fires); without a dot it's a value chip whose
	text the owner updates and whose `onClick` typically cycles the value. Auto-sizes to its
	label.
**/
final class UIChip extends UIComponent {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var label(default, set):String;

	/** Toggle state (only meaningful with `hasDot`). **/
	public var on(default, set):Bool;

	/** Fired after the chip flips its own state. **/
	public var onToggle:Bool->Void = null;

	public var fontSize(default, set):Int = 12;

	public final hasDot:Bool;

	final tf:TextField;

	/**
		@param label the chip text
		@param hasDot `true` makes the chip a self-flipping toggle with a status dot
		@param on the initial toggle state (dot chips only)
		@param onToggle fired after the chip flips its own state
	**/
	public function new(label:String, hasDot:Bool = false, on:Bool = false, ?onToggle:Bool->Void) {
		super(true, true);
		this.hasDot = hasDot;
		@:bypassAccessor this.on = on;
		this.onToggle = onToggle;
		tf = UIFonts.make(UITheme.fs(fontSize), UITheme.text);
		addChild(tf);
		this.label = label;
		render();
	}

	/**
		Switches the label to a localized string.
		@param key the translation key
		@param fallback the source-language text
	**/
	public function localize(key:String, fallback:String):Void {
		this.fallback = fallback;
		this.key = key;
	}

	var dotPop:Float = 1;

	override function click():Void {
		if (hasDot) {
			@:bypassAccessor on = !on;
			invalidate();
			if (on)
				ui.UITween.to(function(p:Float):Void {
					dotPop = 1.6 - 0.6 * p;
					invalidate();
				}, 0, 1, 215, ui.UITween.OUT_QUAD);
			if (onToggle != null)
				onToggle(on);
		}
		super.click();
	}

	override public function render():Void {
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : label;
		UIFonts.restyle(tf, UITheme.fs(fontSize), (hasDot && !on) ? UITheme.text2 : UITheme.text);
		if (tf.text != resolved)
			tf.text = resolved;

		var padX:Float = UITheme.px(10);
		var dotSpace:Float = hasDot ? UITheme.px(16) : 0;
		var height:Float = UITheme.px(24);
		var width:Float = padX * 2 + dotSpace + tf.width;
		w = width;
		h = height;

		var base:Int = (hasDot && on) ? UITheme.panel3 : UITheme.panel2;
		if (hovered)
			base = UIColor.lighten(base, 0.10);
		if (pressed)
			base = UIColor.darken(base, 0.12);
		var line:Int = (hasDot && on) ? UITheme.accentDark : UITheme.border;

		var g = graphics;
		g.clear();
		var r:Float = height / 2;
		g.beginFill(UIColor.rgb(base));
		g.drawRoundRect(0, 0, width, height, r * 2, r * 2);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(line));
		g.drawRoundRect(0.5, 0.5, width - 1, height - 1, r * 2, r * 2);
		g.lineStyle();
		if (hasDot) {
			g.beginFill(UIColor.rgb(on ? UITheme.success : UITheme.border2));
			g.drawCircle(padX + UITheme.px(4), height / 2, UITheme.px(4.5) * dotPop);
			g.endFill();
		}
		tf.x = padX + dotSpace;
		tf.y = (height - tf.height) / 2;
	}

	function set_key(v:String):String {
		key = v;
		invalidate();
		return v;
	}

	function set_label(v:String):String {
		label = v;
		invalidate();
		return v;
	}

	function set_on(v:Bool):Bool {
		if (on == v)
			return v;
		on = v;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
