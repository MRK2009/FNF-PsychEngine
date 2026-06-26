# Example: "Glitch" notes on the v2 note system

A small modchart that adds a custom `Glitch` note type: it looks different, ignores the miss penalty
on the player side, and runs custom logic on hit/miss. The same example is shown in three scripting
flavors so you can compare how each touches the v2 note runtime.

## What changed from the legacy version

- **No `unspawnNotes`.** Notes aren't built up-front anymore, so per-note setup moves into
  `onSpawnNote`, which fires once as each note enters the field. v2 adds `mustPress` as a 6th arg.
- **Skins are decoupled from notes.** There is no per-note `texture` field. The idiomatic way to make
  a note type look different is a note skin / note-type variant; for a one-off you can still re-skin
  the spawned sprite directly (`setSpawnNoteSkin` in plain Lua, `note.frames = …` in HScript/luaproxy).
- **The hit/miss callbacks are unchanged** — they only read `noteType`. (Lua's `id` arg is now always
  `-1`, since there is no `notes`-group index to hand back.)

## Reaching the spawning note from plain Lua

`PlayState` exposes the note currently in `onSpawnNote` as `spawnNote`, so the standard
`getProperty`/`setProperty` (which walk dotted paths) reach its data:

```lua
setProperty('spawnNote.data.ignore', true)   -- valid only inside onSpawnNote
setSpawnNoteSkin('GLITCHNOTE_assets')         -- re-skin it (frames can't be set from plain Lua)
```

HScript and luaproxy don't need this — they get the note object directly and touch `note.data` /
`note.frames`.

## Files

| File | Flavor | Notes |
|---|---|---|
| `hscript.hx` | HScript | Cleanest: touches the note objects directly in `onSpawnNote`. |
| `luaproxy.lua` | LuaProxy | Same as HScript but in Lua, with direct engine access. |
| `psychlua.lua` | standard psychlua | Uses `spawnNote` + `setSpawnNoteSkin`; no note-type file needed. |
