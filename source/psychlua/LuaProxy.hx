#if LUA_ALLOWED
package psychlua;

import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;
import hxluajit.wrapper.LuaConverter;
import llua.Convert;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.math.FlxPoint.FlxBasePoint;

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
	/** This state's id, so anything holding a `ProxyState` can stamp userdata without re-reading it. */
	public var id:Int = 0;

	public var handleToObj:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var objToHandle:haxe.ds.ObjectMap<Dynamic, Int> = new haxe.ds.ObjectMap<Dynamic, Int>();
	public var nextHandle:Int = 1;

	/**
	 * Interned member names, by id. A proxy's env table stores the ID of a classified plain field,
	 * so a cached read looks the name up here instead of rebuilding a Haxe `String` from Lua's C
	 * string on every access -- which was an allocation on the single hottest path in the bridge
	 * (`sprite.x` read or written every frame).
	 */
	public var keyNames:Array<String> = [];

	var keyIds:Map<String, Int> = new Map<String, Int>();

	/**
	 * `ProxyFields` accessor id per interned key, parallel to `keyNames`, or `ProxyFields.NONE`.
	 *
	 * Resolved once when the name is interned, so the hot path never looks a name up in a map: it
	 * already has the integer the typed accessor switches on.
	 */
	public var keyFast:Array<Int> = [];

	/** The id for `key`, assigning one the first time it is seen. */
	public function intern(key:String):Int {
		var id:Null<Int> = keyIds.get(key);
		if (id == null) {
			id = keyNames.length;
			keyNames.push(key);
			keyFast.push(ProxyFields.idOf(key));
			keyIds.set(key, id);
		}
		return id;
	}

	// Resolved (bound) functions referenced by cached method closures, by id.
	public var funcs:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var nextFunc:Int = 1;

	/**
	 * The script this Lua state belongs to.
	 *
	 * Lets a C callback resolve its owner from `L` alone. `CallbackHandler` used to go through
	 * `ScriptHost.current` plus a linear scan plus a `lastCalledScript` guess, which resolves to
	 * nothing whenever the current host is not the one that owns the state -- a tween or timer
	 * callback that outlived its state, for instance.
	 */
	public var owner:FunkinLua = null;

	public function new() {}
}

/**
 * Direct, typed access to the members scripts touch every frame.
 *
 * Once the env cache has classified a key, reading it still went through `Reflect.getProperty`,
 * which on hxcpp is a string-hash dispatch into the generated `__Field` handing back a `Dynamic` --
 * so every `sprite.x` read BOXED a Float that the push path immediately unboxed again. Writes paid
 * the mirror of that through `__SetField`. Keys are interned to dense integer ids now, so this is a
 * C++ switch behind one type check, moving the value between Lua and the typed field with no
 * reflection and no allocation at all.
 *
 * Every field here is declared as a property with a setter on its BASE class, so a typed write is
 * still a virtual `set_*` call and `FlxSpriteGroup`'s overrides -- which propagate to its members --
 * keep working. That is exactly why a plain variable could not be included: it would be written
 * directly and silently skip them.
 *
 * A miss (unknown id, or an object of another type) returns false and the caller falls back to the
 * reflective path, so this is purely a shortcut and never the only way through.
 */
class ProxyFields {
	/** Not a fast field. **/
	public static inline final NONE:Int = -1;

	static inline final X:Int = 0;
	static inline final Y:Int = 1;
	static inline final ANGLE:Int = 2;
	static inline final WIDTH:Int = 3;
	static inline final HEIGHT:Int = 4;
	static inline final VISIBLE:Int = 5;
	static inline final ACTIVE:Int = 6;
	static inline final ALIVE:Int = 7;
	static inline final EXISTS:Int = 8;
	static inline final MOVES:Int = 9;
	static inline final IMMOVABLE:Int = 10;

	static inline final ALPHA:Int = 11;
	static inline final COLOR:Int = 12;
	static inline final FLIP_X:Int = 13;
	static inline final FLIP_Y:Int = 14;
	static inline final ANTIALIASING:Int = 15;
	static inline final FRAME_WIDTH:Int = 16;
	static inline final FRAME_HEIGHT:Int = 17;

