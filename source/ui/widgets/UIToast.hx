package ui.widgets;

import openfl.text.TextField;
import ui.UIColor;
import ui.UIFonts;
import ui.UIRoot;
import ui.UITheme;
import ui.UITween;

/**
	Transient status messages: slide up near the bottom of the viewport, hold, then fade out.
	One shared instance; a new message replaces the current one immediately.
**/
final class UIToast {
	static var tf:TextField = null;
	static var panel:openfl.display.Sprite = null;
	static var hideTween:UITween = null;

	/** Milliseconds a toast stays fully visible before fading. **/
	public static var holdMs:Float = 2600;

	/**
		Shows a message near the bottom center of the viewport (replaces any current toast).
		@param message the text to display
	**/
	public static function show(message:String):Void {
		var root:UIRoot = UIRoot.current;
		if (root == null)
			return;
		if (panel == null) {
			panel = new openfl.display.Sprite();
			panel.mouseEnabled = false;
			panel.mouseChildren = false;
			tf = UIFonts.make(UITheme.fs(12), UITheme.text);
			panel.addChild(tf);
		}
		if (panel.parent != root.tooltipLayer)
			root.tooltipLayer.addChild(panel);

		UIFonts.restyle(tf, UITheme.fs(12), UITheme.text);
		tf.text = message;

		var padX:Float = UITheme.px(14);
		var padY:Float = UITheme.px(7);
		var pw:Float = tf.width + padX * 2;
		var ph:Float = tf.height + padY * 2;
		var g = panel.graphics;
		g.clear();
		g.beginFill(UIColor.rgb(UITheme.panel2), 0.96);
		g.drawRoundRect(0, 0, pw, ph, ph, ph);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(UITheme.border2));
		g.drawRoundRect(0.5, 0.5, pw - 1, ph - 1, ph, ph);
		g.lineStyle();
		tf.x = padX;
		tf.y = padY;

		var vw:Float = viewportW(root);
		var vh:Float = viewportH(root);
		panel.x = (vw - pw) / 2;
		var targetY:Float = vh - ph - UITheme.px(56);

		if (hideTween != null)
			hideTween.cancel();
		panel.alpha = 0;
		panel.y = targetY + UITheme.px(12);
		UITween.to(function(p:Float):Void {
			panel.alpha = p;
			panel.y = targetY + UITheme.px(12) * (1 - p);
		}, 0, 1, 170, UITween.OUT_QUAD, function():Void {
			hideTween = UITween.to(function(p:Float):Void {
				panel.alpha = p;
			}, 1, 1, holdMs, UITween.LINEAR, function():Void {
				hideTween = UITween.to(function(p:Float):Void panel.alpha = p, 1, 0, 310, UITween.LINEAR);
			});
		});
	}

	static inline function viewportW(root:UIRoot):Float {
		return (root.stage != null && root.scaleX > 0) ? root.stage.stageWidth / root.scaleX : 1280;
	}

	static inline function viewportH(root:UIRoot):Float {
		return (root.stage != null && root.scaleY > 0) ? root.stage.stageHeight / root.scaleY : 720;
	}

	/** Drops the shared instance (state teardown). **/
	public static function reset():Void {
		if (hideTween != null) {
			hideTween.cancel();
			hideTween = null;
		}
		if (panel != null && panel.parent != null)
			panel.parent.removeChild(panel);
		panel = null;
		tf = null;
	}
}
