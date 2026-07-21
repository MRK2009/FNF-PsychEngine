package llua;

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
class Convert {
	/**
	 * Proxy-userdata unwrap, installed by `psychlua.LuaProxy`. `convertTable` runs every
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
	public static var userdataToHaxe:cpp.Callable<(L:State, idx:Int) -> Dynamic> = cpp.Callable.fromStaticFunction(rawUserdata);

	static function rawUserdata(L:State, idx:Int):Dynamic
		return LuaConverter.fromLua(L, idx);

	public static inline function toLua(L:State, val:Dynamic):Void
		LuaConverter.toLua(L, val);

	public static function fromLua(L:State, idx:Int):Dynamic {
		return switch (Lua.type(L, idx)) {
			case t if (t == Lua.TFUNCTION):
				// Duplicate so the haxelib's luaL_ref pops the COPY, leaving the
				// original at `idx` for our caller. fromLua on the copy returns the
				// bare LuaFunction; wrap it as a real callable Haxe function.
				Lua.pushvalue(L, idx);
				final fn:LuaFunction = LuaConverter.fromLua(L, -1);
				Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
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
	static function convertTable(L:State, idx:Int):Dynamic {
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
	static function iterate(L:State, idx:Int, fn:Void->Void):Void {
		Lua.pushnil(L);
		while (Lua.next(L, idx < 0 ? idx - 1 : idx) != 0) {
			fn();
			Lua.pop(L, 1);
		}
	}
}