	static final IDS:Map<String, Int> = [
		'x' => X, 'y' => Y, 'angle' => ANGLE, 'width' => WIDTH, 'height' => HEIGHT, 'visible' => VISIBLE, 'active' => ACTIVE, 'alive' => ALIVE,
		'exists' => EXISTS, 'moves' => MOVES, 'immovable' => IMMOVABLE, 'alpha' => ALPHA, 'color' => COLOR, 'flipX' => FLIP_X, 'flipY' => FLIP_Y,
		'antialiasing' => ANTIALIASING, 'frameWidth' => FRAME_WIDTH, 'frameHeight' => FRAME_HEIGHT
	];

	/** The accessor id for a member name, or `NONE`. Consulted once, when the name is interned. */
	public static function idOf(name:String):Int {
		var id:Null<Int> = IDS.get(name);
		return (id == null) ? NONE : id;
	}

	/** Pushes `obj.<id>` and returns true, or returns false for the caller to resolve reflectively. */
	public static function get(L:cpp.RawPointer<Lua_State>, id:Int, obj:Dynamic):Bool {
		if (id < 0)
			return false;

		if ((obj is FlxSprite)) {
			var s:FlxSprite = cast obj;
			switch (id) {
				case ALPHA:
					Lua.pushnumber(L, s.alpha);
				case COLOR:
					Lua.pushinteger(L, s.color);
				case FLIP_X:
					Lua.pushboolean(L, s.flipX ? 1 : 0);
				case FLIP_Y:
					Lua.pushboolean(L, s.flipY ? 1 : 0);
				case ANTIALIASING:
					Lua.pushboolean(L, s.antialiasing ? 1 : 0);
				case FRAME_WIDTH:
					Lua.pushinteger(L, s.frameWidth);
				case FRAME_HEIGHT:
					Lua.pushinteger(L, s.frameHeight);
				default:
					return getObject(L, id, s);
			}
			return true;
		}

		if ((obj is FlxObject))
			return getObject(L, id, cast obj);

		if ((obj is FlxBasePoint))
			return getPoint(L, id, cast obj);

		return false;
	}

	static function getObject(L:cpp.RawPointer<Lua_State>, id:Int, o:FlxObject):Bool {
		switch (id) {
			case X:
				Lua.pushnumber(L, o.x);
			case Y:
				Lua.pushnumber(L, o.y);
			case ANGLE:
				Lua.pushnumber(L, o.angle);
			case WIDTH:
				Lua.pushnumber(L, o.width);
			case HEIGHT:
				Lua.pushnumber(L, o.height);
			case VISIBLE:
				Lua.pushboolean(L, o.visible ? 1 : 0);
			case ACTIVE:
				Lua.pushboolean(L, o.active ? 1 : 0);
			case ALIVE:
				Lua.pushboolean(L, o.alive ? 1 : 0);
			case EXISTS:
				Lua.pushboolean(L, o.exists ? 1 : 0);
			case MOVES:
				Lua.pushboolean(L, o.moves ? 1 : 0);
			case IMMOVABLE:
				Lua.pushboolean(L, o.immovable ? 1 : 0);
			default:
				return false;
		}
		return true;
	}

	// `scale.x`, `offset.y`, `velocity.x` -- a modchart reaches through a point constantly, and the
	// point behind the FlxPoint abstract is an ordinary object, so it proxies and indexes like one.
	static function getPoint(L:cpp.RawPointer<Lua_State>, id:Int, p:FlxBasePoint):Bool {
		switch (id) {
			case X:
				Lua.pushnumber(L, p.x);
			case Y:
				Lua.pushnumber(L, p.y);
			default:
				return false;
		}
		return true;
	}

