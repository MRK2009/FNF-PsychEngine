package editors.mobile;

import flixel.FlxG;
import flixel.math.FlxRect;
import openfl.display.Sprite;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.flixel.FlxSmidr;
import smidr.types.UISurface;
import smidr.widgets.UIButton;
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;
import smidr.widgets.UIScrollPane;
import smidr.widgets.UIDrawer;

/**
 * Shared touch chrome for the mobile editors: a compact top toolbar (Back, Play/Pause, Undo, Redo,
 * a status label, and a Panels button) plus a right-edge `UIDrawer` whose scroll pane the owning
 * editor fills with its settings. Exposes the canvas viewport rect (`field`) below the toolbar so
 * the editor's Flixel view gets the full width; the drawer overlays it when open.
 *
 * Chrome only -- the editor wires the button callbacks and populates `panel`. Built under the mobile
 * `UITheme` preset so every control is finger-sized.
 */
class MobileEditorShell {
	public final root:UIRoot;
	public final drawer:UIDrawer;

	/** The drawer's scroll content -- the editor adds its setting widgets here. **/
	public final panel:UIScrollPane;

	/** Canvas viewport in game px (below the toolbar), for the editor's Flixel view. **/
	public final field:FlxRect;

	public var onBack:Void->Void = null;
	public var onPlayPause:Void->Void = null;
	public var onUndo:Void->Void = null;
	public var onRedo:Void->Void = null;

	final mainUI:Sprite;
	final playBtn:UIButton;
	final statusLabel:UILabel;

	/** Drawer width as a fraction of the screen (clamped to a sensible px range). **/
	public static inline var DRAWER_FRAC:Float = 0.42;

	public function new(title:String) {
		UITheme.applyMobilePreset();

		root = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		mainUI = new Sprite();
		root.content.addChild(mainUI);

		var barH:Float = UITheme.px(34);
		var pad:Float = UITheme.px(6);
		var btnH:Float = barH - pad * 2;

		var bar:UIPanel = new UIPanel(FlxG.width, barH, UISurface.PANEL);
		mainUI.addChild(bar);

		var x:Float = pad;
		function tool(label:String, w:Float, cb:Void->Void):UIButton {
			var b:UIButton = new UIButton(label, w, btnH, cb);
			b.fontSize = 13;
			b.x = x;
			b.y = pad;
			mainUI.addChild(b);
			x += w + pad;
			return b;
		}

		var navW:Float = UITheme.px(52);
		tool('Back', navW, function() if (onBack != null) onBack());
		playBtn = tool('Play', navW, function() if (onPlayPause != null) onPlayPause());
		tool('Undo', navW, function() if (onUndo != null) onUndo());
		tool('Redo', navW, function() if (onRedo != null) onRedo());

		// Panels toggle docks at the right edge.
		var panelsW:Float = UITheme.px(64);
		var panelsBtn:UIButton = new UIButton('Panels', panelsW, btnH, function() toggleDrawer());
		panelsBtn.fontSize = 13;
		panelsBtn.x = FlxG.width - panelsW - pad;
		panelsBtn.y = pad;
		mainUI.addChild(panelsBtn);

		statusLabel = new UILabel(title, 12, 0);
		statusLabel.x = x + pad;
		statusLabel.y = pad + UITheme.px(4);
		mainUI.addChild(statusLabel);

		// Drawer (right) holds the editor's settings; a scroll pane fills it.
		var drawerW:Float = Math.max(UITheme.px(220), Math.min(FlxG.width * DRAWER_FRAC, UITheme.px(340)));
		drawer = new UIDrawer(UIDrawerSide.RIGHT, drawerW);
		panel = new UIScrollPane(drawerW - UITheme.px(16), FlxG.height - UITheme.px(16));
		panel.x = UITheme.px(8);
		panel.y = UITheme.px(8);
		drawer.content.addChild(panel);
		drawer.attachEdge();

		field = FlxRect.get(0, barH, FlxG.width, FlxG.height - barH);
	}

	public function toggleDrawer():Void {
		if (drawer.isOpen)
			drawer.close();
		else
			drawer.open();
	}

	public function setPlaying(playing:Bool):Void {
		playBtn.label = playing ? 'Pause' : 'Play';
	}

	public function setStatus(text:String):Void {
		statusLabel.text = text;
	}

	public function dispose():Void {
		FlxSmidr.dispose();
		UITheme.clearMobilePreset();
		field.put();
	}
}
