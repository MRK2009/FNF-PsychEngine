package ui.widgets;

import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.geom.Rectangle;
import ui.UIColor;
import ui.UIComponent;
import ui.UIRoot;
import ui.UITheme;

/**
	A fixed-size, vertically scrollable container. Add children to `content`; call
	`refreshContent()` after (re)filling it. Scrolls by mouse wheel and by dragging the slim
	scrollbar thumb. Clipping uses `scrollRect` (GPU clip — scrolling never repaints children).
**/
final class UIScrollPane extends UIComponent {
	/** Put pane content here (coordinates relative to the pane's top-left). **/
	public final content:Sprite;

	/** Current scroll offset in pixels (0..maxScroll). **/
	public var scrollY(default, null):Float = 0;

	/** Pixels per wheel notch. **/
	public var wheelStep:Float = 40;

	var contentH:Float = 0;
	var thumb:Shape;
	var dragging:Bool = false;
	var dragGrabY:Float = 0;

	/**
		@param width layout width (the scrollbar lives inside it)
		@param height the visible viewport height
	**/
	public function new(width:Float, height:Float) {
		super(false, true);
		content = new Sprite();
		addChild(content);
		thumb = new Shape();
		addChild(thumb);
		addEventListener(MouseEvent.MOUSE_WHEEL, __onWheel);
		addEventListener(MouseEvent.MOUSE_DOWN, __onBarPress);
		resize(width, height);
		render();
	}

	/**
		Re-measures the content height and clamps the scroll position. Call after (re)filling
		`content`.
		@param explicitHeight overrides the measured `content.height` when provided
	**/
	public function refreshContent(?explicitHeight:Float):Void {
		contentH = (explicitHeight != null) ? explicitHeight : content.height;
		setScroll(scrollY);
		invalidate();
	}

	/** The furthest `scrollY` can go. **/
	public var maxScroll(get, never):Float;

	inline function get_maxScroll():Float {
		var m:Float = contentH - h;
		return (m > 0) ? m : 0;
	}

	/**
		Scrolls to an absolute offset.
		@param value the target offset in pixels (clamped to 0..`maxScroll`)
	**/
	public function setScroll(value:Float):Void {
		var m:Float = maxScroll;
		if (value < 0)
			value = 0;
		if (value > m)
			value = m;
		scrollY = value;
		content.scrollRect = new Rectangle(0, scrollY, w, h);
		positionThumb();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(UIColor.rgb(UITheme.panel));
		g.drawRect(0, 0, w, h);
		g.endFill();
		content.scrollRect = new Rectangle(0, scrollY, w, h);
		drawThumb();
	}

	function drawThumb():Void {
		var g = thumb.graphics;
		g.clear();
		var m:Float = maxScroll;
		thumb.visible = (m > 0);
		if (m <= 0)
			return;
		var barW:Float = UITheme.px(4);
		var trackH:Float = h - 4;
		var thumbH:Float = trackH * (h / contentH);
		if (thumbH < 24)
			thumbH = 24;
		g.beginFill(UIColor.rgb(UITheme.border2));
		g.drawRoundRect(0, 0, barW, thumbH, barW, barW);
		g.endFill();
		positionThumb();
	}

	function positionThumb():Void {
		var m:Float = maxScroll;
		if (m <= 0)
			return;
		var trackH:Float = h - 4;
		var thumbH:Float = trackH * (h / contentH);
		if (thumbH < 24)
			thumbH = 24;
		thumb.x = w - UITheme.px(4) - 2;
		thumb.y = 2 + (trackH - thumbH) * (scrollY / m);
	}

	function __onWheel(e:MouseEvent):Void {
		if (maxScroll <= 0)
			return;
		setScroll(scrollY - e.delta * wheelStep);
		e.stopPropagation();
	}

	function __onBarPress(e:MouseEvent):Void {
		if (maxScroll <= 0)
			return;
		if (e.localX < w - UITheme.px(4) - 4)
			return;
		dragging = true;
		dragGrabY = e.stageY;
		dragStartScroll = scrollY;
		beginCapture();
		e.stopPropagation();
	}

	var dragStartScroll:Float = 0;

	override function onDragMove(stageX:Float, stageY:Float):Void {
		if (!dragging)
			return;
		var trackH:Float = h - 4;
		var thumbH:Float = trackH * (h / contentH);
		if (thumbH < 24)
			thumbH = 24;
		var usable:Float = trackH - thumbH;
		if (usable <= 0)
			return;
		var deltaStage:Float = (stageY - dragGrabY) / (scaleFactorY());
		setScroll(dragStartScroll + deltaStage * (maxScroll / usable));
	}

	override function onDragEnd():Void {
		dragging = false;
	}

	inline function scaleFactorY():Float {
		var root = UIRoot.current;
		return (root != null && root.scaleY > 0) ? root.scaleY : 1.0;
	}

	override public function dispose():Void {
		removeEventListener(MouseEvent.MOUSE_WHEEL, __onWheel);
		removeEventListener(MouseEvent.MOUSE_DOWN, __onBarPress);
		var i:Int = content.numChildren;
		while (--i >= 0) {
			var child = content.getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).dispose();
		}
		content.removeChildren();
		super.dispose();
	}
}
