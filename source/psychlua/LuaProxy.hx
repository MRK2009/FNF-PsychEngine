#if LUA_ALLOWED
package psychlua;

import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;
import llua.Convert;

/**
 * "Real Lua" object bridge.
 *
 * PsychLua exposes the engine through hundreds of string-path callbacks because
 * Haxe objects can't normally cross into Lua (hxluajit-wrapper's LuaConverter
 * pushes `nil` for any class instance). This bridge instead pushes a live Haxe
 * object as a Lua **userdata + shared metatable**, so scripts can do
 * `game.boyfriend.x = 100`, `game:endSong()`, etc. -- the same direct access
 * HScript has.
 *
 * Mechanics mirror psychlua.CallbackHandler: metamethods are static
 * `Lua_CFunction`s registered into a metatable, and the userdata stores a small
 * integer handle into a global registry that owns the real Haxe object.
 */
class LuaProxy {
	// Registry names for the two shared metatables (stored in the Lua registry).
	static inline final INST_META:String = "hxproxy_instance";
	static inline final CLASS_META:String = "hxproxy_class";

	// handle -> Haxe object. The userdata only carries the handle, so the real
	// reference lives here (and is dropped by __gc when Lua collects the proxy).
	static var handleToObj:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	static var nextHandle:Int = 1;

	/** Registers the proxy metatables on a fresh Lua state (call once at setup). */
	public static function setup(L:cpp.RawPointer<Lua_State>):Void {
		if (LuaL.newmetatable(L, INST_META) == 1) {
			setMeta(L, "__index", cpp.Callable.fromStaticFunction(instanceIndex));
			setMeta(L, "__newindex", cpp.Callable.fromStaticFunction(instanceNewIndex));
			setMeta(L, "__tostring", cpp.Callable.fromStaticFunction(proxyToString));
			setMeta(L, "__gc", cpp.Callable.fromStaticFunction(proxyGc));
		}
		Lua.pop(L, 1);

		if (LuaL.newmetatable(L, CLASS_META) == 1) {
			setMeta(L, "__index", cpp.Callable.fromStaticFunction(classIndex));
			setMeta(L, "__call", cpp.Callable.fromStaticFunction(classCall));
			setMeta(L, "__tostring", cpp.Callable.fromStaticFunction(proxyToString));
			setMeta(L, "__gc", cpp.Callable.fromStaticFunction(proxyGc));
		}
		Lua.pop(L, 1);

		// import('package.Class') -> class proxy (statics + construction).
		Lua.pushcfunction(L, cpp.Callable.fromStaticFunction(luaImport));
		Lua.setglobal(L, "import");
	}

	// `import('flixel.FlxSprite')` -> class proxy, gated by ModSecurity so raw
	// Lua can't resolve blacklisted classes.
	static function luaImport(L:cpp.RawPointer<Lua_State>):Int {
		if (Lua.type(L, 1) != Lua.TSTRING) {
			Lua.pushnil(L);
			return 1;
		}
		var path:String = Lua.tostring(L, 1).toString();
		var cls:Dynamic = #if MODS_ALLOWED backend.ModSecurity.safeResolveClass(path) #else Type.resolveClass(path) #end;
		pushClass(L, cls);
		return 1;
	}

	static inline function setMeta(L:cpp.RawPointer<Lua_State>, name:String, fn:Lua_CFunction):Void {
		Lua.pushcfunction(L, fn);
		Lua.setfield(L, -2, name);
	}

	/** Pushes any Haxe value: primitives natively, class instances as proxies. */
	public static function pushHaxe(L:cpp.RawPointer<Lua_State>, v:Dynamic):Void {
		if (v == null) {
			Lua.pushnil(L);
			return;
		}
		if ((v is String)) {
			Lua.pushstring(L, (v : String));
			return;
		}
		switch (Type.typeof(v)) {
			case TInt:
				Lua.pushinteger(L, (v : Int));
			case TFloat:
				Lua.pushnumber(L, (v : Float));
			case TBool:
				Lua.pushboolean(L, v == true ? 1 : 0);
			case TClass(_):
				// Live engine object (FlxSprite, Array, Map, ...) -> instance proxy.
				pushObject(L, v, INST_META);
			default:
				// Anonymous structures / unknowns: copy as plain Lua data.
				Convert.toLua(L, v);
		}
	}

	/** Pushes a `Class<T>` as a class proxy (statics + `new`/construction). */
	public static inline function pushClass(L:cpp.RawPointer<Lua_State>, cls:Dynamic):Void {
		if (cls == null) Lua.pushnil(L);
		else pushObject(L, cls, CLASS_META);
	}

	static function pushObject(L:cpp.RawPointer<Lua_State>, obj:Dynamic, metaName:String):Void {
		var handle:Int = nextHandle++;
		handleToObj.set(handle, obj);

		var raw:cpp.RawPointer<cpp.Void> = Lua.newuserdata(L, cast 4);
		var ptr:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw);
		ptr[0] = handle;

