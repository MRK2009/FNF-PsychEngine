package mobile.objects;

import openfl.text.TextField;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldAutoSize;
import smidr.UIColor;
import smidr.UIComponent;
import smidr.UIFonts;
import smidr.UITheme;

/**
 * A single on-screen touch button rendered in the SmidrUI look (themed rounded rect + label), but
 * driven entirely by the owning `mobile.input.TouchPad` rather than by SmidrUI's own pointer input.
 *
 * It is a **non-interactive** `UIComponent`: no `MouseEvent` listeners, so it never touches SmidrUI's
 * pointer arbitration (`UIPointer.overUI` / `FlxSmidr.mouseBlocked`) and its press state comes from the
 * pad's multitouch hit-testing. It also never calls `resize`/`invalidate`, so it stays out of the
 * global `UIRoot` repaint queue -- it paints itself immediately through `render` whenever its state
 * changes. `tag` maps it to a virtual action (see `TouchPad.controlToTag`).
 */
class SmidrTouchButton extends UIComponent {
	public var tag:String;

	public var held:Bool = false;
	public var justPressed:Bool = false;
	public var justReleased:Bool = false;

	/**
	 * When set, the next `updatePressed` re-baselines the press state without emitting a `justPressed`
	 * / `justReleased` edge -- so a finger already held over the button when this pad regains focus
	 * (e.g. a substate closing over the parent) does not read as a fresh press. Mirrors
	 * `mobile.objects.TouchButton.ignoreHeld`.
	 */
	public var ignoreHeld:Bool = false;

	/** Highlight alpha applied while held. */
	public var pressedAlpha:Float = 1.0;

	/** Resting alpha; assigning live (e.g. the controls-alpha option) re-applies it immediately. */
	public var idleAlpha(default, set):Float = 0.6;

	function set_idleAlpha(value:Float):Float {
		idleAlpha = value;
		if (!held)
			alpha = value;
		return value;
	}

	/** Button edge length (UI units). Owns its own size -- `w`/`h` are left unused (see class doc). */
	public var size:Float;

	/** Accent tint blended into the fill so d-pad vs action buttons stay distinguishable. */
	public var tint:Int;

	final labelField:TextField;
	final labelText:String;

	public function new(tag:String, label:String, size:Float, tint:Int) {
		super(false, false); // non-interactive, pointer-transparent
		this.tag = tag;
		this.size = size;
		this.tint = tint;
		this.labelText = label;

		labelField = UIFonts.make(UITheme.fs(40), UITheme.text, TextFormatAlign.CENTER);
		labelField.autoSize = TextFieldAutoSize.NONE;
		labelField.mouseEnabled = false;
		labelField.selectable = false;
		addChild(labelField);

		alpha = idleAlpha;
		render();
	}

	/**
	 * Updates the held state from the pad's per-frame hit test, deriving the one-frame `justPressed` /
	 * `justReleased` edges (same contract as `TouchButton.update`). Honors `ignoreHeld`.
	 * @param nowPressed whether a touch currently overlaps this button
	 */
	public function updatePressed(nowPressed:Bool):Void {
		if (ignoreHeld) {
			ignoreHeld = false;
			justPressed = false;
			justReleased = false;
			setHeld(nowPressed);
			return;
		}

		justPressed = nowPressed && !held;
		justReleased = !nowPressed && held;
		setHeld(nowPressed);
	}

	inline function setHeld(value:Bool):Void {
		if (held != value) {
			held = value;
			render();
		}
		alpha = held ? pressedAlpha : idleAlpha;
	}

	override public function render():Void {
		graphics.clear();

		final radius:Float = UITheme.px(UITheme.radius) * 2;
		var base:Int = UIColor.lighten(UITheme.panel2, 0.04);
		// fold in the action tint so the button reads like its role, then dim on press
		base = UIColor.rgb(base) | 0xFF000000;
		if (tint != 0)
			base = blend(base, tint, 0.22);
		base = held ? UIColor.darken(base, 0.2) : base;

		graphics.beginFill(UIColor.rgb(base));
		graphics.drawRoundRect(0, 0, size, size, radius, radius);
		graphics.endFill();

		graphics.lineStyle(2, UIColor.rgb(UITheme.border));
		graphics.drawRoundRect(1, 1, size - 2, size - 2, radius, radius);
		graphics.lineStyle();

		final dip:Float = held ? 2 : 0;
		UIFonts.restyle(labelField, UITheme.fs(40), UITheme.text, TextFormatAlign.CENTER);
		if (labelField.text != labelText)
			labelField.text = labelText;
		labelField.width = size;
		labelField.height = labelField.textHeight + 6;
		labelField.x = 0;
		labelField.y = (size - labelField.height) / 2 + dip;
	}

	/** Linear blend of two ARGB colors (keeps `a`'s alpha). */
	inline function blend(a:Int, b:Int, t:Float):Int {
		final ar:Int = (a >> 16) & 0xFF, ag:Int = (a >> 8) & 0xFF, ab:Int = a & 0xFF;
		final br:Int = (b >> 16) & 0xFF, bg:Int = (b >> 8) & 0xFF, bb:Int = b & 0xFF;
		final rr:Int = Std.int(ar + (br - ar) * t);
		final rg:Int = Std.int(ag + (bg - ag) * t);
		final rb:Int = Std.int(ab + (bb - ab) * t);
		return 0xFF000000 | (rr << 16) | (rg << 8) | rb;
	}

	/** Removes the label child; the pad detaches the button from the overlay. */
	public function disposeButton():Void {
		if (labelField.parent == this)
			removeChild(labelField);
	}
}