	/**
	 * Writes the value at Lua stack index 3 into `obj.<id>` and returns true, or returns false for
	 * the caller to resolve reflectively.
	 *
	 * The Lua value has to already BE the field's type. Anything else (a string colour, a number
	 * assigned to a flag) falls through, so whatever the reflective path made of it before is
	 * exactly what it still makes of it.
	 */
	public static function set(L:cpp.RawPointer<Lua_State>, id:Int, obj:Dynamic):Bool {
		if (id < 0)
			return false;

		var type:Int = Lua.type(L, 3);

		if ((obj is FlxSprite)) {
			var s:FlxSprite = cast obj;
			switch (id) {
				case ALPHA:
					if (type != Lua.TNUMBER) return false;
					s.alpha = Lua.tonumber(L, 3);
				case COLOR:
					if (type != Lua.TNUMBER) return false;
					s.color = Lua.tointeger(L, 3);
				case FLIP_X:
					if (type != Lua.TBOOLEAN) return false;
					s.flipX = Lua.toboolean(L, 3) != 0;
				case FLIP_Y:
					if (type != Lua.TBOOLEAN) return false;
					s.flipY = Lua.toboolean(L, 3) != 0;
				case ANTIALIASING:
					if (type != Lua.TBOOLEAN) return false;
					s.antialiasing = Lua.toboolean(L, 3) != 0;
				default:
					return setObject(L, id, s, type); // FRAME_* are read-only and fall through there
			}
			return true;
		}

		if ((obj is FlxObject))
			return setObject(L, id, cast obj, type);

		if ((obj is FlxBasePoint))
			return setPoint(L, id, cast obj, type);

		return false;
	}

	static function setObject(L:cpp.RawPointer<Lua_State>, id:Int, o:FlxObject, type:Int):Bool {
		switch (id) {
			case X:
				if (type != Lua.TNUMBER) return false;
				o.x = Lua.tonumber(L, 3);
			case Y:
				if (type != Lua.TNUMBER) return false;
				o.y = Lua.tonumber(L, 3);
			case ANGLE:
				if (type != Lua.TNUMBER) return false;
				o.angle = Lua.tonumber(L, 3);
			case WIDTH:
				if (type != Lua.TNUMBER) return false;
				o.width = Lua.tonumber(L, 3);
			case HEIGHT:
				if (type != Lua.TNUMBER) return false;
				o.height = Lua.tonumber(L, 3);
			case VISIBLE:
				if (type != Lua.TBOOLEAN) return false;
				o.visible = Lua.toboolean(L, 3) != 0;
			case ACTIVE:
				if (type != Lua.TBOOLEAN) return false;
				o.active = Lua.toboolean(L, 3) != 0;
			case ALIVE:
				if (type != Lua.TBOOLEAN) return false;
				o.alive = Lua.toboolean(L, 3) != 0;
			case EXISTS:
				if (type != Lua.TBOOLEAN) return false;
				o.exists = Lua.toboolean(L, 3) != 0;
			case MOVES:
				if (type != Lua.TBOOLEAN) return false;
				o.moves = Lua.toboolean(L, 3) != 0;
			case IMMOVABLE:
				if (type != Lua.TBOOLEAN) return false;
				o.immovable = Lua.toboolean(L, 3) != 0;
			default:
				return false;
		}
		return true;
	}

