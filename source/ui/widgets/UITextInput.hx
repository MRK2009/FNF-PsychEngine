package ui.widgets;

import openfl.desktop.Clipboard;
import openfl.desktop.ClipboardFormats;
import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UIRoot;
import ui.UITheme;
import ui.input.IUIFocusable;
import ui.input.UIFocus;

/**
	A labelled single-line text field: label left, input box right. Click to focus; while
	focused it captures the keyboard (`UIFocus.typing`) — caret, Shift+arrow selection,
	Home/End, Ctrl+A/C/X/V, Backspace/Delete word-aware basics, Enter commits (`onEnter`),
	Escape blurs. `onChange(text)` fires on every edit.
**/
final class UITextInput extends UIComponent implements IUIFocusable {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var label(default, set):String;

	public var text(default, set):String = "";
	public var onChange:String->Void = null;
	public var onEnter:String->Void = null;
	public var fontSize(default, set):Int = 12;

	/** Optional character filter; return false to reject a typed char. **/
	public var filter:(charCode:Int) -> Bool = null;

	public var maxLength:Int = 0;

	/** Width of the input box on the right; 0 = whole row. **/
	public var boxWidth:Float = 0;

	final tf:TextField;
	final labelTf:TextField;

	var focusedNow:Bool = false;
	var caret:Int = 0;
	var anchor:Int = 0;
	var blink:Float = 0;
	var caretVisible:Bool = true;

