# The base game is a modpack

Friday Night Funkin's own content is no longer engine content. Weeks 1 to 7 and Weekend 1 ship as an
ordinary modpack in `mods/Friday Night Funkin`, built from the repo folder `base_game/`, and their
stages are scripted classes exactly like a mod would write them. Disable the pack in the Mods menu and
the engine boots with no songs, no weeks and no characters beyond its own baseline. That is the point:
the engine is a runtime, not a game.

## What the engine still ships

A modder needs a floor to build on, so this much stays compiled and in `assets/`:

| kept | why |
| --- | --- |
| `states/stages/StageWeek1.hx` + its art, `stages/stage.json` | the fallback stage for the chart editor, the stage editor, `StageData.dummy()` and any mod naming no stage |
| `bf`, `gf`, `dad`, `bf-dead` and the pixel variants, with their sheets, icons and menu characters | the characters every tutorial, template and half-built mod refers to |
| `images/pixelUI/`, `weeb/pixelUI/dialogueBox-pixel`, `hand_textbox`, pixel game-over audio | the pixel baseline: judgements, note skins, dialogue box, death sounds |
| `states/stages/Template.hx` | the documented example of a compiled stage |

Everything else went to the pack, week 1's charts included.

Chart events followed their implementations. The engine's built-in event list
(`legacy.editors.ChartingState.defaultEvents`, which both chart editors read) now holds only events
the engine itself handles, and the five the base game's stages handle -- Dadbattle Spotlight, Philly
Glow, Kill Henchmen, BG Freaks Expression, Trigger BG Ghouls -- ship as `base_game/custom_events/`
text files, whose contents are the description the editor shows. Any pack does the same: drop
`custom_events/<Event Name>.txt` beside your stage script and the event appears in the editor while
your pack is the one loaded. The View menu's old "Stage Events: Hidden" toggle went with them, since
the events now only show up where they mean something.

## Writing a stage as a script

Put a class in the `stages` package under a class root, named after the stage key with its first
letter capitalised, extending `BaseStage`:

```haxe
// mods/MyPack/scripts/classes/stages/Spooky.hx   ->   stage key "spooky"
package stages;

class Spooky extends BaseStage {
    var halloweenBG:BGSprite;

    override function create():Void {
        halloweenBG = new BGSprite('halloween_bg', -200, -100, 1, 1, ['halloweem bg0']);
        add(halloweenBG);
    }

    override function beatHit():Void { ... }
}
```

`PlayState` resolves it through `scripting.ScriptedStages` when no compiled stage claims the key, and
`BaseStage`'s constructor registers it and calls `create()` itself. Every hook a compiled stage has is
available: `create`, `createPost`, `beatHit`, `stepHit`, `sectionHit`, `countdownTick`, `startSong`,
`eventPushed`, `eventCalled`, `goodNoteHit`, `opponentNoteHit`, `noteMiss`, `notesGenerated`,
`openSubState`, `closeSubState`, `gameOverStart`, `gameOverLoopStart`. A missing script is not an
error, since most stages are pure JSON.

The two game over hooks are how a stage decorates the death screen without the engine knowing what
the decoration is. `gameOverStart(gameOver)` runs once the substate has its character, camera and
music: assign `gameOver.overlay` there and the substate plays that sprite's `deathLoop` and
`deathConfirm` in step with the character, so the stage owns the art and not the timing (see
`stages.objects.PicoDeathOverlay`). `gameOverLoopStart(gameOver)` runs when the death loop begins;
return `true` to claim the music, which is how `Tank` drops the loop to 20% and plays a Jeff line
over it.

Helper props live in `stages.objects` beside them, and subclass whatever fits: `FlxSprite`,
`FlxSpriteGroup`, or nothing at all for a plain logic class.

Do not subclass `BGSprite` for now. It is in `ScriptedBridgeMacro.BASES` and constructing one
directly works, but a *scripted subclass* of it has thrown "Null Function Pointer" from its
constructor for two of the three props that tried (`BackgroundTank`, `PhillyTrain`), while the third
(`MallCrowd`) ran fine on the same build, and none of it reproduces against a stand-in base. All
three now extend `FlxSprite` and open with the four lines `BGSprite`'s constructor would have run
(`loadGraphic` or `frames`/`addByPrefix`, `scrollFactor.set`, `active`, `antialiasing`), which is
what the compiled props did anyway. `FlxSprite` and `FlxSpriteGroup` subclasses have never shown it.

## What the interpreter does not do for you

Every one of these cost a play test during the port, and they are the whole difference between a
compiled stage and a scripted one:

- **Optional arguments are never skipped or defaulted.** Haxe lets
  `new BGSprite('bg', x, y, ['anim'])` land the array on `animArray`; a script must write
  `new BGSprite('bg', x, y, 1, 1, ['anim'])`. Same for `scrollFactor.set()`, which needs `set(0, 0)`.
