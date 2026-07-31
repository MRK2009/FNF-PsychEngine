package scripting.lua;

import hxluajit.Types.Lua_State;
import scripting.hscript.HScript;
import haxe.DynamicAccess;
import hxluajit.Lua;
import hxluajit.wrapper.LuaConverter;
import hxluajit.wrapper.LuaFunction;

// Compatibility shim mirroring linc_luajit's `Convert` class.
//
// Most conversions delegate to hxluajit-wrapper's `LuaConverter`, but TWO cases
// are handled here instead of in the (vendored, gitignored) haxelib so the fix
// lives in the project:
//
//  - TFUNCTION: the haxelib returns a bare `LuaFunction` (only `.call()`), which
//    isn't invocable as a real Haxe function — so FlxTween ease/onComplete and
//    FlxTimer callbacks silently never fire. We wrap it with `Reflect.makeVarArgs`
//    so it can be handed to typed Haxe callback APIs.
//  - TFUNCTION stack balance: `luaL_ref` (inside the haxelib's fromLua) POPS the
//    value it stores. Our callers — `convertTable` below, the proxy's per-arg
//    unwrap, callFunctionWithoutName — expect the value to REMAIN at `idx` and pop
//    it themselves. Without a fix, a function-valued table entry (e.g.
//    `{ease=.., onComplete=..}`) pops the key out from under `lua_next` and the
//    table is silently TRUNCATED, dropping the callbacks. We duplicate the value
//    first so `luaL_ref` consumes the copy and the stack stays balanced.
//  - TTABLE: reimplemented here so its values are converted through THIS fromLua
//    (the corrected TFUNCTION path) rather than the haxelib's buggy recursion.
//  - TUSERDATA: routed through the `userdataToHaxe` hook (installed by LuaProxy) so a
//    table of object proxies unwraps its ELEMENTS to their live Haxe objects instead
//    of marshalling them to null (e.g. `cam.filters = {shaderFilter}`).
//  - Array / Map / anonymous structure: reimplemented so their ELEMENTS go through the
//    `haxeToLua` hook. The haxelib's own recursion marshals any class it doesn't
//    special-case to nil, so an `Array<NoteData>` reached Lua as a table of nils.
class Convert {
	/**
	 * Proxy-userdata unwrap, installed by `scripting.lua.LuaProxy`. `convertTable` runs every
	 * element through `fromLua`; when an element is an object proxy this returns the live
	 * Haxe object it wraps, so `{proxyA, proxyB}` becomes a real `Array` of those objects.
	 * Defaults to `rawUserdata` (plain `LuaConverter` marshalling) when no proxy bridge
	 * is active.
	 *
	 * A `cpp.Callable` (raw C function pointer), NOT a Haxe closure: `State` is a
	 * `cpp.RawPointer`, which hxcpp cannot box into `Dynamic`, so assigning a plain
	 * function here makes it emit a `_dyn()` wrapper it never declares ("no member named
	 * 'unwrapUserdata_dyn'" at C++ compile time, invisible to `haxe --no-output`).
	 */
	public static var userdataToHaxe:cpp.Callable<(L:cpp.RawPointer<Lua_State>, idx:Int) -> Dynamic> = cpp.Callable.fromStaticFunction(rawUserdata);

