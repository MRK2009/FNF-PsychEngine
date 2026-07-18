package mobile.input;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import openfl.display.Sprite;
import mobile.objects.SmidrTouchButton;

/**
 * On-screen virtual gamepad for menu navigation, rendered with SmidrUI-styled buttons. A d-pad
 * (bottom-left) and action buttons (bottom-right) whose press state is OR-ed into `backend.Controls`
 * so every existing `controls.UI_UP` / `ACCEPT` / `BACK` check keeps working untouched.
 *
 * The buttons are OpenFL display objects hosted on a self-managed overlay above the game (not on a
 * Flixel camera), so they get the SmidrUI look. Their press state is driven HERE from `FlxG.touches`
 * -- true multitouch, and independent of SmidrUI's single-pointer input -- projected through a
 * scroll-0 reference camera so hit-testing matches the pad's screen-space layout. The pad itself is a
 * `FlxBasic` (added to the state) purely so its `update` ticks each frame.
 *
 * Only one pad is "active" at a time: each MusicBeatState/Substate re-asserts `TouchPad.current` at
 * the top of its update(), so the topmost updating state owns input and states without a pad clear it
 * (current = null). The current pad's overlay is the only one shown (see `set_current`).
 */
class TouchPad extends FlxBasic {
	/** The pad belonging to the state/substate currently updating (null if none). */
	public static var current(default, set):TouchPad = null;

	static function set_current(value:TouchPad):TouchPad {
		if (current == value)
			return value;
		if (current != null && current.overlay != null)
			current.overlay.visible = false;
		current = value;
		if (value != null && value.overlay != null)
			value.overlay.visible = true;
		return value;
	}

	/**
	 * Maps an engine control name (see backend/Controls keyboardBinds) to a button tag. ui and note
	 * directions share the d-pad; accept/back use the action pads.
	 */
	public static final controlToTag:Map<String, String> = [
		'ui_up' => 'UP', 'ui_down' => 'DOWN', 'ui_left' => 'LEFT', 'ui_right' => 'RIGHT',
		'note_up' => 'UP', 'note_down' => 'DOWN', 'note_left' => 'LEFT', 'note_right' => 'RIGHT',
		'accept' => 'A', 'back' => 'B', 'pause' => 'B', 'reset' => 'C'
	];

	public var buttons:Map<String, SmidrTouchButton> = new Map();

	/** The screen-space (game-unit) rect of each button, for touch hit-testing. */
	final rects:Map<String, FlxRect> = new Map();

	final overlay:Sprite;
	final projCam:FlxCamera;
	final dpadMode:String;
	final actionMode:String;

	final btnSize:Float = 130;
	static final _pt:FlxPoint = FlxPoint.get();

	/**
	 * @param dpadMode ∈ FULL/UP_DOWN/LEFT_RIGHT/UP_LEFT_RIGHT/NONE
	 * @param actionMode ∈ A_B/A_B_C/A/B/NONE
	 * @param projCam a scroll-0, zoom-1 reference camera used to project touches into pad space
	 */
	public function new(dpadMode:String = 'FULL', actionMode:String = 'A_B', projCam:FlxCamera) {
		super();
		this.dpadMode = dpadMode;
		this.actionMode = actionMode;
		this.projCam = projCam;

		overlay = new Sprite();
		overlay.mouseEnabled = false;
		overlay.mouseChildren = false;
		overlay.visible = false;

		layout();

		FlxG.addChildBelowMouse(overlay);
		syncViewport();
		FlxG.signals.gameResized.add(onResized);
		FlxG.cameras.cameraAdded.add(onCameraAdded);
	}

	/** (Re)builds every button at its screen position for the current game size. */
	function layout():Void {
		for (btn in buttons)
			if (btn.parent == overlay)
				overlay.removeChild(btn);
		buttons.clear();
		for (r in rects)
			r.put();
		rects.clear();

		buildDpad(dpadMode);
		buildActions(actionMode);
	}

	function buildDpad(mode:String):Void {
		final pad:Float = 20;
		final baseX:Float = pad;
		final baseY:Float = FlxG.height - pad - btnSize * 2;

		switch (mode.toUpperCase()) {
			case 'UP_DOWN':
				makeButton('UP', baseX, baseY, FlxColor.CYAN, '^');
				makeButton('DOWN', baseX, baseY + btnSize, FlxColor.PURPLE, 'v');
			case 'LEFT_RIGHT':
				makeButton('LEFT', baseX, baseY + btnSize, FlxColor.MAGENTA, '<');
				makeButton('RIGHT', baseX + btnSize, baseY + btnSize, FlxColor.RED, '>');
			case 'UP_LEFT_RIGHT':
				makeButton('UP', baseX + btnSize, baseY, FlxColor.CYAN, '^');
				makeButton('LEFT', baseX, baseY + btnSize, FlxColor.MAGENTA, '<');
				makeButton('RIGHT', baseX + btnSize * 2, baseY + btnSize, FlxColor.RED, '>');
			case 'NONE':
			// no d-pad
			default: // FULL diamond
				makeButton('UP', baseX + btnSize, baseY, FlxColor.CYAN, '^');
				makeButton('LEFT', baseX, baseY + btnSize, FlxColor.MAGENTA, '<');
				makeButton('RIGHT', baseX + btnSize * 2, baseY + btnSize, FlxColor.RED, '>');
				makeButton('DOWN', baseX + btnSize, baseY + btnSize, FlxColor.PURPLE, 'v');
		}
	}

