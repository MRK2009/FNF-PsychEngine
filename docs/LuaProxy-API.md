# LuaProxy Patterns — doing things the direct way

Psych's `LuaProxy` bridge pushes **live Haxe objects** into Lua, so most of the
classic string-based callbacks (`getProperty`, `callMethod`, `makeLuaSprite`, …)
have a shorter, faster equivalent: just touch the object directly.

This is a **cookbook of equivalents**. Each entry shows the common task, the
classic way (as an anchor), and the LuaProxy way you should reach for.

> The proxy entry points are `game` (the active PlayState/state) and
> `import('pkg.Class')` for classes. Everything else is reached *through* those.
> Implementation: [`LuaProxy.hx`](../source/psychlua/LuaProxy.hx),
> preset globals in [`HScript.hx`](../source/psychlua/HScript.hx).

---

## Contents

- [⚠️ Status: experimental, expect changes](#️-status-experimental-expect-changes)
- [The two rules that explain everything](#the-two-rules-that-explain-everything)
- [Why (and when) to use LuaProxy over classic psychlua](#why-and-when-to-use-luaproxy-over-classic-psychlua)
  - [Do the math in Lua, not across the bridge](#do-the-math-in-lua-not-across-the-bridge)
  - [How unrestrictive it is](#how-unrestrictive-it-is)
  - [When to prefer the classic callbacks instead](#when-to-prefer-the-classic-callbacks-instead)
- **Patterns**
  - [1. Get / set a property](#1-get--set-a-property)
  - [2. Call a method](#2-call-a-method)
  - [3. Static field / method on a class](#3-static-field--method-on-a-class)
  - [4. Create an instance](#4-create-an-instance)
  - [5. Make and add a sprite](#5-make-and-add-a-sprite)
  - [6. Text](#6-text)
  - [7. Tweens](#7-tweens)
  - [8. Timers](#8-timers)
  - [9. Sound](#9-sound)
  - [10. Cameras](#10-cameras)
  - [11. Colors](#11-colors)
  - [12. Iterate a group or array](#12-iterate-a-group-or-array)
  - [13. Reach into a group member](#13-reach-into-a-group-member)
  - [14. Add / remove from a group](#14-add--remove-from-a-group)
- [The script lifecycle is unchanged](#the-script-lifecycle-is-unchanged)
- [When to still use the classic callbacks](#when-to-still-use-the-classic-callbacks)
- [Gotchas](#gotchas)

---

## ⚠️ Status: experimental, expect changes

LuaProxy is **still in active development.** The bridge itself
([`LuaProxy.hx`](../source/psychlua/LuaProxy.hx) says so in its own header) is
being optimized and iterated on, so:

- **Proxy behaviour can change between engine versions** — caching, how
  containers are pushed, what's 1-based vs native, edge cases around `nil` and
  iteration. Pin your engine version if a mod depends on subtle proxy details.
- **The objects and methods you reach through it are not Psych's API.** When you
  write `game.boyfriend.scale.set(...)` or `FlxG.sound:play(...)`, you're calling
  straight into **Flixel / OpenFL / Lime**. Those libraries get upgraded, and a
  signature, field name, or default can change with them — your script breaks even
  though Psych's own callbacks didn't. The classic string callbacks are a
  stability layer *over* those libs; the proxy deliberately removes that layer.

Treat proxy access as powerful-but-sharp: great for development and mods you
maintain, riskier for "fire and forget" releases meant to run on future builds.

---

## The two rules that explain everything

1. **Property = dot.** `game.health`, `game.boyfriend.x`. Reading and assigning
   both work.
2. **Method = colon.** `game:endSong()`, `game.boyfriend:playAnim('hey', true)`.
   The `:` passes the object as `self`; a `.` will misbehave.

If you remember those two, every pattern below is just a combination of them.

> **You import almost everything yourself.** On the Lua side the proxy only adds
> two things to the global scope: `game` and `import`. There is **no preset list
> of classes** — `FlxSprite`, `FlxTween`, `FlxG`, `FlxColor`, `Paths`, etc. are
> *not* globals until you `local FlxSprite = import('flixel.FlxSprite')`. (This is
> the opposite of HScript, which injects a big preset list — see
> [`HScript.hx → preset()`](../source/psychlua/HScript.hx). That list does **not**
> apply to Lua.) When in doubt, `import` it. That's why nearly every pattern below
> opens with an `import(...)` line.

---

## Why (and when) to use LuaProxy over classic psychlua

The classic callbacks (`getProperty`, `callMethod`, `makeLuaSprite`, …) are a
**curated, string-based wrapper**: a fixed menu of functions the engine chose to
expose, each doing reflection on the path string every call. LuaProxy instead
hands you the **real object**. That buys you:

- **Less ceremony.** No tags, no `add*`/`remove*` pairing, no dotted strings to
  typo. `game.boyfriend.x = 800` instead of `setProperty('boyfriend.x', 800)`.
- **Speed on hot paths.** A cached proxy classifies each key once; method calls
  then run with no per-call reflection (see the caching notes in
  [`LuaProxy.hx`](../source/psychlua/LuaProxy.hx)). Tight `onUpdate` loops benefit.
- **Reach.** You're not limited to what someone added a callback for.

### Do the math in Lua, not across the bridge

LuaJIT is **extremely fast at raw arithmetic** — far faster than reaching into
Flixel/Haxe for it. Every proxy access or `import('flixel.math.FlxMath')` call
crosses the Lua↔Haxe boundary (a C call, argument marshalling, a `Reflect`/
metatable hop). That overhead dwarfs the actual `+`/`*`/`math.sin` you were after.

So for anything number-heavy, **compute in native Lua and write the final value
back through the proxy once**, rather than poking the object every step:

```lua
-- slow: reads + writes cross the bridge every frame, FlxMath does the lerp
function onUpdate(elapsed)
    local FlxMath = import('flixel.math.FlxMath')
    game.camHUD.zoom = FlxMath.lerp(game.camHUD.zoom, 1.0, elapsed * 3)
end

-- fast: keep the running value in a Lua local, do the math natively,
-- touch the proxy only to write the result
local hudZoom = 1.0
function onUpdate(elapsed)
    hudZoom = hudZoom + (1.0 - hudZoom) * math.min(elapsed * 3, 1)
    game.camHUD.zoom = hudZoom
end
```

Same idea for sin/cos wiggles, distance checks, easing, RNG-driven offsets, etc.:
use Lua's `math.*` and plain operators in the loop, and only cross the bridge to
*apply* the result. Pull any `import(...)` you do still need out of the loop and
cache it in a local — don't re-resolve the class every frame.

### How unrestrictive it is

This is the big one: **the proxy exposes essentially the whole object graph.**
Any public field or method on a reachable object is yours, and `import(...)` opens
any resolvable class:

```lua
-- things with no dedicated callback — all reachable through the proxy
game.camHUD.filters = { ... }
game.boyfriend.animation.finishCallback = function(name) ... end
game.vocals.pitch = 1.05
game.camGame.flashSprite.scaleX = 1.02         -- reach into the underlying OpenFL sprite
import('flixel.FlxG').timeScale = 0.5          -- static field, slow-mo everything
```

If Haxe can see it and a script can resolve it, you can touch it — fields,
nested objects, statics, constructors, even functions stored as variables. The
only gate is **ModSecurity**: classes on the blocklist resolve to `nil` (see
`import` / `createInstance`), so untrusted mods can't reach dangerous types.

The flip side of "unrestrictive" is **no guardrails**: nothing validates that a
field exists, that a value is the right type, or that the underlying Flixel
method still has that signature next version. The classic API fails loud with a
debug message; the proxy will just error or do nothing. That's the trade.

### When to prefer the classic callbacks instead

See [the dedicated section below](#when-to-still-use-the-classic-callbacks) — short
version: cross-script helpers, native-table returns, `allowMaps`/`allowInstances`,
and maximum forward-compatibility.

---

## 1. Get / set a property

```lua
-- classic
setProperty('health', 2)
local x = getProperty('boyfriend.x')

-- LuaProxy
game.health = 2
local x = game.boyfriend.x
game.boyfriend.x = game.boyfriend.x + 50
```

Nested paths are just chained dots — no string to split:

```lua
-- classic
setProperty('boyfriend.scale.x', 1.5)

-- LuaProxy
game.boyfriend.scale.x = 1.5
```

## 2. Call a method

```lua
-- classic
callMethod('boyfriend.playAnim', {'hey', true})

-- LuaProxy
game.boyfriend:playAnim('hey', true)
```

```lua
-- classic
callMethod('endSong')

-- LuaProxy
game:endSong()
```

## 3. Static field / method on a class

Bring the class in with `import`, then read or call straight off it. `Conductor`
is a good example — it's all static song-timing state:

```lua
-- classic
local pos  = getPropertyFromClass('backend.Conductor', 'songPosition')
local beat = callMethodFromClass('backend.Conductor', 'getBeatRounded', {pos})

-- LuaProxy
local Conductor = import('backend.Conductor')
local pos  = Conductor.songPosition                 -- static field
local beat = Conductor.getBeatRounded(pos)          -- static method
local step = Conductor.crochet / 4
```

`Paths` is another all-static helper class — and a reminder that it is **not** a
Lua global, so import it before use:

```lua
local Paths = import('backend.Paths')
local img = Paths.image('myImage')          -- static method, returns a graphic
local atlas = Paths.getSparrowAtlas('BOYFRIEND')
```

> `import('pkg.Class')` returns a **class proxy**: static members are read
> directly, and `.new(...)` constructs it (next entry). Blocked classes return
> `nil`, so guard if you're unsure.

## 4. Create an instance

A scrolling `FlxBackdrop` (from flixel-addons) is a good case — there's no
dedicated callback for it, and its constructor takes options the string API can't
pass cleanly:

```lua
-- classic: createInstance can build it, but only with default args, and tweaking
-- it afterwards through string properties is awkward
createInstance('bg', 'flixel.addons.display.FlxBackdrop')
addInstance('bg')

-- LuaProxy: construct it, then touch its fields/points directly
local FlxBackdrop = import('flixel.addons.display.FlxBackdrop')

local Paths = import('backend.Paths')

-- new(?graphic, repeatAxes = XY, spacingX = 0, spacingY = 0)
-- repeatAxes is the FlxAxes enum-abstract, which import() can't resolve (see the
-- gotcha below) — pass its underlying Int: XY = 0x11, X = 0x01, Y = 0x10
local bg = FlxBackdrop.new(Paths.image('sky'), 0x11, 20, 20) -- tile XY, 20px gaps
bg.scrollFactor:set(0.4, 0.4)
bg.velocity.x = -30        -- slow horizontal scroll — backdrop tiles infinitely
game:add(bg)
```

You now hold the object in a local — no tag string, no second `addInstance` call.
(If you *want* it in the shared store so other scripts can find it by tag, use
`setVar('bg', bg)`.)

## 5. Make and add a sprite

```lua
-- classic
makeLuaSprite('bg', 'menuBG', 0, 0)
setProperty('bg.alpha', 0.5)
addLuaSprite('bg', false)

-- LuaProxy
local FlxSprite = import('flixel.FlxSprite')

local Paths = import('backend.Paths')

local bg = FlxSprite.new(0, 0)
bg:loadGraphic(Paths.image('menuBG'))
bg.alpha = 0.5
game:add(bg)
```

Animated sprite (Sparrow atlas):

```lua
local FlxSprite = import('flixel.FlxSprite')

local Paths = import('backend.Paths')

local spr = FlxSprite.new(100, 100)
spr.frames = Paths.getSparrowAtlas('myAtlas')
spr.animation:addByPrefix('idle', 'idle animation', 24, true)
spr.animation:play('idle')
game:add(spr)
```

## 6. Text

```lua
-- classic
makeLuaText('label', 'Hello', 400, 0, 0)
setTextSize('label', 32)
addLuaText('label')

-- LuaProxy
local FlxText = import('flixel.text.FlxText')

local Paths = import('backend.Paths')

local label = FlxText.new(0, 0, 400, 'Hello', 32)
label:setFormat(Paths.font('vcr.ttf'), 32, 0xFFFFFFFF, 'center')
game:add(label)
```

## 7. Tweens

Call `FlxTween` directly — you don't need a tag unless you want to cancel it.

```lua
-- classic
doTweenX('move', 'boyfriend', 800, 1, 'quadOut')

-- LuaProxy
local FlxTween = import('flixel.tweens.FlxTween')

local FlxEase = import('flixel.tweens.FlxEase')

FlxTween.tween(game.boyfriend, {x = 800}, 1, {ease = FlxEase.quadOut})
```

Multiple properties + a completion callback in one call:

```lua
FlxTween.tween(game.boyfriend, {x = 800, alpha = 0}, 1, {
    ease = FlxEase.quadInOut,
    onComplete = function(twn) game.boyfriend.visible = false end
})
```

## 8. Timers

```lua
-- classic
runTimer('wait', 1.5, 1)   -- then handle onTimerCompleted('wait')

-- LuaProxy
local FlxTimer = import('flixel.util.FlxTimer')
FlxTimer.new():start(1.5, function(tmr)
    -- runs after 1.5s; tmr.loopsLeft / tmr.elapsedLoops available
end, 1)
```

## 9. Sound

```lua
-- classic
playSound('cheer', 0.7)

-- LuaProxy
local FlxG = import('flixel.FlxG')

local Paths = import('backend.Paths')

FlxG.sound:play(Paths.sound('cheer'), 0.7)
```

Keep a handle if you need to control it later:

```lua
local snd = FlxG.sound:play(Paths.sound('loop'), 1, true) -- looped
snd.pitch = 1.2
snd:stop()
```

## 10. Cameras

```lua
-- classic
cameraShake('camGame', 0.01, 0.2)

-- LuaProxy
game.camGame:shake(0.01, 0.2)
game.camHUD.zoom = 1.1
```

## 11. Colors

`FlxColor` is an **enum abstract over `Int`**, so `import('flixel.util.FlxColor')`
returns `nil` — you can't reach `FlxColor.RED`/`fromRGB` from Lua that way. But a
color *is just an int*, so the proxy still works fine — assign hex directly:

```lua
-- LuaProxy: colors are ints; assign an ARGB hex literal
game.boyfriend.color = 0xFFFF0000          -- opaque red
game.camHUD.bgColor  = 0x80000000          -- 50% black
```

For named colors or string/RGB conversions, the classic `getColorFrom*` helpers
are the clean route (they return the int you'd assign):

```lua
-- classic helpers, still the right tool here
local c = getColorFromHex('FF0000')
game.boyfriend.color = getColorFromString('red')
```

## 12. Iterate a group or array

Proxied containers are **1-based** and support `#`. Use a numeric loop —
`pairs`/`ipairs` do **not** work on a proxy.

```lua
-- the unspawnNotes / notes group, members, etc.
local notes = game.notes
for i = 1, #notes do
    local n = notes.members[i]   -- groups expose .members; arrays index directly
    n.alpha = 0.6
end
```

```lua
-- a plain Haxe array property
local chars = game.gfGroup.members
for i = 1, #chars do
    chars[i].visible = true
end
```

> ⚠️ A callback that *returns* an array/map hands you a native Lua table (so
> `ipairs` works on those). But anything you index off `game.*` is a live proxy —
> numeric loop only. See [`CallbackHandler.hx`](../source/psychlua/CallbackHandler.hx).

## 13. Reach into a group member

```lua
-- classic
getPropertyFromGroup('notes', 0, 'strumTime')

-- LuaProxy (remember: 1-based from Lua)
game.notes.members[1].strumTime
```

## 14. Add / remove from a group

```lua
-- classic
addToGroup('grpName', 'myTag')

-- LuaProxy
game.someGroup:add(mySprite)
game.someGroup:remove(mySprite, true)   -- true = splice
```

---

## The script lifecycle is unchanged

LuaProxy only changes *how you reach objects* — it does **not** change how scripts
are structured or run. Every Psych script callback still fires exactly as before,
and you put your proxy code inside them:

```lua
function onCreate()
    -- runs before the song's sprites are set up
end

function onCreatePost()
    -- safe to touch game objects here
    game.boyfriend.x = game.boyfriend.x - 40
end

function onUpdate(elapsed)
    -- native Lua math, write the result through the proxy once
    game.camHUD.zoom = game.camHUD.zoom + (1.0 - game.camHUD.zoom) * math.min(elapsed * 3, 1)
end

function onStepHit() end
function onBeatHit() end
function onSectionHit() end
```

Common callbacks the engine calls (verified in
[`PlayState.hx`](../source/states/PlayState.hx)): `onCreate`, `onCreatePost`,
`onUpdate`, `onUpdatePost`, `onStepHit`, `onBeatHit`, `onSectionHit`,
`onStartCountdown`, `onCountdownStarted`, `onCountdownTick`, `onSongStart`,
`onSpawnNote`, `onGhostTap`, `onKeyPress` / `onKeyPressPre`, `onKeyRelease` /
`onKeyReleasePre`, `noteMissPress`, `onUpdateScore` / `preUpdateScore`,
`onEvent` / `onEventPushed` / `eventEarlyTrigger`, `onMoveCamera`, `onResume`,
`onPause`, `onGameOver`, `onEndSong`. (Note hooks like `goodNoteHit` /
`opponentNoteHit` / `noteMiss` are also still dispatched.)

So a typical proxy-style script is just the same lifecycle you already know, with
`game.*` / `import(...)` inside it instead of `getProperty`/`setProperty`.

---

## When to still use the classic callbacks

The string API isn't deprecated — reach for it when:

- You're following an existing tutorial / copy-pasting community snippets.
- You need the cross-script helpers there's no object for: `setOnScripts`,
  `callOnScripts`, `triggerEvent`, `precacheImage`, `startDialogue`, etc.
- You want a value handed back as a **native Lua table** (e.g. `getVar`) rather
  than a proxy.
- A property path needs `allowMaps`/`allowInstances` handling that the raw proxy
  doesn't do.

Otherwise, direct proxy access is shorter, avoids string typos, and skips the
reflection the string API does on every call.

---

## Gotchas

- **Almost nothing is preset on the Lua side** — only `game` and `import` are
  global. Import every class yourself (`FlxSprite`, `FlxG`, `FlxColor`, …); the
  HScript preset list does not apply here.
- **Method `:`, property `.`** — the single most common mistake.
- **1-based + numeric loops** on proxies; no `pairs`/`ipairs`.
- **`import` can return `nil`** (blocked or misspelled class) — guard before
  `.new`.
- **`import` resolves *classes* only** — not enum-abstracts like `FlxAxes`,
  `FlxTweenType`, or typedefs (it uses `Type.resolveClass`). For those, pass the
  underlying value or use a class method that accepts a string.
- **Locals vs the store** — a local you `import().new()` is yours; use
  `setVar(tag, obj)` only if another script must find it by name.
- **Groups expose `.members`**; raw arrays index directly.
