package ui.input;

/**
	A component that can hold keyboard focus (text inputs, key-capture rows).
	Focus is managed by `UIFocus`; while a focused component `capturesKeyboard()`, the host
	application must suppress its own keybinds (`UIFocus.typing`).
**/
interface IUIFocusable {
	/** Called when this component receives focus. **/
	function onFocusGained():Void;

	/** Called when focus moves elsewhere (or is cleared). **/
	function onFocusLost():Void;

	/**
		A key event routed to the focused component.
		@param keyCode the platform key code
		@param charCode the printable character code (0 when none)
		@param ctrl `true` while a Control key is held
		@param shift `true` while a Shift key is held
		@param alt `true` while an Alt key is held
		@return `true` when consumed (the host should not process the key)
	**/
	function onKeyDown(keyCode:Int, charCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool;

	/** `true` while this component wants raw typing (gates app keybinds). **/
	function capturesKeyboard():Bool;
}
