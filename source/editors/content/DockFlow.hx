package editors.content;

import smidr.UIComponent;
import smidr.UITheme;
import smidr.widgets.UIAccordion;
import smidr.widgets.UIScrollPane;

/**
	Single-column dock layout: widgets flow top-down inside a `UIScrollPane`; `UIAccordion`
	headers collapse the widgets added after them (until the next header).
**/
final class DockFlow {
	final pane:UIScrollPane;
	final x:Float;
	final gap:Float;
	final rows:Array<UIComponent> = [];
	final rowSection:Array<Int> = [];
	final open:Array<Bool> = [];
	var section:Int = -1;

	/**
		@param pane the scroll pane the flow fills
		@param x the left inset for every row
		@param gap vertical spacing between rows
	**/
	public function new(pane:UIScrollPane, x:Float, gap:Float) {
		this.pane = pane;
		this.x = x;
		this.gap = gap;
	}

	/**
		Starts a new collapsible section headed by the accordion (its `onToggle` is taken over).
		@param acc the section header
		@return the same accordion, for chaining
	**/
	public function header(acc:UIAccordion):UIAccordion {
		open.push(acc.expanded);
		final idx:Int = open.length - 1;
		section = idx;
		rows.push(acc);
		rowSection.push(-1);
		pane.content.addChild(acc);
		acc.onToggle = function(v:Bool):Void {
			open[idx] = v;
			reflow();
		};
		return acc;
	}

	/**
		Adds a row to the current section (hidden while that section is collapsed).
		@param c the widget (its `h` drives the flow spacing)
		@return the same widget, for chaining
	**/
	public function add(c:UIComponent):UIComponent {
		rows.push(c);
		rowSection.push(section);
		pane.content.addChild(c);
		return c;
	}

	/** Re-lays every row top-down (skipping collapsed sections) and refreshes the pane. **/
	public function reflow():Void {
		var y:Float = UITheme.px(10);
		var i:Int = 0;
		var n:Int = rows.length;
		while (i < n) {
			var c:UIComponent = rows[i];
			var sec:Int = rowSection[i];
			var show:Bool = (sec < 0) || open[sec];
			c.visible = show;
			if (show) {
				if (sec < 0 && i > 0)
					y += gap;
				c.x = x;
				c.y = y;
				y += c.h + gap;
			}
			i++;
		}
		pane.refreshContent(y + UITheme.px(10));
	}
}
