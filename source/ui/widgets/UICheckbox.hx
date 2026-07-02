package ui.widgets;

import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/**
	A labelled checkbox row: label on the left, accent check square on the right (or standalone
	square when the label is empty). Clicking anywhere on the row toggles; `onChange(checked)`
	fires after the flip.
**/
final class UICheckbox extends UIComponent {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var label(default, set):String;
	public var checked(default, set):Bool;
	public var onChange:Bool->Void = null;
	public var fontSize(default, set):Int = 12;

	final tf:TextField;

	/**
		@param label the row text (empty string = standalone check square)
		@param width layout width (the check square sits at the right edge)
		@param checked the initial state
		@param onChange fired after the state flips
	**/
	public function new(label:String, width:Float, checked:Bool = false, ?onChange:Bool->Void) {
		super(true, true);
		this.label = label;
		@:bypassAccessor this.checked = checked;
		this.onChange = onChange;
		tf = UIFonts.make(UITheme.fs(fontSize), UITheme.text2);
		addChild(tf);
		resize(width, UITheme.px(24));
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

	override function click():Void {
		@:bypassAccessor checked = !checked;
		invalidate();
		if (onChange != null)
			onChange(checked);
		super.click();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		// invisible hit surface across the row
		g.beginFill(0, 0);
		g.drawRect(0, 0, w, h);
		g.endFill();

		var box:Float = UITheme.px(16);
		var bx:Float = w - box;
		var by:Float = (h - box) / 2;
		var fill:Int = checked ? UITheme.accentDark : UITheme.panel2;
		if (hovered)
			fill = UIColor.lighten(fill, 0.10);
		g.beginFill(UIColor.rgb(fill));
		g.drawRoundRect(bx, by, box, box, UITheme.px(6), UITheme.px(6));
		g.endFill();
		g.lineStyle(1, UIColor.rgb(UITheme.border2));
		g.drawRoundRect(bx + 0.5, by + 0.5, box - 1, box - 1, UITheme.px(6), UITheme.px(6));
		g.lineStyle();
		if (checked) {
			g.lineStyle(2, UIColor.rgb(UITheme.text));
			g.moveTo(bx + box * 0.22, by + box * 0.52);
			g.lineTo(bx + box * 0.44, by + box * 0.74);
			g.lineTo(bx + box * 0.80, by + box * 0.28);
			g.lineStyle();
		}

		UIFonts.restyle(tf, UITheme.fs(fontSize), UITheme.text2);
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : label;
		if (tf.text != resolved)
			tf.text = resolved;
		tf.x = 0;
		tf.y = (h - tf.height) / 2;
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

	function set_checked(v:Bool):Bool {
		if (checked == v)
			return v;
		checked = v;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
