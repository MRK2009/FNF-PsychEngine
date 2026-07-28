package scripting;

#if HSCRIPT_ALLOWED
import insanity.syntax.Expr.ImportMode;
import insanity.types.TypeCollection;

/**
 * The single definition of what a script can see without setting anything up.
 *
 * Two halves:
 *  - `TYPE_IMPORTS` are registered as insanity global imports, so every script -- a plain
 *    `.hx` mod script, a scripted state, a scripted class -- resolves these names the same
 *    way, with no per-context injection list to keep in sync.
 *  - `inject()` supplies the values and helper functions a scripted class needs
 *    (`controls`, `getVar`, `switchToState`, ...).
 *
 * Types NOT listed here are still reachable: `import` resolves against every type compiled
 * into the engine (`insanity.types.TypeCollection`), which is how real Haxe behaves.
 */
class ScriptGlobals {
	/**
	 * Names every script resolves unqualified. Mirrors `source/import.hx` -- what engine
	 * code itself sees -- plus the gameplay and UI types scripts reach for.
	 *
	 * `File` and `FileSystem` are deliberately absent: `HScript.preset()` binds those names to
	 * Psych-specific replacements, and an import would shadow them because imports resolve ahead
	 * of variables.
	 */
	public static final TYPE_IMPORTS:Array<String> = [
		// source/import.hx
		'backend.Paths',
		'backend.Controls',
		'backend.CoolUtil',
		'backend.MusicBeatState',
		'backend.MusicBeatSubstate',
		'backend.CustomFadeTransition',
		'backend.ClientPrefs',
		'backend.Conductor',
		'backend.Mania',
		'backend.BaseStage',
		'backend.Difficulty',
		'backend.Mods',
		'backend.Language',
		// NOTE: backend.DebugPrefs is deliberately absent -- it's on ModSecurity's blocklist
		// (a debug-only settings store scripts must not reach), so it's never a global import.
		'objects.Alphabet',
		'objects.BGSprite',
		'states.PlayState',
		'states.LoadingState',
		'flixel.FlxG',
		'flixel.FlxSprite',
		'flixel.FlxCamera',
		'flixel.sound.FlxSound',
		'flixel.math.FlxMath',
		'flixel.math.FlxPoint',
		'flixel.util.FlxTimer',
		// A real abstract in scripts, not a stand-in: see macros.ScriptedAbstractMacro.
		'flixel.util.FlxColor',
		'flixel.text.FlxText',
		'flixel.tweens.FlxEase',
		'flixel.tweens.FlxTween',
		'flixel.group.FlxSpriteGroup',
		'flixel.addons.transition.FlxTransitionableState',

		// Engine types scripts build things out of.
		'backend.PsychCamera',
		'backend.Song',
		'backend.Highscore',
		'backend.WeekData',
		'objects.Character',
		'objects.StrumLine',
		'objects.Bar',
		'objects.HealthIcon',
		'objects.NoteSplash',
		'psychlua.CustomSubstate',

		// Flixel types the engine itself rarely names but scripts do.
		'flixel.FlxBasic',
		'flixel.FlxObject',
		'flixel.group.FlxGroup',
		'flixel.ui.FlxButton',
		'flixel.ui.FlxBar',
		'flixel.addons.display.FlxBackdrop',
		'flixel.effects.FlxFlicker',
		'flixel.util.FlxSort',
		'flixel.util.FlxStringUtil',

		// OpenFL -- display, filters/shaders, geometry, assets. What a script reaches for when
		// it drops below Flixel (custom rendering, blend modes, filters, matrices). Entries not
		// compiled into this build are skipped at register() time, so listing extra is harmless.
		'openfl.display.Sprite',
		'openfl.display.Bitmap',
		'openfl.display.BitmapData',
		'openfl.display.BlendMode',
		'openfl.display.Shader',
		'openfl.display.Graphics',
		'openfl.filters.ShaderFilter',
		'openfl.filters.BlurFilter',
		'openfl.filters.GlowFilter',
		'openfl.filters.ColorMatrixFilter',
		'openfl.filters.DropShadowFilter',
		'openfl.geom.Matrix',
		'openfl.geom.Rectangle',
		'openfl.geom.Point',
		'openfl.geom.ColorTransform',
		'openfl.text.TextField',
		'openfl.text.TextFormat',
		'openfl.utils.Assets',
		'openfl.media.Sound',
		'openfl.events.Event',
		'openfl.events.MouseEvent',

		// Lime -- system, app, assets, low-level math.
		'lime.app.Application',
		'lime.system.System',
		'lime.utils.Assets',
		'lime.math.Rectangle',
		'lime.math.Vector2',
	];

