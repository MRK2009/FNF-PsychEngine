#if LUA_ALLOWED
package scripting.lua;

import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;

/**
 * C-callable dispatcher for every Lua-exposed Haxe function.
 *
 * Each call site registered via `Lua_helper.add_callback` pushes a closure
 * with the callback name as upvalue 1 and points at this function. The
 * dispatcher then looks the name up first in the global
 * `Lua_helper.callbacks` map, then falls back to the `lastCalledScript`'s
 * per-instance `callbacks` map (set by `FunkinLua.addLocalCallback`),
 * and finally scans every running script's `callbacks` map for one whose
 * `lua` state pointer matches.
 */
class CallbackHandler {
	// Reusable Array<Dynamic> pool for the args buffer passed to
	// Reflect.callMethod. The dispatcher is reentrant (a Haxe callback
	// can invoke a Lua function which calls another Haxe callback), so
	// each level pops its own array off the pool and returns it after
	// the call. Exception path skips the return -- the array is just
	// GC'd, no correctness issue.
	static final argPool:Array<Array<Dynamic>> = [];

	public static function call(L:cpp.RawPointer<Lua_State>):Int {
		final fname:String = Lua.tostring(L, Lua.upvalueindex(1));

		try {
			var cbf:Dynamic = Lua_helper.callbacks.get(fname);

			// Local functions have the lowest priority -- only resolve the owning script
			// when no global callback owns the name.
			if (cbf == null) {
				// The owner comes off `L` itself (LuaProxy keeps it on the state's registry entry).
				// This used to go through `ScriptHost.current` plus a linear scan plus a
				// `lastCalledScript` guess, so a callback firing while a DIFFERENT host was current --
				// a tween or timer that outlived its state -- resolved to nothing and silently
				// returned no values.
				final owner:FunkinLua = LuaProxy.ownerOf(L);
				if (owner != null) {
					cbf = owner.callbacks.get(fname);
					// Mirror linc_luajit behaviour: dispatcher updates lastCalledScript
					// so per-script API helpers route correctly.
					FunkinLua.lastCalledScript = owner;
				}
			}

			if (cbf == null)
				return 0;

			final nparams:Int = Lua.gettop(L);
			final args:Array<Dynamic> = (argPool.length > 0 ? argPool.pop() : []);
			if (args.length != nparams) args.resize(nparams);

			for (i in 0...nparams)
				args[i] = LuaProxy.unwrap(L, i + 1);

			final ret:Dynamic = Reflect.callMethod(null, cbf, args);

			args.resize(0);
			argPool.push(args);

			if (ret != null) {
				// Traditional psychlua return boundary: data containers (arrays/maps)
				// come back as native 1-based Lua tables so stock mods get real
				// tables; class instances stay live proxies (e.g. getVar). This keeps
				// the direct-access proxy system from leaking into the classic API.
				LuaProxy.pushHaxe(L, ret, true, false);
				return 1;
			}
		} catch (e:Dynamic) {
			// `Dynamic`, not `haxe.Exception`: on hxcpp a null dereference inside a callback throws a
			// NATIVE exception, which `catch (e:haxe.Exception)` does not match. Those escaped this
			// handler, unwound past the hook and surfaced as a bare `C++ exception` naming no callback
			// -- which is what a script that reaches a missing object reports today.
			var detail:String = (e is haxe.Exception) ? cast(e, haxe.Exception).details() : Std.string(e);
			if (Lua_helper.sendErrorsToLua) {
				LuaL.error(L, '%s', 'CALLBACK ERROR ($fname)! $detail');
				return 0;
			}
			throw e;
		}
		return 0;
	}
}
#end
