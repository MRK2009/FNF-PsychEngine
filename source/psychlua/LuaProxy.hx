#if LUA_ALLOWED
package psychlua;

import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;
import llua.Convert;

/**
 * Per-Lua-state registry backing the object proxies. Keeps a two-way object map so
 * the SAME Haxe object reuses the SAME proxy userdata (no per-access allocation),
 * plus a function map so resolved bound-methods are reused by cached method closures.
 * Dropped wholesale when the script's Lua state is disposed.
 * 
 * This class is likely to undergo drastic changes as the proxy system is optimized and iterated on
 * There's a lot of comments and notes in here, this is mostly for future me and anyone else who wants to understand the inner workings
 */
class ProxyState {
	public var handleToObj:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var objToHandle:haxe.ds.ObjectMap<Dynamic, Int> = new haxe.ds.ObjectMap<Dynamic, Int>();
	public var nextHandle:Int = 1;

	// Resolved (bound) functions referenced by cached method closures, by id.
	public var funcs:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var nextFunc:Int = 1;

	public function new() {}
}

/**
 * "Real Lua" object bridge.
 *
 * Pushes live Haxe objects into Lua as userdata + a shared metatable, so scripts can
 * do `game.boyfriend.x = 100`, `game:endSong()`, like HScript.
 *
 *  - Stable objects (fields/globals: game, game.boyfriend) are proxied ONCE per state
 *    and cached (registry table handle->userdata), so hot loops never reallocate.
 *  - On a cached proxy, each key is classified once and stored in the proxy's own Lua
 *    env table (LuaJIT setfenv): a method becomes a reusable closure whose upvalue is a
 *    function-id into ProxyState.funcs (so calls do NO reflection, NO allocation); a
 *    field is tagged so subsequent reads skip the method machinery.
 *  - Transient values (method returns, `new` instances) are pushed UN-cached (ephemeral):
 *    no map/cache/env work, and they GC normally instead of being pinned.
 */
class LuaProxy {
	static inline final INST_META:String = "hxproxy_instance";
	static inline final CLASS_META:String = "hxproxy_class";
	static inline final CACHE_KEY:String = "hxproxy_cache"; // registry: { [handle] = userdata }
	static inline final SID_KEY:String = "hxproxy_sid"; // registry: this state's id

	static var states:Map<Int, ProxyState> = new Map<Int, ProxyState>();
	static var nextStateId:Int = 1;

	// Reusable args buffers for method calls (reentrancy-safe: each level pops/pushes).
	static final argPool:Array<Array<Dynamic>> = [];

	/** Registers metatables + per-state registry on a fresh Lua state. */
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

		Lua.newtable(L);
		Lua.setfield(L, Lua.REGISTRYINDEX, CACHE_KEY);

		var sid:Int = nextStateId++;
		states.set(sid, new ProxyState());
		Lua.pushinteger(L, sid);
		Lua.setfield(L, Lua.REGISTRYINDEX, SID_KEY);

