package scripting;

import backend.MusicBeatState;

#if HSCRIPT_ALLOWED
/**
 * Internal bridge that makes `MusicBeatState` scriptable as a class.
 *
 * insanity registers a scriptable class by its BASE class, so modders extend the
 * real base (`MusicBeatState`) and the engine instantiates THIS bridge for them:
 *
 *     class MyMenu extends MusicBeatState {   // <- the real base, not the bridge
 *         override function create() { super.create(); ... }
 *         override function update(elapsed:Float) { super.update(elapsed); ... }
 *     }
 *
 * The `insanity.IScripted` interface carries an `@:autoBuild` macro that
 * generates, for every inherited method, an override which dispatches to the
 * loaded script's matching function if it defines one, otherwise falls through
 * to `super`. So when Flixel drives this state (create/update/beatHit/...),
 * the script's overrides run.
 *
 * Instantiated by `scripting.ScriptedStates.loadState()`.
 *
 * `@:keep` is required: the class is only ever created reflectively (via the
 * scripted-class registry), so without it DCE would strip the class and the
 * `@:autoBuild` dispatch overrides would never be generated.
 */
@:keep
class ScriptedMusicBeatState extends MusicBeatState implements insanity.IScripted {}
#else
class ScriptedMusicBeatState extends MusicBeatState {}
#end
