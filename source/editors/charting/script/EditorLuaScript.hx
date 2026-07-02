package editors.charting.script;

#if LUA_ALLOWED
import llua.Convert;
import llua.Lua;
import llua.LuaL;
import llua.State;
import psychlua.LuaProxy;

/**
	A lean chart-editor Lua script: real-Lua (raw LuaProxy) mode ONLY - the object bridge
	(`import('pkg.Class')`, proxied `editor`/`api` globals with cached method closures) with
	NO legacy PsychLua callback surface. Mod trust (`ModSecurity`) is enforced like gameplay
	scripts.
**/
final class EditorLuaScript {
	/** The Lua state (null after `stop` or a blocked load). **/
	public var lua:State = null;

	/** The script file path. **/
	public var scriptName:String = '';

	/** The owning mod folder, when loaded from a mod. **/
	public var modFolder:String = null;

	/** `true` once stopped or blocked; calls become no-ops. **/
	public var closed:Bool = false;

	/**
		@param path the .lua file to load and run
		@param globals name/value pairs pushed as proxied globals before the script runs
	**/
	public function new(path:String, globals:Array<{name:String, value:Dynamic}>) {
		scriptName = path.trim();

		var myFolder:Array<String> = scriptName.split('/');
		#if MODS_ALLOWED
		if (myFolder[0] + '/' == Paths.mods() && (Mods.currentModDirectory == myFolder[1] || Mods.getGlobalMods().contains(myFolder[1])))
			modFolder = myFolder[1];

		if (modFolder != null && backend.ModSecurity.isBlocked(modFolder)) {
			closed = true;
			trace('EditorLuaScript: blocked $scriptName -- mod "$modFolder" not trusted');
			return;
		}
		#end

		lua = LuaL.newstate();
		LuaL.openlibs(lua);
		LuaProxy.setup(lua);

		for (g in globals)
			set(g.name, g.value);
		set('modFolder', modFolder);

		try {
			var result:Dynamic = LuaL.dofile(lua, scriptName);
			var resultStr:String = Lua.tostring(lua, -1);
			if (resultStr != null && result != 0) {
				trace('Error on editor lua script $scriptName:\n$resultStr');
				stop();
				return;
			}
		} catch (e:Dynamic) {
			trace('EditorLuaScript: $e');
			stop();
			return;
		}
		trace('editor lua script loaded: $scriptName');
	}

	/**
		Pushes a value as a global (Haxe objects become live proxies).
		@param variable the global name
		@param data the value
	**/
	public function set(variable:String, data:Dynamic):Void {
		if (lua == null)
			return;
		LuaProxy.pushHaxe(lua, data);
		Lua.setglobal(lua, variable);
	}

	/** Calls a global function if the script defines it (missing = silent no-op). **/
	public function call(func:String, args:Array<Dynamic>):Void {
		if (closed || lua == null)
			return;
		try {
			Lua.getglobal(lua, func);
			if (Lua.type(lua, -1) != Lua.TFUNCTION) {
				Lua.pop(lua, 1);
				return;
			}
			for (arg in args)
				Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, args.length, 1, 0);
			if (status != Lua.OK) {
				trace('EditorLuaScript ERROR ($scriptName / $func): ${Lua.tostring(lua, -1)}');
				Lua.pop(lua, 1);
				return;
			}
			Lua.pop(lua, 1);
		} catch (e:Dynamic) {
			trace(e);
		}
	}

	/** Disposes the proxy registry and closes the Lua state. **/
	public function stop():Void {
		closed = true;
		if (lua == null)
			return;
		LuaProxy.dispose(lua);
		Lua.close(lua);
		lua = null;
	}
}
#end
