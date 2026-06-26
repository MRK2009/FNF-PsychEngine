package objects;

// The real note class lives in legacy.LegacyNote now; these aliases keep the existing consumers
// (editors, stages, Lua bridges) compiling. The v2 runtime does not use this gameplay class.
typedef Note = legacy.LegacyNote;
typedef NoteSplashData = legacy.LegacyNote.NoteSplashData;
typedef EventNote = legacy.LegacyNote.EventNote;
