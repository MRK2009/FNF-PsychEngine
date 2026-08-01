# Script hooks, dispatch and `scripts/global/`

How the engine decides which of your scripts hears about an event, what a hook's return value
does, and where a script has to live to run at all.

Four things changed here. Two are fixes you get for free, two are new capability:

| | |
|---|---|
| **Fix** | HScript no longer gets starved when a Lua script returns a value |
| **Fix** | A Lua runtime error is always reported, not hidden behind `luaDebugMode` |
| **New** | `scripts/global/` runs in **every state**, so a mod can touch menus without scripting one |
| **New** | The eight off-convention hook names have consistent `on…` spellings |

## Both languages always run

The engine dispatches a hook to your Lua scripts, then to your HScript scripts.

It used to run the HScript pass **only if the Lua pass had returned nothing meaningful**. So a
single Lua script in your mod returning any value meant no HScript anywhere in that mod saw the
event -- silently, with nothing in the log. If you have ever had an `.hx` file that "just didn't
fire", this was probably why.

Both passes now always run. If you were relying on a Lua return to suppress your HScripts, use
`Function_StopHScript` (below), which says so explicitly.

**Which value wins:** the last script to return something other than `Function_Continue`. HScript
runs second, so an HScript return beats a Lua one. That is unchanged from when the HScript pass ran
at all.

## Return values

Return one of these from a hook to control what happens next. Everything else is an ordinary value.

| Return | Cancels the engine's action | Stops other Lua scripts | Stops HScript scripts |
|---|---|---|---|
| *(nothing)* / `Function_Continue` | no | no | no |
| `Function_Stop` | **yes** | no | **yes** |
| `Function_StopLua` | no | **yes** | no |
| `Function_StopHScript` | no | no | **yes** |
| `Function_StopAll` | **yes** | **yes** | **yes** |

`Function_Stop` deliberately does not stop sibling scripts in its own language. It is how you cancel
a note hit or a countdown, and one script cancelling an action must not hide that action from
another script that is only counting it.

All five are available in Lua and HScript under the same names.

## `scripts/global/` -- scripts in menus

```
mods/MyMod/
  scripts/
    gameplay-thing.lua      loads in PlayState only, exactly as always
    global/
      everywhere.lua        loads in EVERY state
      everywhere.hx         so does this
```

`scripts/` is unchanged: gameplay only. The new `scripts/global/` folder loads in every state that
the engine builds -- the title screen, main menu, freeplay, options, the pause-less menus, and
gameplay. One host per state, so a global script runs **once** in gameplay, not twice.

Both languages work, `_order.txt` works, and everything in
[scripted-classes.md](scripted-classes.md) works: a global script can `buildScripted(...)` your own
classes.

### What a global script gets

- `onCreate` when the state's scripts load, `onDestroy` when the state goes away.
- `onUpdate(elapsed)` and `onUpdatePost(elapsed)` every frame.
- `onBeatHit` / `onStepHit`, driven by whatever music is playing.
- `onStateChange(name)` with the full class name of the state it just loaded into, e.g.
  `states.MainMenuState`. This is how you decide whether to do anything at all.
- In gameplay, everything above **plus** every normal PlayState hook, because it is the same host.

### What it does not get

A menu has no chart, no characters and no `PlayState`. The gameplay-only Lua callbacks
(`setScore`, `characterPlayAnim`, `setCameraFollowPoint`, ...) have nothing to act on there, and
song variables (`bpm`, `songName`, `curStage`, ...) are only set when a song is loaded. Gate on the
state:

```lua
function onStateChange(name)
    if name ~= 'states.PlayState' then return end
    -- gameplay-only setup here
end
```

## Hook names

Eight hooks predate the `onX` convention the other forty-five follow. They still work and always
will -- they are the names the engine dispatches. Each now also accepts the consistent spelling,
bound when your script loads:

| Consistent spelling | Dispatch name |
|---|---|
| `onGoodNoteHit` | `goodNoteHit` |
| `onGoodNoteHitPre` | `goodNoteHitPre` |
| `onOpponentNoteHit` | `opponentNoteHit` |
| `onOpponentNoteHitPre` | `opponentNoteHitPre` |
| `onNoteMiss` | `noteMiss` |
| `onNoteMissPress` | `noteMissPress` |
| `onEventEarlyTrigger` | `eventEarlyTrigger` |
| `onUpdateScorePre` | `preUpdateScore` |

Declare either one. Declaring both is pointless -- the dispatch name wins and the alias is ignored.