	/**
	 * Registers `TYPE_IMPORTS` with insanity. Called once from `HScript.setupConfig()`.
	 * Entries that aren't in the build are skipped rather than left to fail at import
	 * time, where an unknown type aborts the whole script.
	 */
	public static function register():Void {
		for (path in TYPE_IMPORTS) {
			if (TypeCollection.main.fromPath(path) == null) {
				trace('ScriptGlobals: skipping $path, not compiled into this build');
				continue;
			}

			// A blocklisted class must never be a global import: it would resolve on every
			// interpreter setup and log a "blacklisted" warning each time (and shouldn't be
			// reachable anyway).
			#if MODS_ALLOWED
			if (backend.ModSecurity.BLOCKED_CLASSES.exists(path))
				continue;
			#end

			insanity.Config.globalImports.set(path, ImportMode.INormal);
		}
	}

	/**
	 * Everything a script can see that does not depend on which kind of script it is.
	 *
	 * `HScript.preset()` and `inject()` both used to answer this question, separately, and had
	 * drifted: `preset` owned the keyboard and gamepad helpers and `getModSetting`, `inject` owned
	 * the navigation helpers, and adding anything to one meant remembering to add it to the other.
	 * Both now feed this one definition their own sink.
	 *
	 * @param set   Where to put each binding. An ordinary script writes into its interpreter, a
	 *              scripted class into its world's variable table.
	 * @param mod   The mod the script belongs to. `buildScripted` and `getModSetting` resolve
	 *              against it, so a mod always reaches its OWN classes and settings rather than
	 *              whichever mod happens to be the current directory.
	 */
	public static function shared(set:(String, Dynamic) -> Void, ?mod:String):Void {
		// Names bound to Psych-specific replacements (see TYPE_IMPORTS).
		#if android
		set('File', mobile.backend.ScriptFile);
		set('FileSystem', mobile.backend.ScriptFileSystem);
		#elseif sys
		set('File', File);
		set('FileSystem', FileSystem);
		#end
		set('controls', Controls.instance);
		set('buildTarget', psychlua.LuaUtils.getBuildTarget());

		// Static references, not inline closures. An anonymous closure allocates every time the
		// expression is evaluated -- once per binding per script load, so a modpack with a dozen
		// scripts paid a few hundred small allocations for functions that capture nothing. hxcpp
		// caches a static function's `_dyn` object, so each of these allocates once for the process.
		// The three below that close over `mod` genuinely need to.
		set('getVar', getVar);
		set('setVar', setVar);
		set('removeVar', removeVar);
		set('debugPrint', debugPrint);

		set('switchToState', switchToState);
		set('openScriptedSubstate', openScriptedSubstate);
		set('switchState', switchState);
		set('exitToEngine', ScriptedStates.exitToEngine);
		set('launchMod', ScriptedStates.launchMod);

		set('buildScripted', function(path:String, ?args:Array<Dynamic>):Dynamic return ScriptRegistry.instantiate(path, args, mod));
		set('scriptedClass', function(path:String):Dynamic return ScriptRegistry.resolveClass(path, mod));

		set('setExitTarget', states.PlayState.setExitTarget);
		set('exitToState', states.PlayState.exitToState);

		set('getModSetting', function(saveTag:String, ?modName:String):Dynamic {
			if (modName == null) {
				if (mod == null) {
					ScriptError.error('Script', 'getModSetting: Argument #2 is null and script is not inside a packed Mod folder!');
					return null;
				}
				modName = mod;
			}
			return psychlua.LuaUtils.getModSetting(saveTag, modName);
		});

		sharedInput(set);

		set('Function_Stop', psychlua.LuaUtils.Function_Stop);
		set('Function_Continue', psychlua.LuaUtils.Function_Continue);
		set('Function_StopLua', psychlua.LuaUtils.Function_StopLua);
		set('Function_StopHScript', psychlua.LuaUtils.Function_StopHScript);
		set('Function_StopAll', psychlua.LuaUtils.Function_StopAll);
	}

	/**
		Keyboard, gamepad and note-control polling.

		Static references for the same reason as `shared`'s bindings: none of these capture anything,
		so an inline closure would have allocated one object per binding per script load.
	**/
	static function sharedInput(set:(String, Dynamic) -> Void):Void {
		set('keyboardJustPressed', keyboardJustPressed);
		set('keyboardPressed', keyboardPressed);
		set('keyboardReleased', keyboardReleased);

		set('anyGamepadJustPressed', anyGamepadJustPressed);
		set('anyGamepadPressed', anyGamepadPressed);
		set('anyGamepadReleased', anyGamepadReleased);

		set('gamepadAnalogX', gamepadAnalogX);
		set('gamepadAnalogY', gamepadAnalogY);
		set('gamepadJustPressed', gamepadJustPressed);
		set('gamepadPressed', gamepadPressed);
		set('gamepadReleased', gamepadReleased);

		set('keyJustPressed', keyJustPressed);
		set('keyPressed', keyPressed);
		set('keyReleased', keyReleased);
	}

	static function getVar(name:String):Dynamic {
		return MusicBeatState.getVariables().get(name);
	}

