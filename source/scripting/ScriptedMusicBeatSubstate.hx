package scripting;

import backend.MusicBeatSubstate;

#if HSCRIPT_ALLOWED
/**
 * Substate counterpart to `ScriptedMusicBeatState`. Lets modders script a
 * whole substate as a class:
 *
 *     class MyPause extends ScriptedMusicBeatSubstate {
 *         override function create() { super.create(); ... }
 *     }
 *
 * Opened by `scripting.ScriptedStates.openSubstate()`.
 *
 * `@:keep` is required (see ScriptedMusicBeatState for why).
 */
@:keep
class ScriptedMusicBeatSubstate extends MusicBeatSubstate implements insanity.IScripted {}
#else
class ScriptedMusicBeatSubstate extends MusicBeatSubstate {}
#end
