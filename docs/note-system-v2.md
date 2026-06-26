# Note System v2 (osu!-style runtime)

The note/strum runtime was rewritten from scratch on `feature/note-runtime-v2` using the model
osu!(lazer) uses: a pure **data** layer, a **pooled drawable** layer, a **scrolling container**, and a
**decoupled skin service**. This is now the **only** runtime — the legacy `Note`/`StrumNote` gameplay
path has been removed from `PlayState`.

## Old vs new (the differences)

| | Legacy | v2 |
|---|---|---|
| Note model | one `Note` (`FlxSprite`) mixing data + gameplay + skin loading + positioning + clipping | `NoteData` (pure data + judgement state) ↔ pooled `NoteSprite`/`SustainSprite` drawables |
| Spawning | **every** note + **every** sustain piece built up-front into `unspawnNotes` (thousands of sprites) | `NoteData.generate` makes a cheap time-sorted list; `NoteField` recycles a small pool of drawables within a lifetime window |
| Sustains | head + N stacked sustain `Note`s | **one** `SustainSprite` (stretched body + tail cap) per hold |
| Positioning | each `Note.followStrumNote` per frame | centralized in `NoteField.update` |
| Skins | baked into `Note.reloadNote` | `INoteSkin` service; drawables never touch textures/atlases |
| Receptors | `StrumNote` with skin-building inside | `Receptor` (skin via service) |

## Components

- **`objects/notes/NoteData.hx`** — pure data + judgement state (`hit`/`missed`/`canBeHit`/`rating`/
  `hitHealth`/…) + lifetime window. `generate(SONG)` decodes the chart into a flat, time-sorted list
  (a hold is ONE entry). `applyType()` ports the note-type data logic.
- **`backend/noteskin/`** — `INoteSkin` + `NoteVisual` + `FolderNoteSkin` (`.tcfg`/`.json` via
  `NoteSkinConfig`) + `ClassicNoteSkin` (NOTE_assets atlas / pixel / multikey) + `NoteSkinService`
  facade (folder→classic fallback). Standard anim names: head=`note`, body=`hold`, tail=`end`,
  receptor=`static`/`pressed`/`confirm`.
- **`objects/notes/{NoteSprite,SustainSprite,Receptor}.hx`** — pooled, skin-agnostic drawables.
- **`objects/notes/NoteField.hx`** — the scrolling container (one per side): spawn/position/reclaim,
  pooling via `FlxTypedGroup.recycle`, `activeForColumn` for input, `skipTo`/`clear` for jumps.

## PlayState integration

`generateSong` only loads audio/events + scans note-type names (for precache). At countdown,
`buildNoteFields` builds `NoteData` (split by side), `Receptor`s, and two `NoteField`s. `update`
runs `updateFields` (spawn/scroll/reclaim + opponent auto-hit + cpu + late-miss + hit-window flags)
and `keysCheck` (input + hold-release). Judgement (`goodNoteHit`/`opponentNoteHit`/`noteMiss`/
`popUpScore`/…) operates on `NoteData`/`ActiveNote`. Lua callbacks keep their names (index passed as
`-1`; HScript callbacks get the `NoteSprite`).

## Compatibility & the converter (TODO)

The legacy script API (`game.notes`, `game.unspawnNotes`, `game.playerStrums`, `goodNoteHit(note)`,
etc.) is **not** served by the runtime anymore. A **converter** (read pack.json `compatibilityMode`
via `Mods.noteCompatibilityMode()`) will redirect old scripts:

- `game.notes` / `unspawnNotes` reads → a view/adapter over `playerField.active` + `oppField.active`
  (LegacyNote adapters wrapping `NoteSprite`/`NoteData`).
- `game.playerStrums` / `opponentStrums` → adapters over `v2PlayerRecs` / `v2OppRecs`.
- `goodNoteHit(note)` / `noteMiss(note)` / `invalidateNote(note)` calls → resolve the matching
  `ActiveNote`, then call the v2 `goodNoteHit`/`noteMiss`/`field.remove`.
- Callback object identity (`onSpawnNote`/`goodNoteHit` HScript args) already passes a `NoteSprite`.

**Known limitation:** the up-front `unspawnNotes` semantics (the whole chart pre-spawned) cannot be
fully reproduced — v2 has no up-front spawn. Scripts that iterate the entire chart via `unspawnNotes`
must move to reading `playerField.notes` (the `NoteData` list).

These are currently **empty stubs** in `PlayState` (`notes`/`unspawnNotes`/`playerStrums`/
`opponentStrums`/`strumLineNotes`) kept only so stages/Lua/PauseSubState still compile; the converter
will give them real contents.

## Known gaps (v2)

- EditorPlayState/ChartingState still use the legacy `Note`/`StrumNote` classes for their previews.
- Holds grant health only on the head-hit (no per-frame tick like the legacy per-piece model).
- Stage `goodNoteHit`/etc. note hooks (which take a legacy `Note`) are skipped under v2.
- Custom note-splash colors fall back to defaults (the splash is spawned without a `Note`).
- The note classes now live in `legacy.LegacyNote` / `legacy.LegacyStrumNote`; `objects.Note` /
  `objects.StrumNote` are thin `typedef` aliases so the ~27 consumers (editors, stages, Lua bridges)
  keep compiling. **Remaining nuance:** the shared statics (`colArray`/`swagWidth`/
  `initializeGlobalRGBShader`/`defaultNoteSkin`/`getNoteSkinPostfix`/`defaultNoteTypes`/
  `NoteSplashData`) still live on `LegacyNote`, so the v2 drawables read them through the alias.
  Extracting them to a neutral home (so v2 has no transitive legacy dependency) is a later cleanup.
