package states;

#if CRASH_HANDLER
import flixel.FlxObject;
import flixel.math.FlxPoint;
import states.MainMenuState;

using StringTools;

/**
	In-engine crash screen shown by `backend.CrashHandler` instead of hard-killing the process.

	Deliberately self-contained: it draws with plain Flixel primitives (coloured quads + bitmap
	text) and never touches mod assets, the transition system, or scripting, since any of those
	could be what just crashed. It gives the player a way to read the error, copy it, jump back
	to the menu, or quit, so one bad frame doesn't nuke the whole session.
**/
class CrashState extends flixel.FlxState {
	static inline var MARGIN:Int = 40;

	final report:String;
	final summary:String;

	var status:FlxText;
	var buttons:Array<CrashButton> = [];
	final point:FlxPoint = FlxPoint.get();

	public function new(report:String, summary:String) {
		super();
		this.report = report;
		this.summary = summary;
	}

	override public function create():Void {
		super.create();

		// Never pause the crash screen when focus is lost, and make sure the cursor is usable.
		FlxG.autoPause = false;
		#if !mobile
		FlxG.mouse.visible = true;
		#end

		final bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF1B1420);
		bg.scrollFactor.set();
		add(bg);

		final title:FlxText = new FlxText(MARGIN, 28, FlxG.width - MARGIN * 2, "The game crashed", 40);
		title.setFormat(null, 40, 0xFFFF5555, LEFT);
		add(title);

		final sub:FlxText = new FlxText(MARGIN, 78, FlxG.width - MARGIN * 2, "A report was saved. You can try to continue, or quit and send it in.", 16);
		sub.color = 0xFFBBB2C4;
		add(sub);

		// Trimmed report body. Keep it short enough to stay on screen without a real scroll view.
		final body:FlxText = new FlxText(MARGIN, 120, FlxG.width - MARGIN * 2, clampReport(report), 13);
		body.setFormat(null, 13, 0xFFE8E4EE, LEFT);
		body.color = 0xFFE8E4EE;
		add(body);

		buildButtons();

		status = new FlxText(MARGIN, FlxG.height - 34, FlxG.width - MARGIN * 2, "", 14);
		status.color = 0xFF8FE39A;
		add(status);
	}

	function buildButtons():Void {
		final y:Int = FlxG.height - 84;
		var x:Int = MARGIN;
		x = addButton(x, y, "Try to Continue", 0xFF3A6B3E, recover);
		x = addButton(x, y, "Send Issue", 0xFF3A4E6B, doSendIssue);
		x = addButton(x, y, "Copy Report", 0xFF4A3A6B, copyReport);
		#if desktop
		x = addButton(x, y, "Crash Folder", 0xFF4A3A6B, backend.CrashHandler.openCrashFolder);
		#end
		x = addButton(x, y, "Quit", 0xFF6B3A3A, quit);
	}

	function addButton(x:Int, y:Int, label:String, color:Int, onClick:Void->Void):Int {
		final btn:CrashButton = new CrashButton(x, y, label, color, onClick);
		buttons.push(btn);
		add(btn.bg);
		add(btn.label);
		return x + Std.int(btn.bg.width) + 12;
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		var px:Float = 0;
		var py:Float = 0;
		var down:Bool = false;
		var clicked:Bool = false;

		#if mobile
		for (touch in FlxG.touches.list) {
			px = touch.x;
			py = touch.y;
			down = touch.pressed;
			if (touch.justReleased)
				clicked = true;
			break;
		}
		#else
		px = FlxG.mouse.x;
		py = FlxG.mouse.y;
		down = FlxG.mouse.pressed;
		clicked = FlxG.mouse.justReleased;
		#end

		point.set(px, py);
		for (btn in buttons) {
			final over:Bool = btn.bg.overlapsPoint(point);
			btn.setHighlight(over, down);
			if (over && clicked)
				btn.click();
		}
	}

	function recover():Void {
		flixel.addons.transition.FlxTransitionableState.skipNextTransIn = true;
		flixel.addons.transition.FlxTransitionableState.skipNextTransOut = true;
		MusicBeatState.switchState(new MainMenuState());
	}

	function doSendIssue():Void {
		if (backend.CrashHandler.sendIssue())
			setStatus("Report sent. Thank you!");
		else
			setStatus("Issue reporting isn't wired up yet -- please copy the report and open the tracker.");
	}

	function copyReport():Void {
		try {
			lime.system.Clipboard.text = report;
			setStatus("Report copied to clipboard.");
		} catch (_:Dynamic) {
			setStatus("Couldn't access the clipboard.");
		}
	}

	function quit():Void {
		Sys.exit(0);
	}

	function setStatus(msg:String):Void {
		if (status != null)
			status.text = msg;
	}

	inline function clampReport(text:String):String {
		final maxLines:Int = 22;
		final lines:Array<String> = text.split("\n");
		if (lines.length <= maxLines)
			return text;
		return lines.slice(0, maxLines).join("\n") + "\n... (full report saved to crash/)";
	}

	override public function destroy():Void {
		point.put();
		super.destroy();
	}
}

/** A flat coloured button: a quad plus centred label, with a click callback. **/
private class CrashButton {
	public var bg:FlxSprite;
	public var label:FlxText;

	final onClick:Void->Void;
	final baseColor:Int;

	public function new(x:Int, y:Int, text:String, color:Int, onClick:Void->Void) {
		this.onClick = onClick;
		this.baseColor = color;

		label = new FlxText(0, 0, 0, text, 15);
		label.setFormat(null, 15, 0xFFFFFFFF, CENTER);

		final w:Int = Std.int(Math.max(120, label.width + 28));
		bg = new FlxSprite(x, y).makeGraphic(w, 40, color);
		bg.scrollFactor.set();

		label.fieldWidth = w;
		label.x = x;
		label.y = y + 10;
		label.scrollFactor.set();
	}

	public function setHighlight(over:Bool, down:Bool):Void {
		bg.color = over ? (down ? darken(baseColor, 0.7) : lighten(baseColor, 1.25)) : baseColor;
	}

	public function click():Void {
		if (onClick != null)
			onClick();
	}

	static inline function lighten(color:Int, f:Float):Int {
		final c:FlxColor = color;
		return FlxColor.fromRGB(clamp(c.red * f), clamp(c.green * f), clamp(c.blue * f), c.alpha);
	}

	static inline function darken(color:Int, f:Float):Int {
		return lighten(color, f);
	}

	static inline function clamp(v:Float):Int {
		return Std.int(Math.max(0, Math.min(255, v)));
	}
}
#end