	static function setVar(name:String, value:Dynamic):Dynamic {
		MusicBeatState.getVariables().set(name, value);
		return value;
	}

	static function removeVar(name:String):Bool {
		if (MusicBeatState.getVariables().exists(name)) {
			MusicBeatState.getVariables().remove(name);
			return true;
		}
		return false;
	}

	static function debugPrint(text:String, ?color:flixel.util.FlxColor):Void {
		ScriptError.show(text, color == null ? flixel.util.FlxColor.WHITE : color);
	}

	// Wrappers rather than direct references: the engine functions take a further `scope`/state
	// argument that is not part of the script-facing signature.
	static function switchToState(name:String, ?args:Array<Dynamic>):Bool
		return ScriptedStates.switchToState(name, args);

	static function openScriptedSubstate(name:String, ?args:Array<Dynamic>):Bool
		return ScriptedStates.openSubstate(name, args);

	static function switchState(state:flixel.FlxState):Void
		MusicBeatState.switchState(state);

	// Wrappers, not direct references: `FlxGamepadManager`'s `any*` are `inline`, so they have no
	// runtime form to take a closure on -- hxcpp would emit a call to a `_dyn` it never declares,
	// which only shows up at C++ compile time. They also declare `FlxGamepadInputID`, and the
	// script-facing signature has always been a plain String.
	static function anyGamepadJustPressed(name:String):Bool
		return flixel.FlxG.gamepads.anyJustPressed(name);

	static function anyGamepadPressed(name:String):Bool
		return flixel.FlxG.gamepads.anyPressed(name);

	static function anyGamepadReleased(name:String):Bool
		return flixel.FlxG.gamepads.anyJustReleased(name);

	static function keyboardJustPressed(name:String):Dynamic
		return Reflect.getProperty(flixel.FlxG.keys.justPressed, name);

	static function keyboardPressed(name:String):Dynamic
		return Reflect.getProperty(flixel.FlxG.keys.pressed, name);

	static function keyboardReleased(name:String):Dynamic
		return Reflect.getProperty(flixel.FlxG.keys.justReleased, name);

	static function gamepadAnalogX(id:Int, ?leftStick:Bool = true):Float {
		var controller = flixel.FlxG.gamepads.getByID(id);
		return controller == null ? 0.0 : controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
	}

	static function gamepadAnalogY(id:Int, ?leftStick:Bool = true):Float {
		var controller = flixel.FlxG.gamepads.getByID(id);
		return controller == null ? 0.0 : controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
	}

	static function gamepadJustPressed(id:Int, name:String):Bool {
		var controller = flixel.FlxG.gamepads.getByID(id);
		return controller != null && Reflect.getProperty(controller.justPressed, name) == true;
	}

	static function gamepadPressed(id:Int, name:String):Bool {
		var controller = flixel.FlxG.gamepads.getByID(id);
		return controller != null && Reflect.getProperty(controller.pressed, name) == true;
	}

	static function gamepadReleased(id:Int, name:String):Bool {
		var controller = flixel.FlxG.gamepads.getByID(id);
		return controller != null && Reflect.getProperty(controller.justReleased, name) == true;
	}

	static function keyJustPressed(name:String = ''):Bool {
		return switch (name.toLowerCase()) {
			case 'left': Controls.instance.NOTE_LEFT_P;
			case 'down': Controls.instance.NOTE_DOWN_P;
			case 'up': Controls.instance.NOTE_UP_P;
			case 'right': Controls.instance.NOTE_RIGHT_P;
			default: Controls.instance.justPressed(name);
		}
	}

	static function keyPressed(name:String = ''):Bool {
		return switch (name.toLowerCase()) {
			case 'left': Controls.instance.NOTE_LEFT;
			case 'down': Controls.instance.NOTE_DOWN;
			case 'up': Controls.instance.NOTE_UP;
			case 'right': Controls.instance.NOTE_RIGHT;
			default: Controls.instance.pressed(name);
		}
	}

	static function keyReleased(name:String = ''):Bool {
		return switch (name.toLowerCase()) {
			case 'left': Controls.instance.NOTE_LEFT_R;
			case 'down': Controls.instance.NOTE_DOWN_R;
			case 'up': Controls.instance.NOTE_UP_R;
			case 'right': Controls.instance.NOTE_RIGHT_R;
			default: Controls.instance.justReleased(name);
		}
	}

	/**
	 * Values and helper functions available inside scripted classes. `this` (the instance)
	 * and everything inherited from the base are wired by the bridge macro, so this only
	 * covers what isn't reachable through the object itself.
	 *
	 * @param mod The mod this world belongs to. `buildScripted` resolves against it, so a class
	 *            building another class finds its OWN mod's copy rather than whichever mod
	 *            happened to be current.
	 */
	public static function inject(vars:Map<String, Dynamic>, ?mod:String):Void {
		shared(function(name:String, value:Dynamic) vars.set(name, value), mod);
	}
}
#end
