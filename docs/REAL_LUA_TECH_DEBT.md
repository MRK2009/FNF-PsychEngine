# Real Lua (LuaProxy) — known limitations & things to revisit

Running list of implementation shortcuts, residual bugs, and "good enough for now"
decisions in the real-Lua / `LuaProxy` system. None of these block normal modpack
work today, but each is worth a second pass. See [REAL_LUA.md](REAL_LUA.md) for how
the system is *supposed* to work.

> Format: **[severity]** short title — what's wrong, why it's like that, and the
> shape of a proper fix.

---

## 1. **[revisit]** Function-valued tables in Lua *return values* can still be truncated

This is the one to come back to.

The Lua→Haxe converter has a stack-balance hazard: the wrapper's `LuaConverter.fromLua`
`TFUNCTION` branch uses `luaL_ref`, which **pops** the value it stores. Callers that
walk a table (and the per-argument unwrap) expect the value to stay on the stack and
pop it themselves — so a table containing a function (e.g. `{ease=.., onComplete=..}`)
would have its key popped out from under `lua_next` and the table got silently
**truncated**, dropping the callbacks.

We fixed this for the paths the engine actually drives — **argument / options-table
conversion** — in [`source/llua/Convert.hx`](../source/llua/Convert.hx) (duplicate the
value with `Lua.pushvalue` before the haxelib's `ref` pops it; reimplement `TTABLE`
iteration so it recurses through the corrected `fromLua`).

**Residual:** when a Lua callback *returns* a value, the haxelib's
`LuaUtils.callFunctionWithoutName` reads the results with the haxelib's **own**
`fromLua`, bypassing our shim. So a Lua function that returns a *table containing
functions* would still truncate. In practice this never happens (tween eases return a
number, `onComplete` returns nothing), which is why it's deferred.

