# Scripted classes (hscript-insanity)

Scripted **states** ([SCRIPTED_STATES.md](SCRIPTED_STATES.md)) let a mod script a whole
menu. Scripted **classes** go further: a mod can ship its own class library under
`scripts/classes/` and use those classes anywhere the engine reaches scripts, split across as
many files as you like, importing between them like real Haxe. The goal is parity with compiled
Haxe: `enum`, `interface`, `extends`, `implements`, static and `private` members, generics.

This is what makes a whole new subsystem scriptable, up to and including a mod's own
`PlayState` subclass, without touching or rebuilding the engine.

**You do not need scripted states to use this.** A plain modpack with nothing but FNF songs can
keep a class library and reach it from its ordinary `scripts/`, `songs/` and `stages/` scripts --
or from `scripts/global/`, which runs in menus too. See
[the demo mod](#a-mod-with-no-scripted-states) at the bottom, and
[script-hooks-and-dispatch.md](script-hooks-and-dispatch.md) for which script runs where and what
a hook's return value does.

## Where classes live

Everything advanced lives under `scripts/classes/`, with folders as packages, exactly like a Haxe
source tree -- scripted states included, because a state is just a class:

```
mods/MyMod/
  scripts/
    global.hx            an ordinary script (unchanged)
    classes/
      rhythm/
        Judgement.hx     ->  package rhythm;  enum Judgement { ... }
        ScoreKeeper.hx   ->  package rhythm;  class ScoreKeeper { ... }
        Bouncer.hx       ->  package rhythm;  import rhythm.Judgement; class Bouncer extends FlxSprite { ... }
      states/
        MyMenu.hx        ->  package states;  import rhythm.ScoreKeeper;  class MyMenu extends MusicBeatState { ... }
      substates/
        MyPause.hx       ->  package substates;
```

The file path is the type path: `scripts/classes/rhythm/ScoreKeeper.hx` declares
`package rhythm;` and is imported as `import rhythm.ScoreKeeper;`. A state under
`scripts/classes/states/` declares `package states;`, which is what lets any other class
`import states.MyMenu`.

A top-level `classes/` folder is still read, at lower priority, if you would rather keep your
library outside `scripts/`. A top-level `states/` folder is **not** -- states moved into the
classes tree.

Every class a mod loads shares one world, so any of its files can `import` any other, and a class
is parsed once no matter how many times you instantiate it. Each **mod** gets its own world: two
mods can both ship `rhythm.ScoreKeeper` and neither sees the other's, statics included.

## What you can write

### Classes, `extends`, and `override`

Extend an engine class and override its methods, calling `super` like normal Haxe. The
extendable bases are the ones the engine generates a bridge for (see the list at the bottom):
Flixel display classes, states, and gameplay objects like `Character`, `StrumLine`,
`NoteSplash`, `BaseStage`, and `PlayState` itself.

```haxe
package rhythm;

class Bouncer extends FlxSprite {
    var bounceHeight:Float;

    public function new(x:Float, y:Float, bounceHeight:Float = 20) {
        super(x, y);
        this.bounceHeight = bounceHeight;
        makeGraphic(40, 40, FlxColor.CYAN);
    }

    override public function update(elapsed:Float):Void {
        super.update(elapsed);
        y += Math.sin(Conductor.songPosition / 100) * bounceHeight * elapsed;
    }
}
```

A `new` that extends something **must** call `super(...)`, the same rule Haxe has. If your
class declares no `new` at all, it inherits the base's constructor and its arguments pass
straight through.

> **Final classes can't be extended.** The note-runtime drawables (`NoteSprite`, `Receptor`,
> `SustainSprite`, `NoteField`) are deliberately `final` so the per-note hot path stays fast,
> so they are not extendable. Script the strumline, the splash, the stage, or `PlayState`
> around them instead.

### Enums

Full enums, including constructors with parameters, and `switch` pattern matching with
captures, guards, and `|` alternatives:

```haxe
package rhythm;

enum Judgement {
    Perfect;
    Great;
    Good;
    Miss;
}
```

```haxe
function scoreOf(j:Judgement):Int {
    return switch (j) {
        case Perfect: 350;
        case Great:   200;
        case Good:    100;
        case Miss:    0;
    }
}
```

### Interfaces

Declare an `interface`, `implements` it, and check with `is`. `x is IFoo` answers correctly
for a scripted interface, and an interface can `extends` other interfaces.

```haxe
package rhythm;

interface IScoreEvent {
    function points():Int;
    function label():String;
}
```

```haxe
class PerfectHit implements IScoreEvent {
    public function new() {}
    public function points():Int return 350;
    public function label():String return 'PERFECT';
}

// elsewhere:
var e:IScoreEvent = new PerfectHit();
if (e is IScoreEvent) trace(e.label());
```

A scripted class can also implement a **native** engine interface, but only if the engine's
generated bridge for its base declares that interface. If you need this for a specific
interface, it's a one-line addition to `source/macros/ScriptedBridgeMacro.hx`.

### Static and private members

`static` fields and methods work and are shared across the class. `private` is enforced:
reading or writing a `private` member from outside the declaring class (or a subclass) is a
runtime error, caught and shown on-screen like any other script error. Members without an
access keyword are treated as public.

```haxe
class ScoreKeeper {
    public static var instance:ScoreKeeper;

    private var total:Int = 0;

    public function new() {
        instance = this;
    }

    public function add(points:Int):Void {
        total += points;
    }

    public function score():Int {
        return total;
    }
}
```

### Generics

Type parameters parse and run (constraints are accepted and erased):

```haxe
class Pool<T> {
    var items:Array<T> = [];
    public function new() {}
    public function add(item:T):T { items.push(item); return item; }
    public function count():Int { return items.length; }
}
```

### Typedefs