	static function rawUserdata(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic
		return LuaConverter.fromLua(L, idx);

	/**
	 * Container-ELEMENT push, installed by `scripting.lua.LuaProxy`. The container cases below run
	 * every element through this, so an `Array<NoteData>` becomes a real Lua table holding live
	 * object proxies rather than the nils `LuaConverter` produces for any class it does not
	 * special-case (its `toLua` has no proxy bridge and falls through to `pushnil`).
	 *
	 * That gap was not cosmetic: hook arguments are pushed through here, so `onNotesGenerated`
	 * handed Lua a table of nils while HScript got the live note list.
	 *
	 * Defaults to plain `LuaConverter` marshalling when no proxy bridge is active. A
	 * `cpp.Callable`, not a Haxe closure, for the same reason as `userdataToHaxe`.
	 */
	public static var haxeToLua:cpp.Callable<(L:cpp.RawPointer<Lua_State>, v:Dynamic) -> Void> = cpp.Callable.fromStaticFunction(rawToLua);

	static function rawToLua(L:cpp.RawPointer<Lua_State>, v:Dynamic):Void
		LuaConverter.toLua(L, v);

	/**
	 * The proxy state id owning `L`, installed by `scripting.lua.LuaProxy`. A wrapped Lua callback captures
	 * this at CONVERT time (while the state is alive) so it can later check the state is still open
	 * before dereferencing it -- see the TFUNCTION branch below. `0` means no proxy bridge is active,
	 * which disables the check (the callback behaves exactly as before).
	 *
	 * A `cpp.Callable`, not a Haxe closure, for the same reason as `userdataToHaxe`: `State` is a
	 * `cpp.RawPointer` and can't be boxed into `Dynamic`.
	 */
	public static var stateIdOf:cpp.Callable<(L:cpp.RawPointer<Lua_State>) -> Int> = cpp.Callable.fromStaticFunction(noStateId);

	static function noStateId(L:cpp.RawPointer<Lua_State>):Int
		return 0;

	/**
	 * Whether a proxy state is still open, installed by `scripting.lua.LuaProxy` (a plain `Int` closure, so
	 * it needs no `cpp.Callable`). A wrapped Lua callback consults this before touching its state; once
	 * the script's Lua state is closed this returns false and the callback no-ops instead of calling
	 * `lua_rawgeti` on freed memory (a native crash when a surviving `FlxTimer`/`FlxTween` fires after
	 * the script unloads). Defaults to "always alive" so non-proxy use is unchanged.
	 */
	public static var stateAlive:Int->Bool = function(sid:Int):Bool return true;

	// Guards `convertTable` against self-referential tables (`t.self = t`), which would otherwise
	// recurse until the native stack overflows. Depth-based rather than a visited set: Lua tables
	// have no cheap Haxe identity, and real script data never nests anywhere near this deep.
	static inline var MAX_TABLE_DEPTH:Int = 64;

	static var tableDepth:Int = 0;

	// Same guard, for the Haxe -> Lua direction: an object graph that contains itself would
	// otherwise recurse until the native stack overflows.
	static var pushDepth:Int = 0;

	/**
	 * Haxe value -> Lua value.
	 *
	 * Containers and anonymous structures are built here so their elements go through `haxeToLua`;
	 * everything else is left to the haxelib, which marshals it correctly.
	 *
	 * Classified with direct type tests, not `Type.typeof`: on hxcpp the latter CONSTRUCTS a
	 * `ValueType`, and its `TClass(c)` carries a parameter, so classifying a value allocated an
	 * enum instance just to be switched on. Each test below is a single type check.
	 */
	public static function toLua(L:cpp.RawPointer<Lua_State>, val:Dynamic):Void {
		if (val != null) {
			if ((val is Array)) {
				pushArray(L, val);
				return;
			}
			if ((val is haxe.Constraints.IMap)) {
				pushMap(L, val);
				return;
			}
			// What is left with no class of its own, once primitives, strings, enums and functions
			// are excluded, is an anonymous structure.
			if (!(val is String)
				&& !(val is Float) // covers Int
				&& !(val is Bool)
				&& !Reflect.isFunction(val)
				&& !Reflect.isEnumValue(val)
				&& Type.getClass(val) == null) {
				pushAnon(L, val);
				return;
			}
		}
		LuaConverter.toLua(L, val);
	}

	static function pushArray(L:cpp.RawPointer<Lua_State>, arr:Array<Dynamic>):Void {
		if (pushDepth >= MAX_TABLE_DEPTH) {
			Lua.pushnil(L);
			return;
		}
		pushDepth++;

		final len:Int = arr.length;
		Lua.createtable(L, len, 0);
		try {
			for (i in 0...len) {
				Lua.pushinteger(L, i + 1); // Lua is 1-based
				haxeToLua(L, arr[i]);
				Lua.settable(L, -3);
			}
		} catch (e:Dynamic) {
			pushDepth--;
			throw e;
		}
		pushDepth--;
	}

	static function pushMap(L:cpp.RawPointer<Lua_State>, map:haxe.Constraints.IMap<Dynamic, Dynamic>):Void {
		if (pushDepth >= MAX_TABLE_DEPTH) {
			Lua.pushnil(L);
			return;
		}
		pushDepth++;

		Lua.createtable(L, 0, 0);
		try {
			for (key in map.keys()) {
				pushKey(L, key);
				haxeToLua(L, map.get(key));
				Lua.settable(L, -3);
			}
		} catch (e:Dynamic) {
			pushDepth--;
			throw e;
		}
		pushDepth--;
	}

	static function pushAnon(L:cpp.RawPointer<Lua_State>, v:Dynamic):Void {
		if (pushDepth >= MAX_TABLE_DEPTH) {
			Lua.pushnil(L);
			return;
		}
		pushDepth++;

		final fields:Array<String> = Reflect.fields(v);
		Lua.createtable(L, 0, fields.length);
		try {
			for (field in fields) {
				Lua.pushstring(L, field);
				haxeToLua(L, Reflect.field(v, field));
				Lua.settable(L, -3);
			}
		} catch (e:Dynamic) {
			pushDepth--;
			throw e;
		}
		pushDepth--;
	}

	/**
	 * A Haxe map key as a Lua table key. `IntMap` keys have to stay NUMBERS: the haxelib pushed
	 * every key with `lua_pushstring` after casting the map to `Map<String, Dynamic>`, so an
	 * `IntMap` produced garbage keys.
	 */
	static inline function pushKey(L:cpp.RawPointer<Lua_State>, key:Dynamic):Void {
		if ((key is Int))
			Lua.pushinteger(L, (key : Int));
		else if ((key is Float))
			Lua.pushnumber(L, (key : Float));
		else
			Lua.pushstring(L, Std.string(key));
	}

	public static function fromLua(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		return switch (Lua.type(L, idx)) {
			case t if (t == Lua.TFUNCTION):
				// Duplicate so the haxelib's luaL_ref pops the COPY, leaving the
				// original at `idx` for our caller. fromLua on the copy returns the
				// bare LuaFunction; wrap it as a real callable Haxe function.
				Lua.pushvalue(L, idx);
				final fn:LuaFunction = LuaConverter.fromLua(L, -1);
				// Capture the owning state now (it is alive); the callback checks it is still open
				// before invoking, so a tween/timer that outlives the script can't call into a freed state.
				final sid:Int = stateIdOf(L);
				Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
					if (sid > 0 && !stateAlive(sid))
						return null;
					final res:Array<Dynamic> = fn.call(args);
					return (res != null && res.length > 0) ? res[0] : null;
				});
			case t if (t == Lua.TTABLE):
				convertTable(L, idx);
			case t if (t == Lua.TUSERDATA):
				userdataToHaxe(L, idx);
			default:
				LuaConverter.fromLua(L, idx);
		}
	}

	// String-keyed (or sparse/negative-indexed) tables -> anonymous DynamicAccess;
	// 1..n integer-keyed tables -> Array. Mirrors hxluajit's convertTable but routes
	// value conversion through our fromLua so callbacks survive.
	static function convertTable(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		// A table that contains itself (`t.self = t`) would recurse forever; bail past the depth cap.
		if (tableDepth >= MAX_TABLE_DEPTH)
			return {};
		tableDepth++;
		// Decrement even if an element conversion throws, so a single bad table can't leave the counter
		// stuck high and quietly truncate every table converted afterwards.
		var result:Dynamic;
		try {
			result = convertTableInner(L, idx);
		} catch (e:Dynamic) {
			tableDepth--;
			throw e;
		}
		tableDepth--;
		return result;
	}

	static function convertTableInner(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		var isArray:Bool = true;
		var count:Int = 0;
		iterate(L, idx, function():Void {
			if (isArray) {
				if (Lua.type(L, -2) == Lua.TNUMBER) {
					if (Lua.tointeger(L, -2) < 0) isArray = false;
				} else
					isArray = false;
			}
			count++;
		});

		if (count == 0)
			return {};

		if (isArray) {
			final arr:Array<Dynamic> = [];
			iterate(L, idx, function():Void {
				arr[Lua.tointeger(L, -2) - 1] = fromLua(L, -1);
			});
			return arr;
		}

		final obj:DynamicAccess<Dynamic> = {};
		iterate(L, idx, function():Void {
			obj.set(Std.string(fromLua(L, -2)), fromLua(L, -1));
		});
		return obj;
	}

	// Walk a table leaving [key, value] on the stack for `fn`, popping the value
	// after each step (the key stays for the next lua_next).
	static function iterate(L:cpp.RawPointer<Lua_State>, idx:Int, fn:Void->Void):Void {
		Lua.pushnil(L);
		while (Lua.next(L, idx < 0 ? idx - 1 : idx) != 0) {
			fn();
			Lua.pop(L, 1);
		}
	}
}
