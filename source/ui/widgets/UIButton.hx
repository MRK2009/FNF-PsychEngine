package ui.widgets;

import openfl.text.TextField;
import openfl.text.TextFormatAlign;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/**
	A clickable button. Variants: default (panel surface), `accent` (primary action) and
	`danger` (destructive). Hover lightens, press dips; the click fires on press-started
	release (see `UIComponent`).
**/
final class UIButton extends UIComponent {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var label(default, set):String;
	public var accent(default, set):Bool = false;
	public var danger(default, set):Bool = false;

	/** Base (unscaled) font size. **/
	public var fontSize(default, set):Int = 13;

	final tf:TextField;

	/**
		@param label the button text (raw; use `localize` for translated labels)
		@param width layout width
		@param height layout height
		@param onClick fired on a completed click
		@param accent `true` renders the primary-action variant
	**/
	public function new(label:String, width:Float, height:Float, ?onClick:Void->Void, accent:Bool = false) {
		super(true, true);
		this.label = label;
		this.accent = accent;
		this.onClick = onClick;
		tf = UIFonts.make(UITheme.fs(fontSize), UITheme.text, TextFormatAlign.CENTER);
		tf.autoSize = openfl.text.TextFieldAutoSize.NONE;
		addChild(tf);
		resize(width, height);
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

	override public function render():Void {
		var base:Int = accent ? UITheme.accentDark : (danger ? 0xFF60202E : UITheme.panel2);
		var line:Int = accent ? UITheme.accent : (danger ? UITheme.danger : UITheme.border);
		if (pressed)
			base = UIColor.darken(base, 0.18);
		else if (hovered)
			base = UIColor.lighten(base, 0.10);
		var g = graphics;
		g.clear();
		var r:Float = UITheme.px(UITheme.radius);
		g.beginFill(UIColor.rgb(base));
		g.drawRoundRect(0, 0, w, h, r * 2, r * 2);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(line));
		g.drawRoundRect(0.5, 0.5, w - 1, h - 1, r * 2, r * 2);
		g.lineStyle();

		var textColor:Int = (accent || danger) ? UITheme.text : UITheme.text2;
		UIFonts.restyle(tf, UITheme.fs(fontSize), textColor, TextFormatAlign.CENTER);
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : label;
		if (tf.text != resolved)
			tf.text = resolved;
		tf.width = w;
		tf.height = tf.textHeight + 4;
		tf.x = 0;
		tf.y = (h - tf.height) / 2 + (pressed ? 1 : 0); // press dip
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

	function set_accent(v:Bool):Bool {
		accent = v;
		invalidate();
		return v;
	}

	function set_danger(v:Bool):Bool {
		danger = v;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
