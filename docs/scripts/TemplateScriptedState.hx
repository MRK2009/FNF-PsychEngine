// ============================================================================
//  Template scripted STATE (hscript-insanity)
// ----------------------------------------------------------------------------
//  Put this in a mod at:  mods/<YourMod>/states/MyMenu.hx
//  The class name MUST match the file name (here: MyMenu) and MUST extend
//  ScriptedMusicBeatState.
//
//  Switch to it from any Lua or HScript with:
//      switchToState('MyMenu');
//
//  Unlike the old onCreate()/onUpdate() callback scripts, this is a REAL class:
//  you `override` the state's lifecycle methods and call `super` like in Haxe.
// ============================================================================
class MyMenu extends ScriptedMusicBeatState {
	var text:FlxText;
	var bopSize:Float = 1.0;

	// REQUIRED: a constructor that calls super() so the underlying FlxState is
	// initialized. Without it the state's display list is null and add() crashes.
	public function new() {
		super();
	}

	override function create() {
		super.create(); // sets up the camera / transition -- keep this first

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuBG'));
		bg.screenCenter();
		add(bg);

		text = new FlxText(0, 0, FlxG.width, "My Scripted Menu\nPress ACCEPT to go back", 32);
		text.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		text.screenCenter();
		add(text);
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		// ease the title bop back to normal every frame
		bopSize = FlxMath.lerp(bopSize, 1.0, elapsed * 8);
		text.scale.set(bopSize, bopSize);

		if (controls.ACCEPT)
			switchToState('MainMenuState'); // or MusicBeatState.switchState(new states.MainMenuState())
		if (controls.BACK)
			MusicBeatState.switchState(new states.MainMenuState());
	}

	override function beatHit() {
		super.beatHit();
		bopSize = 1.15; // pulse the title on every beat
	}
}
