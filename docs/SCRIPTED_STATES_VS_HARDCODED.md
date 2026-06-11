# Scripted states vs. hardcoded states — what's different

A scripted state (`mods/<Mod>/states/*.hx`) is **not** a 1:1 copy of the engine's
compiled state. The engine does several setup chores for you, and some things that
are *code* in a hardcoded state are *configuration* (pack.json) in a scripted one.

If you port a compiled state by pasting it verbatim, you'll usually write code that
is redundant — or actively wrong (pointing asset lookups at the wrong mod, fighting
the engine's camera/music setup, etc.). This page lists what to **leave out** and
what moves to **pack.json**.

For the full how-to, see [SCRIPTED_STATES.md](SCRIPTED_STATES.md). This page is just
the "what's different / stop scripting this" cheat-sheet.

---

## 1. Things the engine already does — don't script them unless you HAVE to.

| Chore | Hardcoded state does… | In a scripted state… |
|-------|------------------------|----------------------|
| **Camera** | `initPsychCamera()` / `FlxG.cameras.reset(...)` in `create()` | **Done for you** before `create()` runs. No `super.create()` needed. |
| **Mod asset scoping** | n/a (engine state) | **Auto-scoped to your mod.** Don't call `Mods.currentModDirectory = ...`, `Mods.pushGlobalMods()`, or `Mods.loadTopMod()`. Just use `Paths.*`. |
| **Menu music on launch** | the menu relies on music already playing | When your mod is **launched**, the engine swaps to your mod's menu music for you (see pack.json `menuMusic`). |
| **Returning from a song** | menus hardcode going to Freeplay/Story | A song started from your scripted menu **auto-returns to it**. No return flag to set. |
| **Common imports** | `import flixel.*; import backend.*;` | `FlxG`, `FlxSprite`, `FlxText`, `Paths`, `Conductor`, `ClientPrefs`, `PlayState`, … are **already available** as bare identifiers. |

### Concrete example — what to delete when porting

A compiled `MainMenuState.create()` typically starts with something like:

```haxe
// In a scripted state, ALL of this is unnecessary:
override function create() {
    Mods.loadTopMod();
    Mods.currentModDirectory = 'My Mod';
    persistentUpdate = persistentDraw = true;

    var camGame = new FlxCamera();
    FlxG.cameras.reset(camGame);
    FlxG.cameras.setDefaultDrawTarget(camGame, true);

    super.create();
    ...
}
```

The scripted version is just:

```haxe
override function create() {
    persistentUpdate = persistentDraw = true;
    // ...your sprites/text.. // use Paths.image(...) directly
}
```

> Calling `super.create()` is still *safe* (it's idempotent and plays the built-in
> fade-in), it's just not required. The `Mods.*` calls are the dangerous ones to
> copy — they repoint asset resolution and are the usual cause of "my images load
> as the engine's defaults / a black screen."

---

## 2. Configuration that lives in `pack.json` (not in code)

Some behavior a hardcoded state would express in code is instead declared once in
your mod's `pack.json`:

```json
{
    "name": "My Mod",
    "entryState": "MainMenuState",
    "menuMusic": "myMenuTheme",
    "luaMode": "compat"
}
```

| Field | Default | What it does |
|-------|---------|--------------|
| `entryState` | `MainMenuState` | Which `states/<name>.hx` the engine enters when your mod is **launched**. The mod is only "launchable" if this file exists. |
| `menuMusic` | `freakyMenu` | Menu track played on launch (resolved from your mod's `music/`). Only swaps if your mod actually ships the file; otherwise the current menu music keeps playing. |
| `luaMode` | `compat` | Default Lua mode for the mod's scripts (`compat` = legacy callbacks + real-Lua proxies; `raw` = real Lua only). See [REAL_LUA.md](REAL_LUA.md). |

So: don't hand-roll "play my menu song" or "decide which menu opens first" logic in
a script if pack.json already covers it. (You *can* still do it in code if you want
runtime control, but make sure you know what you're doing in that case — pack.json is the no-code default.)

---

## 3. Things that are genuinely different (and you DO need to handle)

These aren't "the engine does it for you" — they're real differences in how scripts
behave vs. compiled Haxe.
These are our current limitations, these things are prone to change in the future.

- **`new() { super(); }` is required.** The interpreter needs a constructor that
  initializes the underlying `FlxState`. Omitting it fails to load with a clear error.
- **Bare enum values don't resolve.** No type inference, so `CENTER`/`LEFT` are
  unknown identifiers. Use the string form where the enum is a string abstract
  (`setFormat(font, size, color, 'center')`).
- **`import` has limits.** Whole-module imports work only if every sibling type
  resolves; sub-type imports (`import Module.SubType;`) don't. Prefer the injected
  globals or aliased single-type imports (`import flixel.ui.FlxButton as FlxButton;`).
  See SCRIPTED_STATES.md → *Import notes*.
- **Bare parent-field access is gone** (for stage/character/event scripts): use the
  injected `game` global instead of referencing `PlayState` fields directly.
- **Leaving a launched mod** is explicit: call `exitToEngine()` from your top
  menu's BACK handler (it returns to the engine Mods menu). `ModsMenuState` can
  never be overridden, so it's always the way back out.

---

## Quick checklist when porting a compiled state

- [ ] Remove `Mods.loadTopMod()` / `Mods.currentModDirectory = ...` / `Mods.pushGlobalMods()`.
- [ ] Remove manual camera creation/reset; drop `super.create()` (optional to keep).
- [ ] Remove imports for things already injected (FlxG/FlxSprite/FlxText/Paths/…).
- [ ] "menu song" → `menuMusic`.
- [ ] Keep `new() { super(); }`.
- [ ] Replace bare enum values with string forms; fix imports per the import notes.
- [ ] Don't set a song-return flag — exiting a song returns to your menu automatically.