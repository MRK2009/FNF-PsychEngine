/*
	Example custom note -- HSCRIPT
	==============================
	The SAME custom note in HScript. Here the note callbacks receive the note OBJECT directly, so we
	read `note.data` (the v2 NoteData) instead of going through strings. No legacy note internals
	(no game.notes / unspawnNotes / new Note) -- this is the native v2 runtime.

	How to use:
	  1. Put this at:  mods/YourMod/custom_notetypes/Example Note.hx
	  2. Set some notes' type to "Example Note" in the chart.

	Note object shape (native v2, i.e. NOT compatibilityMode):
	  - the callback arg is the note's drawable (NoteSprite): `note.multAlpha`, `note.multSpeed`, ...
	  - `note.data` is its NoteData: `note.data.type`, `note.data.column`, `note.data.hitHealth`, ...
*/

var TYPE:String = 'Example Note';

function onCreate() {
	precacheSound('example-hit'); // provide mods/YourMod/sounds/example-hit.ogg (optional)
}

// note = the spawning NoteSprite.
function onSpawnNote(note:Dynamic) {
	if (note == null || note.data == null || note.data.type != TYPE) return;
	note.multAlpha = 0.6;       // dim this note (multAlpha persists; a raw alpha write is overwritten each frame)
	// Give this note its own graphic; assigning note.texture re-skins it now (the v2 `Note.texture`).
	// Provide mods/YourMod/images/MYNOTE_assets.png/.xml (purple0/blue0/green0/red0 prefixes); missing = ignored.
	note.texture = 'MYNOTE_assets';
	note.rgbEnabled = false; // custom sheet ships its own colours
	// Skin the hold trail (body + tail) too, if this note has one. note.sustain is null for taps.
	if (note.sustain != null) {
		note.sustain.texture = 'MYNOTE_assets';
		note.sustain.rgbEnabled = false;
	}
	note.data.hitHealth = 0.08; // heal more when hit (read at hit time)
}

function goodNoteHit(note:Dynamic) {
	if (note == null || note.data == null || note.data.type != TYPE) return;
	FlxG.sound.play(Paths.sound('example-hit'), 0.7);
	game.camGame.shake(0.006, 0.12);
	game.boyfriend.playAnim('hey', true);
}

function noteMiss(note:Dynamic) {
	if (note == null || note.data == null || note.data.type != TYPE) return;
	game.health -= 0.06;
	game.camGame.shake(0.01, 0.15);
}