		LuaL.getmetatable(L, metaName);
		Lua.setmetatable(L, -2);
	}

	/** Lua value -> Haxe, unwrapping our proxies back to the real object. */
	public static function unwrap(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		if (Lua.type(L, idx) == Lua.TUSERDATA && isProxy(L, idx))
			return handleToObj.get(readHandle(L, idx));
		return Convert.fromLua(L, idx);
	}

	static inline function readHandle(L:cpp.RawPointer<Lua_State>, idx:Int):Int {
		var raw:cpp.RawPointer<cpp.Void> = Lua.touserdata(L, idx);
		var ptr:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw);
		return ptr[0];
	}

	static inline function objAt(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		return handleToObj.get(readHandle(L, idx));
	}

	// True if the userdata at idx carries one of our proxy metatables.
	static function isProxy(L:cpp.RawPointer<Lua_State>, idx:Int):Bool {
		if (Lua.getmetatable(L, idx) == 0)
			return false; // no metatable; nothing pushed
		var match:Bool = false;
		LuaL.getmetatable(L, INST_META);
		if (Lua.rawequal(L, -1, -2) == 1) match = true;
		Lua.pop(L, 1);
		if (!match) {
			LuaL.getmetatable(L, CLASS_META);
			if (Lua.rawequal(L, -1, -2) == 1) match = true;
			Lua.pop(L, 1);
		}
		Lua.pop(L, 1); // the object's metatable
		return match;
	}

	static function instanceIndex(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		if (obj == null) {
			Lua.pushnil(L);
			return 1;
		}

		// Array/numeric indexing: obj[i] (0-based, like Haxe/HScript).
		if (Lua.type(L, 2) == Lua.TNUMBER && (obj is Array)) {
			var arr:Array<Dynamic> = obj;
			var i:Int = Lua.tointeger(L, 2);
			pushHaxe(L, (i >= 0 && i < arr.length) ? arr[i] : null);
			return 1;
		}

		var key:String = Lua.tostring(L, 2).toString();
		try {
			var f:Dynamic = Reflect.getProperty(obj, key);
			if (Reflect.isFunction(f)) {
				// Bound-method closure (upvalues: handle + method name).
				Lua.pushinteger(L, readHandle(L, 1));
				Lua.pushstring(L, key);
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCall), 2);
				return 1;
			}
			pushHaxe(L, f);
		} catch (e:Dynamic) {
			Lua.pushnil(L);
		}
		return 1;
	}

	static function instanceNewIndex(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		if (obj == null)
			return 0;

		if (Lua.type(L, 2) == Lua.TNUMBER && (obj is Array)) {
			var arr:Array<Dynamic> = obj;
			arr[Lua.tointeger(L, 2)] = unwrap(L, 3);
			return 0;
		}

		var key:String = Lua.tostring(L, 2).toString();
		try {
			Reflect.setProperty(obj, key, unwrap(L, 3));
		} catch (e:Dynamic) {
			LuaL.error(L, '%s', 'set "$key": ${Std.string(e)}');
		}
		return 0;
	}

	static function methodCall(L:cpp.RawPointer<Lua_State>):Int {
		var handle:Int = Lua.tointeger(L, Lua.upvalueindex(1));
		var key:String = Lua.tostring(L, Lua.upvalueindex(2)).toString();
		var obj:Dynamic = handleToObj.get(handle);
		if (obj == null)
			return 0;

		var nargs:Int = Lua.gettop(L);
		// Skip the implicit `self` when called with `:` (arg 1 is this proxy).
		var start:Int = 1;
		if (nargs >= 1 && Lua.type(L, 1) == Lua.TUSERDATA && isProxy(L, 1) && readHandle(L, 1) == handle)
			start = 2;

		var args:Array<Dynamic> = [];
		for (i in start...nargs + 1)
			args.push(unwrap(L, i));

		try {
			var ret:Dynamic = Reflect.callMethod(obj, Reflect.field(obj, key), args);
			if (ret != null) {
				pushHaxe(L, ret);
				return 1;
			}
		} catch (e:Dynamic) {
			LuaL.error(L, '%s', 'call "$key": ${Std.string(e)}');
		}
		return 0;
	}

	static function classIndex(L:cpp.RawPointer<Lua_State>):Int {
		var cls:Dynamic = objAt(L, 1);
		if (cls == null) {
			Lua.pushnil(L);
			return 1;
		}
		var key:String = Lua.tostring(L, 2).toString();
		if (key == "new") {
			Lua.pushinteger(L, readHandle(L, 1));
			Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(constructorCall), 1);
			return 1;
		}
		try {
			var f:Dynamic = Reflect.field(cls, key); // static field/method
			if (Reflect.isFunction(f)) {
				Lua.pushinteger(L, readHandle(L, 1));
				Lua.pushstring(L, key);
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCall), 2); // static method (callMethod ignores `this`)
				return 1;
			}
			pushHaxe(L, f);
		} catch (e:Dynamic) {
			Lua.pushnil(L);
		}
		return 1;
	}

	static function classCall(L:cpp.RawPointer<Lua_State>):Int {
		// `SomeClass(args...)` -> construct.
		var cls:Dynamic = objAt(L, 1);
		return construct(L, cls, 2);
	}

	static function constructorCall(L:cpp.RawPointer<Lua_State>):Int {
		// `SomeClass.new(args...)`.
		var cls:Dynamic = handleToObj.get(Lua.tointeger(L, Lua.upvalueindex(1)));
		return construct(L, cls, 1);
	}

	static function construct(L:cpp.RawPointer<Lua_State>, cls:Dynamic, start:Int):Int {
		if (cls == null) {
			Lua.pushnil(L);
			return 1;
		}
		var nargs:Int = Lua.gettop(L);
		var args:Array<Dynamic> = [];
		for (i in start...nargs + 1)
			args.push(unwrap(L, i));
		try {
			pushHaxe(L, Type.createInstance(cls, args));
		} catch (e:Dynamic) {
			LuaL.error(L, '%s', 'new: ${Std.string(e)}');
			return 0;
		}
		return 1;
	}

	static function proxyToString(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		Lua.pushstring(L, obj == null ? "null" : Std.string(obj));
		return 1;
	}

	static function proxyGc(L:cpp.RawPointer<Lua_State>):Int {
		handleToObj.remove(readHandle(L, 1));
		return 0;
	}
}
#end