	/**
		@param label the row text on the left (empty = the box spans the whole row)
		@param width layout width
		@param text the initial content
		@param onChange fired on every edit
	**/
	public function new(label:String, width:Float, text:String = "", ?onChange:String->Void) {
		super(true, true);
		hoverCursor = openfl.ui.MouseCursor.IBEAM;
		this.label = label;
		this.onChange = onChange;
		labelTf = UIFonts.make(UITheme.fs(fontSize), UITheme.text2);
		addChild(labelTf);
		tf = UIFonts.make(UITheme.fs(fontSize), UITheme.text);
		tf.autoSize = openfl.text.TextFieldAutoSize.NONE;
		addChild(tf);
		@:bypassAccessor this.text = text;
		caret = text.length;
		anchor = caret;
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

	inline function inputX():Float {
		return (boxWidth > 0) ? (w - boxWidth) : ((label != "" || key != null) ? w * 0.42 : 0);
	}

	public function capturesKeyboard():Bool {
		return focusedNow;
	}

	public function onFocusGained():Void {
		focusedNow = true;
		blink = 0;
		caretVisible = true;
		UIRoot.addTicker(tick);
		invalidate();
	}

	public function onFocusLost():Void {
		focusedNow = false;
		UIRoot.removeTicker(tick);
		invalidate();
	}

	function tick(dtMs:Float):Void {
		blink += dtMs;
		if (blink >= 530) {
			blink = 0;
			caretVisible = !caretVisible;
			invalidate();
		}
	}

	override function onPress(localX:Float, localY:Float):Void {
		var ix:Float = inputX();
		if (localX < ix) {
			return;
		}
		UIFocus.set(this);
		caret = indexAt(localX - ix - UITheme.px(6) + tf.scrollH);
		anchor = caret;
		caretVisible = true;
		blink = 0;
		invalidate();
	}

	function indexAt(px:Float):Int {
		var n:Int = text.length;
		if (n == 0 || px <= 0)
			return 0;
		var i:Int = 0;
		while (i < n) {
			var b = tf.getCharBoundaries(i);
			if (b != null && px < b.x + b.width * 0.5 - 2)
				return i;
			i++;
		}
		return n;
	}

	public function onKeyDown(keyCode:Int, charCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool {
		if (!focusedNow)
			return false;
		switch (keyCode) {
			case 27: // escape
				UIFocus.clear(this);
				return true;
			case 13: // enter
				UIFocus.clear(this);
				if (onEnter != null)
					onEnter(text);
				return true;
			case 8: // backspace
				if (hasSelection())
					deleteSelection();
				else if (caret > 0) {
					setTextInternal(text.substring(0, caret - 1) + text.substring(caret));
					caret--;
					anchor = caret;
				}
				return true;
			case 46: // delete
				if (hasSelection())
					deleteSelection();
				else if (caret < text.length)
					setTextInternal(text.substring(0, caret) + text.substring(caret + 1));
				return true;
			case 37: // left
				if (caret > 0)
					caret--;
				if (!shift)
					anchor = caret;
				resetBlink();
				return true;
			case 39: // right
				if (caret < text.length)
					caret++;
				if (!shift)
					anchor = caret;
				resetBlink();
				return true;
			case 36: // home
				caret = 0;
				if (!shift)
					anchor = caret;
				resetBlink();
				return true;
			case 35: // end
				caret = text.length;
				if (!shift)
					anchor = caret;
				resetBlink();
				return true;
		}
		if (ctrl) {
			switch (keyCode) {
				case 65: // A
					anchor = 0;
					caret = text.length;
					resetBlink();
					return true;
				case 67: // C
					if (hasSelection())
						Clipboard.generalClipboard.setData(ClipboardFormats.TEXT_FORMAT, selectionText());
					return true;
				case 88: // X
					if (hasSelection()) {
						Clipboard.generalClipboard.setData(ClipboardFormats.TEXT_FORMAT, selectionText());
						deleteSelection();
					}
					return true;
				case 86: // V
					var clip:Dynamic = Clipboard.generalClipboard.getData(ClipboardFormats.TEXT_FORMAT);
					if (clip != null)
						insert(Std.string(clip));
					return true;
			}
			return true;
		}
		if (charCode >= 32 && charCode != 127) {
			if (filter == null || filter(charCode))
				insert(String.fromCharCode(charCode));
			return true;
		}
		return true;
	}

	function insert(s:String):Void {
		if (hasSelection())
			deleteSelection();
		var next:String = text.substring(0, caret) + s + text.substring(caret);
		if (maxLength > 0 && next.length > maxLength)
			return;
		setTextInternal(next);
		caret += s.length;
		anchor = caret;
	}

	inline function hasSelection():Bool {
		return caret != anchor;
	}

	function selectionText():String {
		var a:Int = (caret < anchor) ? caret : anchor;
		var b:Int = (caret < anchor) ? anchor : caret;
		return text.substring(a, b);
	}

	function deleteSelection():Void {
		var a:Int = (caret < anchor) ? caret : anchor;
		var b:Int = (caret < anchor) ? anchor : caret;
		setTextInternal(text.substring(0, a) + text.substring(b));
		caret = a;
		anchor = a;
	}

	function setTextInternal(v:String):Void {
		@:bypassAccessor text = v;
		resetBlink();
		invalidate();
		if (onChange != null)
			onChange(v);
	}

	inline function resetBlink():Void {
		blink = 0;
		caretVisible = true;
		invalidate();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(0, 0);
		g.drawRect(0, 0, w, h);
		g.endFill();

		var ix:Float = inputX();
		var bw:Float = w - ix;
		var r:Float = UITheme.px(6);
		g.beginFill(UIColor.rgb(UITheme.inputBg));
		g.drawRoundRect(ix, 1, bw, h - 2, r, r);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(focusedNow ? UITheme.accent : UITheme.border));
		g.drawRoundRect(ix + 0.5, 1.5, bw - 1, h - 3, r, r);
		g.lineStyle();

		UIFonts.restyle(labelTf, UITheme.fs(fontSize), UITheme.text2);
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : label;
		if (labelTf.text != resolved)
			labelTf.text = resolved;
		labelTf.visible = resolved != "";
		labelTf.x = 0;
		labelTf.y = (h - labelTf.height) / 2;

		UIFonts.restyle(tf, UITheme.fs(fontSize), UITheme.text);
		if (tf.text != text)
			tf.text = text;
		tf.width = bw - UITheme.px(12);
		tf.height = tf.textHeight + 4;
		tf.x = ix + UITheme.px(6);
		tf.y = (h - tf.height) / 2;

		// keep the caret inside the box (the field scrolls horizontally with it)
		if (focusedNow) {
			var rawCaret:Float = rawCaretX(caret);
			var innerW:Float = tf.width - 4;
			if (rawCaret - tf.scrollH > innerW)
				tf.scrollH = Std.int(rawCaret - innerW + 8);
			else if (rawCaret - tf.scrollH < 0)
				tf.scrollH = Std.int(Math.max(0, rawCaret - 8));
		} else if (tf.scrollH != 0)
			tf.scrollH = 0;

		if (focusedNow) {
			if (hasSelection()) {
				var a:Int = (caret < anchor) ? caret : anchor;
				var b:Int = (caret < anchor) ? anchor : caret;
				var x0:Float = caretX(a);
				var x1:Float = caretX(b);
				g.beginFill(UIColor.rgb(UITheme.accentDark), 0.45);
				g.drawRect(tf.x + x0, tf.y + 1, x1 - x0, tf.height - 2);
				g.endFill();
			}
			if (caretVisible) {
				var cx:Float = tf.x + caretX(caret);
				g.beginFill(UIColor.rgb(UITheme.text));
				g.drawRect(cx, tf.y + 1, 1.5, tf.height - 2);
				g.endFill();
			}
		}
	}

	function caretX(index:Int):Float {
		return rawCaretX(index) - tf.scrollH;
	}

	function rawCaretX(index:Int):Float {
		if (index <= 0 || text.length == 0)
			return 0;
		if (index > text.length)
			index = text.length;
		var b = tf.getCharBoundaries(index - 1);
		return (b != null) ? (b.x + b.width) : 0;
	}

	override public function dispose():Void {
		UIFocus.clear(this);
		UIRoot.removeTicker(tick);
		super.dispose();
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

	function set_text(v:String):String {
		if (text == v)
			return v;
		text = v;
		if (caret > v.length)
			caret = v.length;
		if (anchor > v.length)
			anchor = v.length;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
