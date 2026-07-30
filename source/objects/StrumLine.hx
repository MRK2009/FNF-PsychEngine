package objects;

import objects.Character;
import objects.notes.NoteField;
import objects.notes.Receptor;
import flixel.input.keyboard.FlxKey;
import flixel.sound.FlxSound;

/**
	A first-class strumline: one lane group owning its receptors, its scrolling `NoteField`, the
	characters that animate for it, and (for the human line) its input map. What the old implicit
	opponent/player split becomes -- `PlayState.strumLines` holds one per active line.

	Notes reference a strumline by its absolute `index`; the camera targets a strumline; gf is just a
	strumline whose `characters` are gf. Non-`player` lines are auto-hit; a hidden line (`visible ==
	false`) skips rendering but its characters still sing. The role never decides that -- any line marked
	visible renders, up to `SongChart.MAX_VISIBLE_LINES`.
**/
class StrumLine {
	/** Absolute index in the chart's strumline list (what a note's `strumLine` refers to). **/
	public var index:Int;

	public var id:String;

	/** Role: 0=OPPONENT, 1=PLAYER, 2=ADDITIONAL (see `SongChart.StrumLineType`). `isPlayer == type==1`. **/
	public var type:Int = 0;

	public var isPlayer:Bool;

	/** Whether this line renders receptors/notes on screen. **/
	public var visible:Bool;

	public var keyCount:Int;

	/** The characters that animate when this line's notes are hit (index 0 is the camera target). **/
	public var characters:Array<Character> = [];

	public var receptors:Array<Receptor> = [];
	public var field:NoteField = null;
	public var downScroll:Bool = false;
	public var cpuControlled:Bool = false;

	/** This line's own vocal track (Codename-style per-strumline vocals), muted/unmuted by its notes.
		`null` until PlayState loads it; the suffix resolves from `vocalsSuffix` or the line's character. **/
	public var vocals:FlxSound = null;

	public var vocalsSuffix:String = null;

	/**
		Player-line input: the ordered control names and the `FlxKey -> column` map, both sized to this
		line's own `keyCount`. `null` for auto/opponent lines.

		Filled by `PlayState.rebuildPlayerInput` for the line the human plays, and re-filled whenever the
		count changes. Only one line is wired for input at present, so only `controlledLine` carries
		these -- but they are the line's, not a global, which is what lets a 6K player line beside a 4K
		one bind six keys instead of the song's four.
	**/
	public var keys:Array<String> = null;

	public var keyToColumn:Map<FlxKey, Int> = null;

	public function new(index:Int, id:String, isPlayer:Bool, keyCount:Int, visible:Bool = true) {
		this.index = index;
		this.id = id;
		this.isPlayer = isPlayer;
		this.keyCount = keyCount;
		this.visible = visible;
	}

	/** The character the camera focuses for this line (its first character), or `null` if it has none. **/
	public inline function cameraCharacter():Character
		return (characters != null && characters.length > 0) ? characters[0] : null;
}
