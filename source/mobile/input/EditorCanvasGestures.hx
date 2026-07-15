package mobile.input;

import flixel.FlxG;
import flixel.math.FlxRect;
import smidr.input.UIPointer;

/**
 * Touch gesture controller for a mobile editor's Flixel canvas (chart notefield, stage, character).
 *
 * Polled once per frame with the editor's game-space viewport rect; it recognizes one-finger pan
 * (with fling momentum), two-finger pinch-zoom, tap and long-press, and reports each through a
 * callback so the editor can drive its own canvas (scroll / zoom / place / delete). Gestures that
 * begin over a SmidrUI widget or outside the viewport are ignored, so the toolbar/drawer keep their
 * own input.
 *
 * On desktop the mouse stands in for a single finger (pan/tap/long-press) and the wheel drives zoom,
 * so the mobile editors are testable in a Windows build. Multi-touch pinch is mobile-only.
 */
class EditorCanvasGestures {
	/** Canvas area, in game (view) pixels; gestures outside it are ignored. Update when the layout changes. **/
	public var viewport:FlxRect;

	public var enabled:Bool = true;

	/** Drag delta in game px since the last frame (also fed by fling momentum). **/
	public var onPan:Float->Float->Void = null;

	/** Pinch scale factor (>1 zoom in) about the focal point (game px). **/
	public var onZoom:Float->Float->Float->Void = null;

	/** A tap at (x, y) in game px. **/
	public var onTap:Float->Float->Void = null;

	/** A long-press at (x, y) in game px. **/
	public var onLongPress:Float->Float->Void = null;

	/** Called on press-down at (x, y); return `true` to claim the press as an object DRAG (routed to
		`onDragMove`/`onDragEnd`) instead of the pan/tap/long-press flow -- e.g. the finger landed on a
		note. `null` (or returning `false`) keeps the normal canvas behavior. **/
	public var onDragStart:Float->Float->Bool = null;

	/** While a claimed drag is in progress: delta since last frame + absolute pos, all in game px. **/
	public var onDragMove:Float->Float->Float->Float->Void = null;

	/** A claimed drag released. **/
	public var onDragEnd:Void->Void = null;

	// Tuning (seconds / px).
	public var tapMaxMovePx:Float = 14;
	public var tapMaxSec:Float = 0.3;
	public var longPressSec:Float = 0.45;
	public var flingEnabled:Bool = true;
	public var wheelZoomStep:Float = 0.12; // desktop wheel -> zoom factor per notch

	var active:Bool = false; // a one-finger gesture is in progress
	var dragging:Bool = false; // the active gesture is a claimed object drag (onDragStart returned true)
	var pinching:Bool = false;
	var suppressUntilRelease:Bool = false; // set after a pinch so a lingering finger doesn't tap/pan
	var startX:Float = 0;
	var startY:Float = 0;
	var lastX:Float = 0;
	var lastY:Float = 0;
	var heldSec:Float = 0;
	var moved:Bool = false;
	var longFired:Bool = false;
	var lastPinchDist:Float = 0;

	var velX:Float = 0;
	var velY:Float = 0;
	var flinging:Bool = false;

	public function new(viewport:FlxRect) {
		this.viewport = viewport;
	}

	/** Call once per frame from the editor's `update`. **/
	public function update(elapsed:Float):Void {
		if (!enabled) {
			reset();
			return;
		}

		#if !mobile
		if (onZoom != null && FlxG.mouse.wheel != 0 && inViewport(FlxG.mouse.viewX, FlxG.mouse.viewY) && !UIPointer.overUI)
			onZoom(1 + FlxG.mouse.wheel * wheelZoomStep, FlxG.mouse.viewX, FlxG.mouse.viewY);
		#end

		var count:Int = pointerCount();
		if (count >= 2) {
			handlePinch();
			return;
		}
		pinching = false;

		if (count == 1)
			handleSingle(pointerX(0), pointerY(0), elapsed);
		else
			handleRelease(elapsed);
	}

