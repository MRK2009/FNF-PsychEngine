# Class-based scripted states (hscript-insanity)

This fork swaps the HScript interpreter from **hscript-iris** to
**[hscript-insanity](https://github.com/inky03/hscript-insanity)** so that mods
can script **whole classes** — most usefully, entire game **states** (custom
menus, etc.), not just `onCreate`/`onUpdate` callback hooks.

## Writing a scripted state

Create `mods/<YourMod>/states/MyMenu.hx`. The class name must match the file
name and must extend `ScriptedMusicBeatState`:

```haxe
class MyMenu extends ScriptedMusicBeatState {
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

### Substates

Same idea, in `mods/<YourMod>/substates/MyPause.hx`, extending
`ScriptedMusicBeatSubstate`.

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
`switchToState`/`openScriptedSubstate`/`switchState`, plus `this` (the state
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
