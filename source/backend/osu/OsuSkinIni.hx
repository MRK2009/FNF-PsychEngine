package backend.osu;

using StringTools;

/**
	A parsed osu! `skin.ini`. Only the parts the mania skin converter needs are kept: the `[General]`
	block (skin name/author) and EVERY `[Mania]` block (osu repeats `[Mania]` once per key count, so a
	plain section map would lose all but the last -- they're collected into a list here).

	Keys are matched case-insensitively (osu is lenient); values keep their original text. Lines starting
	with `//` are comments and dropped.
**/
class OsuSkinIni {
	/** `[General]` key -> value (lower-cased keys). **/
	public var general:Map<String, String> = new Map();

	/** One map per `[Mania]` block (lower-cased keys). **/
	public var mania:Array<Map<String, String>> = [];

	public function new() {}

	/** The `Name:` from `[General]`, else `null`. **/
	public function name():String
		return general.exists('name') ? general.get('name') : null;

	/**
		Parses skin.ini text.
		@param text the file contents
		@return the parsed skin
	**/
	public static function parse(text:String):OsuSkinIni {
		var out:OsuSkinIni = new OsuSkinIni();
		if (text == null)
			return out;

		var cur:Map<String, String> = null; // the section currently being filled
		var section:String = '';

		for (rawLine in text.split('\n')) {
			var line:String = rawLine.replace('\r', '').trim();
			if (line.length == 0 || line.startsWith('//'))
				continue;

			if (line.startsWith('[') && line.endsWith(']')) {
				section = line.substr(1, line.length - 2).trim().toLowerCase();
				if (section == 'general') {
					cur = out.general;
				} else if (section == 'mania') {
					cur = new Map();
					out.mania.push(cur);
				} else
					cur = null; // a section we don't care about (Colours, Fonts, ...)
				continue;
			}

			if (cur == null)
				continue;

			var idx:Int = line.indexOf(':');
			if (idx < 0)
				continue;
			var key:String = line.substr(0, idx).trim().toLowerCase();
			var value:String = line.substr(idx + 1).trim();
			// osu allows trailing `//` comments on value lines.
			var cmt:Int = value.indexOf('//');
			if (cmt >= 0)
				value = value.substr(0, cmt).trim();
			if (key.length > 0)
				cur.set(key, value);
		}
		return out;
	}
}
