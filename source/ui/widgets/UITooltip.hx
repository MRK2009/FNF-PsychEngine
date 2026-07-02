package ui.widgets;

import openfl.display.Sprite;
import openfl.text.TextField;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UIRoot;
import ui.UITheme;
import ui.UITween;

/**
	The shared hover tooltip. `install()` hooks it into `UIRoot`'s hover-delay driver; any widget
	with a `tooltip` (and optional `tooltipShortcut`, rendered right-aligned) gets one for free.
	One instance, idle-free, fades via `UITween`.
**/
final class UITooltip {
	static var panel:Sprite = null;
	static var textTf:TextField = null;
	static var shortcutTf:TextField = null;
	static var installed:Bool = false;

	/** Hooks the tooltip into the root's hover timing. Call once after creating the `UIRoot`. **/
	public static function install():Void {
		UIRoot.onTooltipShow = show;
		UIRoot.onTooltipHide = hide;
		installed = true;
	}

	static function show(target:UIComponent):Void {
		var root:UIRoot = UIRoot.current;
		if (root == null || root.stage == null)
			return;
		if (panel == null) {
			panel = new Sprite();
			panel.mouseEnabled = false;
			panel.mouseChildren = false;
			textTf = UIFonts.make(UITheme.fs(11), UITheme.text);
			panel.addChild(textTf);
			shortcutTf = UIFonts.make(UITheme.fs(11), UITheme.text3);
			panel.addChild(shortcutTf);
		}
		if (panel.parent != root.tooltipLayer)
			root.tooltipLayer.addChild(panel);

		var hasText:Bool = target.tooltip != null && target.tooltip != "";
		var hasShortcut:Bool = target.tooltipShortcut != null && target.tooltipShortcut != "";
		if (!hasText && !hasShortcut)
			return;

		UIFonts.restyle(textTf, UITheme.fs(11), UITheme.text);
		textTf.text = hasText ? target.tooltip : "";
		textTf.visible = hasText;
		UIFonts.restyle(shortcutTf, UITheme.fs(11), UITheme.text3);
		shortcutTf.text = hasShortcut ? target.tooltipShortcut : "";
		shortcutTf.visible = hasShortcut;

		var padX:Float = UITheme.px(9);
		var padY:Float = UITheme.px(5);
		var gap:Float = (hasText && hasShortcut) ? UITheme.px(14) : 0;
		var pw:Float = padX * 2 + (hasText ? textTf.width : 0) + gap + (hasShortcut ? shortcutTf.width : 0);
		var ph:Float = padY * 2 + Math.max(hasText ? textTf.height : 0, hasShortcut ? shortcutTf.height : 0);

		var g = panel.graphics;
		g.clear();
		g.beginFill(UIColor.rgb(UITheme.panel3), 0.97);
		g.drawRoundRect(0, 0, pw, ph, UITheme.px(6), UITheme.px(6));
		g.endFill();
		g.lineStyle(1, UIColor.rgb(UITheme.border2));
		g.drawRoundRect(0.5, 0.5, pw - 1, ph - 1, UITheme.px(6), UITheme.px(6));
		g.lineStyle();
		textTf.x = padX;
		textTf.y = padY;
		shortcutTf.x = pw - padX - shortcutTf.width;
		shortcutTf.y = padY;

		var local = root.tooltipLayer.globalToLocal(new openfl.geom.Point(root.stage.mouseX, root.stage.mouseY));
		var vw:Float = (root.scaleX > 0) ? root.stage.stageWidth / root.scaleX : 1280;
		var vh:Float = (root.scaleY > 0) ? root.stage.stageHeight / root.scaleY : 720;
		var px:Float = local.x + 14;
		var py:Float = local.y + 20;
		if (px + pw > vw - 4)
			px = vw - pw - 4;
		if (py + ph > vh - 4)
			py = local.y - ph - 8;
		panel.x = px;
		panel.y = py;

		UITween.to(function(a:Float):Void panel.alpha = a, 0, 1, 130, UITween.OUT_QUAD);
	}

	static function hide():Void {
		if (panel == null || panel.parent == null)
			return;
		panel.alpha = 0;
	}

	/** Drops the shared instance (state teardown). **/
	public static function reset():Void {
		if (panel != null && panel.parent != null)
			panel.parent.removeChild(panel);
		panel = null;
		textTf = null;
		shortcutTf = null;
		if (installed) {
			UIRoot.onTooltipShow = null;
			UIRoot.onTooltipHide = null;
			installed = false;
		}
	}
}
