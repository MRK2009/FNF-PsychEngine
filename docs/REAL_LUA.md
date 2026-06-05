# Real Lua (direct object access)

This fork adds a **real Lua** layer on top of the classic PsychLua API. Instead of
string-path callbacks (`setProperty('boyfriend.x', 100)`), Lua can hold and use live
engine objects directly — the same way HScript does:

```lua
game.boyfriend.x = 100          -- set a field
local hp = game.health          -- read a field
game:endSong()                  -- call a method (use ':' for methods)
local n = game.boyfriend:getScreenPosition()

-- import any (non-blacklisted) engine/Haxe class:
local FlxSprite = import('flixel.FlxSprite')
local spr = FlxSprite.new(0, 0)         -- or FlxSprite(0, 0)
spr:loadGraphic(Paths.image and Paths.image('mySprite') or 'mySprite')
game:add(spr)

local FlxG = import('flixel.FlxG')
trace(FlxG.width)
```

A full, commented **stage** example (imports, add/remove sprites, live variable access,
lifecycle hooks) lives at [docs/scripts/ExampleStage.lua](scripts/ExampleStage.lua).

## How it works

Haxe objects are pushed into Lua as **userdata with a shared metatable**
(`source/psychlua/LuaProxy.hx`). `__index`/`__newindex` reflect onto the real object,
methods become bound closures, and `import('pkg.Class')` returns a class proxy (static
fields + `new`). Arrays index 0-based (like Haxe/HScript). This bridge is active in **both**
modes, so even classic scripts can use `game.boyfriend.x`.

Always available (both modes): `game` / `instance` (the PlayState), `getVar` / `setVar` /
`removeVar`, and `import(...)`.

## Modes: `compat` vs `raw`

- **compat** (default): the full legacy PsychLua callback API (`getProperty`, `makeLuaSprite`,
  the hundreds of helpers) **plus** the real-Lua proxies.
- **raw**: the legacy callback API is **not registered** — scripts rely solely on direct object
  access (`game.*`, `import(...)`, `getVar`/`setVar`). Lighter, and forces the modern style.

### Choosing the mode (precedence: per-script > per-mod > global)

1. **Per-script** — put a directive near the top of the `.lua` file:
   ```lua
   -- @luamode raw
   ```
   (or `-- @luamode compat`).
2. **Per-mod** — in the mod's `pack.json`:
   ```json
   { "name": "My Mod", "luaMode": "raw" }
   ```
3. **Global** — Options → Misc Settings → **Lua Mode** (`compat` / `raw`), stored as
   `ClientPrefs.data.luaMode`.

## Notes
- `import(...)` is gated by Mod Security (the same blacklist HScript uses), so untrusted/blocked
  classes resolve to `nil`.
- Reflection happens per field access (like HScript) — fine for normal scripting; avoid in tight
  per-frame loops.
- Returned Haxe objects from existing callbacks (e.g. `getVar('mySprite')`) now come back as live
  proxies instead of `nil`.
