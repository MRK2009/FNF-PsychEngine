package ui.widgets;

import ui.UIColor;
import ui.UIComponent;
import ui.UITheme;

/** A 1px themed divider line (horizontal by default). **/
final class UISeparator extends UIComponent {
	/**
		@param length the line length
		@param vertical `true` for a vertical divider
	**/
	public function new(length:Float, vertical:Bool = false) {
		super(false, false);
		resize(vertical ? 1 : length, vertical ? length : 1);
		render();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(UIColor.rgb(UITheme.border));
		g.drawRect(0, 0, (w > 1) ? w : 1, (h > 1) ? h : 1);
		g.endFill();
	}
}