		Lua.pushcfunction(L, cpp.Callable.fromStaticFunction(luaImport));
		Lua.setglobal(L, "import");
	}

	/** Drops this state's registry. Call BEFORE Lua.close(). */
	public static function dispose(L:cpp.RawPointer<Lua_State>):Void {
		var sid:Int = stateId(L);
		if (sid > 0) states.remove(sid);
	}

	static inline function setMeta(L:cpp.RawPointer<Lua_State>, name:String, fn:Lua_CFunction):Void {
		Lua.pushcfunction(L, fn);
		Lua.setfield(L, -2, name);
	}

	static inline function stateId(L:cpp.RawPointer<Lua_State>):Int {
		Lua.getfield(L, Lua.REGISTRYINDEX, SID_KEY);
		var sid:Int = (Lua.type(L, -1) == Lua.TNUMBER) ? Lua.tointeger(L, -1) : 0;
		Lua.pop(L, 1);
		return sid;
	}

	// userdata layout: [0]=stateId, [1]=handle, [2]=cached(1/0)
	static inline function ptrAt(L:cpp.RawPointer<Lua_State>, idx:Int):cpp.Pointer<Int> {
		return cast cpp.Pointer.fromRaw(Lua.touserdata(L, idx));
	}

	static inline function objAt(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		var raw:cpp.RawPointer<cpp.Void> = Lua.touserdata(L, idx);
		if (raw == null) return null;
		var ptr:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw);
		var st:ProxyState = states.get(ptr[0]);
		return (st == null) ? null : st.handleToObj.get(ptr[1]);
	}

	static inline function stAt(L:cpp.RawPointer<Lua_State>, idx:Int):ProxyState {
		var raw:cpp.RawPointer<cpp.Void> = Lua.touserdata(L, idx);
		if (raw == null) return null;
		var ptr:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw);
		return states.get(ptr[0]);
	}

	public static function pushHaxe(L:cpp.RawPointer<Lua_State>, v:Dynamic, cached:Bool = true):Void {
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
				pushObject(L, v, INST_META, cached);
			default:
				Convert.toLua(L, v); // anonymous structures / unknowns
		}
	}

	public static inline function pushClass(L:cpp.RawPointer<Lua_State>, cls:Dynamic):Void {
		if (cls == null) Lua.pushnil(L);
		else pushObject(L, cls, CLASS_META, true);
	}

	static function pushObject(L:cpp.RawPointer<Lua_State>, obj:Dynamic, metaName:String, cached:Bool):Void {
		var sid:Int = stateId(L);
		var st:ProxyState = states.get(sid);
		if (st == null) {
			Lua.pushnil(L);
			return;
		}

		if (!cached) {
			// Ephemeral proxy: handle for objAt/__gc only. No env, no cache, cached=0.
			var h:Int = st.nextHandle++;
			st.handleToObj.set(h, obj);
			var raw0:cpp.RawPointer<cpp.Void> = Lua.newuserdata(L, cast 12);
			var p0:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw0);
			p0[0] = sid;
			p0[1] = h;
			p0[2] = 0;
			LuaL.getmetatable(L, metaName);
			Lua.setmetatable(L, -2);
			return;
		}

		var handle:Null<Int> = st.objToHandle.get(obj);
		if (handle == null) {
			handle = st.nextHandle++;
			st.handleToObj.set(handle, obj);
			st.objToHandle.set(obj, handle);
		}

		Lua.getfield(L, Lua.REGISTRYINDEX, CACHE_KEY); // [cache]
		Lua.rawgeti(L, -1, handle); // [cache, cached|nil]
		if (Lua.type(L, -1) == Lua.TUSERDATA) {
			Lua.remove(L, -2); // [ud]
			return;
		}
		Lua.pop(L, 1); // [cache]

		var raw:cpp.RawPointer<cpp.Void> = Lua.newuserdata(L, cast 12); // [cache, ud]
		var ptr:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw);
		ptr[0] = sid;
		ptr[1] = handle;
		ptr[2] = 1;
		LuaL.getmetatable(L, metaName); // [cache, ud, meta]
		Lua.setmetatable(L, -2); // [cache, ud]

		// Per-object method-classification cache lives in the userdata's env table.
		Lua.newtable(L); // [cache, ud, env]
		Lua.setfenv(L, -2); // ud.env = env -> [cache, ud]

		Lua.pushvalue(L, -1); // [cache, ud, ud]
		Lua.rawseti(L, -3, handle); // cache[handle] = ud -> [cache, ud]
		Lua.remove(L, -2); // [ud]
	}

	public static function unwrap(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		if (Lua.type(L, idx) == Lua.TUSERDATA && isProxy(L, idx))
			return objAt(L, idx);
		return Convert.fromLua(L, idx);
	}

	static function isProxy(L:cpp.RawPointer<Lua_State>, idx:Int):Bool {
		if (Lua.getmetatable(L, idx) == 0)
			return false;
		var match:Bool = false;
		LuaL.getmetatable(L, INST_META);
		if (Lua.rawequal(L, -1, -2) == 1) match = true;
		Lua.pop(L, 1);
		if (!match) {
			LuaL.getmetatable(L, CLASS_META);
			if (Lua.rawequal(L, -1, -2) == 1) match = true;
			Lua.pop(L, 1);
		}
		Lua.pop(L, 1);
		return match;
	}

	static function instanceIndex(L:cpp.RawPointer<Lua_State>):Int {
		var ptr:cpp.Pointer<Int> = ptrAt(L, 1);
		var st:ProxyState = states.get(ptr[0]);
		var obj:Dynamic = (st == null) ? null : st.handleToObj.get(ptr[1]);
		if (obj == null) {
			Lua.pushnil(L);
			return 1;
		}

		if (Lua.type(L, 2) == Lua.TNUMBER && (obj is Array)) {
			var arr:Array<Dynamic> = obj;
			var i:Int = Lua.tointeger(L, 2);
			pushHaxe(L, (i >= 0 && i < arr.length) ? arr[i] : null);
			return 1;
		}

		if (ptr[2] == 1)
			return cachedIndex(L, st, obj, false);

		// Ephemeral: no env cache, simple resolve.
		var key:String = Lua.tostring(L, 2).toString();
		try {
			var f:Dynamic = Reflect.getProperty(obj, key);
			if (Reflect.isFunction(f)) {
				Lua.pushvalue(L, 1);
				Lua.pushstring(L, key);
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCall), 2);
				return 1;
			}
			pushHaxe(L, f, false);
		} catch (e:Dynamic) {
			Lua.pushnil(L);
		}
		return 1;
	}

	// Cached fast path: classify the key once into the proxy's env, then reuse.
	// `isClass` switches static (Reflect.field) vs instance (Reflect.getProperty) lookup
	// and enables the `new` constructor key for class proxies.
	static function cachedIndex(L:cpp.RawPointer<Lua_State>, st:ProxyState, obj:Dynamic, isClass:Bool):Int {
		Lua.getfenv(L, 1); // [env]
		Lua.pushvalue(L, 2); // [env, key]
		Lua.rawget(L, -2); // [env, entry]
		var et:Int = Lua.type(L, -1);
		if (et == Lua.TFUNCTION) {
			Lua.remove(L, -2); // [closure]
			return 1;
		}
		if (et == Lua.TBOOLEAN) {
			// Known plain field: read its current value (no method machinery).
			Lua.pop(L, 2);
			var key:String = Lua.tostring(L, 2).toString();
			pushHaxe(L, isClass ? Reflect.field(obj, key) : Reflect.getProperty(obj, key));
			return 1;
		}
		Lua.pop(L, 1); // [env]

		var key:String = Lua.tostring(L, 2).toString();
		try {
			if (isClass && key == "new") {
				Lua.pushvalue(L, 1); // self -> [env, self]
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(constructorCall), 1); // [env, closure]
				return cacheAndReturnClosure(L);
			}

			var f:Dynamic = isClass ? Reflect.field(obj, key) : Reflect.getProperty(obj, key);
			if (Reflect.isFunction(f)) {
				var fid:Int = st.nextFunc++;
				st.funcs.set(fid, f);
				Lua.pushvalue(L, 1); // self -> [env, self]
				Lua.pushinteger(L, fid); // [env, self, fid]
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCallFast), 2); // [env, closure]
				return cacheAndReturnClosure(L);
			}

			// Plain field: tag it so future reads skip the function check.
			Lua.pushvalue(L, 2); // [env, key]
			Lua.pushboolean(L, 1); // [env, key, true]
			Lua.rawset(L, -3); // env[key]=true -> [env]
			Lua.pop(L, 1); // []
			pushHaxe(L, f);
		} catch (e:Dynamic) {
			Lua.pushnil(L);
		}
		return 1;
	}

	// Given [env, closure] on top: set env[key]=closure (key from arg 2) and leave closure.
	static inline function cacheAndReturnClosure(L:cpp.RawPointer<Lua_State>):Int {
		Lua.pushvalue(L, 2); // [env, closure, key]
		Lua.pushvalue(L, -2); // [env, closure, key, closure]
		Lua.rawset(L, -4); // env[key]=closure -> [env, closure]
		Lua.remove(L, -2); // [closure]
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

	// Cached method closure: upvalues (self userdata, funcId). Zero reflection per call.
	static function methodCallFast(L:cpp.RawPointer<Lua_State>):Int {
		var self:Int = Lua.upvalueindex(1);
		var st:ProxyState = stAt(L, self);
		if (st == null) return 0;
		var obj:Dynamic = st.handleToObj.get(ptrAt(L, self)[1]);
		var f:Dynamic = st.funcs.get(Lua.tointeger(L, Lua.upvalueindex(2)));
		if (obj == null || f == null) return 0;

		var nargs:Int = Lua.gettop(L);
		var start:Int = (nargs >= 1 && Lua.rawequal(L, 1, self) == 1) ? 2 : 1;

		var args:Array<Dynamic> = (argPool.length > 0 ? argPool.pop() : []);
		args.resize(0);
		for (i in start...nargs + 1)
			args.push(unwrap(L, i));

		var ret:Dynamic = null;
		try {
			ret = Reflect.callMethod(null, f, args); // f already bound to obj (or static)
		} catch (e:Dynamic) {
			args.resize(0);
			argPool.push(args);
			LuaL.error(L, '%s', 'call: ${Std.string(e)}');
			return 0;
		}
		args.resize(0);
		argPool.push(args);
		if (ret != null) {
			pushHaxe(L, ret, false);
			return 1;
		}
		return 0;
	}

	// Simple method closure (ephemeral proxies): upvalues (self userdata, key).
	static function methodCall(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, Lua.upvalueindex(1));
		var key:String = Lua.tostring(L, Lua.upvalueindex(2)).toString();
		if (obj == null)
			return 0;

		var nargs:Int = Lua.gettop(L);
		var start:Int = (nargs >= 1 && Lua.rawequal(L, 1, Lua.upvalueindex(1)) == 1) ? 2 : 1;

		var args:Array<Dynamic> = (argPool.length > 0 ? argPool.pop() : []);
		args.resize(0);
		for (i in start...nargs + 1)
			args.push(unwrap(L, i));

		var ret:Dynamic = null;
		try {
			ret = Reflect.callMethod(obj, Reflect.field(obj, key), args);
		} catch (e:Dynamic) {
			args.resize(0);
			argPool.push(args);
			LuaL.error(L, '%s', 'call "$key": ${Std.string(e)}');
			return 0;
		}
		args.resize(0);
		argPool.push(args);
		if (ret != null) {
			pushHaxe(L, ret, false);
			return 1;
		}
		return 0;
	}

	static function classIndex(L:cpp.RawPointer<Lua_State>):Int {
		var ptr:cpp.Pointer<Int> = ptrAt(L, 1);
		var st:ProxyState = states.get(ptr[0]);
		var cls:Dynamic = (st == null) ? null : st.handleToObj.get(ptr[1]);
		if (cls == null) {
			Lua.pushnil(L);
			return 1;
		}
		return cachedIndex(L, st, cls, true);
	}

	static function classCall(L:cpp.RawPointer<Lua_State>):Int {
		return construct(L, objAt(L, 1), 2);
	}

	static function constructorCall(L:cpp.RawPointer<Lua_State>):Int {
		return construct(L, objAt(L, Lua.upvalueindex(1)), 1);
	}

	static function construct(L:cpp.RawPointer<Lua_State>, cls:Dynamic, start:Int):Int {
		if (cls == null) {
			Lua.pushnil(L);
			return 1;
		}
		var nargs:Int = Lua.gettop(L);
		var args:Array<Dynamic> = (argPool.length > 0 ? argPool.pop() : []);
		args.resize(0);
		for (i in start...nargs + 1)
			args.push(unwrap(L, i));
		var inst:Dynamic = null;
		try {
			inst = Type.createInstance(cls, args);
		} catch (e:Dynamic) {
			args.resize(0);
			argPool.push(args);
			LuaL.error(L, '%s', 'new: ${Std.string(e)}');
			return 0;
		}
		args.resize(0);
		argPool.push(args);
		pushHaxe(L, inst, false); // freshly constructed -> ephemeral
		return 1;
	}

	static function proxyToString(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		Lua.pushstring(L, obj == null ? "null" : Std.string(obj));
		return 1;
	}

	static function proxyGc(L:cpp.RawPointer<Lua_State>):Int {
		var raw:cpp.RawPointer<cpp.Void> = Lua.touserdata(L, 1);
		if (raw == null) return 0;
		var ptr:cpp.Pointer<Int> = cast cpp.Pointer.fromRaw(raw);
		var st:ProxyState = states.get(ptr[0]);
		if (st != null) {
			var obj:Dynamic = st.handleToObj.get(ptr[1]);
			st.handleToObj.remove(ptr[1]);
			// Only clear the cache mapping if THIS handle owns it (an ephemeral proxy
			// shares the object with a possibly-still-live cached proxy).
			if (obj != null && st.objToHandle.get(obj) == ptr[1])
				st.objToHandle.remove(obj);
		}
		return 0;
	}

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
}
#end