	static function setPoint(L:cpp.RawPointer<Lua_State>, id:Int, p:FlxBasePoint, type:Int):Bool {
		if (type != Lua.TNUMBER)
			return false;

		switch (id) {
			case X:
				p.x = Lua.tonumber(L, 3);
			case Y:
				p.y = Lua.tonumber(L, 3);
			default:
				return false;
		}
		return true;
	}
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
 *
 * A consequence worth knowing when writing scripts: an ephemeral proxy is a FRESH userdata every
 * read, so `field.active[i]` hands back a different value each frame for the same note. `==` still
 * answers correctly (`proxyEq` compares the Haxe objects), but a Lua TABLE KEY does not -- Lua 5.1
 * indexes userdata keys by identity and never consults `__eq`. Keying per-object state by a proxy
 * therefore misses every lookup, re-runs whatever the entry was meant to do once per frame, and pins
 * each frame's proxy in the table forever. Key by something stable off the object instead (a note's
 * time and column, an id field).
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

	/**
	 * Integer slot in a proxy metatable holding `MARK_VALUE`, i.e. "this is one of ours".
	 *
	 * `isProxy` used to compare the value's metatable against each of ours in turn, and each
	 * comparison was a registry lookup by STRING name -- up to six Lua calls, run for every
	 * argument of every method call. A `rawgeti` on slot 1 hits the metatable's array part, answers
	 * for BOTH metatables at once, and leaves their identity alone (Lua 5.1 dispatches `__eq` only
	 * when both operands share one, so merging them was not an option).
	 */
	static inline final MARK_KEY:Int = 1;

	/** Distinctive enough that a foreign metatable with something at slot 1 cannot be mistaken for ours. */
	static inline final MARK_VALUE:Int = 0x48585052;
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
			markProxyMeta(L);
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
			markProxyMeta(L);
		}
		Lua.pop(L, 1);

		Lua.newtable(L);
		Lua.setfield(L, Lua.REGISTRYINDEX, CACHE_KEY);

		var sid:Int = nextStateId++;
		var st:ProxyState = new ProxyState();
		st.id = sid;
		states.set(sid, st);
		Lua.pushinteger(L, sid);
		Lua.setfield(L, Lua.REGISTRYINDEX, SID_KEY);

		Lua.pushcfunction(L, cpp.Callable.fromStaticFunction(luaImport));
		Lua.setglobal(L, "import");

		installIterators(L);
		Convert.userdataToHaxe = cpp.Callable.fromStaticFunction(unwrapUserdata);
		Convert.haxeToLua = cpp.Callable.fromStaticFunction(pushElement);
		// Let wrapped Lua callbacks (Convert's TFUNCTION path) check their state is still open before
		// firing, so a tween/timer outliving the script can't call into a freed Lua state.
		Convert.stateIdOf = cpp.Callable.fromStaticFunction(sidHook);
		Convert.stateAlive = isStateAlive;
	}

	/**
	 * Teaches the stock `pairs` / `ipairs` about proxies.
	 *
	 * LuaJIT is a 5.1 core, where `__pairs` / `__ipairs` do not exist, so iterating a proxied Array
	 * or Map was simply impossible -- scripts had to fall back to a manual numeric loop, and there
	 * was no way at all to walk a proxied object's fields. Both wrappers defer to the originals for
	 * everything that is not a proxy, so ordinary table iteration is unchanged.
	 *
	 * The two C helpers are captured as upvalues and then removed from the global table, so scripts
	 * see only the `pairs` / `ipairs` they already know.
	 */
	static function installIterators(L:cpp.RawPointer<Lua_State>):Void {
		Lua.pushcfunction(L, cpp.Callable.fromStaticFunction(luaIsProxy));
		Lua.setglobal(L, "__hxisproxy");
		Lua.pushcfunction(L, cpp.Callable.fromStaticFunction(luaProxyKeys));
		Lua.setglobal(L, "__hxproxykeys");

		if (LuaL.dostring(L, ITERATOR_PATCH) != 0) {
			var cs:cpp.ConstCharStar = Lua.tostring(L, -1);
			FlxG.log.warn('LuaProxy: pairs/ipairs patch failed: ' + ((cs == null) ? 'unknown error' : cs.toString()));
			Lua.pop(L, 1);
		}
	}

	static final ITERATOR_PATCH:String = "
local isproxy, keysof = __hxisproxy, __hxproxykeys
local rawpairs, rawipairs = pairs, ipairs

function pairs(t)
	if isproxy(t) then
		local keys, i = keysof(t), 0
		return function()
			i = i + 1
			local k = keys[i]
			if k == nil then return nil end
			return k, t[k]
		end
	end
	return rawpairs(t)
end

function ipairs(t)
	if isproxy(t) then
		local i = 0
		return function()
			i = i + 1
			local v = t[i]
			if v == nil then return nil end
			return i, v
		end
	end
	return rawipairs(t)
end

