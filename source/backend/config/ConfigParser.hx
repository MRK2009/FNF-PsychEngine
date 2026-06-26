package backend.config;

/**
 * Parses a note-skin config string into an anonymous-object/array/scalar `Dynamic` tree so callers
 * can keep using `Reflect.field`/direct access. The tabbed `.tcfg` format is primary; plain JSON
 * (via tjson) is the secondary fallback. Both emit real Bool/Int/Float/String scalars, matching
 * engine checks like `cfg.rotate != false`.
 */
class ConfigParser {
	public static function parse(ext:String, text:String):Dynamic {
		if (text == null)
			return null;
		try {
			return switch ((ext == null ? '' : ext).toLowerCase()) {
				case 'tcfg':
					TcfgParser.parse(text);
				default: // json (and any unknown extension) -> tolerant JSON
					tjson.TJSON.parse(text);
			}
		} catch (e:Dynamic) {
			FlxG.log.error('ConfigParser: failed to parse .$ext config -- $e');
			return null;
		}
	}
}