The canonical list of every hook lives in `source/scripting/ScriptHooks.hx`.

## Errors are always reported

A script failure now always reaches the debug console, the log file and the on-screen overlay.

Lua errors used to go through `luaTrace`, which was gated behind the script's own `luaDebugMode`
flag -- so a runtime error in a Lua hook was invisible unless you had already suspected one and
turned debugging on. `luaDebugMode` still gates ordinary `debugPrint`-style output; it no longer
gates failures.

The overlay also works in every state now, not just gameplay, so a broken menu script tells you
what went wrong instead of the screen going black.

## Performance notes

Relevant if you ship a lot of scripts:

- A script that does not declare a hook costs a map lookup per dispatch, not a round trip into the
  Lua state. Declaring `onUpdate` in one script no longer taxes the others.
- Return values are classified once per call instead of being string-compared repeatedly.
- If you define a hook at runtime (assigning `onUpdate = function() ... end` from inside another
  function, rather than declaring it at the top level), the engine has already cached the miss. Top
  level declarations -- what essentially every script does -- are unaffected.

## Security: what is and is not a boundary

Worth stating plainly, because the two halves get conflated and only one of them actually contains
anything.

### The source scan is a trust prompt, not a sandbox

`backend.ModSecurity` reads every script in a mod at enable time and pattern-matches for risky calls
(`sys.io.File`, `os.execute`, `Type.resolveClass`, ...). If it finds any and you have not already
made a decision, the mod's scripts do not run until you press Trust.

That is a **speed bump, and it is meant to be**. It reads source text, so anything that hides the
name defeats it -- string concatenation, a name assembled at runtime, reflection, a call routed
through a variable. It exists so a mod that obviously wants to touch your filesystem has to say so
before it runs, and so a mod whose scripts change after you trusted it asks again. Treat a Trust
prompt as "this mod does something worth knowing about", not as "blocking this makes me safe".

### The binding layer is the real boundary

What a script can actually reach is decided by what the engine exposes to it, and that is enforced
at runtime rather than by reading source:

- **Resolving a class by name** -- `import('pkg.Class')`, `createInstance`, `getPropertyFromClass`,
  `callMethodFromClass`, `addHaxeLibrary` -- goes through `ModSecurity.safeResolveClass`. It returns
  `null` for anything on `BLOCKED_CLASSES` (individual engine classes: `ModSecurity` itself,
  `DebugPrefs`, `Main`, the FPS counter, `hxscript.Config`) or under a blocked **package**:
  `sys`, `cpp`, `neko`, `java` and `llua`. Those five are where the danger is the package rather than
  any one type -- the process and filesystem, native handles, and the raw Lua state sitting behind
  the script's own interpreter -- so a new class under any of them is unreachable without anyone
  having to notice it was added.
- **`import` in HScript** is a separate path -- it resolves through the interpreter's own type
  collection, not `safeResolveClass` -- so the same package list is mirrored into the interpreter's
  blacklist, and both surfaces agree.
- **`File` and `FileSystem`** are bound to Psych-specific replacements scoped to the mod's own
  folders, not to `sys.io`.

> **`hxscript` is not blocked as a package, on purpose.** It is the interpreter itself: `Std`, `Type`
> and `Reflect` inside a script resolve to `hxscript.proxy.*`, and scripted abstracts run on
> `hxscript.types.*`. Blocking the package blacklists the machinery scripts are written against, and
> every script that touches `Std` dies with `Unknown identifier: Std`. `hxscript.Config`, which holds
> the blacklist, is blocked by name instead.

### What this does not claim

This is a blocklist, so it fails open: a class the engine compiles is reachable unless something says
otherwise. That is the deliberate trade -- an allowlist would make every new engine class unreachable
until it was added to a list, which breaks mods for no gain the moment anyone forgets.

A trusted mod also runs code with the engine's privileges. The blocklist decides which *classes* it
can name; it does not sandbox what it does with the ones it can. None of this defends against a mod
you have already chosen to trust -- it defends against reaching the process and the filesystem, and
against a mod changing under you after you trusted it.

## For engine work

`scripting.ScriptHost` owns the script arrays, the load-order scan, dispatch and teardown; it hangs
off `MusicBeatState.scriptHost`, and `PlayState`'s `callOnScripts` / `setOnScripts` /
`startLuasNamed` / ... are one-line delegates to it. `scripting.ScriptError` is the single reporter.
`scripting.ScriptHooks` holds the names and aliases.
