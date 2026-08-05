package scripting;
#if SCRIPT_COMPILER
import haxe.io.Bytes;
import hxscript.Environment;
import hxscript.Module;
import hxscript.compile.Cppia;
import hxscript.compile.CppiaInput;
import hxscript.compile.CppiaResult;
import hxscript.syntax.Expr;
#end
/**
 * Compiles scripted classes to cppia so hxcpp JIT-compiles them instead of the tree being walked.
 *
 * Everything here is inert without `SCRIPT_COMPILER`, and a module the compiler cannot express keeps
 * being interpreted, so turning it on changes speed and nothing else.
 */
class ScriptCompiler {
	/** Whether this build can compile scripts at all. */
	public static var available(get, never):Bool;
	/** Paths of the classes that compiled, mapped to the loaded class. */
	static var compiled:Map<String, Class<Dynamic>> = new Map();
	/** Modules that could not compile, mapped to the reason, for the debug console. */
	public static var skipped:Map<String, String> = new Map();
	static var jitEnabled:Bool = false;
	static function get_available():Bool {
		#if SCRIPT_COMPILER
		return true;
		#else
		return false;
		#end
	}
	#if SCRIPT_COMPILER
	/**
	 * Compiles a batch of freshly loaded modules and registers whatever came out.
	 *
	 * Gated because its signature names an hxscript type whose import is gated too. The query
	 * methods below deliberately are not: a script asks whether it is compiled in every build, and
	 * in one without the compiler the honest answer is no rather than a missing class.
	 *
	 * @param modules The modules to compile.
	 */
	public static function compile(modules:Array<Module>, env:Environment):Void {
		if (modules.length == 0)
			return;
		if (!jitEnabled) {
			jitEnabled = true;
			cpp.cppia.Host.enableJit(true);
		}
		var fresh:Array<Module> = [];
		var inputs:Array<CppiaInput> = [];
		for (module in modules) {
			if (settled(module, env))
				continue;

			fresh.push(module);
			inputs.push({name: module.name, decls: module.decls});
		}

		if (inputs.length > 0) {
			var started:Float = haxe.Timer.stamp();
			var outside:Array<String> = [];
			for (path in compiled.keys())
				outside.push(path);

			var result:CppiaResult = Cppia.compile(inputs, ambientTypes(), outside, ambientStatics());
			for (entry in result.skipped)
				skipped.set(entry.name, entry.reason);
			if (result.bytes != null)
				load(result.bytes, fresh, env);
			report(inputs.length, result, (haxe.Timer.stamp() - started) * 1000);
		}

		var was:Bool = env.substituting;
		env.substituting = anyCompiled(env);

		if (env.substituting && !was)
			ScriptError.show('Script compiler: compiled classes are now the ones that run', 0xFF66DD66);
	}

	/**
	 * Whether a module's classes are already compiled and need no second pass.
	 *
	 * A state is re-read every time it is entered, which would otherwise offer the same classes again
	 * in a batch of their own -- where they can no longer see the classes they were compiled beside,
	 * so they would be refused and reported as interpreted while their compiled form was sitting right
	 * there. The re-read is only wanted for its declarations.
	 *
	 * Skipping the work is not the same as skipping the binding. This map outlives any one world, so a
	 * world built after a reload finds everything already compiled and would be handed nothing: the
	 * classes exist, every report says so, and not one of them is what runs, because the interpreter
	 * reads the world's own map and that map is empty. So the classes are bound here as well as
	 * where they are built.
	 *
	 * @param module The freshly read module.
	 * @param env The world it belongs to, which is given the classes it is not being handed.
	 * @return Whether every class it declares is compiled already.
	 */
	static function settled(module:Module, env:Environment):Bool {
		var paths:Array<String> = declaredPaths(module);
		if (paths.length == 0)
			return false;

		for (path in paths) {
			if (!compiled.exists(path))
				return false;
		}

		for (path in paths)
			env.compiled.set(path, compiled.get(path));

		return true;
	}

