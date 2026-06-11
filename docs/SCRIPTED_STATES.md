# Class-based scripted states (hscript-insanity)

This fork swaps the HScript interpreter from **hscript-iris** to
**[hscript-insanity](https://github.com/inky03/hscript-insanity)** so that mods
can script **whole classes** — most usefully, entire game **states** (custom
menus, etc.), not just `onCreate`/`onUpdate` callback hooks.

> **Porting a compiled state?** See
> [SCRIPTED_STATES_VS_HARDCODED.md](SCRIPTED_STATES_VS_HARDCODED.md) first — it lists
> what the engine already does for you (so you don't re-script it) and what moves to
> `pack.json` instead of code.

## Writing a scripted state

Create `mods/<YourMod>/states/MyMenu.hx`. The class name must match the file
name and must extend `MusicBeatState` (the normal engine state class — the
engine makes it scriptable for you):

```haxe
class MyMenu extends MusicBeatState {
    // REQUIRED: a constructor that calls super() (see "Boilerplate" below).
    public function new() {
        super();
    }

    override function create() {
        // No super.create() needed -- the engine sets up the camera for you.
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

### Boilerplate: `super` calls

- **`super.create()` is optional.** The engine prepares the state's camera
  *before* your `create()` runs (via a `preStateCreate` hook in `Main`), so a
  scripted state renders whether or not you call it. Calling it is still safe
  (it's idempotent and also plays the built-in fade-in transition).
- **`new() { super(); }` is still required.** The interpreter needs a
  constructor that initializes the underlying `FlxState`; if you omit it the
  state fails to load with a clear error. Keep the one-liner.
- For `update`/`beatHit`/`stepHit`/etc., call `super.x(...)` when you want the
  base behaviour (beat tracking, etc.), like normal Haxe.

### In-game error overlay

Runtime errors in any scripted method are caught and printed to the debug
console **and shown on-screen** (red text, like PlayState's script errors) in
whatever state is active — so a broken scripted menu tells you what went wrong
instead of just going black. This works in every state now, not only PlayState.

### Mod sandboxing (no `Mods.*` needed)

A scripted state loaded from a mod is automatically scoped to **its own mod**:
`Paths.image(...)`, `Paths.sound(...)`, etc. resolve that mod's assets first
(shared engine assets as fallback). You do **not** need to call
`Mods.pushGlobalMods()` or set `Mods.currentModDirectory` — doing so manually is
unnecessary and can point asset lookups at the wrong mod. Just use `Paths.*`.

### Available without `import`

These resolve as bare identifiers inside a scripted state (no `import` needed),
and can be used as real field types (not `Dynamic`):

`FlxG`, `FlxSprite`, `FlxText`, `FlxCamera`, `FlxTimer`, `FlxTween`, `FlxEase`,
`FlxColor`, `FlxSound`, `FlxMath`, `FlxObject`, `FlxGroup`, `FlxTypedGroup`,
`FlxSpriteGroup`, `FlxButton`, `FlxBar`, `FlxBackdrop`, `FlxFlicker`,
`FlxSort`, `FlxStringUtil`, `PsychCamera`, `Paths`,
`Conductor`, `ClientPrefs`, `Alphabet`, `PlayState`, `MusicBeatState`,
`MusicBeatSubstate`, `Song`, `LoadingState`, `Difficulty`, `Highscore`,
`WeekData`, `CoolUtil`, `controls`, plus the
`getVar`/`setVar`/`switchToState`/`launchMod`/… helpers.

Anything else still needs an `import` (see the import notes below).

A full example lives in [docs/scripts/TemplateScriptedState.hx](scripts/TemplateScriptedState.hx).

> **Gotcha — bare enum values don't resolve.** hscript has no type inference, so
> a bare enum value like `CENTER` or `LEFT` (which compiled Haxe infers from the
> argument type) is an *unknown identifier* in a script. Use the string form
> where the enum is a string abstract — e.g. `setFormat(font, size, color, 'center')`.
> A runtime error like this is caught, printed to the debug console, and shown
> on-screen (`<State>.<func>(): <error>`) rather than crashing the game.

### Import notes (what works)

Most things you need are already injected (see the list above), so you rarely
import. When you do, the interpreter's import resolver has limits:

- **A whole-module import works** for a module whose extra (sibling) types all
  resolve — e.g. `import flixel.text.FlxText;` (also brings `FlxTextBorderStyle`).
- **It fails** if a sibling type can't resolve — e.g. `import flixel.ui.FlxButton;`
  pulls the generic `FlxTypedButton` and errors. Use the **aliased** form to grab
  only the one type: `import flixel.ui.FlxButton as FlxButton;` — or just use the
  injected global (`FlxButton` is already available without any import).
- **Sub-type imports don't work**: `import flixel.text.FlxText.FlxTextBorderStyle;`
  errors. Import the module instead, or use a string where the enum is a string
  abstract.
- Wildcard `import pkg.*` is not reliable; prefer the injected globals or aliased
  single-type imports.

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

**Returning from a song:** when a song is started from a scripted state (e.g. a
custom menu calling `LoadingState.loadAndSwitchState(new PlayState())`), exiting
that song — finishing it, pause → "Exit to menu", or dying — automatically
returns to the scripted state it was launched from (rather than the built-in
Freeplay/Story menus). You don't need to set anything; the engine tracks it. To
override the return target explicitly, set `PlayState.returnToScriptedState` to a
scripted state name before switching to PlayState.

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

See **"Available without `import`"** above for the full list of injected types
and helpers (`switchToState`/`openScriptedSubstate`/`switchState`,
`getVar`/`setVar`/`removeVar`, `launchMod(folder)`/`exitToEngine()`, plus `this`
and all inherited state members). `import` works for anything else, within the
limits in the import notes above. The injected set is defined in
`source/scripting/ScriptedStates.hx` (`injectGlobals`) — add to it there if a
type is commonly needed.

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