**Proper fix:** push the correct conversion upstream — either fork/patch
`hxluajit-wrapper` so `fromLua`'s `TFUNCTION` branch is stack-balanced at the source
(and `convertTable` recurses through it), or route `callFunctionWithoutName`'s result
reading through our shim. Right now the logic is **duplicated** between the haxelib and
`Convert.hx`, which is itself drift risk (see #2).

> `.haxelib/` is **gitignored** — do not "fix it in the haxelib unless there are no possible way to do it engine-side " 
> conversion fix has to live in `source/` (today: `Convert.hx`) or be vendored properly.

---

## 2. **[maintainability]** `Convert.hx` duplicates haxelib table-conversion logic

`source/llua/Convert.hx` now reimplements `convertTable` / table iteration **and** the
Haxe→Lua container pushes (array / map / anonymous structure) that also exist in
`hxluajit-wrapper`. They can drift. A cleaner setup: a single source of truth (proper
vendored fork of the wrapper, or move *all* conversion into the project and stop
delegating). Tied to #1.

The Haxe→Lua half had to be reimplemented for correctness, not just for symmetry: the
haxelib's `toLua` has no proxy bridge, so its `default` branch pushes **nil** for any class
it does not special-case. An `Array<NoteData>` therefore reached Lua as a table of nils,
which is what made `onNotesGenerated` useless from Lua while HScript saw the live list.
Container elements now go through the `haxeToLua` hook, the mirror of `userdataToHaxe`.

---

## 3. **[ergonomics]** Raw mode has no tween/timer tag registry — cancellation is manual

Compat PsychLua's `doTween*`/`startTween` cancel the prior tween sharing a tag
(`LuaUtils.tweenPrepare` → `cancelTween`). Raw scripts call `FlxTween.tween` directly,
which does **not** cancel — so rapid re-triggers (fades, strobes) stack uncancelled
tweens and the effect looks stuck / "flashes once". We currently emulate this per-script
with `FlxTween.cancelTweensOf(obj, {field})`, which is:
- **manual** (easy to forget when porting a script), and
- **coarser** than per-tag (it cancels by object+field, not by an arbitrary tag).

**Proper fix:** offer a small raw-friendly tagged-tween helper (or document the
`cancelTweensOf` pattern as the official idiom). Decide whether raw mode should ship a
thin tag registry or stay deliberately bare.

---

## 4. **[ergonomics]** Stage scripts must manually re-insert sprites behind characters

A stage `.lua` runs in `PlayState` **after** the character groups are added, so a plain
`game:add(bg)` draws on top of the characters. Today each raw stage has to re-insert
behind them (`game:remove(spr,true); game:insert(idx, spr)`), replicating the old
`setObjectOrder`. This is non-obvious and repetitive across ~13 stages.

**Proper fix:** an engine helper exposed to raw mode (e.g. an `addBehindChars`/order
helper), or load stage scripts before the character groups, or document one canonical
helper to paste.

---

## 5. **[perf]** Per-frame proxy churn & callback round-trips

Partly addressed. What was done:

- Ephemeral pushes now **reuse an object's existing cached proxy** when it has one, so a
  method returning `this` (or a getter for something the script already touched) stops
  allocating a fresh handle per call.
- A classified plain field is tagged in the proxy env with an **interned key id**, not
  `true`, so a cached read no longer rebuilds a Haxe `String` from Lua's C string on
  every access. `__newindex` shares the same classification, which it previously had no
  fast path for at all.
- Metatable callbacks carry the resolved `ProxyState` instead of re-reading the state id
  out of the Lua registry on every value pushed.

- `isProxy` is a `getmetatable` plus a `rawgeti` on an integer slot, instead of one or two
  registry lookups **by string name** plus a `rawequal`. It runs per argument of every
  method call. Both metatables keep their own identity, which Lua 5.1 `__eq` dispatch
  depends on.
- `Type.typeof` is gone from the push path in both `LuaProxy` and `Convert`. On hxcpp it
  CONSTRUCTS a `ValueType`, and `TClass(c)`/`TEnum(e)` carry a parameter — so classifying
  a value to push it allocated an enum instance per push, purely to be switched on.
- `ProxyFields` gives the members scripts touch every frame (`x`, `y`, `angle`, `alpha`,
  `color`, `visible`, `scale.x`, …) direct typed access: an interned integer id switches
  into a real field read or a virtual `set_*`, with no `Reflect` and no `Dynamic` boxing of
  the value. Reflection remains the fallback for everything else.

Still open:

- Method returns for objects with **no** cached proxy are still a fresh handle per call.
  Pooling would help tight loops.
- An `ease` passed as a proxy method closure (`FlxEase.linear`) becomes a `makeVarArgs`
  wrapper that round-trips Haxe→Lua→Haxe **every tween step**. Correct, but heavy.
  Consider detecting/short-circuiting known `FlxEase` functions, or passing eases by name.
- `ProxyFields` only covers `FlxObject`, `FlxSprite` and `FlxBasePoint`. Engine types with
  their own hot members (`Character`, `Receptor`, `Conductor` statics) still go through
  reflection. Extending it is mechanical, but every field added must be a property with a
  setter **on the base class** — a plain variable would be written directly and skip
  `FlxSpriteGroup`'s propagating overrides.

---

## 8. **[fixed, needs play test]** Anonymous structures are proxied on the direct path

Anonymous structures used to marshal to a **table copy**, so on the direct path
`game.SONG.notes[0].mustHitSection = true` wrote to a throwaway and was silently lost —
chart data is made of typedefs (`ChartSection`, `SongNote`, `SwagSection`). They are proxied
now, so writes reach the real structure. The traditional callback API is unchanged: it still
hands back table copies, byte-compatible with upstream Psych.

**This is the one behaviour change in the batch that a raw-Lua script could notice.** A
section reached off `game.*` is now `userdata`, not `table`, so a script doing
`type(section) == 'table'`, `table.insert(section, …)` or passing one to `table.*` breaks.
Iteration is covered — `pairs`/`ipairs` work on proxies now — but the raw stages should be
play-tested before this is trusted.

---

## 9. **[perf]** Lua numbers always reach Haxe as `Float`

`LuaConverter.fromLua` returns `lua_tonumber` for every number, so a Lua `1` arrives at a
Haxe `Int` parameter as `1.0` boxed in `Dynamic`, and `Std.isOfType(v, Int)` is false for it.
`mapKeyAt` already narrows integral values for map lookups; `unwrap` does not.

Narrowing in `unwrap` would fix it, but `unwrap` feeds **every** argument of the whole
classic callback API, and this codebase has been bitten by hxcpp `Dynamic` numeric coercion
before. Worth doing, but with a real play test, not a type-check.

---

## 6. **[cleanup]** Compat-stage + raw-event mixing relies on the shared variables map

Cross-mode sprite sharing works because `makeLuaSprite` (compat) stores into
`MusicBeatState.getVariables()`, the same map raw `getVar` reads. That's intentional and
fine, but it's an implicit contract. When the FNAF3 stages are all converted to raw,
re-verify nothing still depends on a compat stage feeding a raw event (and document the
contract in REAL_LUA.md if we keep relying on it).

---

## 7. **[accepted]** `camera bounce` event does not cancel its tweens

Intentional: its tweens use near-instant durations and span four different fields per
beat/step, so they don't meaningfully overlap. Noted here so a future audit doesn't
"fix" it and add needless overhead. Revisit only if it visibly misbehaves.
