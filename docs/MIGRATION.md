# Mod Migration Guide

Every script-facing break in this fork, newest version first. If your mod ran on an older build and
does not now, the reason should be on this page.

The Lua / HScript surface is kept stable on purpose, so most mods need nothing from here. What does
change gets listed with its replacement rather than just being removed.

> **Run the Script Converter first.** Editors -> Converters -> Script Converter scans a mod and
> applies the mechanical half of this page for you, writing `*.converted` copies next to your scripts
> and never touching the originals. Every rename in the tables below marked **auto** is one it fixes.
> See [Script Converter modes](NOTE_SYSTEM_V2_MIGRATION.md#the-script-converter-two-modes).

## Contents

- [Version map](#version-map)
- [1.3.0](#130)
  - [Scripting packages moved](#scripting-packages-moved)
  - [Notes, callbacks and skins](#notes-callbacks-and-skins)
  - [Script hooks](#script-hooks)
  - [Older Lua callback renames](#older-lua-callback-renames)
  - [objects.BGSprite is gone](#objectsbgsprite-is-gone)
  - [Data and folder layout](#data-and-folder-layout)
- [1.1](#11)
  - [Modpack metadata](#modpack-metadata)
  - [Camera filters API (Shaders)](#camera-filters-api-shaders)
  - [FlxAnimate to flixel-animate (Texture Atlas)](#flxanimate-to-flixel-animate-texture-atlas)
- [2.0.0 (not released)](#200-not-released)
- [Need help?](#need-help)

---

## Version map

| Version | What it is |
| --- | --- |
| **1.0.4** | the upstream Psych release this fork started from |
| **1.1** | first fork release: camera filters, texture-atlas backend swap, pack.json types |
| **1.3.0** | current development line: Note System V2, the scripting package restructure, song packages |
| **2.0.0** | separate branch, not released. Removes the legacy layer entirely |

There was no 1.2 release; the line went 1.1 to 1.3.0.

---

## 1.3.0

### Scripting packages moved

`psychlua`, `llua` and `scripting` were one subsystem under three package names. It is now all
`scripting.*`, and the thin `llua` aliases resolve to the `hxluajit` types they always were.

**This only affects scripts that name a type by its full path** - `import psychlua.LuaUtils;` in
HScript, `import('psychlua.LuaUtils')` in LuaProxy Lua. The bare names scripts normally see
(`CustomSubstate` and friends) never changed, so most mods are unaffected.

All of these are **auto**:

| Old path | New path |
| --- | --- |
| `psychlua.ReflectionFunctions` | `scripting.lua.api.ReflectionFunctions` |
| `psychlua.FlxAnimateFunctions` | `scripting.lua.api.FlxAnimateFunctions` |
| `psychlua.DeprecatedFunctions` | `scripting.lua.api.DeprecatedFunctions` |
| `psychlua.ModchartAnimateSprite` | `scripting.lua.ModchartAnimateSprite` |
| `psychlua.ShaderFunctions` | `scripting.lua.api.ShaderFunctions` |
| `psychlua.ExtraFunctions` | `scripting.lua.api.ExtraFunctions` |
| `psychlua.TextFunctions` | `scripting.lua.api.TextFunctions` |
| `psychlua.CallbackHandler` | `scripting.lua.CallbackHandler` |
| `psychlua.ModchartSprite` | `scripting.lua.ModchartSprite` |
| `psychlua.CustomSubstate` | `scripting.lua.CustomSubstate` |
| `psychlua.DebugLuaText` | `scripting.lua.DebugLuaText` |
| `psychlua.PropertyPath` | `scripting.lua.PropertyPath` |
| `psychlua.PsychInterp` | `scripting.hscript.PsychInterp` |
| `psychlua.FunkinLua` | `scripting.lua.FunkinLua` |
| `psychlua.LuaProxy` | `scripting.lua.LuaProxy` |
| `psychlua.LuaUtils` | `scripting.lua.LuaUtils` |
| `psychlua.HScript` | `scripting.hscript.HScript` |
| `llua.Lua_helper` | `scripting.lua.Lua_helper` |
| `llua.Convert` | `scripting.lua.Convert` |
| `llua.LuaL` | `hxluajit.LuaL` |
| `llua.Lua` | `hxluajit.Lua` |

One has no single-path equivalent and is **not** auto-fixed: `llua.State` was an alias for a raw
pointer, now written `cpp.RawPointer<hxluajit.Types.Lua_State>`. Scripts effectively never named it.

### Notes, callbacks and skins

Note System V2 replaced the note runtime: a note is data plus a pooled drawable rather than one
object, and a hold is a single note rather than a head plus a tail chain. The field renames are
**auto**:

| Old field | New | |
| --- | --- | --- |
| `strumTime` | `time` | auto |
| `noteData` | `column` | auto |
| `sustainLength` | `length` | auto |
| `wasGoodHit` / `noteWasHit` | `hit` | auto |
| `ignoreNote` | `ignore` | auto |
| `isSustainNote` | `isSustain()` | auto, rewrites mode only |
| `noteType` | `type` | by hand - the converter cannot tell the field from the callback argument of the same name |
| `distance`, `prevNote`, `nextNote`, `tail`, `parent` | removed | by hand |

Callback arguments, `game.lastJudgedNote`, the `unspawnNotes` loop that becomes `onSpawnNote`, the
strum groups that become note fields, and the note-skin formats each need more than a table:
**[Note System V2 migration guide](NOTE_SYSTEM_V2_MIGRATION.md)** covers all of it, and is the one to
read if your mod touches notes at all.

Can't migrate yet? `"compatibilityMode": true` in `pack.json` puts a pack back on the legacy layer.
It is a stopgap - 2.0.0 removes it.

### Script hooks

**Every hook can now be written `onX`.** Eight predate that convention and are still dispatched under
their original names, so nothing breaks; each simply also answers to its `onX` spelling. If a script
declares the original name it keeps it, and the alias only binds when the original is absent.

| Original (still works) | Also answers to |
| --- | --- |
| `goodNoteHit` | `onGoodNoteHit` |
| `goodNoteHitPre` | `onGoodNoteHitPre` |
| `opponentNoteHit` | `onOpponentNoteHit` |
| `opponentNoteHitPre` | `onOpponentNoteHitPre` |
| `noteMiss` | `onNoteMiss` |
| `noteMissPress` | `onNoteMissPress` |
| `eventEarlyTrigger` | `onEventEarlyTrigger` |
| `preUpdateScore` | `onUpdateScorePre`, `onPreUpdateScore` |

There is deliberately no alias in the other direction: a hook is never reachable as a bare `update`
or `spawnNote`, because those are names a script is likely to use for its own helpers.

New hooks, none of which break anything - they exist so a script can stop polling in `onUpdate`:

| Hook | Fires when |
| --- | --- |
| `onSelectionChange` | the highlighted entry changed in Freeplay / Story |
| `onDifficultyChange` | the chosen difficulty changed |
| `onSongSelected` | a song is about to load. `Function_Stop` cancels |
| `onWeekSelected` | a week is about to load. `Function_Stop` cancels |
| `onChartParsed` | the chart is parsed, before it becomes notes |
| `onNoteSkinLoaded` / `onUISkinLoaded` | the song resolved a skin |
| `onStrumsCreated` | receptors and note fields all exist |
| `onKeyCountChange` | a strumline's key count changed |
| `onDespawnNote` | a note left play, however it left |
| `onSustainRelease` | a hold was dropped early |
| `onCharacterChange` | a Change Character swap finished |
| `onHealthChange` | health changed, with the previous value |
| `onSongRetry` / `onSongExit` | the player restarted or left the song |
| `onResults` | the results screen is about to open |
| `onAchievementUnlocked` | an achievement unlocked |
| `onModSwitched` | the active mod changed |
| `onStageChanged` | the `Change Stage` event swapped the stage |

Full list with arguments: [script hooks and dispatch](script-hooks-and-dispatch.md).

### Older Lua callback renames

Long-deprecated Lua callbacks that still worked through a compatibility shim. All **auto**:

| Old | New |
| --- | --- |
| `addAnimationByIndicesLoop` | `addAnimationByIndices` |
| `objectPlayAnimation` | `playAnim` |
| `characterPlayAnim` | `playAnim` |
| `luaSpriteMakeGraphic` | `makeGraphic` |
| `luaSpriteAddAnimationByPrefix` | `addAnimationByPrefix` |
| `luaSpriteAddAnimationByIndices` | `addAnimationByIndices` |
| `luaSpritePlayAnimation` | `playAnim` |
| `setLuaSpriteCamera` | `setObjectCamera` |
| `setLuaSpriteScrollFactor` | `setScrollFactor` |
| `scaleLuaSprite` | `scaleObject` |
| `getPropertyLuaSprite` | `getProperty` |
| `setPropertyLuaSprite` | `setProperty` |
| `musicFadeIn` | `soundFadeIn` |
| `musicFadeOut` | `soundFadeOut` |
| `updateHitboxFromGroup` | `updateHitbox` |

### objects.BGSprite is gone

Every compiled stage was built out of `BGSprite`, so it lived in the engine and was a global import.
The base game is a modpack now and its stages set their props up themselves, which left the engine
carrying a class only mods used.

It is **not** auto-fixed. There is no drop-in replacement, because `BGSprite` was a constructor
rather than a name: what it did was four lines on a plain `FlxSprite`.

```haxe
// before
var bg:BGSprite = new BGSprite('sky', -100, 0, 0.3, 0.3);

// after
var bg:FlxSprite = new FlxSprite(-100, 0);
bg.loadGraphic(Paths.image('sky'));
bg.scrollFactor.set(0.3, 0.3);
bg.active = false;                                   // it never animates
bg.antialiasing = ClientPrefs.data.antialiasing;
```

With an animation array, swap the `loadGraphic` line for the atlas and its prefixes, and drop the
`active = false`:

```haxe
bg.frames = Paths.getSparrowAtlas('sky');
bg.animation.addByPrefix('idle', 'sky idle', 24, false);
bg.animation.play('idle');
```

`dance()` came from `BGSprite` too; it replayed the first animation added, so it becomes
`animation.play(idleName, forceplay)`.

A stage that builds many props is better off with a private helper than with the four lines repeated
-- that is what the base-game stages do, and why this is not simply a rename.

Subclassing it is also gone, and that is a small mercy: a scripted subclass of `BGSprite` threw
"Null Function Pointer" from its constructor for two of the three base-game props that tried it.

### Data and folder layout

Neither of these needs anything from a script - both migrate existing installs on their own - but
they change where files live, which matters if your mod ships or reads them.

- **`database/`** now holds the engine's `.db` files (the freeplay library, profiles, scores)
  instead of the game root. Existing files are moved on first launch.
- **Song packages**: a song owns its folder. `songs/<songKey>/` holds the charts, metadata, events
  and audio together, replacing the old split between `data/<song>/` and `songs/<song>/`. Old layouts
  still resolve - `SongPaths` falls back through the previous shapes - and the in-engine
  **Chart Converter** moves a mod to the new layout. See [song packages](song-packages.md).

---

## 1.1

The first fork release. Two of these are runtime breaks for mods that touch them, and the Script
Converter does not cover either - they are API shape changes, not renames.

### Modpack metadata

Extended pack.json metadata a bit for convenience.
- Two types of packs, defined in pack.json. "Mod pack" or "Script Pack"
  - Script packs run globally and are always accessable through pause menus "Mod Settings".
  - Mod packs run locally with the option to opt in using "runsGlobally" as usual. If a mod pack has settings, it will also show up in pause menus "Mod Settings".

If no type is specified, it defaults to "modpack". So if your modpack is a collection of scripts, you should set type to "scriptpack" or runsGlobally to "true". I recommend setting type over runsGlobally as there may be changes to how runsGlobally is handled.


### Camera filters API (Shaders)

The old camera helper methods were removed when HaxeFlixel turned
`FlxCamera.filters` into a plain public field. Mods that previously called
those methods will now throw `Tried to call null function setFilters` (or
similar) when run.

#### What changed

| Removed (Psych 1.0.4)              | Replace with (Psych 1.1)                       |
| ---------------------------------- | ---------------------------------------------- |
| `camera.setFilters([...])`         | `camera.filters = [...]`                       |
| `camera.addFilter(filter)`         | `camera.filters.push(filter)` *(init if null)* |
| `camera.removeFilter(filter)`      | `camera.filters.remove(filter)`                |
| `camera.clearFilters()`            | `camera.filters = null`                        |

Applies to **all** cameras (`camGame`, `camHUD`, `camOther`, custom cameras),
not just `PsychCamera`.

#### Before (1.0.4, HScript)

```haxe
camHUD.setFilters([new ShaderFilter(shader)]);
// ...
camHUD.clearFilters();
```

#### After (1.1, HScript)

```haxe
camHUD.filters = [new ShaderFilter(shader)];
// ...
camHUD.filters = null;
```

#### Adding / removing a single filter

```haxe
// add
if (camHUD.filters == null) camHUD.filters = [];
camHUD.filters.push(new ShaderFilter(shader));

// remove
if (camHUD.filters != null) {
    camHUD.filters.remove(myFilter);
    if (camHUD.filters.length == 0) camHUD.filters = null;
}
```
---

### FlxAnimate to flixel-animate (Texture Atlas)

The Adobe Animate / Texture Atlas backend was swapped from
[`Dot-Stuff/flxanimate`](https://github.com/Dot-Stuff/flxanimate) to
[`MaybeMaru/flixel-animate`](https://github.com/MaybeMaru/flixel-animate).

This is a **breaking change** for any mod that imports the atlas library
directly in HScript, or that touches `sprite.anim.curInstance` /
`sprite.anim.curSymbol` / the old `pauseAnimation()` / `resumeAnimation()`
helpers from HScript or Lua callbacks.

Most mods do **not** need any changes: characters declared via
`character.json` (with a sibling `Animation.json`) continue to load and play
exactly as before. The Lua helpers `makeFlxAnimateSprite`,
`loadAnimateAtlas`, `addAnimationBySymbol`, and `addAnimationBySymbolIndices`
keep the same names and parameters - see [Lua bindings](#lua-bindings)
for the one signature trim.

#### Why the swap

- The new library reuses Flixel's standard `FlxAnimationController`, so
  texture-atlas sprites now expose the *same* `anim.play() / .finished /
  .curAnim / .pause() / .resume()` surface as regular `FlxSprite`s. No more
  parallel "symbol" API to learn.
- `FlxAnimateFrames.fromAnimate(...)` auto-detects spritemap exports, so
  Psych's custom `PsychFlxAnimate.loadAtlasEx` subclass is gone (the
  multi-format loader logic now lives in upstream).
- It is actively maintained and ships fixes/features that the older fork
  never received.

#### Package / import changes

| Old (`flxanimate`)                           | New (`flixel-animate`)                  |
| -------------------------------------------- | --------------------------------------- |
| `import flxanimate.FlxAnimate;`              | `import animate.FlxAnimate;`            |
| `import flxanimate.frames.FlxAnimateFrames;` | `import animate.FlxAnimateFrames;`      |
| `import flxanimate.PsychFlxAnimate;`         | **removed** - use `animate.FlxAnimate`  |
| `#if flxanimate`                             | `#if flixel_animate`                    |

In HScript the engine pre-registers `FlxAnimate` for you (it points at
`animate.FlxAnimate`), so `new FlxAnimate(x, y)` keeps working without an
explicit `import`.

#### API translation table

All of these are **runtime-breaking** if your mod scripts touch them.

| Removed (old `flxanimate`)                                       | Replace with (new `flixel-animate`)                                  |
| ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| `sprite.anim.curInstance`                                        | `sprite.isAnimate` *(bool: "is currently playing a texture atlas")*   |
| `sprite.anim.curSymbol`                                          | `sprite.library` / `sprite.timeline` *(or `sprite.anim.curAnim`)*     |
| `sprite.anim.curInstance.symbol.name`                            | `sprite.anim.name` *(name passed to the last `play()`)*               |
| `sprite.anim.length`                                             | `sprite.anim.curAnim.numFrames` *(per-animation frame count)*         |
| `sprite.anim.curFrame` *(controller-level, animation-relative)*  | `sprite.anim.curAnim.curFrame` *(guard `curAnim != null`)*            |
| `sprite.anim.curFrame = N`                                       | `sprite.anim.curAnim.curFrame = N` *(guard `curAnim != null`)*        |
| `sprite.anim.isPlaying`                                          | `!sprite.anim.paused` *(or check `sprite.anim.finished`)*             |
| `sprite.anim.onComplete` *(FlxSignal)*                           | `sprite.anim.onFinish` *(FlxTypedSignal<(name:String)\->Void>)*       |
| `sprite.anim.animsMap` *(internal map, used with `@:privateAccess`)* | `sprite.anim.remove(name)` *(public method, no privateAccess needed)* |
| `sprite.anim.metadata`                                           | `sprite.library.frameRate` *(plus `sprite.timeline`)*                 |
| `sprite.pauseAnimation()`                                        | `sprite.anim.pause()`                                                 |
| `sprite.resumeAnimation()`                                       | `sprite.anim.resume()`                                                |
| `sprite.showPivot = false;`                                      | **removed** - no longer drawn, delete the line                        |
| `sprite.loadAtlasEx(img, json, anim)` *(Psych subclass)*         | `Paths.loadAnimateAtlas(sprite, folder)` *or* `sprite.frames = FlxAnimateFrames.fromAnimate(...)` |
| `sprite.anim.addBySymbol(name, sym, fps, loop, matX, matY)`      | `sprite.anim.addBySymbol(name, sym, fps, loop, flipX, flipY)` *(matX/matY dropped)* |
| `sprite.anim.addBySymbolIndices(..., matX, matY)`                | same minus `matX, matY`                                               |

Unchanged: `sprite.anim.play(name, force, reverse, frame)`,
`sprite.anim.finished`, `sprite.anim.paused`, `sprite.anim.name`,
`Paths.loadAnimateAtlas(sprite, folder)`.

> **Note on `onFinish` callback signature.** The old `onComplete` listener
> took no arguments. The new `onFinish` dispatches the *animation name*
> as a single `String` parameter. If your old listener was
> `function() { ... }`, change it to `function(name:String) { ... }`
> (or `_ -> ...`). The same applies to `signal.has(listener)` /
> `signal.remove(listener)` - they only match by reference, so the listener
> stored must already have the new signature.

#### HScript example

```haxe
// 1.0.4
import flxanimate.FlxAnimate;

var atlas = new FlxAnimate(100, 100);
atlas.showPivot = false;
Paths.loadAnimateAtlas(atlas, 'cutscenes/myAtlas');
atlas.anim.addBySymbol('idle', 'My Symbol', 24, true);
atlas.anim.onComplete.add(function() trace('done'));
atlas.anim.play('idle', true);

function onUpdate(elapsed:Float) {
    if (atlas.anim.curInstance != null && atlas.anim.curSymbol != null) {
        // ...
    }
    if (someCondition) atlas.pauseAnimation();
    else atlas.resumeAnimation();
}
```

```haxe
// 1.1
// `FlxAnimate` is pre-imported by HScript; no `import` line needed.
var atlas = new FlxAnimate(100, 100);
Paths.loadAnimateAtlas(atlas, 'cutscenes/myAtlas');
atlas.anim.addBySymbol('idle', 'My Symbol', 24, true);
atlas.anim.onFinish.add(function(name:String) trace('done: ' + name));
atlas.anim.play('idle', true);

function onUpdate(elapsed:Float) {
    if (atlas.isAnimate) {
        // ...
    }
    atlas.anim.paused = someCondition; // or atlas.anim.pause()/resume()
}
```

#### Lua bindings

All Lua callbacks keep their names. Two of them dropped trailing
parameters that the new library no longer supports:

| Callback                          | 1.0.4 signature                                                                | 1.1 signature                                                            |
| --------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `makeFlxAnimateSprite`            | `(tag, x, y, loadFolder)`                                                      | unchanged                                                                |
| `loadAnimateAtlas`                | `(tag, folderOrImg, spriteJson, animationJson)`                                | unchanged                                                                |
| `addAnimationBySymbol`            | `(tag, name, symbol, framerate, loop, matX, matY)`                             | `(tag, name, symbol, framerate, loop)` - *`matX`/`matY` ignored*         |
| `addAnimationBySymbolIndices`     | `(tag, name, symbol, indices, framerate, loop, matX, matY)`                    | `(tag, name, symbol, indices, framerate, loop)` - *`matX`/`matY` ignored* |

Lua scripts that pass `matX` / `matY` continue to load without errors
(the extra arguments are silently dropped by the Haxe callback dispatcher),
but the offsets will no longer apply. If you relied on them, apply the
offset by adjusting `sprite.x` / `sprite.y` instead.

#### `Paths.loadAnimateAtlas` behavior

The helper is still the recommended entry point and its signature is
unchanged:

```haxe
Paths.loadAnimateAtlas(spr, folderOrImg, spriteJson = null, animationJson = null);
```

Internally it now:

1. Reads `images/<folder>/Animation.json` through Psych's mod-aware path
   resolver.
2. Picks up an optional `images/<folder>/metadata.json` if present (newer
   Animate exports ship one).
3. Walks `spritemap0.json` → `spritemap9.json` and pairs each with its
   matching `spritemap<N>.png`, supporting multi-page atlases out of the
   box.
4. Hands everything to `animate.FlxAnimateFrames.fromAnimate(...)` so the
   sprite gets a normal `FlxAtlasFrames` collection on its `.frames`
   property - no more custom subclass required.

If you previously called `spr.loadAtlasEx(...)` directly, switch the
call to `Paths.loadAnimateAtlas(spr, folder)` (or build a
`FlxAnimateFrames.fromAnimate(...)` call yourself with the JSON content
and spritemap inputs).

---

## 2.0.0 (not released)

A separate branch, listed here so nothing on it is a surprise:

- **The legacy layer is gone.** `compatibilityMode` / `legacyMode` do nothing; every idiom this page
  marks as legacy-only stops working. Migrating now is what keeps a pack running then.

---

## Need help?

If your mod relied on something not covered here, open an issue report and we will either document the migration step or add a compatibility shim where it makes sense.
