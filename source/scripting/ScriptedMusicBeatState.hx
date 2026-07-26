package scripting;

import backend.MusicBeatState;

#if HSCRIPT_ALLOWED
/**
 * Back-compat alias. The real bridge is now generated as
 * `scripting.bridges.ScriptedMusicBeatState` by `macros.ScriptedBridgeMacro`,
 * alongside one for every other extendable base.
 *
 * Scripts should extend the REAL base (`class MyMenu extends MusicBeatState`);
 * this name only exists so scripts written against the old two-bridge system
 * keep resolving.
 */
typedef ScriptedMusicBeatState = scripting.bridges.ScriptedMusicBeatState;
#else
class ScriptedMusicBeatState extends MusicBeatState {}
#end
