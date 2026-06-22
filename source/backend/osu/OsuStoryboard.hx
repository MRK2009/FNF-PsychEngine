package backend.osu;

using StringTools;

class OsuSbCommand {
	public var event:String;
	public var easing:Int = 0;
	public var startTime:Float = 0;
	public var endTime:Float = 0;
	public var startVals:Array<Float> = [];
	public var endVals:Array<Float> = [];
	public var paramType:String = '';
	public var children:Array<OsuSbCommand> = [];
	public var loopCount:Int = 1;
	public var triggerType:String = '';

	public function new() {}

	public function loopLength():Float {
		var len:Float = 0;
		for (child in children) {
			var end:Float = (child.event == 'L') ? child.startTime + child.loopCount * child.loopLength() : child.endTime;
			if (end > len)
				len = end;
		}
		return len;
	}
}

class OsuSbObject {
	public var isAnimation:Bool = false;
	public var layer:String = 'Background';
	public var origin:String = 'Centre';
	public var path:String = '';
	public var x:Float = 0;
	public var y:Float = 0;

	public var frameCount:Int = 1;
	public var frameDelay:Float = 0;
	public var loopType:String = 'LoopForever'; // or LoopOnce

	public var commands:Array<OsuSbCommand> = [];

	public function new() {}

	public function timeBounds():{min:Float, max:Float} {
		var min:Float = Math.POSITIVE_INFINITY;
		var max:Float = Math.NEGATIVE_INFINITY;
		for (cmd in commands) {
			var end:Float = (cmd.event == 'L') ? cmd.startTime + cmd.loopCount * cmd.loopLength() : cmd.endTime;
			if (cmd.startTime < min)
				min = cmd.startTime;
			if (end > max)
				max = end;
		}
		if (min == Math.POSITIVE_INFINITY)
			return {min: 0, max: 0};
		return {min: min, max: max};
	}

	public function framePaths():Array<String> {
		if (!isAnimation)
			return [path];
		return [for (i in 0...frameCount) OsuStoryboard.frameName(path, i)];
	}
}

class OsuStoryboard {
	public var objects:Array<OsuSbObject> = [];

	public function new() {}

	public function isEmpty():Bool
		return objects.length < 1;

	public function imagePaths():Array<String> {
		var seen:Map<String, Bool> = new Map();
		var out:Array<String> = [];
		for (obj in objects)
			for (p in obj.framePaths())
				if (p.length > 0 && !seen.exists(p)) {
					seen.set(p, true);
					out.push(p);
				}
		return out;
	}

	public static function parse(text:String):OsuStoryboard {
		var sb:OsuStoryboard = new OsuStoryboard();
		if (text == null)
			return sb;

		var inEvents:Bool = false;
		var curObj:OsuSbObject = null;
		var curContainer:OsuSbCommand = null;

		for (rawLine in text.split('\n')) {
			var line:String = rawLine.replace('\r', '');
			if (line.trim().length < 1 || line.startsWith('//'))
				continue;

			if (line.startsWith('[') && line.endsWith(']')) {
				inEvents = (line == '[Events]');
				continue;
			}
			if (!inEvents)
				continue;

			var depth:Int = indentDepth(line);
			if (depth == 0) {
				curObj = parseObjectLine(line);
				curContainer = null;
				if (curObj != null)
					sb.objects.push(curObj);
				continue;
			}
			if (curObj == null)
				continue;

			var cmd:OsuSbCommand = parseCommandLine(line.substr(depth));
			if (cmd == null)
				continue;

			if (depth == 1) {
				curObj.commands.push(cmd);
				curContainer = (cmd.event == 'L' || cmd.event == 'T') ? cmd : null;
			} else if (curContainer != null) {
				curContainer.children.push(cmd);
			}
		}
		return sb;
	}

	public static function frameName(path:String, index:Int):String {
		var dot:Int = path.lastIndexOf('.');
		if (dot < 0)
			return path + index;
		return path.substring(0, dot) + index + path.substring(dot);
	}

