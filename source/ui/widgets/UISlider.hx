package ui.widgets;

import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/**
	A labelled horizontal slider: label left, track + knob right, current value drawn beside the
	knob. Dragging anywhere on the track seeks; `onChange(value)` fires while dragging.
**/
final class UISlider extends UIComponent {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var label(default, set):String;

	public var value(default, set):Float;
	public var min:Float = 0;
	public var max:Float = 1;
	public var decimals:Int = 2;
	public var onChange:Float->Void = null;
	public var fontSize(default, set):Int = 12;

	/** Width of the track area on the right. **/
	public var trackWidth:Float;

	final tf:TextField;
	final valueTf:TextField;

	var dragging:Bool = false;

	/**
		@param label the row text on the left
		@param width layout width (the track sits at the right edge)
		@param min the range minimum
		@param max the range maximum
		@param value the initial value
		@param onChange fired while dragging/seeking
	**/
	public function new(label:String, width:Float, min:Float, max:Float, value:Float, ?onChange:Float->Void) {
		super(true, true);
		this.label = label;
		this.min = min;
		this.max = max;
		@:bypassAccessor this.value = value;
		this.onChange = onChange;
		trackWidth = UITheme.px(120);
		tf = UIFonts.make(UITheme.fs(fontSize), UITheme.text2);
		addChild(tf);
		valueTf = UIFonts.make(UITheme.fs(fontSize), UITheme.text);
		addChild(valueTf);
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

	override function onPress(localX:Float, localY:Float):Void {
		var tx:Float = w - trackWidth;
		if (localX < tx - UITheme.px(6))
			return;
		dragging = true;
		beginCapture();
		seekTo(localX);
	}

	override function onDragMove(stageX:Float, stageY:Float):Void {
		if (!dragging)
			return;
		var local = globalToLocal(new openfl.geom.Point(stageX, stageY));
		seekTo(local.x);
	}

	override function onDragEnd():Void {
		dragging = false;
	}

	function seekTo(localX:Float):Void {
		var tx:Float = w - trackWidth;
		var p:Float = (localX - tx) / trackWidth;
		if (p < 0)
			p = 0;
		if (p > 1)
			p = 1;
		var next:Float = min + (max - min) * p;
		var factor:Float = Math.pow(10, decimals);
		next = Math.round(next * factor) / factor;
		if (next == value)
			return;
		@:bypassAccessor value = next;
		invalidate();
		if (onChange != null)
			onChange(next);
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(0, 0);
		g.drawRect(0, 0, w, h);
		g.endFill();

		var tx:Float = w - trackWidth;
		var cy:Float = h / 2;
		var p:Float = (max > min) ? (value - min) / (max - min) : 0;
		if (p < 0)
			p = 0;
		if (p > 1)
			p = 1;

		g.beginFill(UIColor.rgb(UITheme.panel3));
		g.drawRoundRect(tx, cy - UITheme.px(2), trackWidth, UITheme.px(4), UITheme.px(4), UITheme.px(4));
		g.endFill();
		g.beginFill(UIColor.rgb(UITheme.accentDark));
		g.drawRoundRect(tx, cy - UITheme.px(2), trackWidth * p, UITheme.px(4), UITheme.px(4), UITheme.px(4));
		g.endFill();
		var knob:Int = hovered || dragging ? UIColor.lighten(UITheme.accent, 0.15) : UITheme.accent;
		g.beginFill(UIColor.rgb(knob));
		g.drawCircle(tx + trackWidth * p, cy, UITheme.px(6));
		g.endFill();

		UIFonts.restyle(tf, UITheme.fs(fontSize), UITheme.text2);
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : label;
		if (tf.text != resolved)
			tf.text = resolved;
		tf.x = 0;
		tf.y = (h - tf.height) / 2;

		UIFonts.restyle(valueTf, UITheme.fs(fontSize), UITheme.text);
		var vs:String = formatValue();
		if (valueTf.text != vs)
			valueTf.text = vs;
		valueTf.x = tx - valueTf.width - UITheme.px(8);
		valueTf.y = (h - valueTf.height) / 2;
	}

	function formatValue():String {
		if (decimals <= 0)
			return Std.string(Std.int(value));
		var factor:Float = Math.pow(10, decimals);
		return Std.string(Math.round(value * factor) / factor);
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

	function set_value(v:Float):Float {
		if (value == v)
			return v;
		value = v;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
