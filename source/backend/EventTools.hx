package backend;

using StringTools;

/**
	Value parsing for the built-in chart events.

	A chart event carries two strings, so anything with more than two settings packs them as a
	comma-separated list (`camHUD, true`). These helpers read one field out of such a list without
	allocating per lookup beyond the split itself, and every one of them takes a fallback, because a
	charter leaving a field blank is the normal case rather than an error.
**/
class EventTools {
	/**
		Splits a packed value into trimmed fields, dropping empty ones at the ends.
		@param value the raw event value
		@return the fields, or an empty array when there is nothing to read
	**/
	public static function fields(value:String):Array<String> {
		if (value == null)
			return [];

		var raw:Array<String> = value.split(',');
		var out:Array<String> = [];
		for (part in raw) {
			var t:String = part.trim();
			out.push(t);
		}
		while (out.length > 0 && out[out.length - 1].length < 1)
			out.pop();
		return out;
	}

	/** The `index`th field, or `fallback` when it is missing or blank. **/
	public static function str(parts:Array<String>, index:Int, fallback:String):String {
		if (index < 0 || index >= parts.length)
			return fallback;
		var v:String = parts[index];
		return v.length > 0 ? v : fallback;
	}

	/** The `index`th field as a number, or `fallback` when it is missing, blank or not a number. **/
	public static function num(parts:Array<String>, index:Int, fallback:Float):Float {
		if (index < 0 || index >= parts.length || parts[index].length < 1)
			return fallback;
		var v:Float = Std.parseFloat(parts[index]);
		return Math.isNaN(v) ? fallback : v;
	}

	/**
		The `index`th field as a boolean, or `fallback` when it is missing or blank.

		Only an explicit false-ish spelling reads as false, so a typo leans towards the field being
		set rather than silently off.
	**/
	public static function bool(parts:Array<String>, index:Int, fallback:Bool):Bool {
		if (index < 0 || index >= parts.length || parts[index].length < 1)
			return fallback;
		return switch (parts[index].toLowerCase()) {
			case 'false' | 'no' | '0' | 'off': false;
			case 'true' | 'yes' | '1' | 'on': true;
			default: fallback;
		}
	}

	/**
		Reads a colour from `parts` starting at `index`, accepting the three spellings a charter is
		likely to reach for:

		- `random`, one field
		- `RRGGBB` or `#RRGGBB` or `0xRRGGBB`, one field
		- `r, g, b` as three separate 0-255 fields

		@param parts the split value
		@param index where the colour starts
		@param fallback the colour to use when nothing parses
		@return the colour, and how many fields it consumed (so the caller can read what follows)
	**/
	public static function color(parts:Array<String>, index:Int, fallback:FlxColor):{color:FlxColor, used:Int} {
		var read = readColor(parts, index);
		if (read.used < 1)
			return {color: fallback, used: 0};
		if (read.rgb < 0)
			return {color: fallback, used: read.used};
		return {color: (read.rgb : FlxColor), used: read.used};
	}

	/**
		The decision half of `color`, kept free of any Flixel type so it can be exercised on its own.

		@return the 24-bit RGB value (or -1 when the fields were present but unreadable) and how many
		fields it consumed (0 when there was nothing there at all)
	**/
	public static function readColor(parts:Array<String>, index:Int):{rgb:Int, used:Int} {
		if (index < 0 || index >= parts.length || parts[index].length < 1)
			return {rgb: -1, used: 0};

		var first:String = parts[index];
		if (first.toLowerCase() == 'random')
			return {rgb: (FlxG.random.int(0, 255) << 16) | (FlxG.random.int(0, 255) << 8) | FlxG.random.int(0, 255), used: 1};

		// Three numeric fields in a row are an RGB triplet, tested BEFORE hex because a bare "255" is
		// also a valid hex string: reading `255, 255, 255, 1` as hex would silently give the wrong
		// colour and eat the wrong number of fields.
		if (index + 2 < parts.length) {
			var r:Null<Int> = int255(parts[index]);
			var g:Null<Int> = int255(parts[index + 1]);
			var b:Null<Int> = int255(parts[index + 2]);
			if (r != null && g != null && b != null)
				return {rgb: (r << 16) | (g << 8) | b, used: 3};
		}

		var hex:String = first;
		if (hex.startsWith('#'))
			hex = hex.substr(1);
		else if (hex.toLowerCase().startsWith('0x'))
			hex = hex.substr(2);

		if (hex.length != 6)
			return {rgb: -1, used: 1};
		for (i in 0...hex.length) {
			var c:Int = hex.charCodeAt(i);
			var isHexDigit:Bool = (c >= '0'.code && c <= '9'.code) || (c >= 'a'.code && c <= 'f'.code) || (c >= 'A'.code && c <= 'F'.code);
			if (!isHexDigit)
				return {rgb: -1, used: 1};
		}
		return {rgb: Std.parseInt('0x' + hex), used: 1};
	}

	/** A 0-255 channel, clamped, or null when the field is not a number at all. **/
	static function int255(field:String):Null<Int> {
		var v:Float = Std.parseFloat(field);
		if (Math.isNaN(v))
			return null;
		return v < 0 ? 0 : (v > 255 ? 255 : Std.int(v));
	}
}
