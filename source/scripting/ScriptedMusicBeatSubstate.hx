package scripting;

import backend.MusicBeatSubstate;

#if HSCRIPT_ALLOWED
/**
 * Substate counterpart to `ScriptedMusicBeatState`. Modders extend the real
 * base (`MusicBeatSubstate`); the engine instantiates this bridge for them:
 *
 *     class MyPause extends MusicBeatSubstate {
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
