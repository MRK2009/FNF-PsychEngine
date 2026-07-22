#if LUA_ALLOWED
package psychlua;

import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;
import hxluajit.wrapper.LuaConverter;
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
	/**
	 * Anchors runtime classes that scripts reach ONLY through `import()`.
	 *
	 * `import()` resolves by name at runtime, which is not a Haxe reference, so the compiler never
	 * loads the module and the lookup returns nil. `@:keep` on the class does not help: it stops DCE
	 * dropping a compiled type, it does not pull one in — and neither does `--macro keep()`, which
	 * only adds that same metadata. Only a hard reference like this one does.
	 *
	 * It lives here, beside the `import` binding, because that is the exact feature it serves. The
	 * storyboard runtime previously anchored off the osu CONVERTER, which is desktop-only, so mobile
	 * silently shipped without it.
	 */
	@:keep static var _importAnchors:Array<Class<Dynamic>> = [backend.osu.OsuStoryboardPlayer];

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
			setMeta(L, "__len", cpp.Callable.fromStaticFunction(instanceLen));
			setMeta(L, "__eq", cpp.Callable.fromStaticFunction(proxyEq));
			setMeta(L, "__concat", cpp.Callable.fromStaticFunction(proxyConcat));
			setMeta(L, "__tostring", cpp.Callable.fromStaticFunction(proxyToString));
			setMeta(L, "__gc", cpp.Callable.fromStaticFunction(proxyGc));
		}
		Lua.pop(L, 1);

		if (LuaL.newmetatable(L, CLASS_META) == 1) {
			setMeta(L, "__index", cpp.Callable.fromStaticFunction(classIndex));
			setMeta(L, "__newindex", cpp.Callable.fromStaticFunction(classNewIndex));
			setMeta(L, "__call", cpp.Callable.fromStaticFunction(classCall));
			setMeta(L, "__eq", cpp.Callable.fromStaticFunction(proxyEq));
			setMeta(L, "__concat", cpp.Callable.fromStaticFunction(proxyConcat));
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
		Convert.userdataToHaxe = cpp.Callable.fromStaticFunction(unwrapUserdata);
		// Let wrapped Lua callbacks (Convert's TFUNCTION path) check their state is still open before
		// firing, so a tween/timer outliving the script can't call into a freed Lua state.
		Convert.stateIdOf = cpp.Callable.fromStaticFunction(sidHook);
		Convert.stateAlive = isStateAlive;
	}

	// Non-inline so it can be taken as a C function pointer (`stateId` itself is inline).
	static function sidHook(L:cpp.RawPointer<Lua_State>):Int
		return stateId(L);

	/** Whether a proxy state id is still registered (i.e. its Lua state hasn't been disposed). */
	public static function isStateAlive(sid:Int):Bool
		return states.exists(sid);

	// other userdata -> the raw converter (must NOT re-enter Convert.fromLua, which would
	// loop back here). Stateless; the owning state is read from the userdata itself.
	static function unwrapUserdata(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		if (isProxy(L, idx))
			return objAt(L, idx);
		return LuaConverter.fromLua(L, idx);
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

	// `proxyContainers`: whether Array/Map values are pushed as LIVE proxies
	// (direct-access path, default) or as native 1-based Lua tables. The
	// traditional psychlua API (CallbackHandler) passes `false` so stock scripts
	// get real tables -- with working `#`, `ipairs`, `table.*` -- exactly like
	// upstream Psych; class instances stay proxies regardless so `getProperty`
	// can still return a live object.
	public static function pushHaxe(L:cpp.RawPointer<Lua_State>, v:Dynamic, cached:Bool = true, proxyContainers:Bool = true):Void {
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
				if (!proxyContainers && (v is Array || v is haxe.Constraints.IMap))
					Convert.toLua(L, v); // native 1-based table for the traditional API
				else
					pushObject(L, v, INST_META, cached);
			case TEnum(_):
				// `Convert` has no enum case and pushes nil, which is indistinguishable from "no such
				// field". An ephemeral proxy instead round-trips: `tostring()` gives the constructor
				// name and handing it back to Haxe yields the SAME enum value.
				//
				// Only on the direct-access path. The traditional API is deliberately byte-compatible
				// with upstream Psych, where an enum reads as nil; a stock mod testing `== nil` would
				// change behaviour if we handed it userdata there.
				if (proxyContainers)
					pushObject(L, v, INST_META, false);
				else
					Convert.toLua(L, v);
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

	/**
	 * `==` on two proxies compares the HAXE OBJECTS behind them, not the userdata.
	 *
	 * Without this, identity comparison silently lies: every method return and field read of an object
	 * is pushed as a fresh EPHEMERAL proxy (own handle, own userdata), so `a.shader == a.shader` was
	 * false even though both sides are the same Haxe instance. Cached proxies happened to compare
	 * correctly, which made the failure look intermittent rather than systematic.
	 *
	 * Lua 5.1 only dispatches `__eq` when both operands share a metatable, so an instance proxy never
	 * compares equal to a class proxy -- which is correct anyway.
	 */
	static function proxyEq(L:cpp.RawPointer<Lua_State>):Int {
		var a:Dynamic = objAt(L, 1);
		var b:Dynamic = objAt(L, 2);
		// Two dead handles are not "equal"; null here means the object is already gone.
		Lua.pushboolean(L, (a != null && a == b) ? 1 : 0);
		return 1;
	}

	/**
	 * A Lua stack slot as a Haxe field name, or null when the value can't be one.
	 *
	 * `lua_tostring` returns NULL for anything that is not a string or a number, and the raw
	 * `.toString()` on that is unguarded -- so `obj[{}]`, `obj[true]` or `obj[somefunc]` used to push a
	 * null string straight into `Reflect`. Callers must treat null as "no such key".
	 */
	static inline function keyAt(L:cpp.RawPointer<Lua_State>, idx:Int):String {
		var t:Int = Lua.type(L, idx);
		if (t != Lua.TSTRING && t != Lua.TNUMBER)
			return null;
		var cs:cpp.ConstCharStar = Lua.tostring(L, idx);
		return (cs == null) ? null : cs.toString();
	}

	/**
	 * A Lua stack slot as a Haxe MAP key. Integral numbers are narrowed to `Int` so `IntMap` lookups
	 * hit (a bare `Convert.fromLua` hands back a Float, which never matches an `IntMap` key).
	 */
	static function mapKeyAt(L:cpp.RawPointer<Lua_State>, idx:Int):Dynamic {
		if (Lua.type(L, idx) == Lua.TNUMBER) {
			var n:Float = Lua.tonumber(L, idx);
			var i:Int = Std.int(n);
			return (i == n) ? (i : Dynamic) : (n : Dynamic);
		}
		return unwrap(L, idx);
	}

	static inline function asMap(obj:Dynamic):haxe.Constraints.IMap<Dynamic, Dynamic> {
		return (obj is haxe.Constraints.IMap) ? cast obj : null;
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
			// Lua is 1-based; map to the Haxe array's 0-based index so direct
			// access matches Lua/Psych convention (e.g. arr[1] is the first item).
			var i:Int = Lua.tointeger(L, 2) - 1;
			// EPHEMERAL: a cached element proxy is pinned in the registry for the state's life, so
			// iterating a large array (e.g. every NoteData in a chart) would leak thousands of proxies.
			// `__eq` compares the underlying objects, so re-proxying the same element still compares equal.
			pushHaxe(L, (i >= 0 && i < arr.length) ? arr[i] : null, false);
			return 1;
		}

		if (ptr[2] == 1)
			return cachedIndex(L, st, obj, false);

		// Ephemeral: no env cache, simple resolve.
		var key:String = keyAt(L, 2);
		if (key == null) {
			Lua.pushnil(L);
			return 1;
		}
		try {
			var f:Dynamic = Reflect.getProperty(obj, key);
			if (Reflect.isFunction(f)) {
				Lua.pushvalue(L, 1);
				Lua.pushstring(L, key);
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCall), 2);
				return 1;
			}
			if (f == null)
				f = mapLookup(L, obj);
			pushHaxe(L, f, false);
		} catch (e:Dynamic) {
			// A THROWING getter -- not a missing field (Reflect.getProperty returns null for those
			// without throwing). Surface it instead of the old silent nil, which hid the failure and
			// resurfaced later as an unrelated nil-index somewhere downstream.
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'get "$key": ${Std.string(e)}'); #end
			LuaL.error(L, '%s', 'get "$key": ${Std.string(e)}');
		}
		return 1;
	}

	/**
	 * Map CONTENT for the key in stack slot 2, or null when `obj` isn't a Map.
	 *
	 * `pushHaxe` proxies `Map` like any other class, but only `Array` ever got element access -- so
	 * `someMap['tag']` resolved through `Reflect` (which sees fields, not entries) and was always nil,
	 * leaving `:get()` as the only way in. Content is consulted only AFTER reflection comes up empty,
	 * so a map's own methods (`get`/`set`/`exists`/`keys`) still win and nothing that worked breaks.
	 */
	static function mapLookup(L:cpp.RawPointer<Lua_State>, obj:Dynamic):Dynamic {
		var m = asMap(obj);
		return (m == null) ? null : m.get(mapKeyAt(L, 2));
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
			var key:String = keyAt(L, 2);
			if (key == null) {
				Lua.pushnil(L);
				return 1;
			}
			var v:Dynamic = isClass ? Reflect.field(obj, key) : Reflect.getProperty(obj, key);
			if (v == null && !isClass)
				v = mapLookup(L, obj);
			pushHaxe(L, v);
			return 1;
		}
		Lua.pop(L, 1); // [env]

		var key:String = keyAt(L, 2);
		if (key == null) {
			Lua.pop(L, 1);
			Lua.pushnil(L);
			return 1;
		}
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
			if (f == null && !isClass)
				f = mapLookup(L, obj);
			pushHaxe(L, f);
		} catch (e:Dynamic) {
			// A throwing getter/static, surfaced rather than swallowed to nil (see instanceIndex). The
			// leftover env table on the stack doesn't need cleanup: LuaL.error longjmps out of the call.
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'get "$key": ${Std.string(e)}'); #end
			LuaL.error(L, '%s', 'get "$key": ${Std.string(e)}');
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

	// `#proxy` for proxied arrays so length and `for i = 1, #arr` loops work on
	// the direct-access path. LuaJIT (5.1 core) honours __len on userdata.
	// Non-array objects report 0. Note: pairs/ipairs over a proxy still need a
	// numeric loop -- their metamethods are Lua 5.2 and not honoured by LuaJIT
	// without the 5.2-compat build flag (not enabled here).
	static function instanceLen(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		if (obj is Array) {
			Lua.pushinteger(L, (obj : Array<Dynamic>).length);
			return 1;
		}
		var m = asMap(obj);
		if (m != null) {
			var n:Int = 0;
			for (_ in m.keys())
				n++;
			Lua.pushinteger(L, n);
			return 1;
		}
		Lua.pushinteger(L, 0);
		return 1;
	}

	static function instanceNewIndex(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		if (obj == null)
			return 0;

		if (Lua.type(L, 2) == Lua.TNUMBER && (obj is Array)) {
			var arr:Array<Dynamic> = obj;
			arr[Lua.tointeger(L, 2) - 1] = unwrap(L, 3); // 1-based Lua -> 0-based Haxe
			return 0;
		}

		var m = asMap(obj);
		if (m != null) {
			// A Map's entries are its content; it has no script-settable fields, so a write is a `set`.
			m.set(mapKeyAt(L, 2), unwrap(L, 3));
			return 0;
		}

		var key:String = keyAt(L, 2);
		if (key == null)
			return 0;
		try {
			Reflect.setProperty(obj, key, unwrap(L, 3));
		} catch (e:Dynamic) {
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'set "$key": ${Std.string(e)}'); #end
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

		var ret:Dynamic = null;
		try {
			// Arg conversion is inside the try: `unwrap` can throw (a cyclic table, a bad value), and
			// letting that unwind out of a C callback is UB and would strand the pooled `args` buffer.
			for (i in start...nargs + 1)
				args.push(unwrap(L, i));
			ret = Reflect.callMethod(null, f, args); // f already bound to obj (or static)
		} catch (e:Dynamic) {
			args.resize(0);
			argPool.push(args);
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'call: ${Std.string(e)}'); #end
			LuaL.error(L, '%s', 'call: ${Std.string(e)}');
			return 0;
		}
		args.resize(0);
		argPool.push(args);
		// ALWAYS one return value. Pushing nothing for a null result made a nullable return
		// indistinguishable from a void one at the Lua end: `print(o:f())` printed a blank line and
		// `select('#', o:f())` was 0, so nil could not be handled positionally.
		pushHaxe(L, ret, false);
		return 1;
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

		var ret:Dynamic = null;
		try {
			// Arg conversion inside the try (see methodCallFast): `unwrap` can throw.
			for (i in start...nargs + 1)
				args.push(unwrap(L, i));
			ret = Reflect.callMethod(obj, Reflect.field(obj, key), args);
		} catch (e:Dynamic) {
			args.resize(0);
			argPool.push(args);
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'call "$key": ${Std.string(e)}'); #end
			LuaL.error(L, '%s', 'call "$key": ${Std.string(e)}');
			return 0;
		}
		args.resize(0);
		argPool.push(args);
		// ALWAYS one return value. Pushing nothing for a null result made a nullable return
		// indistinguishable from a void one at the Lua end: `print(o:f())` printed a blank line and
		// `select('#', o:f())` was 0, so nil could not be handled positionally.
		pushHaxe(L, ret, false);
		return 1;
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
		var inst:Dynamic = null;
		try {
			// Arg conversion inside the try (see methodCallFast): `unwrap` can throw.
			for (i in start...nargs + 1)
				args.push(unwrap(L, i));
			inst = Type.createInstance(cls, args);
		} catch (e:Dynamic) {
			args.resize(0);
			argPool.push(args);
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'new: ${Std.string(e)}'); #end
			LuaL.error(L, '%s', 'new: ${Std.string(e)}');
			return 0;
		}
		args.resize(0);
		argPool.push(args);
		pushHaxe(L, inst, false); // freshly constructed -> ephemeral
		return 1;
	}

	/**
	 * Static-field WRITE on a class proxy (`Conductor.bpm = 150`).
	 *
	 * Without a `__newindex` on `CLASS_META`, Lua 5.1 RAISES on any assignment to class userdata, so
	 * writing a static was impossible even though reading one worked. Statics use `Reflect.setField`
	 * (not `setProperty`, which is for instances).
	 */
	static function classNewIndex(L:cpp.RawPointer<Lua_State>):Int {
		var cls:Dynamic = objAt(L, 1);
		if (cls == null)
			return 0;
		var key:String = keyAt(L, 2);
		if (key == null)
			return 0;
		try {
			Reflect.setField(cls, key, unwrap(L, 3));
		} catch (e:Dynamic) {
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', 'set static "$key": ${Std.string(e)}'); #end
			LuaL.error(L, '%s', 'set static "$key": ${Std.string(e)}');
		}
		return 0;
	}

	/**
	 * `..` on a proxy. Either operand may be the proxy (`"x=" .. obj` or `obj .. "!"`), so both slots
	 * are stringified: a proxy through its object's `Std.string`, anything else through Lua's own
	 * `tostring`. Without this, concatenating a proxy raised "attempt to concatenate" despite the
	 * `__tostring` already installed -- a common shape in exactly the debug prints scripts reach for.
	 */
	static function proxyConcat(L:cpp.RawPointer<Lua_State>):Int {
		Lua.pushstring(L, concatSide(L, 1) + concatSide(L, 2));
		return 1;
	}

	static function concatSide(L:cpp.RawPointer<Lua_State>, idx:Int):String {
		if (Lua.type(L, idx) == Lua.TUSERDATA && isProxy(L, idx)) {
			var obj:Dynamic = objAt(L, idx);
			return obj == null ? "null" : Std.string(obj);
		}
		var cs:cpp.ConstCharStar = Lua.tostring(L, idx);
		return (cs == null) ? "" : cs.toString();
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
		if (cls == null) {
			// A bare nil here surfaces much later as "attempt to index a nil value" somewhere unrelated.
			// Warn at the point of failure instead -- a typo, a class dropped by DCE (see
			// `_importAnchors`) and one blocked by ModSecurity all land here.
			var msg:String = 'import("$path") failed: class not found, removed by DCE, or blocked';
			FlxG.log.warn(msg);
			#if CRASH_HANDLER backend.CrashHandler.reportScriptError('LuaProxy', msg); #end
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug(msg, 0xFFFF8800);
		}
		pushClass(L, cls);
		return 1;
	}
}
#end
