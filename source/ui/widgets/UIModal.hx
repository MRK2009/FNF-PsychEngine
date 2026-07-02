package ui.widgets;

import openfl.text.TextFormatAlign;
import ui.UIColor;
import ui.UIComponent;
import ui.UIRoot;
import ui.UITheme;
import ui.UITween;

/**
	A modal dialog panel centered over a dimmed, click-blocking backdrop on `UIRoot.popupLayer`.
	Add content to `body` (coordinates relative to the panel, below the title). Escape or the
	backdrop click closes it (unless `dismissable = false`). Opens/closes with a short fade+scale.
**/
final class UIModal extends UIComponent {
	/** Panel content container (children below the title area). **/
	public final body:UIComponent;

	/** Set false for must-answer dialogs. **/
	public var dismissable:Bool = true;

	/** Fired after the modal fully closes. **/
	public var onClosed:Void->Void = null;

	public var titleText(default, set):String;

	var backdrop:UIComponent;
	var titleLabel:UILabel;
	var closing:Bool = false;

	/**
		@param title the header text
		@param width the panel width
		@param height the panel height
	**/
	public function new(title:String, width:Float, height:Float) {
		super(false, true);
		titleText = title;

		backdrop = new UIComponent(true, true);
		backdrop.hoverCursor = null;
		backdrop.onClick = requestClose;
		backdrop.graphics.beginFill(0x000000, 0.55);
		backdrop.graphics.drawRect(-16000, -16000, 32000, 32000);
		backdrop.graphics.endFill();

		titleLabel = new UILabel(title, 15, 0);
		addChild(titleLabel);

		body = new UIComponent(false, false);
		addChild(body);

		resize(width, height);
		render();
	}

	/** Shows the modal centered in the root viewport. **/
	public function open():Void {
		var root:UIRoot = UIRoot.current;
		if (root == null)
			return;
		root.popupLayer.addChild(backdrop);
		root.popupLayer.addChild(this);
		var vw:Float = root.stage != null ? root.stage.stageWidth / (root.scaleX > 0 ? root.scaleX : 1) : 1280;
		var vh:Float = root.stage != null ? root.stage.stageHeight / (root.scaleY > 0 ? root.scaleY : 1) : 720;
		x = (vw - w) / 2;
		y = (vh - h) / 2;
		UIRoot.pushOverlayCloser(requestClose);
		alpha = 0;
		UITween.to(setOpenProgress, 0, 1, 155, UITween.OUT_QUAD);
	}

	function setOpenProgress(p:Float):Void {
		alpha = p;
		backdrop.alpha = p;
		scaleX = 0.98 + 0.02 * p;
		scaleY = scaleX;
	}

	/** Closes when dismissable (Escape / backdrop). **/
	public function requestClose():Void {
		if (dismissable)
			close();
	}

	/** Closes unconditionally. **/
	public function close():Void {
		if (closing)
			return;
		closing = true;
		UIRoot.removeOverlayCloser(requestClose);
		UITween.to(setOpenProgress, 1, 0, 110, UITween.IN_QUAD, finishClose);
	}

	function finishClose():Void {
		if (backdrop.parent != null)
			backdrop.parent.removeChild(backdrop);
		backdrop.dispose();
		var done:Void->Void = onClosed;
		dispose();
		if (done != null)
			done();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		var r:Float = UITheme.px(12);
		g.beginFill(UIColor.rgb(UITheme.panel));
		g.drawRoundRect(0, 0, w, h, r, r);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(UITheme.border2));
		g.drawRoundRect(0.5, 0.5, w - 1, h - 1, r, r);
		g.lineStyle();

		titleLabel.text = titleText;
		titleLabel.x = UITheme.px(16);
		titleLabel.y = UITheme.px(12);
		body.x = 0;
		body.y = UITheme.px(40);
	}

	function set_titleText(v:String):String {
		titleText = v;
		invalidate();
		return v;
	}
}