__hxisproxy, __hxproxykeys = nil, nil
";

	static function luaIsProxy(L:cpp.RawPointer<Lua_State>):Int {
		Lua.pushboolean(L, (Lua.type(L, 1) == Lua.TUSERDATA && isProxy(L, 1)) ? 1 : 0);
		return 1;
	}

	/**
	 * Every key of a proxied value, as a Lua array: indices for an `Array`, entry keys for a `Map`,
	 * field names for anything else.
	 */
	static function luaProxyKeys(L:cpp.RawPointer<Lua_State>):Int {
		var obj:Dynamic = objAt(L, 1);
		if (obj == null) {
			Lua.newtable(L);
			return 1;
		}

		var st:ProxyState = stAt(L, 1);
		var n:Int = 0;

		if ((obj is Array)) {
			var arr:Array<Dynamic> = obj;
			Lua.createtable(L, arr.length, 0);
			while (n < arr.length) {
				Lua.pushinteger(L, n + 1); // the key, 1-based like the proxy's own indexing
				Lua.rawseti(L, -2, n + 1);
				n++;
			}
			return 1;
		}

		var m = asMap(obj);
		if (m != null) {
			Lua.newtable(L);
			for (key in m.keys()) {
				pushValue(L, st, key, false);
				Lua.rawseti(L, -2, ++n);
			}
			return 1;
		}

		var fields:Array<String> = Reflect.fields(obj);
		Lua.createtable(L, fields.length, 0);
		for (field in fields) {
			Lua.pushstring(L, field);
			Lua.rawseti(L, -2, ++n);
		}
		return 1;
	}

	// Non-inline so it can be taken as a C function pointer (`stateId` itself is inline).
	static function sidHook(L:cpp.RawPointer<Lua_State>):Int
		return stateId(L);

	/** Whether a proxy state id is still registered (i.e. its Lua state hasn't been disposed). */
	public static function isStateAlive(sid:Int):Bool
		return states.exists(sid);

	/** Records which script owns `L`. Called once, right after `setup`. */
	public static function setOwner(L:cpp.RawPointer<Lua_State>, owner:FunkinLua):Void {
		var st:ProxyState = states.get(stateId(L));
		if (st != null)
			st.owner = owner;
	}

	/** The script owning `L`, or null. Resolved from the state itself, with no global involved. */
	public static function ownerOf(L:cpp.RawPointer<Lua_State>):FunkinLua {
		var st:ProxyState = states.get(stateId(L));
		return (st == null) ? null : st.owner;
	}

	/**
	 * One ELEMENT of a container `Convert` is pushing as a native Lua table.
	 *
	 * A class instance becomes a proxy so the table holds the live object; everything else
	 * marshals natively, and a nested container recurses back into `Convert` as another table.
	 * Without this the haxelib's own recursion pushed nil for any class it does not special-case,
	 * which is what made `onNotesGenerated` hand Lua a table of nils.
	 *
	 * EPHEMERAL: a container can be enormous (a chart's whole note list), and a cached proxy is
	 * pinned in the registry for the state's life. `__eq` compares the underlying objects, so
	 * re-proxying the same element still compares equal.
	 */
	static function pushElement(L:cpp.RawPointer<Lua_State>, v:Dynamic):Void
		pushHaxe(L, v, false, false);

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

	/** Stamps the metatable on top of the stack as one of ours. Leaves it in place. */
	static inline function markProxyMeta(L:cpp.RawPointer<Lua_State>):Void {
		Lua.pushinteger(L, MARK_VALUE);
		Lua.rawseti(L, -2, MARK_KEY);
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
		pushValue(L, stateOf(L), v, cached, proxyContainers);
	}

	/** The proxy state owning `L`, or null. The registry read the hot paths avoid by carrying it. */
	static inline function stateOf(L:cpp.RawPointer<Lua_State>):ProxyState {
		return states.get(stateId(L));
	}

	/**
	 * `pushHaxe` with the owning state already resolved.
	 *
	 * Every metatable callback already holds the `ProxyState` (it is reached through the userdata
	 * being indexed), so pushing a field value, a method result or an array element no longer costs
	 * a registry `getfield` on the state id -- which it did on every single one of them.
	 */
	static function pushValue(L:cpp.RawPointer<Lua_State>, st:ProxyState, v:Dynamic, cached:Bool = true, proxyContainers:Bool = true):Void {
		if (v == null) {
			Lua.pushnil(L);
			return;
		}

		// Direct type tests rather than `Type.typeof`. On hxcpp that CONSTRUCTS a `ValueType`, and
		// its `TClass(c)` / `TEnum(e)` carry a parameter -- so classifying an object allocated an
		// enum instance purely to be switched on and thrown away, on the hottest path in the bridge.
		// Each test below lowers to a single type check.
		if ((v is String)) {
			Lua.pushstring(L, (v : String));
			return;
		}
		if ((v is Int)) {
			Lua.pushinteger(L, (v : Int));
			return;
		}
		if ((v is Float)) { // after Int: every Int is also a Float
			Lua.pushnumber(L, (v : Float));
			return;
		}
		if ((v is Bool)) {
			Lua.pushboolean(L, v == true ? 1 : 0);
			return;
		}

		// A bare Haxe closure has no Lua-callable form (only a resolved MEMBER becomes one, in
		// `cachedIndex`). nil, which is what it marshalled to before.
		if (Reflect.isFunction(v)) {
			Lua.pushnil(L);
			return;
		}

		if (Reflect.isEnumValue(v)) {
			// An ephemeral proxy round-trips: `tostring()` gives the constructor name and handing it
			// back to Haxe yields the SAME enum value.
			//
			// Only on the direct-access path. The traditional API is deliberately byte-compatible
			// with upstream Psych, where an enum reads as nil; a stock mod testing `== nil` would
			// change behaviour if we handed it userdata there.
			if (proxyContainers)
				pushObject(L, st, v, INST_META, false);
			else
				Lua.pushnil(L);
			return;
		}

		// `Std.isOfType`, not `is`: the operator rejects a type parameter, and a bare `Class` is the
		// runtime value that matches any class reference.
		if (Std.isOfType(v, Class)) {
			// A class REFERENCE read out of a field. On the direct path it becomes a real class
			// proxy, so `:new()` and statics work exactly as they do for `import(...)`; the
			// traditional API keeps marshalling it, which yields a table of its static fields.
			if (proxyContainers)
				pushObject(L, st, v, CLASS_META, true);
			else
				Convert.toLua(L, v);
			return;
		}

		if (!proxyContainers) {
			// Traditional API: data containers and anonymous structures become native Lua values, so
			// stock scripts get real tables with working `#`, `ipairs` and `table.*`. Class instances
			// stay proxies regardless, so `getVar`/`getProperty` still return a live object.
			if ((v is Array) || (v is haxe.Constraints.IMap) || Type.getClass(v) == null)
				Convert.toLua(L, v);
			else
				pushObject(L, st, v, INST_META, cached);
			return;
		}

		// Direct-access path: everything left is proxied, ANONYMOUS STRUCTURES included. They used
		// to marshal to a table COPY, which silently swallowed writes -- chart sections and note
		// structs are typedefs, so `game.SONG.notes[0].mustHitSection = true` updated a throwaway.
		// `Reflect` reads and writes anonymous structures like any other object, and `pairs` walks
		// one through `Reflect.fields`.
		pushObject(L, st, v, INST_META, cached);
	}

	public static inline function pushClass(L:cpp.RawPointer<Lua_State>, cls:Dynamic):Void {
		if (cls == null) Lua.pushnil(L);
		else pushObject(L, stateOf(L), cls, CLASS_META, true);
	}

	static function pushObject(L:cpp.RawPointer<Lua_State>, st:ProxyState, obj:Dynamic, metaName:String, cached:Bool):Void {
		if (st == null) {
			Lua.pushnil(L);
			return;
		}
		var sid:Int = st.id;

		var handle:Null<Int> = st.objToHandle.get(obj);

		if (!cached) {
			// An object that ALREADY has a cached proxy is handed that one rather than a second
			// userdata: a method returning `this` (or a getter for an object the script has already
			// touched) used to allocate a fresh handle on every call. Reusing it also makes identity
			// hold for free, instead of relying on `__eq`.
			if (handle != null) {
				Lua.getfield(L, Lua.REGISTRYINDEX, CACHE_KEY); // [cache]
				Lua.rawgeti(L, -1, handle); // [cache, cached|nil]
				if (Lua.type(L, -1) == Lua.TUSERDATA) {
					Lua.remove(L, -2); // [ud]
					return;
				}
				Lua.pop(L, 2); // []
			}

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
			return false; // [] -- no metatable, nothing pushed

		Lua.rawgeti(L, -1, MARK_KEY); // [mt, mark|nil]
		var ok:Bool = (Lua.type(L, -1) == Lua.TNUMBER && Lua.tointeger(L, -1) == MARK_VALUE);
		Lua.pop(L, 2);
		return ok;
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
			pushValue(L, st, (i >= 0 && i < arr.length) ? arr[i] : null, false);
			return 1;
		}

		if (ptr[2] == 1)
			return cachedIndex(L, st, obj, false);

		// Ephemeral: no env cache, simple resolve.
		var key:String = keyAt(L, 2);
		if (key == null) {
			// Not usable as a member name, but it can still be a MAP KEY -- an ObjectMap is indexed
			// by object, which `pairs` now hands straight back as a proxy.
			pushValue(L, st, mapLookup(L, obj), false);
			return 1;
		}
		try {
			// An ephemeral proxy has no env to classify into (`group.members[i]` is a fresh userdata
			// each read), so the typed accessor is found by name instead of by interned id -- one map
			// lookup, against the reflection and boxing it saves.
			if (ProxyFields.get(L, ProxyFields.idOf(key), obj))
				return 1;

			// PropertyPath is the shared answer to "what is obj.key" -- the classic getProperty
			// family resolves through it too, so the two APIs cannot drift apart again.
			var f:Dynamic = PropertyPath.member(obj, key);
			if (Reflect.isFunction(f)) {
				Lua.pushvalue(L, 1);
				Lua.pushstring(L, key);
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCall), 2);
				return 1;
			}
			// Still consulted for a non-string key, which PropertyPath cannot express.
			if (f == null)
				f = mapLookup(L, obj);
			pushValue(L, st, f, false);
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
	//
	// A classified plain field is stored as its INTERNED ID, not as `true`: the name then comes
	// from `st.keyNames` instead of being rebuilt from Lua's C string, which was a Haxe String
	// allocation on every read of every field.
	static function cachedIndex(L:cpp.RawPointer<Lua_State>, st:ProxyState, obj:Dynamic, isClass:Bool):Int {
		Lua.getfenv(L, 1); // [env]
		Lua.pushvalue(L, 2); // [env, key]
		Lua.rawget(L, -2); // [env, entry]
		var et:Int = Lua.type(L, -1);
		if (et == Lua.TFUNCTION) {
			Lua.remove(L, -2); // [closure]
			return 1;
		}
		if (et == Lua.TNUMBER) {
			// Known plain field: read its current value (no method machinery, no key rebuild).
			var id:Int = Lua.tointeger(L, -1);
			Lua.pop(L, 2);

			// A typed accessor first: no reflection, and no `Dynamic` boxing of the value.
			if (!isClass && ProxyFields.get(L, fastAt(st, id), obj))
				return 1;

			var key:String = internedAt(st, id);
			if (key == null) {
				Lua.pushnil(L);
				return 1;
			}
			var v:Dynamic = isClass ? Reflect.field(obj, key) : PropertyPath.member(obj, key);
			if (v == null && !isClass)
				v = mapLookup(L, obj);
			pushValue(L, st, v);
			return 1;
		}
		Lua.pop(L, 1); // [env]

		var key:String = keyAt(L, 2);
		if (key == null) {
			Lua.pop(L, 1); // [] -- drop the env
			// Not usable as a member name, but it can still be a MAP KEY (see instanceIndex).
			pushValue(L, st, isClass ? null : mapLookup(L, obj), false);
			return 1;
		}
		try {
			if (isClass && key == "new") {
				Lua.pushvalue(L, 1); // self -> [env, self]
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(constructorCall), 1); // [env, closure]
				return cacheAndReturnClosure(L);
			}

			var f:Dynamic = isClass ? Reflect.field(obj, key) : PropertyPath.member(obj, key);
			if (Reflect.isFunction(f)) {
				var fid:Int = st.nextFunc++;
				st.funcs.set(fid, f);
				Lua.pushvalue(L, 1); // self -> [env, self]
				Lua.pushinteger(L, fid); // [env, self, fid]
				Lua.pushcclosure(L, cpp.Callable.fromStaticFunction(methodCallFast), 2); // [env, closure]
				return cacheAndReturnClosure(L);
			}

			// Plain field: tag it with its interned id so future reads skip the function check
			// AND the key rebuild. `__newindex` reads the same tag.
			Lua.pushvalue(L, 2); // [env, key]
			Lua.pushinteger(L, st.intern(key)); // [env, key, id]
			Lua.rawset(L, -3); // env[key]=id -> [env]
			Lua.pop(L, 1); // []
			if (f == null && !isClass)
				f = mapLookup(L, obj);
			pushValue(L, st, f);
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
	// Non-array objects report 0. `__pairs`/`__ipairs` do NOT exist in 5.1, which
	// is why those two are patched in Lua instead (see `installIterators`).
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

	/** An interned name by id, or null when the id is not one we handed out. */
	static inline function internedAt(st:ProxyState, id:Int):String {
		return (id >= 0 && id < st.keyNames.length) ? st.keyNames[id] : null;
	}

	/** The typed-accessor id for an interned key, or `ProxyFields.NONE`. */
	static inline function fastAt(st:ProxyState, id:Int):Int {
		return (id >= 0 && id < st.keyFast.length) ? st.keyFast[id] : ProxyFields.NONE;
	}

	/**
	 * Whether `obj.key` resolves to a method, for the write path's one-time classification.
	 *
	 * A throwing getter answers "no": it is certainly not a method, and letting the exception unwind
	 * out of a C callback would be undefined behaviour. The write that follows reports it properly.
	 */
	static function isMethod(obj:Dynamic, key:String):Bool {
		try {
			return Reflect.isFunction(PropertyPath.member(obj, key));
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
	 * Field WRITE on a proxy.
	 *
	 * Shares the read path's per-object env classification: a key already known to be a plain field
	 * is stored there as its interned id, so a repeat write skips rebuilding the name from Lua's C
	 * string. Writes had no fast path at all, and in a modchart they are as hot as reads -- `spr.x`
	 * assigned every frame paid a Haxe String allocation each time.
	 *
	 * The env is only consulted for a CACHED proxy. An ephemeral one was never given its own env
	 * table, and `lua_getfenv` on it hands back the GLOBALS table, where an unrelated global of the
	 * same name would be mistaken for a classification.
	 */
	static function instanceNewIndex(L:cpp.RawPointer<Lua_State>):Int {
		var ptr:cpp.Pointer<Int> = ptrAt(L, 1);
		var st:ProxyState = states.get(ptr[0]);
		var obj:Dynamic = (st == null) ? null : st.handleToObj.get(ptr[1]);
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

		var key:String = null;
		var unclassified:Bool = false;
		var triedFast:Bool = false;
		if (ptr[2] == 1) {
			Lua.getfenv(L, 1); // [env]
			Lua.pushvalue(L, 2); // [env, key]
			Lua.rawget(L, -2); // [env, entry]
			var et:Int = Lua.type(L, -1);
			var id:Int = (et == Lua.TNUMBER) ? Lua.tointeger(L, -1) : -1;
			Lua.pop(L, 2); // []

			if (id >= 0) {
				// A typed accessor first: a virtual `set_*` with no reflection and no boxing.
				if (ProxyFields.set(L, fastAt(st, id), obj))
					return 0;
				triedFast = true;
				key = internedAt(st, id);
			} else
				unclassified = (et == Lua.TNIL); // TFUNCTION means the read path owns it: a method
		}

		if (key == null) {
			key = keyAt(L, 2);
			if (key == null)
				return 0;

			// Classify it for next time, exactly as a read would, so a field only ever WRITTEN still
			// gets the fast path. Only for a genuine plain field: tagging a method name would make a
			// later read take the field branch and hand back nil instead of a callable.
			if (unclassified && !isMethod(obj, key)) {
				Lua.getfenv(L, 1); // [env]
				Lua.pushvalue(L, 2); // [env, key]
				Lua.pushinteger(L, st.intern(key)); // [env, key, id]
				Lua.rawset(L, -3); // env[key]=id -> [env]
				Lua.pop(L, 1); // []
			}
		}

		try {
			// Reached by NAME when there was no interned id to reach it by: an ephemeral proxy (which
			// has no env at all) or the very first write to a key on a cached one.
			if (!triedFast && ProxyFields.set(L, ProxyFields.idOf(key), obj))
				return 0;

			PropertyPath.setMember(obj, key, unwrap(L, 3));
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
		pushValue(L, st, ret, false);
		return 1;
	}

	// Simple method closure (ephemeral proxies): upvalues (self userdata, key).
	static function methodCall(L:cpp.RawPointer<Lua_State>):Int {
		var self:Int = Lua.upvalueindex(1);
		var st:ProxyState = stAt(L, self);
		var obj:Dynamic = objAt(L, self);
		var key:String = Lua.tostring(L, Lua.upvalueindex(2)).toString();
		if (obj == null)
			return 0;

		var nargs:Int = Lua.gettop(L);
		var start:Int = (nargs >= 1 && Lua.rawequal(L, 1, self) == 1) ? 2 : 1;

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
		pushValue(L, st, ret, false);
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
		return construct(L, stAt(L, 1), objAt(L, 1), 2);
	}

	static function constructorCall(L:cpp.RawPointer<Lua_State>):Int {
		var self:Int = Lua.upvalueindex(1);
		return construct(L, stAt(L, self), objAt(L, self), 1);
	}

	static function construct(L:cpp.RawPointer<Lua_State>, st:ProxyState, cls:Dynamic, start:Int):Int {
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
		pushValue(L, st, inst, false); // freshly constructed -> ephemeral
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
