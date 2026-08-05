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

		registerBytes(shims);
		registerTimer(shims);
	}

	/**
	 * Byte access.
	 *
	 * Every accessor on `haxe.io.Bytes` that a script would reach for is declared `inline` in the
	 * standard library, so on a compiled target there is no method to reflect on and a script asking
	 * for one is told it cannot call null. That is not a flixel quirk; it is the std, and it makes
	 * `Bytes` effectively unusable from a script without a workaround.
	 *
	 * The eval target ships its own `Bytes` where these are real methods, so nothing about this is
	 * visible to an interpreter test. It only appears on the engine's own target.
	 *
	 * Inlining works normally here, because this is compiled Haxe. The script gets a real call and
	 * the shim gets the inlined field access.
	 */
	static function registerBytes(shims:Map<String, (Dynamic, Array<Dynamic>) -> Dynamic>):Void {
		shims.set('haxe.io.Bytes.get', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			return (cast o : haxe.io.Bytes).get(args[0]);
		});

		shims.set('haxe.io.Bytes.set', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			(cast o : haxe.io.Bytes).set(args[0], args[1]);
			return null;
		});

		shims.set('haxe.io.Bytes.getUInt16', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			return (cast o : haxe.io.Bytes).getUInt16(args[0]);
		});

		shims.set('haxe.io.Bytes.getInt32', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			return (cast o : haxe.io.Bytes).getInt32(args[0]);
		});

		shims.set('haxe.io.Bytes.getDouble', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			return (cast o : haxe.io.Bytes).getDouble(args[0]);
		});

		shims.set('haxe.io.Bytes.getFloat', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			return (cast o : haxe.io.Bytes).getFloat(args[0]);
		});
	}

	/**
	 * `haxe.Timer.stamp` is `inline` as well, which leaves a script with no way to measure elapsed
	 * time at all. `FlxG.game.ticks` is reachable but only counts whole milliseconds, which is too
	 * coarse for anything a script would want a timer for.
	 */
	static function registerTimer(shims:Map<String, (Dynamic, Array<Dynamic>) -> Dynamic>):Void {
		shims.set('haxe.Timer.stamp', function(o:Dynamic, args:Array<Dynamic>):Dynamic {
			return haxe.Timer.stamp();
		});
	}
}
#end