	function buildActions(mode:String):Void {
		final pad:Float = 20;
		final aX:Float = FlxG.width - pad - btnSize;
		final baseY:Float = FlxG.height - pad - btnSize;

		switch (mode.toUpperCase()) {
			case 'NONE':
			case 'A':
				makeButton('A', aX, baseY, FlxColor.LIME, 'A');
			case 'B': // single button, used as pause in gameplay -- top-right, clear of the lanes
				makeButton('B', aX, pad, FlxColor.ORANGE, 'II');
			case 'A_B_C': // adds a third button for the 'reset' control
				makeButton('A', aX, baseY, FlxColor.LIME, 'A');
				makeButton('B', aX - (btnSize + pad), baseY, FlxColor.ORANGE, 'B');
				makeButton('C', aX - 2 * (btnSize + pad), baseY, FlxColor.CYAN, 'C');
			default: // A_B
				makeButton('A', aX, baseY, FlxColor.LIME, 'A');
				makeButton('B', aX - btnSize - pad, baseY, FlxColor.ORANGE, 'B');
		}
	}

	function makeButton(tag:String, x:Float, y:Float, tint:FlxColor, label:String):Void {
		final btn:SmidrTouchButton = new SmidrTouchButton(tag, label, btnSize, tint);
		btn.idleAlpha = ClientPrefs.data.controlsAlpha;
		btn.x = x;
		btn.y = y;
		overlay.addChild(btn);
		buttons.set(tag, btn);
		rects.set(tag, FlxRect.get(x, y, btnSize, btnSize));
	}

	/** Places the overlay over the Flixel game viewport (offset carried by FlxG.game; scale applied here). */
	function syncViewport():Void {
		final scale = FlxG.scaleMode.scale;
		overlay.x = 0;
		overlay.y = 0;
		overlay.scaleX = scale.x;
		overlay.scaleY = scale.y;
	}

	function onResized(_:Int, __:Int):Void {
		layout();
		syncViewport();
	}

	/** Keeps the overlay above the camera layers (Flixel inserts new cameras at the input container). */
	function onCameraAdded(_:FlxCamera):Void {
		if (overlay.parent != FlxG.game)
			return;
		@:privateAccess var inputIdx:Int = FlxG.game.getChildIndex(FlxG.game._inputContainer);
		if (FlxG.game.getChildIndex(overlay) < inputIdx - 1)
			FlxG.game.setChildIndex(overlay, inputIdx - 1);
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		for (tag => btn in buttons) {
			final r:FlxRect = rects.get(tag);
			var now:Bool = false;

			#if FLX_TOUCH
			for (touch in FlxG.touches.list) {
				if (!touch.pressed)
					continue;
				touch.getScreenPosition(projCam, _pt);
				if (r.containsPoint(_pt)) {
					now = true;
					break;
				}
			}
			#end
			#if FLX_MOUSE
			if (!now && FlxG.mouse.pressed) {
				FlxG.mouse.getScreenPosition(projCam, _pt);
				if (r.containsPoint(_pt))
					now = true;
			}
			#end

			btn.updatePressed(now);
		}
	}

	public inline function buttonPressed(tag:String):Bool
		return buttons.exists(tag) && buttons.get(tag).held;

	public inline function buttonJustPressed(tag:String):Bool
		return buttons.exists(tag) && buttons.get(tag).justPressed;

	public inline function buttonJustReleased(tag:String):Bool
		return buttons.exists(tag) && buttons.get(tag).justReleased;

	/**
	 * Whether the pointer currently sits over any pad button (projected the same way `update` hit-tests).
	 * Lets a state ignore a tap that landed on the pad -- e.g. Freeplay must not click-select the list row
	 * under the d-pad when the tap was meant for navigation.
	 */
	public function overlapsPointer():Bool {
		#if FLX_MOUSE
		FlxG.mouse.getScreenPosition(projCam, _pt);
		for (r in rects)
			if (r.containsPoint(_pt))
				return true;
		#end
		return false;
	}

	/**
	 * Re-baselines every button so a touch already held when this pad (re)gains focus does not read as
	 * a fresh press. Called when a state resumes from a closed substate: the finger may still be down on
	 * a button (e.g. Back) that the substate's pad handled, and the parent's pad must not fire it again.
	 */
	public function ignoreHeldTouches():Void
		for (btn in buttons)
			btn.ignoreHeld = true;

	override public function destroy():Void {
		if (current == this)
			current = null;

		FlxG.signals.gameResized.remove(onResized);
		FlxG.cameras.cameraAdded.remove(onCameraAdded);

		for (btn in buttons) {
			if (btn.parent == overlay)
				overlay.removeChild(btn);
			btn.disposeButton();
		}
		buttons.clear();
		for (r in rects)
			r.put();
		rects.clear();

		if (overlay.parent != null)
			overlay.parent.removeChild(overlay);

		super.destroy();
	}
}
