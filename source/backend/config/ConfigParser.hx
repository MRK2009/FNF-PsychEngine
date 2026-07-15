package backend.config;

/**
 * Parses a note-skin config string into an anonymous-object/array/scalar `Dynamic` tree so callers
 * can keep using `Reflect.field`/direct access. The tabbed `.tcfg` format is primary; plain JSON
 * (via tjson) is the secondary fallback. Both emit real Bool/Int/Float/String scalars, matching
 * engine checks like `cfg.rotate != false`.
 */
class ConfigParser {
	// `kind` selects the tcfg schema: 'note' (note skins, default) or 'ui' (UI/judgement skins). JSON is
	// schema-agnostic (the consumer reads its own fields), so `kind` only affects the .tcfg branch.
	public static function parse(ext:String, text:String, kind:String = 'note'):Dynamic {
		if (text == null)
			return null;
		try {
			return switch ((ext == null ? '' : ext).toLowerCase()) {
				case 'tcfg':
					(kind == 'ui') ? UiTcfgParser.parse(text) : TcfgParser.parse(text);
				default: // json (and any unknown extension) -> tolerant JSON
					CoolUtil.parseJson(text);
			}
		} catch (e:Dynamic) {
			FlxG.log.error('ConfigParser: failed to parse .$ext config -- $e');
			return null;
		}
	}
}
