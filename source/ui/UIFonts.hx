package ui;

import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.utils.Assets;

/**
	Font + `TextFormat` cache for the library's `TextField`s.

	`register()` points every widget at an embedded font asset; formats are cached per
	(size, color, align) so text restyles never allocate. `TextField`s copy assigned formats
	internally, so sharing cached instances is safe.
**/
final class UIFonts {
	/** The active font face name (falls back to the system sans). **/
	public static var fontName(default, null):String = "_sans";

	static var embedded:Bool = false;
	static final cache:Map<String, TextFormat> = new Map();

	/**
		Loads an embedded font asset and makes it the library font.
		@param assetPath the embedded font asset (e.g. `assets/fonts/main.ttf`)
		@return `true` when the font was found and applied
	**/
	public static function register(assetPath:String):Bool {
		var font = Assets.getFont(assetPath);
		if (font == null)
			return false;
		fontName = font.fontName;
		embedded = true;
		cache.clear();
		return true;
	}

	/**
		A cached `TextFormat` for the library font.
		@param size font size in px
		@param color text color (`0xRRGGBB`; alpha bits are masked off)
		@param align paragraph alignment (default LEFT)
		@return the shared cached format — safe to assign, `TextField` copies it
	**/
	public static function format(size:Int, color:Int, ?align:TextFormatAlign):TextFormat {
		var key:String = size + "|" + color + "|" + (align != null ? Std.string(align) : "l");
		var fmt:TextFormat = cache.get(key);
		if (fmt == null) {
			fmt = new TextFormat(fontName, size, color & 0xFFFFFF);
			fmt.align = (align != null) ? align : TextFormatAlign.LEFT;
			cache.set(key, fmt);
		}
		return fmt;
	}

	/**
		Builds a non-interactive single-line auto-sizing `TextField` in the library font.
		@param size font size in px
		@param color text color
		@param align paragraph alignment (default LEFT)
		@return the configured field (mouse-transparent, not selectable)
	**/
	public static function make(size:Int, color:Int, ?align:TextFormatAlign):TextField {
		var tf:TextField = new TextField();
		tf.embedFonts = embedded;
		tf.defaultTextFormat = format(size, color, align);
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.multiline = false;
		tf.autoSize = TextFieldAutoSize.LEFT;
		return tf;
	}

	/**
		Restyles an existing field with a cached format (applies to current and future text).
		@param tf the field to restyle
		@param size font size in px
		@param color text color
		@param align paragraph alignment (default LEFT)
	**/
	public static inline function restyle(tf:TextField, size:Int, color:Int, ?align:TextFormatAlign):Void {
		tf.embedFonts = embedded;
		tf.defaultTextFormat = format(size, color, align);
		tf.setTextFormat(format(size, color, align));
	}
}
