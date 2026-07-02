package ui.input;

import ui.UIComponent;

/**
	Global pointer state shared by `UIRoot` and the widgets.

	Click correctness is enforced here by construction: a *click* only fires when the press
	STARTED on a widget and the release happens while still over it (`pressTarget`), so events
	leaking through closing menus can never trigger whatever sits underneath. `captureTarget`
	routes every pointer move to one widget for the duration of a drag (sliders, scrollbars,
	popup interactions), regardless of what the cursor passes over.
**/
final class UIPointer {
	/** The widget the current press started on (cleared on release). **/
	public static var pressTarget(default, null):UIComponent = null;

	/** The widget receiving exclusive drag callbacks until release. **/
	public static var captureTarget(default, null):UIComponent = null;

	/** `true` while the cursor is over any UI (updated by `UIRoot`). **/
	public static var overUI(default, null):Bool = false;

	/** `true` while a press that started on UI is held (updated by `UIRoot`). **/
	public static var downOnUI(default, null):Bool = false;

	/** Marks the widget the current press started on. Called from `UIComponent`. **/
	@:allow(ui.UIComponent)
	static function beginPress(target:UIComponent):Void {
		pressTarget = target;
		downOnUI = true;
	}

	/**
		Grabs exclusive drag routing until the pointer releases: `target` receives every
		`onDragMove`/`onDragEnd` regardless of what the cursor passes over.
		@param target the widget taking the drag
	**/
	public static function capture(target:UIComponent):Void {
		captureTarget = target;
	}

	/**
		Drops drag routing.
		@param target when set, only releases if that widget currently holds capture
	**/
	public static function releaseCapture(?target:UIComponent):Void {
		if (target == null || captureTarget == target)
			captureTarget = null;
	}

	@:allow(ui.UIRoot)
	static function setOverUI(value:Bool):Void {
		overUI = value;
	}

	@:allow(ui.UIRoot)
	static function clearPress():Void {
		pressTarget = null;
		downOnUI = false;
	}

	/** Forgets a widget entirely (called from `UIComponent.dispose`). **/
	@:allow(ui.UIComponent)
	static function forget(target:UIComponent):Void {
		if (pressTarget == target)
			pressTarget = null;
		if (captureTarget == target)
			captureTarget = null;
	}
}
