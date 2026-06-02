# Class-based scripted states (hscript-insanity)

This fork swaps the HScript interpreter from **hscript-iris** to
**[hscript-insanity](https://github.com/inky03/hscript-insanity)** so that mods
can script **whole classes** — most usefully, entire game **states** (custom
menus, etc.), not just `onCreate`/`onUpdate` callback hooks.

## Writing a scripted state

Create `mods/<YourMod>/states/MyMenu.hx`. The class name must match the file
name and must extend `MusicBeatState` (the normal engine state class — the
engine makes it scriptable for you):

```haxe
class MyMenu extends MusicBeatState {
    // REQUIRED: call super() so the underlying FlxState gets initialized.
    public function new() {
        super();
    }

    override function create() {
        super.create();
        var text = new FlxText(0, 0, FlxG.width, "Hello from a scripted state!", 32);
        text.screenCenter();
        add(text);
    }

    override function update(elapsed:Float) {
        super.update(elapsed);
        if (controls.BACK)
            MusicBeatState.switchState(new states.MainMenuState());
    }

    override function beatHit() {
        super.beatHit();
        // pulse something on the beat
    }
}
```

You can `override` any inherited lifecycle method (`create`, `update`,
`beatHit`, `stepHit`, `sectionHit`, `destroy`, `openSubState`, `closeSubState`,
`onFocus`, `onFocusLost`, …) and call `super` like normal Haxe. Inside methods
you can use inherited members directly (`add(...)`, `openSubState(...)`,
`controls`, `this`).

A full example lives in [docs/scripts/TemplateScriptedState.hx](scripts/TemplateScriptedState.hx).

> **Gotcha — bare enum values don't resolve.** hscript has no type inference, so
> a bare enum value like `CENTER` or `LEFT` (which compiled Haxe infers from the
> argument type) is an *unknown identifier* in a script. Use the string form
> where the enum is a string abstract — e.g. `setFormat(font, size, color, 'center')`
> — or import and qualify it: `import flixel.text.FlxText.FlxTextAlign;` then
> `FlxTextAlign.CENTER`. A runtime error like this is caught and printed to the
> debug console (`<State>.<func>(): <error>`) rather than crashing the game.

### Substates

Same idea, in `mods/<YourMod>/substates/MyPause.hx`, extending
`MusicBeatSubstate`.

## Launching a mod (taking over the core menus)

A mod can replace the engine's built-in menus (MainMenu, Freeplay, StoryMenu,
…) with its own scripted versions — but only when the user opts in, and only
**one mod at a time**, so different mods never fight over the menus.

**How a mod overrides a core menu:** ship a scripted state whose file/class name
matches the engine state, e.g. `mods/<YourMod>/states/MainMenuState.hx`:

```haxe
class MainMenuState extends MusicBeatState {
    public function new() { super(); }
    override function create() {
        super.create();
        // your custom main menu...
    }
}
```

Overridable by name: `MainMenuState`, `FreeplayState`, `StoryMenuState`,
`TitleState`, `OptionsState`, `CreditsState`, etc. **`ModsMenuState` can never be
overridden** — it's the guaranteed way back out of a launched mod.

**Entry state (`pack.json`):** declare which state the engine enters when the mod
is launched (defaults to `MainMenuState` if omitted):

```json
{ "name": "My Mod", "entryState": "MainMenuState" }
```

A mod is "launchable" only if `states/<entryState>.hx` exists.

**Launching:** in the in-game **Mods menu**, highlight a launchable mod and press
ACCEPT. The engine makes it the active source and enters its entry state. From a
script you can also call `launchMod('<modFolder>')`.

**Getting back out:** call `exitToEngine()` from the mod's BACK handler — it
returns to the engine Mods menu and restores the built-in menus for the rest of
the session.

### The `State Source` option (Options → Misc Settings)

Controls what happens at **boot** (and is the safe default):

| Mode | Behavior |
|------|----------|
| **Psych (Default)** | Built-in menus only. Enabled mods provide assets but never auto-override menus. *This is the default.* |
| **From Mod** | The top enabled (launchable) mod's scripted states override the core menus automatically at boot. |
| **Global Script** | Scripted overrides come from global mods (`type: "scriptpack"` / `runsGlobally: true`) + shared assets, applied across the engine. |

Because overrides only ever come from the single active source (the launched
mod, or the global/scriptpack layer), two mods that both ship a
`states/MainMenuState.hx` will never both load — only the active one does.

## Switching to a scripted state

From any Lua or HScript:

```lua
switchToState('MyMenu')             -- replaces the current state
openScriptedSubstate('MyPause')     -- opens a substate over the current state
```

Both take an optional array of constructor arguments as a second parameter.

## Globals available in scripted states

`FlxG`, `FlxSprite`, `FlxText`, `FlxTween`, `FlxEase`, `FlxColor`, `FlxTimer`,
`FlxMath`, `Paths`, `Conductor`, `ClientPrefs`, `Alphabet`, `PlayState`,
`MusicBeatState`, `controls`, `getVar`/`setVar`/`removeVar`,
`switchToState`/`openScriptedSubstate`/`switchState`,
`launchMod(folder)`/`exitToEngine()`, plus `this` (the state
instance). `import` works for anything else.

## Notes for mod authors migrating from Iris

The interpreter changed, so a few behaviours differ:

- **Whole-class scripting** is new. Existing callback-style scripts
  (`function onCreate() ... function onUpdate(elapsed) ...` inside
  stage/character/event/notetype `.hx` files) keep working unchanged — the
  `runHaxeCode`/`runHaxeFunction`/`addHaxeLibrary` Lua bridge and all PlayState
  hooks are preserved.
- `Type`, `Reflect` and `Std` inside scripts now resolve to insanity's
  proxied versions (which honour the security blacklist). Their common API
  (`Type.resolveClass`, `Reflect.field`, …) is unchanged.
- The old convenience where a stage/character script could reference the parent
  `PlayState`'s fields as bare identifiers (e.g. `curStage` instead of
  `game.curStage`) is **gone**. Use the injected `game` global, or `import`/`PlayState.instance`.
- insanity adds Haxe features Iris lacked: map literals, string interpolation,
  full pattern matching, regex literals, null-coalescing (`??`, `??=`),
  abstracts (incl. `FlxColor`). These are supersets — existing scripts are
  unaffected.

## Security

The mod-trust model is unchanged: `backend.ModSecurity` still hashes mods,
prompts for trust, and scans script **source** for dangerous patterns
(`sys.io.File`, `Type.resolveClass`, `import sys`, tampering with `ModSecurity`,
…) before anything runs. That scan is interpreter-agnostic and is the primary
gate.

As defense-in-depth, `ModSecurity.BLOCKED_CLASSES` is mirrored into
insanity's `Config` type blacklist at boot (`HScript.setupConfig()`), so scripts
that try to resolve those classes through the `Type`/`Reflect`/`Std` proxies get
`null` back — the equivalent of the old `PatchIris` macro.
