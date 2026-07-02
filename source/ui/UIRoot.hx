package ui;

import openfl.Lib;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import ui.input.IUIFocusable;
import ui.input.UIFocus;
import ui.input.UIPointer;

/**
	The library's stage-attached root: three layers (`content` < `popupLayer` < `tooltipLayer`),
	the invalidation scheduler, the pointer arbiter and the tween/tooltip driver.

	One `ENTER_FRAME` handler flushes dirty widgets and steps tweens — an idle UI performs no
	work. Global mouse listeners (capture phase) maintain `UIPointer.overUI/downOnUI` so the host
	game layer can ignore pointer input that belongs to the UI, complete press-started clicks,
	and route drag capture. A key listener routes typing to `UIFocus` and consumes handled keys
	before they reach the host.

	The host positions the root over its game viewport with `setViewport` (offset + scale) so UI
	coordinates match game coordinates under any letterboxing.
**/
final class UIRoot extends Sprite {
	/** The active root (one per state/screen). **/
	public static var current(default, null):UIRoot = null;

	/** Regular widget layer. **/
	public final content:Sprite;

	/** Dropdown popups, menus, modals — always above content. **/
	public final popupLayer:Sprite;

	/** The shared tooltip — always on top. **/
	public final tooltipLayer:Sprite;

	static var dirty:Array<UIComponent> = [];
	static var dirtySwap:Array<UIComponent> = [];
	static var tickers:Array<Float->Void> = [];

	static var hoverComp:UIComponent = null;
	static var hoverTime:Float = 0;

	var lastTimer:Int = 0;
	var attachedStage:openfl.display.Stage = null;

	public function new() {
		super();
		current = this;
		mouseEnabled = false;
		content = new Sprite();
		popupLayer = new Sprite();
		tooltipLayer = new Sprite();
		tooltipLayer.mouseEnabled = false;
		tooltipLayer.mouseChildren = false;
		addChild(content);
		addChild(popupLayer);
		addChild(tooltipLayer);
		UITheme.onChanged = invalidateAll;
		UILocale.onChanged = invalidateAll;
		addEventListener(Event.ADDED_TO_STAGE, __onAddedToStage);
		addEventListener(Event.REMOVED_FROM_STAGE, __onRemovedFromStage);
	}

	/**
		Adds the root to a display parent.
		@param parent the container to attach to (typically above the game view)
		@param index optional child depth; -1 appends on top
	**/
	public function attach(parent:DisplayObjectContainer, index:Int = -1):Void {
		if (index >= 0)
			parent.addChildAt(this, index);
		else
			parent.addChild(this);
	}

	/**
		Positions/scales the root over the host's content viewport, so UI coordinates match the
		host's coordinate space under any letterboxing.
		@param offsetX viewport left edge in stage pixels
		@param offsetY viewport top edge in stage pixels
		@param scaleX horizontal stage-pixels-per-unit factor
		@param scaleY vertical stage-pixels-per-unit factor
	**/
	public function setViewport(offsetX:Float, offsetY:Float, scaleX:Float, scaleY:Float):Void {
		this.x = offsetX;
		this.y = offsetY;
		this.scaleX = scaleX;
		this.scaleY = scaleY;
	}

	/**
		Queues a widget repaint for the next frame (deduplicated).
		@param c the widget whose `render()` should run on the next flush
	**/
	public static function schedule(c:UIComponent):Void {
		if (c.__dirty)
			return;
		c.__dirty = true;
		dirty.push(c);
	}

	static var overlayClosers:Array<Void->Void> = [];

	/**
		Pushes a closer for the topmost transient overlay (popup/menu/modal); Escape pops it.
		@param fn closes the overlay when invoked
	**/
	public static function pushOverlayCloser(fn:Void->Void):Void {
		overlayClosers.push(fn);
	}

	/**
		Removes a previously pushed overlay closer (call when the overlay closes itself).
		@param fn the same function passed to `pushOverlayCloser`
	**/
	public static function removeOverlayCloser(fn:Void->Void):Void {
		overlayClosers.remove(fn);
	}