	/**
	 * Whether anything in a world compiled, which is when its scripted classes must start being
	 * reached through their compiled form.
	 *
	 * The hazard is a class existing both compiled and interpreted at once, the two halves disagreeing
	 * about statics and identity. What rules that out is not every class being compiled -- it is every
	 * reference going the same way, including from the classes still interpreted. So this asks whether
	 * there is anything to substitute at all, and a module left interpreted simply has nothing to
	 * substitute to: the emitter refuses anything that names it, so no compiled class can hold a
	 * second opinion about it.
	 *
	 * @param env The world to weigh.
	 * @return Whether any of its classes has a compiled form.
	 */
	static function anyCompiled(env:Environment):Bool {
		// The world's own map, not the global one. They differ exactly when a world was handed nothing
		// because the work was already done for a previous one, and answering from the global map
		// there announces a substitution that cannot happen.
		for (module in env.modules) {
			for (path in declaredPaths(module)) {
				if (env.compiled.exists(path))
					return true;
			}
		}

		return false;
	}
	#end
	/** Whether a scripted class is running compiled rather than interpreted. */
	public static function isCompiled(path:String):Bool {
		return compiled.exists(path);
	}
	/**
	 * A readable account of what is compiled and what is still interpreted.
	 *
	 * @return One line per class, compiled first, with the reason beside anything that is not.
	 */
	public static function summary():String {
		var lines:Array<String> = [];
		var names:Array<String> = [for (path in compiled.keys()) path];
		names.sort(Reflect.compare);
		for (path in names)
			lines.push('compiled     $path');
		var refused:Array<String> = [for (name in skipped.keys()) name];
		refused.sort(Reflect.compare);
		for (name in refused)
			lines.push('interpreted  $name  (${skipped.get(name)})');
		if (lines.length == 0)
			return 'Script compiler: nothing loaded yet.';
		return lines.join('\n');
	}
	#if SCRIPT_COMPILER
	/**
	 * Puts the outcome where it can be seen: the log, and the in-game debug overlay.
	 *
	 * Anything left interpreted is named with its reason, since that is the only way to find out
	 * which construct a mod is paying for.
	 *
	 * @param offered How many modules were put forward.
	 * @param result What came back.
	 * @param ms How long compiling took.
	 */
	static function report(offered:Int, result:CppiaResult, ms:Float):Void {
		var took:String = Std.string(Math.round(ms * 100) / 100);
		if (result.bytes == null && result.compiled.length == 0) {
			ScriptError.show('Script compiler: all $offered module(s) interpreted', 0xFFFFCC00);
		} else {
			var size:String = Std.string(Math.round(result.bytes.length / 102.4) / 10);
			ScriptError.show('Script compiler: ${result.compiled.length}/$offered compiled in $took ms (${size} KB)', 0xFF66DD66);
		}
		for (entry in result.skipped)
			ScriptError.show('  interpreted: ${entry.name} -- ${entry.reason}', 0xFFFFCC00);
	}
	#end
	/** The compiled class for a scripted path, or null when it is being interpreted. */
	public static function resolve(path:String):Class<Dynamic> {
		return compiled.get(path);
	}
	/** Forgets every compiled class, for a mod reload. */
	public static function dispose():Void {
		compiled = new Map();
		skipped = new Map();
	}
	#if SCRIPT_COMPILER
	/**
	 * Type paths a script may name without importing them.
	 *
	 * `TYPE_IMPORTS` covers the ones registered as global imports. `File` and `FileSystem` are not
	 * among them: `shared` binds those names to class values instead, so they have to be named here
	 * or every script touching the disk is refused.
	 *
	 * @return Full paths, each usable under its last segment.
	 */
	static function ambientTypes():Array<String> {
		var paths:Array<String> = ScriptGlobals.TYPE_IMPORTS.copy();
		#if android
		paths.push('File=mobile.backend.ScriptFile');
		paths.push('FileSystem=mobile.backend.ScriptFileSystem');
		#elseif sys
		paths.push('File=sys.io.File');
		paths.push('FileSystem=sys.FileSystem');
		#end
		return paths;
	}

