package ui;

/**
	The active UI palette + metric scale.

	Surfaces are neutral material-dark ramps; the brand accents are reserved for active/selected
	states only. All values are plain `0xAARRGGBB` ints so the library carries no framework color
	dependency. Widgets read these at `render()` time, so calling `changed()` after mutating any
	value (or `setScale`) re-skins every live widget through `UIRoot.invalidateAll`.
**/
final class UITheme {
	/** Window/backdrop — the darkest step of the neutral surface ramp. **/
	public static var bg:Int = 0xFF121214;

	/** Base panel surface (docks, scroll panes). **/
	public static var panel:Int = 0xFF1E1E21;

	/** Raised surface (buttons, chips, value boxes). **/
	public static var panel2:Int = 0xFF26262B;

	/** Highest surface (hover pills, active rows). **/
	public static var panel3:Int = 0xFF34343B;

	/** Card surface (grouped content blocks). **/
	public static var card:Int = 0xFF2C2C32;

	/** Text-input well (recessed). **/
	public static var inputBg:Int = 0xFF17171B;

	/** Standard 1px border. **/
	public static var border:Int = 0xFF3C3C44;

	/** Emphasized border (popups, focus-adjacent chrome). **/
	public static var border2:Int = 0xFF585864;

	/** Primary text. **/
	public static var text:Int = 0xFFE9E7EF;

	/** Secondary text (labels, inactive titles). **/
	public static var text2:Int = 0xFFB2B0BC;

	/** Tertiary text (hints, captions). **/
	public static var text3:Int = 0xFF7F7D8A;

	/** Primary brand accent — active/selected/primary states ONLY, never surfaces. **/
	public static var accent:Int = 0xFF8A5EE0;

	/** Darker accent fill (primary buttons, checked boxes). **/
	public static var accentDark:Int = 0xFF6B3FC4;

	/** Alternate accent hue (secondary emphasis). **/
	public static var accentAlt:Int = 0xFFC558D6;

	/** Bright accent tint (selection highlights). **/
	public static var highlight:Int = 0xFFE6AEEF;

	/** Positive state (enabled dots, confirmations). **/
	public static var success:Int = 0xFF63D68A;

	/** Destructive state (delete buttons, errors). **/
	public static var danger:Int = 0xFFF05C7C;

	/** Caution state. **/
	public static var warning:Int = 0xFFFFCA6E;

	/** Global UI density multiplier (user setting). Apply via `setScale`. **/
	public static var scale(default, null):Float = 1.0;

	/** Base corner radius, pre-scale. **/
	public static var radius:Float = 7;

	/** Fired after theme mutations; `UIRoot` assigns this to re-render every widget. **/
	public static var onChanged:Void->Void = null;

	/**
		Scales a base pixel metric by the global UI scale.
		@param base the design-size value (at scale 1)
		@return the scaled value
	**/
	public static inline function px(base:Float):Float {
		return base * scale;
	}

	/**
		Scales a base font size by the global UI scale.
		@param base the design font size (at scale 1)
		@return the scaled size, rounded to the nearest int
	**/
	public static inline function fs(base:Int):Int {
		return Std.int(base * scale + 0.5);
	}

	/**
		Sets the density multiplier and re-skins live widgets.
		@param value the new scale (> 0; no-op when unchanged)
	**/
	public static function setScale(value:Float):Void {
		if (value <= 0 || value == scale)
			return;
		scale = value;
		changed();
	}

	/** Notifies live widgets that theme values changed. **/
	public static function changed():Void {
		if (onChanged != null)
			onChanged();
	}
}