	static function indentDepth(line:String):Int {
		var i:Int = 0;
		while (i < line.length) {
			var c:String = line.charAt(i);
			if (c == ' ' || c == '_')
				i++;
			else
				break;
		}
		return i;
	}

	static function parseObjectLine(line:String):OsuSbObject {
		var parts:Array<String> = line.split(',');
		if (parts.length < 6)
			return null;

		var kind:String = parts[0].trim();
		if (kind != 'Sprite' && kind != 'Animation')
			return null; // defer handling

		var obj:OsuSbObject = new OsuSbObject();
		obj.isAnimation = (kind == 'Animation');
		obj.layer = parts[1].trim();
		obj.origin = parts[2].trim();
		obj.path = stripQuotes(parts[3]);
		obj.x = parseFloatSafe(parts[4], 0);
		obj.y = parseFloatSafe(parts[5], 0);

		if (obj.isAnimation) {
			obj.frameCount = (parts.length > 6) ? parseIntSafe(parts[6], 1) : 1;
			obj.frameDelay = (parts.length > 7) ? parseFloatSafe(parts[7], 0) : 0;
			obj.loopType = (parts.length > 8) ? parts[8].trim() : 'LoopForever';
			if (obj.frameCount < 1)
				obj.frameCount = 1;
		}
		return obj;
	}

	static function parseCommandLine(body:String):OsuSbCommand {
		var parts:Array<String> = body.split(',');
		if (parts.length < 2)
			return null;

		var cmd:OsuSbCommand = new OsuSbCommand();
		cmd.event = parts[0].trim();

		if (cmd.event == 'L') {
			cmd.startTime = parseFloatSafe(parts[1], 0);
			cmd.loopCount = (parts.length > 2) ? parseIntSafe(parts[2], 1) : 1;
			return cmd;
		}

		if (cmd.event == 'T') {
			cmd.triggerType = parts[1].trim();
			cmd.startTime = (parts.length > 2) ? parseFloatSafe(parts[2], 0) : 0;
			cmd.endTime = (parts.length > 3) ? parseFloatSafe(parts[3], cmd.startTime) : cmd.startTime;
			return cmd;
		}

		if (parts.length < 4)
			return null;
		cmd.easing = parseIntSafe(parts[1], 0);
		cmd.startTime = parseFloatSafe(parts[2], 0);
		cmd.endTime = (parts[3].trim().length > 0) ? parseFloatSafe(parts[3], cmd.startTime) : cmd.startTime;

		if (cmd.event == 'P') {
			cmd.paramType = (parts.length > 4) ? parts[4].trim() : '';
			return cmd;
		}

		var arity:Int = arityOf(cmd.event);
		if (arity < 1)
			return cmd;

		var first:Int = 4;
		cmd.startVals = [
			for (i in 0...arity)
				(first + i < parts.length)
			?parseFloatSafe
			(parts[first + i], 0)
			:0];

		var hasEnd:Bool = parts.length > first + arity;
		cmd.endVals = [
			for (i in 0...arity)
				(hasEnd && first + arity + i < parts.length)
			?parseFloatSafe
			(parts[first + arity + i], cmd.startVals[i])
			:cmd.startVals[i]];
		return cmd;
	}

	static function arityOf(event:String):Int {
		return switch (event) {
			case 'F', 'S', 'R', 'MX', 'MY': 1;
			case 'M', 'V': 2;
			case 'C': 3;
			default: 0;
		}
	}

	static inline function stripQuotes(raw:String):String {
		var value:String = raw.trim();
		if (value.startsWith('"') && value.endsWith('"') && value.length >= 2)
			value = value.substring(1, value.length - 1);
		return value;
	}

	static inline function parseIntSafe(raw:String, fallback:Int):Int {
		var parsed:Null<Int> = Std.parseInt(raw.trim());
		return parsed == null ? fallback : parsed;
	}

	static inline function parseFloatSafe(raw:String, fallback:Float):Float {
		var parsed:Float = Std.parseFloat(raw.trim());
		return Math.isNaN(parsed) ? fallback : parsed;
	}
}