	/**
	 * Bare names the engine puts in every interpreter, paired with the static they really live on.
	 *
	 * Compiled code has no interpreter to have anything injected into it, so a class using one of
	 * these would be refused, and one refusal costs the whole world its substitution. Reaching the
	 * static directly is both faster than a variable lookup and the only way these can be compiled.
	 *
	 * `buildScripted`, `scriptedClass` and `getModSetting` are absent on purpose: each closes over the
	 * mod that owns the script, so there is no single static to point at. A class calling one stays
	 * interpreted.
	 *
	 * @return Entries written `name=owner.path::field`.
	 */
	static function ambientStatics():Array<String> {
		return [
			'controls=backend.Controls::instance',
			'buildTarget=scripting.ScriptGlobals::buildTarget',
			'getVar=scripting.ScriptGlobals::getVar',
			'setVar=scripting.ScriptGlobals::setVar',
			'removeVar=scripting.ScriptGlobals::removeVar',
			'debugPrint=scripting.ScriptGlobals::debugPrint',
			'switchToState=scripting.ScriptGlobals::switchToState',
			'openScriptedSubstate=scripting.ScriptGlobals::openScriptedSubstate',
			'switchState=scripting.ScriptGlobals::switchState',
			'exitToEngine=scripting.ScriptedStates::exitToEngine',
			'launchMod=scripting.ScriptedStates::launchMod',
			'setExitTarget=states.PlayState::setExitTarget',
			'exitToState=states.PlayState::exitToState',
			'Function_Stop=scripting.lua.LuaUtils::Function_Stop',
			'Function_Continue=scripting.lua.LuaUtils::Function_Continue',
			'Function_StopLua=scripting.lua.LuaUtils::Function_StopLua',
			'Function_StopHScript=scripting.lua.LuaUtils::Function_StopHScript',
			'Function_StopAll=scripting.lua.LuaUtils::Function_StopAll',
			'keyboardJustPressed=scripting.ScriptGlobals::keyboardJustPressed',
			'keyboardPressed=scripting.ScriptGlobals::keyboardPressed',
			'keyboardReleased=scripting.ScriptGlobals::keyboardReleased',
			'anyGamepadJustPressed=scripting.ScriptGlobals::anyGamepadJustPressed',
			'anyGamepadPressed=scripting.ScriptGlobals::anyGamepadPressed',
			'anyGamepadReleased=scripting.ScriptGlobals::anyGamepadReleased',
			'gamepadAnalogX=scripting.ScriptGlobals::gamepadAnalogX',
			'gamepadAnalogY=scripting.ScriptGlobals::gamepadAnalogY',
			'gamepadJustPressed=scripting.ScriptGlobals::gamepadJustPressed',
			'gamepadPressed=scripting.ScriptGlobals::gamepadPressed',
			'gamepadReleased=scripting.ScriptGlobals::gamepadReleased',
			'keyJustPressed=scripting.ScriptGlobals::keyJustPressed',
			'keyPressed=scripting.ScriptGlobals::keyPressed',
			'keyReleased=scripting.ScriptGlobals::keyReleased'
		];
	}

	/**
	 * Loads a compiled module and binds each class it defines to its scripted path.
	 *
	 * Each class is recorded twice, and both matter. The map here answers what was compiled, for
	 * `instantiate` and for anything asking. The world's own map is what the interpreter reads when
	 * it builds an object or reaches a static, so a class missing from THAT one is compiled, loaded,
	 * reported as compiled, and never runs.
	 *
	 * @param bytes The compiled module.
	 * @param modules The modules it was built from, read for the paths to bind.
	 * @param env The world the classes belong to.
	 */
	static function load(bytes:Bytes, modules:Array<Module>, env:Environment):Void {
		try {
			var loaded = cpp.cppia.Module.fromData(bytes.getData());
			loaded.boot();
			for (module in modules) {
				for (path in declaredPaths(module)) {
					var cls:Class<Dynamic> = loaded.resolveClass(path);
					if (cls != null) {
						compiled.set(path, cls);
						env.compiled.set(path, cls);
					}
				}
			}
		} catch (e:Dynamic) {
			scripting.hscript.HScript.error('Script compiler: could not load compiled module ($e)');
			dump(bytes);
		}
	}
	/**
	 * Writes a module that would not load, so the bytes that failed can be read back.
	 *
	 * The loader reports which reference it could not resolve but not what was emitted for it, and
	 * that is the difference worth seeing.
	 *
	 * @param bytes The module that failed.
	 */
	static function dump(bytes:Bytes):Void {
		try {
			var path:String = 'script-compiler-failed.cppia';
			sys.io.File.saveBytes(path, bytes);
			ScriptError.show('Script compiler: wrote the failed module to $path', 0xFFFFCC00);
		} catch (e:Dynamic) {}
	}

	/** Dotted paths of every class a module declares. */
	static function declaredPaths(module:Module):Array<String> {
		var pack:String = '';
		var paths:Array<String> = [];
		for (decl in module.decls) {
			switch (decl.d) {
				case DPackage(path):
					pack = path.join('.');
				case DClass(c):
					paths.push(pack.length > 0 ? pack + '.' + c.name : c.name);
				case _:
			}
		}
		return paths;
	}
	#end
}
