package macros;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

/**
	Makes chosen abstracts usable from scripts as real abstracts.

	An abstract has no runtime representation, so a script handed one sees nothing: no instance
	members, no operators, no implicit conversions. hscript-insanity fixes that with a build macro
	that emits a reflectable wrapper, but the macro has to be applied to the abstract, and these
	abstracts live in libraries we do not own. `Compiler.addMetadata` applies it from outside.

	The payoff is that `FlxColor` stops needing a hand-written stand-in class: scripts get the
	genuine abstract, with `color.red`, `color.getDarkened(0.5)`, its operators, and its constants.

	Adding one is a line in `ABSTRACTS`. Each entry costs a generated wrapper class, so list the ones
	scripts actually handle as values rather than every abstract in the build.

	Invoked from Project.xml as an init macro.
**/
class ScriptedAbstractMacro {
	static final ABSTRACTS:Array<String> = [
		// Scripts pass colours around constantly: tweens, text, debug output, shader uniforms.
		'flixel.util.FlxColor',
	];

	public static function generate():Void {
		if (!Context.defined('HSCRIPT_ALLOWED'))
			return;

		for (path in ABSTRACTS)
			Compiler.addMetadata('@:build(insanity.macro.AbstractMacro.build())', path);
	}
}
#end