	function handleSingle(x:Float, y:Float, elapsed:Float):Void {
		if (!active) {
			if (suppressUntilRelease || !inViewport(x, y) || UIPointer.downOnUI || UIPointer.overUI) {
				// Started on the toolbar/drawer or off-canvas -- ignore the whole gesture.
				suppressUntilRelease = true;
				return;
			}
			active = true;
			moved = false;
			longFired = false;
			heldSec = 0;
			startX = lastX = x;
			startY = lastY = y;
			stopFling();
			// Let the owner claim this press as an object drag (finger on a note); else it's a normal gesture.
			dragging = (onDragStart != null && onDragStart(x, y));
			return;
		}
		if (suppressUntilRelease)
			return;

		var dx:Float = x - lastX;
		var dy:Float = y - lastY;
		lastX = x;
		lastY = y;
		heldSec += elapsed;

		if (dragging) {
			if (onDragMove != null)
				onDragMove(dx, dy, x, y);
			return;
		}

		if (!moved && (Math.abs(x - startX) > tapMaxMovePx || Math.abs(y - startY) > tapMaxMovePx))
			moved = true;

		if (moved) {
			if (onPan != null)
				onPan(dx, dy);
			if (elapsed > 0) {
				velX = dx / elapsed;
				velY = dy / elapsed;
			}
		} else if (!longFired && heldSec >= longPressSec) {
			longFired = true;
			if (onLongPress != null)
				onLongPress(startX, startY);
			haptic();
		}
	}

	function handleRelease(elapsed:Float):Void {
		if (active && !suppressUntilRelease) {
			if (dragging) {
				if (onDragEnd != null)
					onDragEnd();
			} else if (!moved && !longFired && heldSec <= tapMaxSec) {
				if (onTap != null)
					onTap(startX, startY);
			} else if (moved && flingEnabled && (Math.abs(velX) > 40 || Math.abs(velY) > 40)) {
				flinging = true;
			}
		}
		active = false;
		dragging = false;
		suppressUntilRelease = false;
		updateFling(elapsed);
	}

	function handlePinch():Void {
		// Two fingers down: cancel any single-finger gesture and suppress it until full release so a
		// lingering finger after the pinch doesn't tap or jump the pan.
		if (dragging && onDragEnd != null)
			onDragEnd();
		active = false;
		dragging = false;
		suppressUntilRelease = true;
		stopFling();

		var ax:Float = pointerX(0), ay:Float = pointerY(0);
		var bx:Float = pointerX(1), by:Float = pointerY(1);
		var dist:Float = Math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
		var focalX:Float = (ax + bx) * 0.5;
		var focalY:Float = (ay + by) * 0.5;

		if (!pinching || lastPinchDist <= 0) {
			pinching = true;
			lastPinchDist = dist;
			return;
		}
		if (dist > 0 && onZoom != null && inViewport(focalX, focalY))
			onZoom(dist / lastPinchDist, focalX, focalY);
		lastPinchDist = dist;
	}

	function updateFling(elapsed:Float):Void {
		if (!flinging)
			return;
		if (onPan != null)
			onPan(velX * elapsed, velY * elapsed);
		var decay:Float = Math.exp(-elapsed * 4.5);
		velX *= decay;
		velY *= decay;
		if (Math.abs(velX) < 20 && Math.abs(velY) < 20)
			stopFling();
	}

	inline function stopFling():Void {
		flinging = false;
		velX = velY = 0;
	}

	inline function inViewport(x:Float, y:Float):Bool {
		return viewport == null || viewport.containsXY(x, y);
	}

	function haptic():Void {
		#if android
		if (ClientPrefs.data.vibration)
			try extension.haptics.Haptic.vibrateOneShot(0.03, 1, 0.4) catch (_:Dynamic) {}
		#end
	}

	function reset():Void {
		active = pinching = dragging = suppressUntilRelease = false;
		stopFling();
	}

	// ---- Unified pointer source: touches on mobile, the mouse on desktop ----

	inline function pointerCount():Int {
		#if mobile
		var n:Int = 0;
		for (t in FlxG.touches.list)
			if (t.pressed)
				n++;
		return n;
		#else
		return FlxG.mouse.pressed ? 1 : 0;
		#end
	}

	inline function pointerX(index:Int):Float {
		#if mobile
		return pressedTouch(index).viewX;
		#else
		return FlxG.mouse.viewX;
		#end
	}

	inline function pointerY(index:Int):Float {
		#if mobile
		return pressedTouch(index).viewY;
		#else
		return FlxG.mouse.viewY;
		#end
	}

	#if mobile
	function pressedTouch(index:Int):flixel.input.touch.FlxTouch {
		var i:Int = 0;
		for (t in FlxG.touches.list) {
			if (!t.pressed)
				continue;
			if (i == index)
				return t;
			i++;
		}
		return FlxG.touches.list[0];
	}
	#end
}