- **Enum abstracts are not inferred from the field.** Write `blend = BlendMode.ADD`, never a bare
  `ADD`. Reaching the abstract at all needs a generated wrapper, which
  `macros.ScriptedAbstractMacro` produces for every abstract in the engine, Flixel and SmidrUI --
  see [scripted-classes.md](scripted-classes.md#enum-abstracts) for the rules and how to list them.
- **An array of abstracts does not unwrap at a native call.** A single wrapper unwraps when passed as
  an argument, but `Array<FlxPoint>` stays an array of wrappers, so `FlxTween.quadPath` receives the
  wrong thing. Annotate each point as `FlxBasePoint` (`FlxPoint` converts `to` it) and the array holds
  raw values. See `stages/PhillyStreets.hx`.
- **`Class<T>` APIs cannot take a scripted class.** `FlxTypedGroup.recycle(MyThing)` instantiates a
  compiled class; pool by hand instead (`Philly.spawnParticle`, `Tank.recycleTankman`).
- **`bind` is a compiler feature.** Use a closure.
- **A script method is not a compiled `Void->Void`.** Wrap it when handing it to a native callback
  field: `doof.finishThing = function() { startCountdown(); }`.
- **Keep the same function object** when a signal will later `has`/`remove` it, so hold it in a var
  (`Tank.stressIntro`'s `picoStressCycle`).
- **Copy a loop variable into a block-scoped local** before capturing it in a closure that outlives
  the iteration (`PhillyStreets.darkenStageProps`).
- **A bridged base's constructor is re-emitted from its typed form**, and a loop there carries
  compiler temporaries that cannot be printed back as syntax. Keep loops out of the constructor of
  anything in `ScriptedBridgeMacro.BASES`; `objects.BGSprite.addAnims` exists for that reason.
- **Method bodies need braces.** A brace-less one-liner does not survive.
- **To reach a type declared inside another module, import the MODULE** and use the type as a bare
  name. `import flixel.math.FlxPoint;` makes `FlxBasePoint` available, because a plain module import
  registers every type in it. Neither alternative works: `import flixel.math.FlxBasePoint` is the
  compile path, which the type index does not key, and in `import flixel.math.FlxPoint.FlxBasePoint`
  the trailing segment is read as a *field* of `FlxPoint`. Note a global import (anything in
  `ScriptGlobals.TYPE_IMPORTS`) registers only the one type, so the module still needs importing by
  hand for its siblings.
- **Statics work, including from a field initializer and self-qualified.** They did not: a class's
  statics live on the class interpreter, which only the scope methods are built with received, so
  `var state:Int = WAITING;` failed as an unknown identifier while `state = WAITING` inside a method
  worked, and a class could not name itself to qualify (`MyClass.WAITING`). Both are fixed in
  hscript-insanity's `ScriptedMacro.__construct`, sharing the statics by reference so a mutable one
  stays a single value for the class. The ported state machines still use instance fields, which is
  simply what they were written against.
- **A capitalised identifier in a `case` pattern is a pattern variable**, not a constant, so
  `case KILLING:` is rejected outright ("pattern variables must be lower-case or with 'var ' prefix").
  Either compare with `if`/`else` or name the constants in lower case. This is why the ported state
  machines (`Limo`, `PhillyStreets`, `SpraycanAtlasSprite`) use `stWait`-style instance fields and
  if/else chains rather than the enums the compiled versions had.

Reach `PlayState`-only state through `PlayState.instance`. `BaseStage`'s own properties (`boyfriend`,
`camHUD`, `defaultCamZoom`, `members`, ...) resolve fine.

## Consequences

The pack is isolated: it does not set `runsGlobally`, so its assets resolve only while its own songs
play. A mod that leaned on base-game art it does not ship -- week 2-7 backgrounds, `senpai`, `spirit`,
`tankman`, the base charts -- has to bundle its own copy. The retained baseline above is deliberately
the set most mods actually depend on.

Compiled classes that only the pack's scripts use are kept alive by `scripting.lua.LuaProxy._importAnchors`
(`CutsceneHandler`, `PsychFlxAnimate`, `RainShader`, `ABotSpectrum`). Anything else a script imports
by name and nothing compiled references will be dropped by DCE and resolve to nothing, so add it
there.

## Known leftovers

Base-game specifics still sitting in engine code, all inert without the pack:

- `backend/StageData.hx`: `vanillaSongStage`, the legacy song-to-stage fallback for charts with no
  stage field.
- `editors/charting/VSlice.hx`: the V-Slice stage-id table (`spookyMansion` -> `spooky` and friends),
  which an importer needs whether or not the pack is installed.
- `states/stages/StageWeek1.hx`: the Dadbattle Spotlight fog, since the week 1 stage itself is part of
  the retained baseline. Its editor description moved to the pack with the rest.

An event needing to fire early declares that itself now, from a `custom_events/<name>.hx` beside its
description: `eventEarlyTrigger(name, value1, value2, strumTime)` returning milliseconds. `PlayState`
has no offsets of its own -- Kill Henchmen's 280ms used to be hardcoded there, and is now
`base_game/custom_events/Kill Henchmen.hx`.
