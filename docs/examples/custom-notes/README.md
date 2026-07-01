# Custom note examples (v2-native, no legacy)

Three versions of the **same** custom note type — `Example Note` — one per scripting flavor. They use
the v2 note runtime directly and touch **no legacy internals**: no `game.notes`, no `game.unspawnNotes`,
no `new Note()`, no `setPropertyFromGroup('unspawnNotes', ...)`, no `Note` class. So they work without
`compatibilityMode`.

| File | Flavor | How it reaches the note |
|---|---|---|
| `psychlua - Example Note.lua` | Classic Psych Lua | `getProperty`/`setProperty` strings + `spawnNote` |
| `luaproxy - Example Note.lua` | LuaProxy ("real" Lua objects) | `game.spawnNote.head.multAlpha = …`, `game.boyfriend:playAnim(…)` |
| `hscript - Example Note.hx` | HScript | callback receives the note object; `note.data.type` |

Each does the same thing: on spawn it dims the note and boosts its heal; on hit it plays a sound,
bumps the camera, and pops a BF anim; on miss it drains a bit of health.

## Using one

1. Copy the file into your mod as **`mods/YourMod/custom_notetypes/Example Note.<ext>`** (the file name
   must match the note-type name). The engine auto-loads `custom_notetypes/<type>.lua` / `.hx` for every
   note type present in the chart.
2. In the chart editor, set some notes' **type** to `Example Note`.

The note callbacks (`onSpawnNote` / `goodNoteHit` / `noteMiss`) fire for *every* note, so each script
filters by `noteType`/`note.data.type`.

## The v2 note surface these use

- **`onSpawnNote`** fires right after a note spawns.
  - Lua: the spawning note is `spawnNote` (an `ActiveNote`), valid **only** inside this callback —
    `spawnNote.data` (its `NoteData`) and `spawnNote.head` (its `NoteSprite`).
  - HScript: the callback arg **is** the `NoteSprite`; `note.data` is its `NoteData`.
- **`goodNoteHit` / `noteMiss`** — Lua gets `(id, direction, noteType, isSustain)` (id is `-1` in v2, so
  filter by `noteType`); HScript gets the note object.
- **Persistent per-note visuals:** set `head.multAlpha` / `head.multSpeed`, **not** `alpha`/`x`/`y` — the
  runtime recomputes those from the receptor every frame, so raw writes get overwritten. `multAlpha`
  and `multSpeed` are the knobs it respects.
- **Per-note graphic:** assign **`head.texture`** (the v2 `Note.texture`) — re-skins the head from the
  named sparrow/pixel sheet (standard `purple0`/`blue0`/`green0`/`red0` prefixes; a missing sheet is
  ignored). For a hold, skin the trail too via **`sustain.texture`** (body/tail use the same sheet's
  `<colour> hold piece` / `<colour> hold end` prefixes). Reach the trail from the head as
  **`note.sustain`** (HScript) or **`spawnNote.sustain`** (Lua) — it's `null` for a tap.
- **Per-note RGB:** toggle the colour palette shader with **`head.rgbEnabled`** / **`sustain.rgbEnabled`**
  (`false` = off, e.g. a custom sheet that ships its own colours). The examples turn it off alongside a
  custom texture.
- **Gameplay data** (`data.hitHealth`, `data.missHealth`, `data.ignore`, `data.hitsound`,
  `data.splashDisabled`, …) is read at judge time, so setting it in `onSpawnNote` takes effect.

## Note-skinning Lua callbacks (shortcuts)

For classic Lua there are callbacks that skin the note being spawned — call them from `onSpawnNote`
(they act on `spawnNote`):

- **`setNoteTexture(atlas)`** — skins the whole note (head + hold body + tail) from one sparrow atlas.
- **`setNoteTexturePart(part, source, asImage)`** — skins one part independently. `part` is
  `'head'`/`'hold'`/`'tail'`; `asImage` false = a sparrow atlas (frames like the skin), true = a single
  static image. Mix atlas + image parts, like a folder skin.
- **`setNoteColorable(colorable, part)`** — toggles the RGB palette shader. `part` defaults to `'all'`
  (or `'head'`/`'hold'`).

(HScript/LuaProxy don't need these — they set `note.texture` / `note.sustain.texture` / `note.rgbEnabled`
on the objects directly, as the examples show.)

## Setting the graphic without any script

If every note of the type shares one look, skip the script and add a note-type data file
**`custom_notetypes/Example Note.txt`**:

```
texture: YOUR_SHEET_assets
disableRGB: true
hitHealth: 0.08
```

Those set `NoteData` fields at load (via Reflect), *before* the note spawns, so the drawable picks up
`YOUR_SHEET_assets` (for both head and hold) and turns RGB off — no `onSpawnNote` needed. Property names
are `NoteData` fields; dotted names work too (e.g. `extraData.foo`). Use this for a uniform type; use the
`head.texture`/`sustain.texture`/`rgbEnabled` setters in a script when it varies per note.
