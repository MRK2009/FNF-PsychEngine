package scripting;

#if HSCRIPT_ALLOWED
import flixel.FlxG;
import flixel.sound.FlxSound;

/**
 * Emulation shims for methods that have NO runtime representation, so a script can't reach
 * them by reflection and gets `Cannot call null`. The usual offenders are `inline extern`
 * overloads: compiled Haxe inlines them at the call site, but there is no method to reflect
 * on. flixel 6.2 turned several previously-plain methods into this form (notably
 * `FlxG.sound.playMusic`, which was a real method in 6.1), which silently broke scripts.
 *
 * Each shim is a compiled closure keyed by `<owner class>.<method>`; the interpreter looks it
 * up (walking the receiver's superclasses) when a call finds no runtime method. See
 * `hxscript.Config.callShims` and `Interp.resolveCallShim`.
 *
 * Registered once at boot from `HScript.setupConfig`.
 */
class ScriptShims {
	public static function register():Void {
		var shims = hxscript.Config.callShims;

		// flixel 6.2: FlxG.sound.playMusic is now an `inline extern` overload. Rebuild it the
		// reflectable way -- stop any current track, then load + play the new one as
		// FlxG.sound.music (which the sound frontend still updates every frame, so
		// FlxG.sound.music.time keeps tracking playback for a conductor).
		shims.set('flixel.system.frontEnds.SoundFrontEnd.playMusic', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			var volume:Float = (args.length > 1 && args[1] != null) ? args[1] : 1.0;
			var looped:Bool = (args.length > 2 && args[2] != null) ? args[2] : true;

			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();

			FlxG.sound.music = FlxG.sound.load(args[0], volume, looped);
			FlxG.sound.music.play();
			return FlxG.sound.music;
		});
	}
}
#end