Structural typedefs (`typedef Vec = { x:Float, y:Float }`, function types) and simple type
aliases work. They're erased, so they're for readability and annotations, not runtime checks.

## Building a scripted class from another script

Inside a scripted class or state, just `import` and `new` it. From an ordinary script -- a
global, song or stage script, HScript **or** Lua -- use `buildScripted`:

```haxe
var keeper = buildScripted('rhythm.ScoreKeeper');   // an instance
var cls    = scriptedClass('rhythm.ScoreKeeper');   // the class itself, for statics
```

```lua
local keeper = buildScripted('rhythm.ScoreKeeper')
```

Both are bound to the mod the calling script lives in, so you always get your own mod's class.

> **A scripted class cannot extend another scripted class.** It constructs, but calling an
> overridden method on the instance from outside fails. Extending a *native* engine class (the
> list at the bottom) is the supported path. Give the classes the same shape and call them
> structurally instead.

## A scripted `PlayState` (a whole game mode)

`PlayState` is an extendable base, so a mod can subclass it and override gameplay hooks
(`createPost`, `beatHit`, note callbacks, etc.). Name it anything **except** `PlayState`
(a module's own types shadow imports, so `class PlayState extends PlayState` would resolve
to itself):

```haxe
package rhythm;

class DemoPlayState extends PlayState {
    override public function new() {
        super();
    }

    override function beatHit():Void {
        super.beatHit();
        // custom on-beat behaviour for this mode
    }
}
```

Launch it the same way any song starts, from your scripted menu:

```haxe
Song.loadFromJson(chartName, songName);
LoadingState.loadAndSwitchState(new rhythm.DemoPlayState());
```

There is no engine-level "game mode" setting: a mode is just a `PlayState` subclass your
scripts construct and switch to. That keeps game-mode logic entirely in the mod.

## Available without `import`

Engine singletons and helpers resolve as bare identifiers everywhere scripts run. The full
list is `source/scripting/ScriptGlobals.hx` (`TYPE_IMPORTS` for types, `inject()` for
values/helpers). It covers the common Flixel classes, `FlxG`, `Conductor`, `ClientPrefs`,
`Paths`, `controls`, gameplay classes (`Character`, `StrumLine`, `Bar`, `HealthIcon`,
`NoteSplash`), the note runtime (`NoteData`, `NoteField`, `ActiveNote`, `NoteSprite`,
`SustainSprite`, `Receptor`, `NoteDefaults`, `NoteSkinConfig` — the types the note callbacks
hand you), `PlayState`, `Song`, `LoadingState`, and the
`getVar`/`switchToState`/`buildScripted`/… helpers.

A useful slice of **OpenFL** and **Lime** is included too (display objects, filters/shaders,
`openfl.geom.*`, `openfl.utils.Assets`, `lime.utils.Assets`, ...), so scripts can drop below
Flixel for custom rendering, blend modes and filters.

Anything else is reachable by an ordinary `import` of any type compiled into the engine, or
of another of your own `classes/`. To expose a new engine type as a bare identifier for
every script, add its path to `ScriptGlobals.TYPE_IMPORTS`.

### Emulated methods (`inline extern`)

A few flixel methods are declared `inline extern` — the compiler inlines them at call sites and
leaves **no runtime method**, so a script reaching one by reflection would fail. The engine
registers emulation shims (in `scripting.ScriptShims`) for the common ones, so e.g.
`FlxG.sound.playMusic(...)` works from a script exactly like compiled Haxe. If you hit an
unshimmed one (`Cannot call null` on a method that exists in the API), add a shim there.

## Extendable bases

Generated by `source/macros/ScriptedBridgeMacro.hx`. Add a base by adding one line there.

| Group | Bases |
|-------|-------|
| Flixel | `FlxBasic`, `FlxObject`, `FlxSprite`, `FlxGroup`, `FlxSpriteGroup`, `FlxText` |
| States | `MusicBeatState`, `MusicBeatSubstate`, `PlayState`, `PauseSubState`, `GameOverSubstate` |
| Gameplay | `Character`, `StrumLine`, `NoteSplash`, `BaseStage` |
| UI / helpers | `Alphabet`, `Bar`, `HealthIcon`, `ModchartSprite` |

## A mod with no scripted states

Nothing above needs a `states/` folder. A plain modpack can keep a class library and use it from
the scripts it already has:

```
mods/MyMod/
  scripts/
    global.hx                 buildScripted('demo.Counter')
    classes/demo/Counter.hx   package demo;
  songs/<song>/song.hx        getVar('demoCounter').bump()
  stages/<stage>.hx           same object again
```

A working one ships at `mods/Scripted Classes Demo/`.

## Leaving a song

From any script in a song -- HScript or Lua:

| Function | What it does |
|---|---|
| `setExitTarget(name)` | Where the song goes when it ends or the player backs out. |
| `exitToState(name)` | Go there now. |

`name` is one of your own scripted states, or a built-in menu: `MainMenuState`, `FreeplayState`,
`StoryMenuState`, `OptionsState`, `ModsMenuState`. This works in a plain modpack, not just a
launched one, and an unresolvable name falls back to Freeplay rather than stranding the player.

## Security

Unchanged from scripted states: `backend.ModSecurity` hashes mods, prompts for trust, and scans
script source before anything runs. The same gate applies to every class loaded from a class root.

The source scan is a trust prompt rather than a sandbox; the boundary that holds is class
resolution. A scripted class can `import` any engine type except the blocked classes and the blocked
packages (`sys`, `cpp`, `neko`, `java`, `llua`) -- see
[the security model](script-hooks-and-dispatch.md#security-what-is-and-is-not-a-boundary).

A working multi-file reference mod is in
[docs/examples/scripted-classes/](examples/scripted-classes/).
