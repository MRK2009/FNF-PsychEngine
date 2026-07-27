package psychlua;

import backend.MusicBeatState;

/**
	Resolving a member of an object, in one place.

	Two APIs reached engine objects and disagreed about what a member is. The classic stringly-typed
	family (`getProperty('boyfriend.x')`, `setPropertyFromClass`, `getPropertyFromGroup`, ...) walked
	paths through `LuaUtils`, while the direct proxy (`game.boyfriend.x`) resolved keys at the Lua
	metatable boundary in `LuaProxy`. They differed on map access, on whether a method could be
	shadowed by an entry, and each carried its own copy of the walk. A fix or an optimisation landed
	on one and not the other.

	This is the single answer to "what does `obj.key` mean", used by both. `LuaProxy` keeps its
	metatable fast path -- per-key classification cached in the proxy's env table, which cannot be
	expressed in Haxe -- but resolves through here when that cache misses, so the two agree.

	### Map access

	Reflection wins, and map CONTENT is a fallback for a key that is not a real field. That is the
	proxy's rule, and it is the correct one: it can never shadow `get`/`set`/`exists`/`keys` with an
	entry of the same name. The classic `allowMaps` flag is therefore no longer needed to read or
	write entries -- it is still accepted so no script signature changes, but map content is now
	reachable either way.
**/
class PropertyPath {
	/**
		Resolves the object a path starts from.

		@param name The first segment: `this`/`game`/`instance`, a script variable, or a field of
		            the active state.
		@return The object, or null.
	**/
	public static function root(name:String, allowMaps:Bool = false):Dynamic {
		switch (name) {
			case 'this' | 'instance' | 'game':
				return PlayState.instance;

			default:
				var obj:Dynamic = MusicBeatState.getVariables().get(name);
				if (obj == null)
					// `get`, not `member`: a root segment can still be indexed (`myArray[2].x`).
					obj = get(LuaUtils.getTargetInstance(), name, allowMaps);
				return obj;
		}
	}

	/**
		Reads one member of one object. The core both APIs share.

		@param instance The object to read from.
		@param key A plain member name, no dots or brackets.
		@return The value, or null when there is no such member.
	**/
	public static function member(instance:Dynamic, key:String, allowMaps:Bool = false):Dynamic {
		if (instance == null || key == null)
			return null;

		// Ordered for the hot path: a proxied sprite fails the type check and returns on the single
		// reflection call. The fallbacks only run where the answer would have been null anyway.
		if ((instance is MusicBeatState) && MusicBeatState.getVariables().exists(key)) {
			var stored:Dynamic = MusicBeatState.getVariables().get(key);
			if (stored != null)
				return stored;
		}

		var value:Dynamic = Reflect.getProperty(instance, key);
		if (value != null)
			return value;

		// `x.members[i]` on a plain array (playerReceptors and friends have no `members` group).
		if (key == 'members' && (instance is Array))
			return instance;

		return mapEntry(instance, key);
	}

	/**
		Writes one member of one object. The core both APIs share.

		@param instance The object to write to.
		@param key A plain member name, no dots or brackets.
		@param value What to store.
		@return `value`.
	**/
	public static function setMember(instance:Dynamic, key:String, value:Dynamic, allowMaps:Bool = false):Dynamic {
		if (instance == null || key == null)
			return value;

		// A Map's entries are its content; it has no script-settable fields, so a write is a `set`.
		var map:haxe.Constraints.IMap<Dynamic, Dynamic> = asMap(instance);
		if (map != null) {
			map.set(key, value);
			return value;
		}

		if ((instance is MusicBeatState) && MusicBeatState.getVariables().exists(key)) {
			MusicBeatState.getVariables().set(key, value);
			return value;
		}

		Reflect.setProperty(instance, key, value);
		return value;
	}

	/**
		Reads `path` relative to `instance`, walking dots and `[...]` brackets in one pass.

		@param instance The object the path is relative to.
		@param path e.g. `x`, `boyfriend.x`, `members[2].alpha`.
		@return The value, or null if any step of the path is missing.
	**/
	public static function get(instance:Dynamic, path:String, allowMaps:Bool = false):Dynamic {
		if (path == null)
			return null;

		if (path.indexOf('.') < 0 && path.indexOf('[') < 0)
			return member(instance, path, allowMaps);

		var target:Dynamic = instance;
		var segments:Array<String> = path.split('.');
		for (segment in segments) {
			if (target == null)
				return null;
			target = step(target, segment, allowMaps);
		}
		return target;
	}

	/**
		Writes `value` at `path` relative to `instance`.

		@param instance The object the path is relative to.
		@param path e.g. `x`, `boyfriend.x`, `members[2].alpha`.
		@return `value`.
	**/
	public static function set(instance:Dynamic, path:String, value:Dynamic, allowMaps:Bool = false):Dynamic {
		if (path == null)
			return value;

		if (path.indexOf('.') < 0 && path.indexOf('[') < 0)
			return setMember(instance, path, value, allowMaps);

		var target:Dynamic = instance;
		var segments:Array<String> = path.split('.');
		var last:Int = segments.length - 1;
		for (i in 0...last) {
			if (target == null)
				return value;
			target = step(target, segments[i], allowMaps);
		}
		if (target == null)
			return value;

		return setStep(target, segments[last], value, allowMaps);
	}

	/**
		One dot-free segment, which may still carry `[...]` indexes: `members[2]`, `grid[1][3]`.
	**/
	static function step(instance:Dynamic, segment:String, allowMaps:Bool):Dynamic {
		if (segment.indexOf('[') < 0)
			return member(instance, segment, allowMaps);

		var parts:Array<String> = segment.split('[');
		var target:Dynamic = member(instance, parts[0], allowMaps);
		for (i in 1...parts.length) {
			if (target == null)
				return null;
			target = index(target, parts[i]);
		}
		return target;
	}

	/** `step`, but assigning at the final index. **/
	static function setStep(instance:Dynamic, segment:String, value:Dynamic, allowMaps:Bool):Dynamic {
		if (segment.indexOf('[') < 0)
			return setMember(instance, segment, value, allowMaps);

		var parts:Array<String> = segment.split('[');
		var target:Dynamic = member(instance, parts[0], allowMaps);
		var last:Int = parts.length - 1;
		for (i in 1...last) {
			if (target == null)
				return value;
			target = index(target, parts[i]);
		}
		if (target == null)
			return value;

		target[indexKey(target, parts[last])] = value;
		return value;
	}

	static inline function index(target:Dynamic, raw:String):Dynamic
		return target[indexKey(target, raw)];

	/**
		The key inside a `[...]`, as an Int for arrays.

		A String key against a Haxe array goes through `Reflect.getProperty` and silently returns
		something unrelated, so a numeric bracket on an array has to be parsed.
	**/
	static inline function indexKey(target:Dynamic, raw:String):Dynamic {
		var key:String = (raw.length > 0 && raw.charAt(raw.length - 1) == ']') ? raw.substr(0, raw.length - 1) : raw;
		var idx:Null<Int> = Std.parseInt(key);
		return (idx != null && (target is Array)) ? (idx : Dynamic) : key;
	}

	static inline function asMap(obj:Dynamic):haxe.Constraints.IMap<Dynamic, Dynamic>
		return (obj is haxe.Constraints.IMap) ? cast obj : null;

	static inline function mapEntry(instance:Dynamic, key:String):Dynamic {
		var map:haxe.Constraints.IMap<Dynamic, Dynamic> = asMap(instance);
		return (map == null) ? null : map.get(key);
	}
}
