package macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Generates the scriptable bridges that let mod scripts write `class X extends <Base>`.

	hscript-insanity registers a scriptable class by its BASE class: for every entry below it
	emits an otherwise empty `scripting.bridges.Scripted<Name> extends <Base> implements
	insanity.IScripted`, whose `@:autoBuild` macro generates, for each inherited method, an
	override that dispatches to the loaded script when it defines that method and falls through
	to `super` otherwise. Scripts therefore extend the REAL base, and the engine instantiates the
	bridge for them.

	Adding a new extendable base is one line in `BASES`. The cost is one generated override per
	inherited non-inline, non-final method, so keep the list to classes mods actually subclass.

	`final` classes cannot appear here: the note-runtime drawables (`Receptor`, `NoteSprite`,
	`SustainSprite`, `NoteField`) are deliberately final so hxcpp can devirtualize the per-note
	hot path, and un-finalizing them for scriptability would cost frame time in the one place
	the engine can least afford it.

	Invoked from Project.xml as an init macro.
**/
class ScriptedBridgeMacro {
	static final BASES:Array<BridgeEntry> = [
		// Flixel display primitives -- the generic "make me an object" bases.
		{base: 'flixel.FlxBasic'},
		{base: 'flixel.FlxObject'},
		{base: 'flixel.FlxSprite'},
		{base: 'flixel.group.FlxGroup'},
		{base: 'flixel.group.FlxSpriteGroup'},
		{base: 'flixel.text.FlxText'},

		// States and substates.
		{base: 'backend.MusicBeatState'},
		{base: 'backend.MusicBeatSubstate'},
		{base: 'states.PlayState'},
		{base: 'substates.PauseSubState'},
		{base: 'substates.GameOverSubstate'},

		// Gameplay objects.
		{base: 'objects.Character'},
		{base: 'objects.StrumLine'},
		{base: 'objects.NoteSplash'},
		{base: 'backend.BaseStage'},

		// UI and script-facing helpers.
		{base: 'objects.Alphabet'},
		{base: 'objects.Bar'},
		{base: 'objects.HealthIcon'},
		{base: 'psychlua.ModchartSprite'},
		// NOTE: openfl display objects (Sprite/Bitmap) are intentionally NOT bridged. Their deep
		// DisplayObject method surface references openfl-internal types (a private `Listener`,
		// `openfl.Vector`) that a generated override can't reproduce. They're still importable and
		// constructible from scripts via ScriptGlobals -- scripts subclass FlxSprite, not these.
	];

	static inline var PACK:String = 'scripting.bridges';

	public static function generate():Void {
		if (!Context.defined('HSCRIPT_ALLOWED'))
			return;

		var pos:Position = Context.currentPos();
		var pack:Array<String> = PACK.split('.');

		var bridgeRefs:Array<Expr> = [];
		var basePaths:Array<Expr> = [];

		for (entry in BASES) {
			var superPath:TypePath = toTypePath(entry.base);
			var name:String = 'Scripted' + superPath.name;

			var interfaces:Array<TypePath> = [{pack: ['insanity'], name: 'IScripted'}];
			if (entry.interfaces != null)
				for (i in entry.interfaces)
					interfaces.push(toTypePath(i));

			// One module per bridge: a type defined as a sub-type of another module can
			// only be named through that module, which would make every reference read
			// `scripting.bridges.Bridges.ScriptedFlxSprite`.
			Context.defineModule('$PACK.$name', [{
				pack: pack,
				name: name,
				pos: pos,
				meta: [{name: ':keep', pos: pos}],
				kind: TDClass(superPath, interfaces, false, false, false),
				fields: []
			}]);

			bridgeRefs.push(macro $p{pack.concat([name])});
			basePaths.push(macro $v{entry.base});
		}

		// Referencing every bridge from one kept array is what forces them to be typed --
		// they are only ever created reflectively, so nothing else would.
		Context.defineModule('$PACK.Bridges', [{
			pack: pack,
			name: 'Bridges',
			pos: pos,
			meta: [{name: ':keep', pos: pos}],
			kind: TDClass(null, [], false, false, false),
			fields: [
				{
					name: 'all',
					access: [APublic, AStatic],
					pos: pos,
					doc: 'Every generated bridge class. Referenced to keep them out of DCE.',
					kind: FVar(macro :Array<Class<Dynamic>>, {expr: EArrayDecl(bridgeRefs), pos: pos})
				},
				{
					name: 'bases',
					access: [APublic, AStatic],
					pos: pos,
					doc: 'Fully-qualified paths of every extendable base, in the same order as `all`.',
					kind: FVar(macro :Array<String>, {expr: EArrayDecl(basePaths), pos: pos})
				}
			]
		}]);
	}

	static function toTypePath(path:String):TypePath {
		var parts:Array<String> = path.split('.');
		var name:String = parts.pop();

		return {pack: parts, name: name};
	}
}

typedef BridgeEntry = {
	var base:String;

	/**
		Native interfaces the bridge should declare. A scripted class only satisfies a
		compiled `is IFoo` check when its bridge implements `IFoo`, so list them here.
	**/
	var ?interfaces:Array<String>;
}
#end
