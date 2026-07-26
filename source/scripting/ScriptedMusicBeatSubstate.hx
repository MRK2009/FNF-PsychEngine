package scripting;

import backend.MusicBeatSubstate;

#if HSCRIPT_ALLOWED
/** Back-compat alias for the generated bridge (see `ScriptedMusicBeatState`). */
typedef ScriptedMusicBeatSubstate = scripting.bridges.ScriptedMusicBeatSubstate;
#else
class ScriptedMusicBeatSubstate extends MusicBeatSubstate {}
#end
