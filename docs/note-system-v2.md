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

## Compatibility & the converter (Phase 2 — implemented, awaiting play-test)

`compatibilityMode` (pack.json, read via `Mods.noteCompatibilityMode()`) is now served by
**`legacy.NoteCompatLayer`**, an adapter-over-v2 mirror. It is constructed by `PlayState` **only**
when the active pack opts in, so non-compat play is byte-for-byte unaffected.

- `game.notes` → one inert `LegacyNote` adapter per active v2 note, re-synced each frame from
  `playerField.active` + `opponentField.active` (`syncNotes`), with screen position mirrored from the
  live drawable.
- `game.playerStrums` / `opponentStrums` / `strumLineNotes` → one inert `LegacyStrumNote` adapter per
  receptor, built once and position-mirrored each frame (`syncStrums`).
- `game.unspawnNotes` → one **write-through** `legacy.UnspawnNoteProxy` per chart note. To make this
  work the chart is **pre-decoded in `generateSong`** (compat-only) so the list exists before
  `onCreatePost`; after `onCreatePost` the proxies are `flush`ed back onto the `NoteData`, and
  `buildNoteFields` reuses that same decode. So old load-time loops like
  `setPropertyFromGroup('unspawnNotes', i, 'texture'/'missHealth'/..., v)` take effect when the note
  spawns. (Mutated props: `texture`, `missHealth`, `hitHealth`, `ignoreNote`.)
- Callback identity → `PlayState.cbArg(note)` hands HScript note callbacks (and, via `fireStageNote`,
  the compiled stage `goodNoteHit`/`opponentNoteHit`/`noteMiss` hooks) a `LegacyNote` adapter in
  compat mode; in v2 play it returns the `NoteSprite` unchanged.

The `game.notes` / strum adapters are never drawn/updated (`visible = active = false`) — pure data
carriers, safe in the scene-added `notes` group.

**Per-note custom textures (v2 primitive, all modes):** `NoteData.texture` overrides the active skin
for a note's head; `NoteSprite.apply` loads it via `ClassicNoteSkin.applyNoteTexture`. Set it from a
note type (`NoteTypesConfig` `texture` property) or, in compat, via the `unspawnNotes` write-through.
The trail follows the head's `data.texture` through the same setter, so a custom-textured note skins
whole rather than head-only.

**Known limitations (alias-impossible — handled by the Script Converter):** script *writes* to an
adapter's visual props (`note.x`/`alpha`/strum position) do not reflect back onto the v2 drawables.
The
**`legacy.ScriptConverter`** is a non-destructive scanner that flags these patterns (and pre-v2 field
names like `.strumTime`→`.time`) and writes annotated `*.converted.<ext>` copies + a `compat-report.txt`
— it never edits originals. Wire `ScriptConverter.convertFolder(dir)` to a debug-menu entry to run it.

## Known gaps (v2)

- The **legacy** chart editor (`source/legacy/editors/`) still previews with the legacy
  `Note`/`StrumNote` classes. The current editor has its own pooled drawables
  (`editors/charting/render/EditorNoteField.hx`) and does not.
- Non-GH holds tick health per segment (`PlayState.sustainSegmentHit`), matching the legacy
  per-piece model. GH holds remain a single unit judged at release.
- Stage `goodNoteHit`/`opponentNoteHit`/`noteMiss` hooks fire for every stage, compat or not, and
  take the native `NoteData` (`PlayState.fireStageNote`).
- Per-note splash colours are applied: `noteSplashData.r`/`g`/`b` override the palette the splash
  would otherwise take, and a note type's splash texture with them.
- Shared statics (`defaultNoteTypes`/`defaultNoteSkin`/`getNoteSkinPostfix`/`initializeGlobalRGBShader`/
  `globalRgbShaders`/`SUSTAIN_SIZE`/`NoteSplashData`/`EventNote`) now live on the neutral
  **`objects.notes.NoteDefaults`**; `swagWidth`/`colArray` read from their owner `Mania`. The v2
  drawables/skin/splash reference these directly, so **v2 no longer has a transitive `legacy`
  dependency**. `LegacyNote` (hence `objects.Note`) forwards to `NoteDefaults`, so editor/Lua `Note.*`
  is unchanged. (Fixed in passing: `defaultNoteTypes[3]` was the rename-mangled `'Hurt LegacyNote'`,
  which broke v2's `'Hurt Note'` switch for integer-typed hurt notes — restored to `'Hurt Note'`, with
  `LegacyNote.set_noteType` updated in lockstep.)
- The note classes live in `legacy.LegacyNote` / `legacy.LegacyStrumNote`; `objects.Note` /
  `objects.StrumNote` are thin `typedef` aliases so the ~27 consumers keep compiling.
  Extracting them to a neutral home (so v2 has no transitive legacy dependency) is a later cleanup.
