package ui.input;

/**
	Keyboard focus manager. Exactly one `IUIFocusable` holds focus; `typing` is the single flag
	host applications check before processing their own keybinds.
**/
final class UIFocus {
	/** The focused component, or `null`. **/
	public static var focused(default, null):IUIFocusable = null;

	/** `true` while the focused component captures raw typing. **/
	public static var typing(get, never):Bool;

	static inline function get_typing():Bool {
		return focused != null && focused.capturesKeyboard();
	}

	/**
		Moves focus (notifies the old and new holders).
		@param target the new focus holder, or `null` to blur
	**/
	public static function set(target:IUIFocusable):Void {
		if (focused == target)
			return;
		var old:IUIFocusable = focused;
		focused = target;
		if (old != null)
			old.onFocusLost();
		if (target != null)
			target.onFocusGained();
	}

	/**
		Clears focus.
		@param ifTarget when set, only clears if that component currently holds focus
	**/
	public static function clear(?ifTarget:IUIFocusable):Void {
		if (ifTarget != null && focused != ifTarget)
			return;
		set(null);
	}

	/**
		Routes a key event to the focused component.
		@param keyCode the platform key code
		@param charCode the printable character code (0 when none)
		@param ctrl `true` while a Control key is held
		@param shift `true` while a Shift key is held
		@param alt `true` while an Alt key is held
		@return `true` when the focused component consumed the key
	**/
	public static function keyDown(keyCode:Int, charCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool {
		return (focused != null) && focused.onKeyDown(keyCode, charCode, ctrl, shift, alt);
	}
}
