package ui.widgets;

import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/**
	A collapsible section header: chevron, all-caps title, underline and an optional
	right-aligned hint. The owner toggles its section's content visibility from
	`onToggle(expanded)` and re-flows the layout.
**/
final class UIAccordion extends UIComponent {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var title(default, set):String;
	public var hint(default, set):String = null;
	public var expanded(default, set):Bool = true;
	public var onToggle:Bool->Void = null;

	final tf:TextField;
	var hintTf:TextField = null;

	/**
		@param title the header text (rendered upper-case)
		@param width layout width
		@param expanded the initial state
		@param onToggle fired after a click flips the state
	**/
	public function new(title:String, width:Float, expanded:Bool = true, ?onToggle:Bool->Void) {
		super(true, true);
		this.title = title;
		@:bypassAccessor this.expanded = expanded;
		this.onToggle = onToggle;
		tf = UIFonts.make(UITheme.fs(10), UITheme.text3);
		addChild(tf);
		resize(width, UITheme.px(22));
		render();
	}

	/**
		Switches the title to a localized string.
		@param key the translation key
		@param fallback the source-language text
	**/
	public function localize(key:String, fallback:String):Void {
		this.fallback = fallback;
		this.key = key;
	}

	override function click():Void {
		@:bypassAccessor expanded = !expanded;
		invalidate();
		if (onToggle != null)
			onToggle(expanded);
		super.click();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(0, 0);
		g.drawRect(0, 0, w, h);
		g.endFill();

		// chevron
		var c:Int = UIColor.rgb(UITheme.text3);
		var cy:Float = h / 2;
		g.beginFill(c);
		if (expanded) {
			g.moveTo(UITheme.px(1), cy - UITheme.px(2.5));
			g.lineTo(UITheme.px(9), cy - UITheme.px(2.5));
			g.lineTo(UITheme.px(5), cy + UITheme.px(3));
		} else {
			g.moveTo(UITheme.px(2), cy - UITheme.px(4));
			g.lineTo(UITheme.px(7.5), cy);
			g.lineTo(UITheme.px(2), cy + UITheme.px(4));
		}
		g.endFill();

		UIFonts.restyle(tf, UITheme.fs(10), UITheme.text3);
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : title;
		resolved = resolved.toUpperCase();
		if (tf.text != resolved)
			tf.text = resolved;
		tf.x = UITheme.px(14);
		tf.y = (h - tf.height) / 2 - 1;

		if (hint != null && hint != "") {
			if (hintTf == null) {
				hintTf = UIFonts.make(UITheme.fs(9), UITheme.text3);
				addChild(hintTf);
			}
			UIFonts.restyle(hintTf, UITheme.fs(9), UITheme.text3);
			if (hintTf.text != hint)
				hintTf.text = hint;
			hintTf.visible = true;
			hintTf.x = w - hintTf.width;
			hintTf.y = (h - hintTf.height) / 2;
		} else if (hintTf != null)
			hintTf.visible = false;

		g.beginFill(UIColor.rgb(UITheme.border));
		g.drawRect(0, h - 1, w, 1);
		g.endFill();
	}

	function set_key(v:String):String {
		key = v;
		invalidate();
		return v;
	}

	function set_title(v:String):String {
		title = v;
		invalidate();
		return v;
	}

	function set_hint(v:String):String {
		hint = v;
		invalidate();
		return v;
	}

	function set_expanded(v:Bool):Bool {
		if (expanded == v)
			return v;
		expanded = v;
		invalidate();
		return v;
	}
}