	/** `true` while any transient overlay (popup/menu/modal) is open. **/
	public static var overlayOpen(get, never):Bool;

	static inline function get_overlayOpen():Bool {
		return overlayClosers.length > 0;
	}

	/**
		Registers a per-frame callback (held-repeat, caret blink). Keep these rare — an idle
		UI should have no tickers running.
		@param fn receives the elapsed milliseconds each frame
	**/
	public static function addTicker(fn:Float->Void):Void {
		if (tickers.indexOf(fn) < 0)
			tickers.push(fn);
	}

	/**
		Removes a per-frame callback.
		@param fn the same function passed to `addTicker`
	**/
	public static function removeTicker(fn:Float->Void):Void {
		tickers.remove(fn);
	}

	/** Re-renders every live widget (theme/locale change). **/
	public function invalidateAll():Void {
		invalidateTree(this);
	}

	static function invalidateTree(container:DisplayObjectContainer):Void {
		var i:Int = container.numChildren;
		while (--i >= 0) {
			var child:DisplayObject = container.getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).invalidate();
			if (child is DisplayObjectContainer)
				invalidateTree(cast child);
		}
	}

	/**
		Whether a display object sits inside this UI tree (walks the parent chain).
		@param obj the event target to test
		@return `true` when `obj` is this root or one of its descendants
	**/
	public function containsTarget(obj:DisplayObject):Bool {
		while (obj != null) {
			if (obj == this)
				return true;
			obj = obj.parent;
		}
		return false;
	}

	/** The widget currently awaiting/showing a tooltip. **/
	public static var tooltipTarget(get, never):UIComponent;

	static inline function get_tooltipTarget():UIComponent {
		return hoverComp;
	}

	/** Fired when the hover delay elapses; assigned by the tooltip widget. **/
	public static var onTooltipShow:UIComponent->Void = null;

	/** Fired when the hovered widget is left/pressed; assigned by the tooltip widget. **/
	public static var onTooltipHide:Void->Void = null;

	/** Hover-delay before a tooltip appears, in ms. **/
	public static var tooltipDelayMs:Float = 500;

	@:allow(ui.UIComponent)
	static function tooltipEnter(c:UIComponent):Void {
		hoverComp = c;
		hoverTime = 0;
	}

	@:allow(ui.UIComponent)
	static function tooltipLeave(c:UIComponent):Void {
		if (hoverComp != c)
			return;
		hoverComp = null;
		hoverTime = 0;
		if (onTooltipHide != null)
			onTooltipHide();
	}

	function __onFrame(_:Event):Void {
		var now:Int = Lib.getTimer();
		var dt:Float = now - lastTimer;
		lastTimer = now;
		if (dt < 0 || dt > 250)
			dt = 16.6;

		if (dirty.length > 0) {
			var flushing:Array<UIComponent> = dirty;
			dirty = dirtySwap;
			dirtySwap = flushing;
			var i:Int = 0;
			var n:Int = flushing.length;
			while (i < n) {
				var c:UIComponent = flushing[i];
				c.__dirty = false;
				c.render();
				i++;
			}
			flushing.resize(0);
		}

		UITween.step(dt);

		var ti:Int = tickers.length;
		while (--ti >= 0)
			tickers[ti](dt);

		if (hoverComp != null && hoverTime >= 0) {
			hoverTime += dt;
			if (hoverTime >= tooltipDelayMs) {
				hoverTime = -1;
				if (onTooltipShow != null && (hoverComp.tooltip != null || hoverComp.tooltipShortcut != null))
					onTooltipShow(hoverComp);
			}
		}
	}

	function __onAddedToStage(_:Event):Void {
		attachedStage = stage;
		lastTimer = Lib.getTimer();
		attachedStage.addEventListener(Event.ENTER_FRAME, __onFrame);
		attachedStage.addEventListener(MouseEvent.MOUSE_DOWN, __onStageMouseDown, true);
		attachedStage.addEventListener(MouseEvent.MOUSE_UP, __onStageMouseUp, true);
		attachedStage.addEventListener(MouseEvent.MOUSE_MOVE, __onStageMouseMove, true);
		// keyboard events TARGET the stage (no focus object), so a capture-phase listener
		// would never fire — listen in the target phase and consume via stopImmediatePropagation
		attachedStage.addEventListener(KeyboardEvent.KEY_DOWN, __onStageKeyDown, false, 100);
	}

	function __onRemovedFromStage(_:Event):Void {
		if (attachedStage == null)
			return;
		attachedStage.removeEventListener(Event.ENTER_FRAME, __onFrame);
		attachedStage.removeEventListener(MouseEvent.MOUSE_DOWN, __onStageMouseDown, true);
		attachedStage.removeEventListener(MouseEvent.MOUSE_UP, __onStageMouseUp, true);
		attachedStage.removeEventListener(MouseEvent.MOUSE_MOVE, __onStageMouseMove, true);
		attachedStage.removeEventListener(KeyboardEvent.KEY_DOWN, __onStageKeyDown, false);
		attachedStage = null;
	}

	function __onStageMouseDown(e:MouseEvent):Void {
		var target:DisplayObject = cast(e.target, DisplayObject);
		var inside:Bool = containsTarget(target);
		if (!inside)
			@:privateAccess UIPointer.clearPress();
		@:privateAccess UIPointer.downOnUI = inside;

		var focused:IUIFocusable = UIFocus.focused;
		if (focused != null && focused is UIComponent && !chainContains(target, cast focused))
			UIFocus.clear();

		if (hoverComp != null && onTooltipHide != null) {
			hoverTime = -1;
			onTooltipHide();
		}
	}

	function __onStageMouseUp(_:MouseEvent):Void {
		var capture:UIComponent = UIPointer.captureTarget;
		if (capture != null) {
			UIPointer.releaseCapture(capture);
			capture.onDragEnd();
		}
		var press:UIComponent = UIPointer.pressTarget;
		if (press != null)
			press.releasePress(press.hovered);
		@:privateAccess UIPointer.clearPress();
	}

	function __onStageMouseMove(e:MouseEvent):Void {
		@:privateAccess UIPointer.setOverUI(containsTarget(cast(e.target, DisplayObject)));
		var capture:UIComponent = UIPointer.captureTarget;
		if (capture != null)
			capture.onDragMove(e.stageX, e.stageY);
	}

	function __onStageKeyDown(e:KeyboardEvent):Void {
		if (UIFocus.keyDown(e.keyCode, e.charCode, e.ctrlKey, e.shiftKey, e.altKey)) {
			e.stopImmediatePropagation();
			return;
		}
		if (e.keyCode == 27 && overlayClosers.length > 0) {
			var closer:Void->Void = overlayClosers[overlayClosers.length - 1];
			closer();
			e.stopImmediatePropagation();
		}
	}

	static function chainContains(obj:DisplayObject, ancestor:UIComponent):Bool {
		while (obj != null) {
			if (obj == ancestor)
				return true;
			obj = obj.parent;
		}
		return false;
	}

	/** Full teardown: listeners, layers, statics. Call from the host state's `destroy`. **/
	public function dispose():Void {
		removeEventListener(Event.ADDED_TO_STAGE, __onAddedToStage);
		removeEventListener(Event.REMOVED_FROM_STAGE, __onRemovedFromStage);
		if (parent != null)
			parent.removeChild(this);
		var i:Int = content.numChildren;
		while (--i >= 0) {
			var child = content.getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).dispose();
		}
		content.removeChildren();
		popupLayer.removeChildren();
		tooltipLayer.removeChildren();
		UITween.cancelAll();
		UIFocus.clear();
		@:privateAccess UIPointer.clearPress();
		UIPointer.releaseCapture();
		dirty.resize(0);
		dirtySwap.resize(0);
		tickers.resize(0);
		overlayClosers.resize(0);
		hoverComp = null;
		onTooltipShow = null;
		onTooltipHide = null;
		if (UITheme.onChanged == invalidateAll)
			UITheme.onChanged = null;
		if (UILocale.onChanged == invalidateAll)
			UILocale.onChanged = null;
		if (current == this)
			current = null;
	}
}
