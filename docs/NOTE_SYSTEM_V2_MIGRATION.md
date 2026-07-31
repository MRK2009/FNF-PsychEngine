# Note System V2 - Scripting and Note-Skin Migration Guide

For Lua/HScript modders. Covers what changed in **Note System V2**: the note callbacks,
`getProperty`/`setProperty`, and how note skins work now.

**Read this even if your pack still runs.** The **master branch (1.3.x)** runs V2 but keeps a
compatibility bridge (section 6) so old packs *SOMEWHAT* works for now. That bridge is a temporary crutch - it is
**already gone on the psych-v2.0.0 branch**, where native V2 is the only way. Whether you are new or
experienced, migrating your scripts and skins now is how you stay working when legacy is fully phased
out. This guide is the checklist for that.

**Fastest path:** run the in-engine **Script Converter** (Editors menu) on your modpack first - it
auto-fixes the mechanical renames - then hand-fix the rest using this guide. It writes `*.converted`
copies next to your scripts and never edits the originals, so there is nothing to undo if you don't
like the result. See [Script Converter modes](#the-script-converter-two-modes) for what it will and
won't touch.

---

## Contents

- [0. The one big change](#0-the-one-big-change)
- [1. Note callbacks](#1-note-callbacks)
  - [1.1 Renamed note fields](#11-renamed-note-fields)
  - [1.2 Callback arguments](#12-callback-arguments)
  - [1.3 game.lastJudgedNote](#13-gamelastjudgednote)
- [2. getProperty / setProperty](#2-getproperty--setproperty-reaching-what-the-callbacks-dont-give-you)
  - [2.1 Notes: point at the FIELDS](#21-notes-point-at-the-fields)
  - [2.2 Strums / receptors](#22-strums--receptors)
  - [2.3 Note skins from a script](#23-note-skins-from-a-script)
  - [2.4 Three easy mistakes](#24-three-easy-mistakes)
  - [2.5 Worked example: a custom note type](#25-worked-example-a-custom-note-type)
  - [2.6 Worked example: a hit callback](#26-worked-example-a-hit-callback)
- [3. Checklist](#3-checklist)
  - [The Script Converter: two modes](#the-script-converter-two-modes)
- [4. Note skins](#4-note-skins)
- [5. Full reference: what broke or changed](#5-full-reference-what-broke-or-changed)
- [6. compatibilityMode (the legacy bridge)](#6-compatibilitymode-the-legacy-bridge---a-last-resort)
- [7. Where this lives in source](#7-where-this-lives-in-source)

---

## 0. The one big change

Before, a note was one object: the data and the on-screen sprite together. The whole chart was
pre-spawned into `unspawnNotes`, a hold was a head note plus a chain of tail sprites, and scripts
poked those sprites through `game.notes.members`.

V2 splits that into **data** and **sprite**:

- **`NoteData`** - just the data. The whole chart lives here. **A hold is ONE `NoteData` with
  `length > 0`** (no tail chain, no `prevNote`).
- **`NoteField`** - owns the notes and only creates sprites for the ones currently on screen. There
  are two: `game.playerField` and `game.opponentField`.

What this means for you:

- `game.notes` / `game.unspawnNotes` are gone (they only come back as a mirror under
  `compatibilityMode`, section 6).
- Note callbacks pass different arguments (section 1).
- Some note fields were renamed (section 1.1).
- Strums are reached through the real receptors (section 2.2).

---

## 1. Note callbacks

### 1.1 Renamed note fields

Shorter names. Use these anywhere you read a note (`note.data.<field>` in HScript) or pass a field to
`getPropertyFromGroup` / `setPropertyFromGroup`.

| Old             | New (V2)        | |
|-----------------|-----------------|--|
| `strumTime`     | `time`          | ms |
| `noteData`      | `column`        | 0-based lane |
| `noteType`      | `type`          | the note-type string (see note below) |
| `sustainLength` | `length`        | hold length in ms; `0` = tap |
| `wasGoodHit` / `noteWasHit` | `hit`   | |
| `ignoreNote`    | `ignore`        | |
| `isSustainNote` | `isSustain()`   | now a method; or check `length > 0` |
| `distance`      | (gone)          | was the per-note scroll offset; scroll is driven by the scroll-velocity system now (per-note anchor is `scrollPos`, and `multSpeed` still scales it) |
| `prevNote` / `nextNote` / `tail` / `parent` | (gone) | a hold is one note, not a head + tail chain |

(HScript still lets old scripts read `strumTime` / `noteData` / `isSustainNote` off the note so they
don't crash, but they're read-only - prefer `note.data.time` etc.)

`noteType` is the one rename the Script Converter can never do for you: `noteType` is also the usual
name of the callback's third argument, and it can't tell a field read from the argument, so **you**
rename it when you read it off a note (`getPropertyFromGroup(..., 'type')`, HScript `note.data.type`).
The callback argument can stay named whatever you like.

`isSustainNote` it *can* do, but only in the rewrites mode - it becomes a call rather than a name.
See [Script Converter modes](#the-script-converter-two-modes).

### 1.2 Callback arguments

Lua callbacks get plain values. HScript callbacks get the note object (its `.data` is the `NoteData`).

| Callback | Lua arguments |
|----------|---------------|
| `onSpawnNote` | `(id, column, type, isSustain, time, mustPress)` |
| `goodNoteHit` | `(id, column, type, isSustain)` |
| `opponentNoteHit` | `(id, column, type, isSustain)` |
| `noteMiss` | `(id, column, type, isSustain)` |
| `goodNoteHitPre` / `opponentNoteHitPre` | same args; `return Function_Stop` to cancel the hit |
| `onDespawnNote` | `(-1, column, type, isSustain, time, mustPress)` |
| `onSustainRelease` | `(-1, column, type, time)` |
| `onStrumsCreated` | `(strumlineCount)` |

Three of those are new, and each closes a hole the pooled runtime opened:

- **`onDespawnNote`** fires as a note leaves play, however it left -- hit, missed, or simply scrolled
  past. Its drawables are already back in the pool by then, so this is where you drop whatever you
  were tracking for that note. The sprite you were handed in `onSpawnNote` now belongs to the field
  again and will be handed out for a different note. HScript gets the note object; plain Lua reads
  `game.despawnNote` (the mirror of `game.spawnNote`), valid only inside the callback.
- **`onSustainRelease`** fires when a hold is dropped early. `noteMiss` still fires too -- this one
  exists so you can tell a dropped hold apart from a note that was never pressed, which the miss
  arguments alone cannot express.
- **`onStrumsCreated`** fires the moment receptors, note fields and the strum aliases all exist.
  Every other callback is either too early (`onCreatePost`, `onStartCountdown`, both of which run
  before the fields are built) or well into the song, so restyling or repositioning lanes had no
  correct moment to happen in.

**The thing to know: what `id` (the first argument) means now.**

- In `onSpawnNote`, `id` points at the note *inside its field* (`game.playerField` /
  `game.opponentField`). Use it to change the spawning note (section 2.1). Only valid inside the
  callback.
- In `goodNoteHit` / `opponentNoteHit` / `noteMiss`, **`id` is always `-1`**. There's no note list to
  index anymore. To read the note that was just hit/missed, use **`game.lastJudgedNote`**.

### 1.3 game.lastJudgedNote

The `NoteData` that was just judged. Read it in hit/miss callbacks (where `id` is `-1`):

```lua
function goodNoteHit(id, column, noteType, isSustain)
    local t = getProperty('lastJudgedNote.time')
end
```

HScript already gets the note as the callback argument, so this is mainly for Lua.

---

## 2. getProperty / setProperty: reaching what the callbacks don't give you

Callbacks only hand you a few values (`column`, `type`, ...). To reach anything else - a note's other
fields, a receptor, the note skin - use the property functions:

- `getProperty` / `setProperty` - things on the game (`getProperty('health')`,
  `setProperty('boyfriend.x', 100)`).
- `getPropertyFromClass` - static class fields (`getPropertyFromClass('backend.ClientPrefs',
  'data.noteSkin')`).
- `getPropertyFromGroup` / `setPropertyFromGroup` - one member of a group, array, or **note field**.
  The note workhorse.

### 2.1 Notes: point at the FIELDS

`game.notes` / `game.unspawnNotes` are empty unless `compatibilityMode` is on. Use the fields:
`game.playerField` and `game.opponentField` (you can write `.notes` after them, it's the same thing).

```lua
function onSpawnNote(id, column, noteType, isSustain, time, mustPress)
    setPropertyFromGroup('game.playerField.notes', id, 'multAlpha', 0.5)
end
```

- `id` is the value from `onSpawnNote`. It's not a global index and only works inside that callback.
- **Write the offsets, not the position.** A note follows its receptor every frame, so `x`, `y`,
  `alpha` and `angle` are *recomputed* each frame and a direct write is gone by the next one. Use
  `offsetX` / `offsetY` / `multAlpha` / `multSpeed` / `offsetAngle`, which are inputs to that
  calculation and therefore stick.
- To own a property outright, turn its follow off first: `copyX`, `copyY`, `copyAlpha` and
  `copyAngle` each stop the note recomputing that one, after which a plain `x` / `alpha` write holds.

This is also how you reach a note's other settings that the callback didn't pass:

| Field | What it does |
|-------|--------------|
| `texture` | give this note a custom sheet (head + hold) |
| `disableRGB` | turn off this note's recolor shader |
| `multAlpha` / `multSpeed` | per-note alpha / scroll-speed |
| `ignore` | note isn't judged |
| `noAnimation` / `noMissAnimation` | don't play the sing / miss anim |
| `hitHealth` / `missHealth` | health gained / lost |
| `hitCausesMiss`, `blockHit`, `lowPriority`, `hitsound`, `hitsoundDisabled`, `splashDisabled`, ... | the other per-note knobs |

Full list: `objects/notes/NoteData.hx`. In HScript you can also just touch `game.spawnNote` (the note
spawning right now).

### 2.2 Strums / receptors

The receptors are `game.playerReceptors` and `game.opponentReceptors` - arrays with one entry per
lane. Move or restyle them directly:

```lua
setPropertyFromGroup('playerReceptors', 0, 'x', 500)   -- player's leftmost receptor
```

`x` / `y` / `alpha` / `angle` writes stick; other props may be read-only. (The old `playerStrums` /
`opponentStrums` / `strumLineNotes` names still point at these same receptors, but use the direct
names above.)

### 2.3 Note skins from a script

Read the chosen skin:

```lua
getPropertyFromClass('backend.ClientPrefs', 'data.noteSkin')       -- e.g. "Default"
getPropertyFromClass('backend.ClientPrefs', 'data.forceNoteSkin')  -- see 5.5
```

Change how a single note looks. **These act on the note in `onSpawnNote`, so call them there.** Each
returns `false` if no note is spawning:

| Function | What it does |
|----------|--------------|
| `setNoteSkin(image)` | reskin the note's **head** from sparrow atlas `image` |
| `setNoteTexture(texture)` | reskin the **whole** note (head + body + tail) from one atlas |
| `setNoteTexturePart(part, source, asImage)` | reskin **one part**: `part` = `'head'` / `'hold'` / `'tail'`. `asImage=false` = atlas, `true` = single image. Lets you mix parts. |
| `setNoteColorable(colorable, part)` | toggle the recolor shader. `part` = `'all'` / `'head'` / `'hold'` |

```lua
function onSpawnNote(id, column, noteType, isSustain, time, mustPress)
    if noteType == 'BulletNote' then
        setNoteTexture('BULLETNOTE_assets')
        setNoteColorable(false)
    end
end
```

(HScript can skip these and set `game.spawnNote.head.texture` / `.sustain.texture` and `rgbEnabled`
directly.) Section 5 explains the skin files these point at.

### 2.4 Three easy mistakes

- **Using `i`/loop counters in note callbacks.** Inside a note callback there is no `i`; Lua turns it
  into `0`, so you keep hitting note 0. Use the `id` argument.
- **`game.notes.members[...]` in hit/miss.** `id` is `-1` there, so this is always wrong. Read
  `game.lastJudgedNote`.
- **Holding on to a note's sprite past its lifetime.** Heads and trails are pooled: the sprite you
  styled in `onSpawnNote` is handed to a different note once yours leaves. Do your styling in
  `onSpawnNote` every time rather than caching the sprite, and use `onDespawnNote` to drop anything
  you were tracking. The engine resets colour, flip, blend and camera assignment when a sprite is
  reused, so a tint no longer bleeds onto an unrelated note -- but a reference you kept is still
  pointing at a sprite that has moved on.

### 2.5 Worked example: a custom note type

A very common pattern: a note type that reskins every note of its type and stops the player from
ignoring it. Here is the old shape and its conversion.

**Old** - loops the whole chart up front in `onCreate`, edits `unspawnNotes`:

```lua
function onCreate()
    precacheImage('BULLETNOTE_assets')
    for i = 0, getProperty('unspawnNotes.length') - 1 do
        if getPropertyFromGroup('unspawnNotes', i, 'noteType') == 'bulletnote' then
            setPropertyFromGroup('unspawnNotes', i, 'texture', 'BULLETNOTE_assets')
            if getPropertyFromGroup('unspawnNotes', i, 'mustPress') then
                setPropertyFromGroup('unspawnNotes', i, 'ignoreNote', false)
            end
        end
    end
end

function goodNoteHit(id, direction, noteType, isSustainNote)
    if noteType == 'bulletnote' then
        characterPlayAnim('dad', 'attack', true)
    end
end
```

**New** - the loop becomes `onSpawnNote` (runs once per note), `texture`/`ignoreNote` become
`setNoteTexture`/`ignore`, and `characterPlayAnim` becomes `playAnim` (the Script Converter does that
last rename for you):

```lua
function onCreate()
    precacheImage('BULLETNOTE_assets')
end

function onSpawnNote(id, column, noteType, isSustain, time, mustPress)
    if noteType == 'bulletnote' then
        setNoteTexture('BULLETNOTE_assets')                       -- reskin this note
        local field = mustPress and 'playerField' or 'opponentField'
        setPropertyFromGroup('game.'..field..'.notes', id, 'ignore', false)
    end
end

function goodNoteHit(id, column, noteType, isSustain)
    if noteType == 'bulletnote' then
        playAnim('dad', 'attack', true)
    end
end
```

Tip: for a note *type*, you can skip the reskin script entirely by putting `"texture":
"BULLETNOTE_assets"` in the note type's JSON.

### 2.6 Worked example: a hit callback

A hit callback that makes a character sing the lane you just hit. Its old comment is worth showing
because it spells out the mental model V2 breaks.

**Old:**

```lua
-- id: the note member id, e.g. getPropertyFromGroup('notes', id, 'strumTime')
-- noteData: 0 = Left, 1 = Down, 2 = Up, 3 = Right
function goodNoteHit(id, noteData, noteType, isSustainNote)
    if noteType == 'Duet' then
        if noteData == 0 then characterPlayAnim('gf', 'singLEFT', true) end
        if noteData == 1 then characterPlayAnim('gf', 'singDOWN', true) end
        -- ...
    end
end
```

That comment's advice - `getPropertyFromGroup('notes', id, 'strumTime')` - is now broken three ways:
`id` is `-1` here, `notes` is only a compat mirror, and the field is `time`, not `strumTime`.

**New** - the lane is now `column` (same position), `characterPlayAnim` becomes `playAnim`, and if you
need the note itself you read `game.lastJudgedNote`:

```lua
function goodNoteHit(id, column, noteType, isSustain)
    if noteType == 'Duet' then
        if column == 0 then playAnim('gf', 'singLEFT', true) end
        if column == 1 then playAnim('gf', 'singDOWN', true) end
        -- ...
    end
    -- 'id' is -1 in hit callbacks, so to read the note that was hit (its time, length, etc.)
    -- go through game.lastJudgedNote, e.g.:  local hitTime = getProperty('lastJudgedNote.time')
end
```

Any pre-V2 modpack with custom note types or hit/miss callbacks makes a good conversion test - these
two patterns cover most of what you will run into.

---

## 3. Checklist

1. Run the **Script Converter** (fixes the field renames and the moved type paths).
2. In hit/miss callbacks, read `game.lastJudgedNote` instead of the first argument.
3. Target `game.playerField` / `game.opponentField` (with the `onSpawnNote` `id`) instead of
   `game.notes` / `unspawnNotes`.
4. Move `unspawnNotes` loops into `onSpawnNote`.
5. Move strum edits to `playerReceptors` / `opponentReceptors`.
6. Can't do the above? Set `compatibilityMode: true` in `pack.json` (a temporary bridge - see
   section 6).

### The Script Converter: two modes

The **Convert** dropdown picks how much the converter is allowed to change. The split is by the KIND
of edit, not by how confident the tool is:

| Mode | Applies | Leaves alone |
|------|---------|--------------|
| **Renames and paths only** (default) | note-field renames (`strumTime` -> `time` and the rest of [1.1](#11-renamed-note-fields)), the old Lua callback renames (`characterPlayAnim` -> `playAnim`, ...), and moved type paths (`psychlua.LuaUtils` -> `scripting.lua.LuaUtils`) | anything that changes the shape of a line |
| **Renames plus code rewrites** | the above, plus `isSustainNote` -> `isSustain()` | assignment targets and Lua string properties (see below) |

A rename swaps one name for another and leaves the structure of the line intact, so you can check the
whole diff by eye. A rewrite can be right about the API and still wrong about your code - which is why
it is opt-in rather than a judgement the tool makes for you.

`isSustainNote` is the one rewrite that exists today, and it is a good example of the difference: it
was a field and `isSustain()` is a method, so the read has to become a call. That is correct for a
plain `note.isSustainNote` read, and wrong the moment the name is being *assigned to* -
`note.isSustain() = true` is not valid in either language. The converter skips assignments and Lua
string properties (`setProperty('isSustainNote', ...)`, which can't carry a call) in both modes.

Whatever a mode declines to rewrite is not lost: it is reported in `script-convert-report.txt` and
commented in place in the `.converted` copy, so you can fix it by hand with the context in front of
you. The report names the mode it ran in.

**Suggested order:** run the default first and read the report. If the only thing left is
`isSustainNote` reads, run again with rewrites on and diff the two.

---

## 4. Note skins

Skins changed too, but that has its own docs - here is only what a migrating pack needs to know:

- **Old single-sheet `NOTE_assets` skins still work.** They load as "classic" skins, so existing packs
  keep their arrows with no changes.
- **`arrowSkin` in the chart still applies**, unless the player turns on Force Note Skin.
- The modern format is **folder skins** (individual images + a `skin.tcfg`), which unlock per-lane
  config, hi-res, folder splashes, and pixel variants.
- From a script, reskin a note with `setNoteTexture` / `setNoteTexturePart` / `setNoteColorable` in
  `onSpawnNote` (see [2.3](#23-note-skins-from-a-script)).

Full formats, config, and how to build or convert skins: **[The Note Skin System](note-skin-system.md)**
(how skins work and are chosen) and **[Making Note Skins](making-note-skins.md)** (authoring reference).

---

## 5. Full reference: what broke or changed

Only the old note-system and skin idioms that changed. Anything not listed here (e.g. `noteMissPress`,
`onGhostTap`, `noteTweenX/Y/Angle`, `defaultPlayerStrumX#`, `arrowSkin`, old `NOTE_assets` sheets)
still works as before. **"Broken"** means it silently does nothing in V2 unless `compatibilityMode` is
on (section 6). `<side>` = `player` or `opponent`.

### Notes: how you reach them

| Old idiom | Status | Do this instead |
|-----------|--------|-----------------|
| `game.notes`, `notes.members`, `getPropertyFromGroup('notes', id, ...)` | Broken (list is empty) | `game.<side>Field.notes` with the `onSpawnNote` `id` |
| `game.unspawnNotes`, `getProperty('unspawnNotes.length')` loops | Broken (under compat: load-time only) | move the loop into `onSpawnNote` |
| `setPropertyFromGroup('unspawnNotes', i, ...)` | Broken | `setPropertyFromGroup('game.<side>Field.notes', id, ...)` in `onSpawnNote` |

### Note fields

Renamed or removed - see the table in [1.1](#11-renamed-note-fields) (`strumTime`->`time`,
`noteData`->`column`, `noteType`->`type`, `sustainLength`->`length`, `wasGoodHit`/`noteWasHit`->`hit`,
`ignoreNote`->`ignore`, `isSustainNote`->`isSustain()`, and `distance`, `prevNote`, `nextNote`, `tail`,
`parent` removed). The Script Converter fixes all of these except `noteType` (see
[1.1](#11-renamed-note-fields)) and `isSustainNote`, which needs the rewrites mode (see
[Script Converter modes](#the-script-converter-two-modes)).

### Callbacks

| Old idiom | Status |
|-----------|--------|
| Using the hit/miss callback's first arg as a note index | It's `-1` now - read `game.lastJudgedNote` |
| `getPropertyFromGroup('notes', id, 'strumTime')` inside a hit/miss callback | Broken 3 ways (`id` is `-1`, `notes` empty, field renamed) - use `getProperty('lastJudgedNote.time')` |
| `onSpawnNote`'s first arg | Works, but it now means the note's index in its field - use it with `game.<side>Field.notes` |

### Per-note color and texture

| Old idiom | Status | Do this instead |
|-----------|--------|-----------------|
| `setPropertyFromGroup('notes', id, 'rgbShader.r'/'g'/'b', ...)` (recolor) | Broken via `notes` | same write on `game.<side>Field.notes` with the `onSpawnNote` `id` (the note drawable has `rgbShader`) |
| `setPropertyFromGroup('unspawnNotes', i, 'texture', ...)` | Broken | `setNoteTexture(...)` in `onSpawnNote`, or `"texture"` in the note-type JSON |
| `noteSplashHue` / `noteSplashSat` / `noteSplashBrt` | Gone (silently ignored) | the skin's `splash` config, `splashDisabled`, or `disableRGB` |
| per-note `copyX`/`copyY`/`copyAngle`, `scrollFactor`, `offsetX`/`offsetY` | Set them on the field note | `setPropertyFromGroup('game.<side>Field.notes', id, ...)` in `onSpawnNote` |

### Strums / receptors

| Old idiom | Status |
|-----------|--------|
| Re-skinning a strum's texture at runtime (`'texture'` on a receptor) | Does not apply - the note skin owns the receptor look |

(Otherwise the receptors - `game.playerReceptors` / `game.opponentReceptors` - still take the usual
`x`/`y`/`alpha`/`angle` and `rgbShader.*` writes.)

---

## 6. compatibilityMode (the legacy bridge - a last resort)

For a pack you can't update yet, add to its `pack.json`:

```json
{ "compatibilityMode": true }
```

(`legacyMode` is the same thing.) This mirrors the old `game.notes` / `game.unspawnNotes` API over the
V2 runtime so old scripts keep running unchanged.

Treat it as a temporary crutch, not a fix. It **does not exist on psych-v2.0.0**, so a pack that leans
on it stops working the moment legacy is dropped. Use it to buy time, then migrate to the native
fields above - that is the only version-proof path.

Even while it's on, it can't add or remove notes mid-song (only load-time `unspawnNotes` edits apply),
its `game.notes` members aren't real sprites, and hit/miss callbacks still pass `id = -1` (use
`game.lastJudgedNote`).

---

## 7. Where this lives in source

- `objects/notes/NoteData.hx` - the note fields.
- `objects/notes/NoteField.hx`, `NoteSprite.hx`, `SustainSprite.hx` - the sprites/pool.
- `states/PlayState.hx` - callbacks, `lastJudgedNote`, the fields and strum aliases.
- `scripting/lua/api/ReflectionFunctions.hx`, `scripting/lua/LuaUtils.hx` - `getProperty` family,
  `setNoteSkin`.
- `scripting/lua/FunkinLua.hx` - `setNoteTexture` / `setNoteTexturePart` / `setNoteColorable`.
- `backend/tools/scriptconvert/` - the Script Converter.
- `backend/NoteSkinConfig.hx`, `backend/noteskin/` - the skin system.
- `legacy/NoteCompatLayer.hx` - the `compatibilityMode` bridge.
