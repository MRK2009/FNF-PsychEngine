package macros;

#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;

/**
	Makes the build's abstracts usable from scripts as real abstracts.

	An abstract has no runtime representation, so a script handed one sees nothing: no instance
	members, no operators, no implicit conversions, and for an `enum abstract` none of its constants
	(`sprite.blend = BlendMode.ADD` fails as an unknown identifier). hxscript fixes that with
	a build macro that emits a reflectable wrapper, but the macro has to be applied to the abstract,
	and these abstracts live in libraries we do not own. This applies it from outside.

	It used to be a hand-maintained list of individual types, so every abstract a script touched was
	discovered the hard way: a runtime "Unknown identifier" from somebody's mod, then an engine
	rebuild to add one line. Instead the classpath is scanned for abstract declarations under
	`PACKAGES` and the build macro is applied to each, so an abstract added to any of those libraries
	later is covered without touching this file.

	Scanning rather than `Compiler.addGlobalMetadata` on the whole package, because the generator
	cannot wrap every abstract and a package-wide filter has no way to skip the ones it chokes on --
	and it does not degrade on those, it fails the build. Two shapes are known to break it, both
	skipped here: an `enum abstract` with value-less constructors (detected, see
	`hasValuelessConstructor`) and an abstract whose members call each other unqualified (named in
	`EXCLUDE`).

	Invoked from Project.xml as an init macro.
**/
class ScriptedAbstractMacro {
	/**
		Packages scanned for abstracts: the libraries scripts build things out of, plus the engine
		itself, since a script reaching an engine API reaches its abstracts too.
	**/
	static final PACKAGES:Array<String> = [
		// Flixel and its addons: FlxColor, FlxTweenType, FlxTextAlign, FlxAxes...
		'flixel',
		// SmidrUI, which scripted menus lay themselves out with.
		'smidr',
		// The engine's own packages.
		'backend',
		'objects',
		'states',
		'substates',
		'psychlua',
		'scripting',
		'shaders',
		'cutscenes',
		'options',
		'debug',
		'mobile',
	];

	/**
		Individually named abstracts from packages too big to scan.

		openfl and lime hold roughly 400 abstracts between them, nearly all of it platform plumbing no
		script will ever hold as a value, and every generated wrapper is a `@:keep` class in the
		binary. Add one here when a script actually needs it.
	**/
	static final TYPES:Array<String> = [
		// `sprite.blend = BlendMode.ADD` is how any additive light, glow or flash is written.
		'openfl.display.BlendMode',
	];

	/**
		Abstracts the generator cannot wrap for a reason the scan cannot see. Empty, for now.
	**/
	static final EXCLUDE:Array<String> = [];

	public static function generate():Void {
		if (!Context.defined('HSCRIPT_ALLOWED'))
			return;

		var wrapped:Array<String> = [];
		for (path in discover().concat(TYPES)) {
			if (EXCLUDE.contains(path))
				continue;

			Compiler.addMetadata('@:build(hxscript.macro.AbstractMacro.build())', path);
			wrapped.push(path);
		}

		Context.info('ScriptedAbstractMacro: ${wrapped.length} abstract(s) exposed to scripts', Context.currentPos());

		// The scan makes the set implicit -- what a script can reach depends on what happens to be
		// declared under PACKAGES. `-D scripted_abstracts_list` prints it.
		if (Context.defined('scripted_abstracts_list')) {
			wrapped.sort(Reflect.compare);
			for (path in wrapped)
				Context.info('  $path', Context.currentPos());
		}
	}

	/** Every wrappable abstract declared under `PACKAGES`, as dotted type paths. **/
	static function discover():Array<String> {
		var found:Array<String> = [];
		for (classPath in Context.getClassPath()) {
			if (classPath == null || classPath.length < 1)
				continue;

			for (pack in PACKAGES) {
				var root:String = Path.join([classPath, pack.split('.').join('/')]);
				if (FileSystem.exists(root) && FileSystem.isDirectory(root))
					scan(root, pack, found);
			}
		}
		return found;
	}

	static function scan(dir:String, pack:String, found:Array<String>):Void {
		for (entry in FileSystem.readDirectory(dir)) {
			var path:String = Path.join([dir, entry]);

			if (FileSystem.isDirectory(path)) {
				scan(path, pack + '.' + entry, found);
				continue;
			}
			if (!StringTools.endsWith(entry, '.hx'))
				continue;

			var module:String = entry.substr(0, entry.length - 3);
			for (decl in abstractsIn(File.getContent(path))) {
				if (decl.valueless)
					continue;

				// A type declared inside another module still lives in the module's PACKAGE, so its
				// path is `pack.Name` however it is imported. A private one is the exception: it lands
				// in the module-private `pack._Module` package.
				var typePath:String = decl.isPrivate ? pack + '._' + module + '.' + decl.name : pack + '.' + decl.name;
				if (!found.contains(typePath))
					found.push(typePath);
			}
		}
	}

	/**
		The abstracts declared in one module's source.

		A regex rather than a parse: a false positive costs nothing, because metadata for a path that
		never gets typed is simply never applied, and over-skipping only leaves a type where it already
		stood.
	**/
	static function abstractsIn(source:String):Array<AbstractDecl> {
		var decls:Array<AbstractDecl> = [];
		// Metadata may sit on the declaration line (`@:forward abstract FlxPoint(FlxBasePoint)`), so it
		// is skipped over rather than anchoring straight to the keyword.
		var decl:EReg = ~/(^|[\r\n])[ \t]*((@:[A-Za-z0-9_.]+(\([^)]*\))?[ \t]*)*)(private[ \t]+)?(enum[ \t]+)?abstract[ \t]+([A-Z][A-Za-z0-9_]*)/;
		var rest:String = source;

		while (decl.match(rest)) {
			var isEnum:Bool = decl.matched(6) != null;
			var right:String = decl.matchedRight();

			decls.push({
				name: decl.matched(7),
				isPrivate: decl.matched(5) != null,
				valueless: isEnum && hasValuelessConstructor(right)
			});
			rest = right;
		}
		return decls;
	}

	/**
		Whether an `enum abstract` body declares a constructor with no explicit value (`var RENAMED;`,
		taking the auto-incremented one).

		This is the shape that breaks the generator: with no initializer expression to read it emits an
		invalid field, and `Context.defineModule` rejects the whole wrapper. The throw is deferred to
		when the type is typed, so it cannot be caught at the call site either -- it has to be avoided.
	**/
	static function hasValuelessConstructor(afterDeclaration:String):Bool {
		var open:Int = afterDeclaration.indexOf('{');
		if (open < 0)
			return false;

		var depth:Int = 0;
		var end:Int = afterDeclaration.length;
		var i:Int = open;
		while (i < afterDeclaration.length) {
			var c:String = afterDeclaration.charAt(i);
			if (c == '{') {
				depth++;
			} else if (c == '}') {
				depth--;
				if (depth == 0) {
					end = i;
					break;
				}
			}
			i++;
		}

		// A constructor line that ends at the `;` with no `=` in between.
		var valueless:EReg = ~/(^|[\r\n;])[ \t]*var[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(:[ \t]*[A-Za-z_.<>, \t]+)?[ \t]*;/;
		return valueless.match(afterDeclaration.substring(open + 1, end));
	}
}

private typedef AbstractDecl = {
	var name:String;
	var isPrivate:Bool;
	var valueless:Bool;
}
#end
