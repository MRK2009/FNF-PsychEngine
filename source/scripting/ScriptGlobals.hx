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
	 * Values and helper functions available inside scripted classes. `this` (the instance)
	 * and everything inherited from the base are wired by the bridge macro, so this only
	 * covers what isn't reachable through the object itself.
	 */
	public static function inject(vars:Map<String, Dynamic>):Void {
		inline function s(name:String, value:Dynamic)
			vars.set(name, value);

		// Names bound to Psych-specific replacements (see TYPE_IMPORTS).
		#if android
		s('File', mobile.backend.ScriptFile);
		s('FileSystem', mobile.backend.ScriptFileSystem);
		#elseif sys
		s('File', File);
		s('FileSystem', FileSystem);
		#end
		s('controls', Controls.instance);

		s('getVar', function(name:String):Dynamic {
			return MusicBeatState.getVariables().exists(name) ? MusicBeatState.getVariables().get(name) : null;
		});
		s('setVar', function(name:String, value:Dynamic):Dynamic {
			MusicBeatState.getVariables().set(name, value);
			return value;
		});
		s('removeVar', function(name:String):Bool {
			if (MusicBeatState.getVariables().exists(name)) {
				MusicBeatState.getVariables().remove(name);
				return true;
			}
			return false;
		});

		// Navigation between scripted states from within a scripted class.
		s('switchToState', function(name:String, ?args:Array<Dynamic>):Bool return ScriptedStates.switchToState(name, args));
		s('openScriptedSubstate', function(name:String, ?args:Array<Dynamic>):Bool return ScriptedStates.openSubstate(name, args));
		s('switchState', function(state:flixel.FlxState) MusicBeatState.switchState(state));
		s('exitToEngine', function() ScriptedStates.exitToEngine());
		s('launchMod', function(folder:String):Bool return ScriptedStates.launchMod(folder));

		// Building scripted objects from other scripts.
		s('buildScripted', function(path:String, ?args:Array<Dynamic>):Dynamic return ScriptRegistry.instantiate(path, args));
	}
}
#end
