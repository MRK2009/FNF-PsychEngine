# Release Notes: v1.3.1

A patch release on top of v1.3.0: bug fixes reported against 1.3.0, with no new
features.

## General

### Fixes
- **Hurt Notes**: no longer render uncolored. The note-system-v2 rewrite applied
  a note type's gameplay effects but never its visual half, so Hurt Notes lost
  their tint. The drawable now applies the type's RGB palette and electric splash
  to both the note head and the sustain trail.
- **Freeplay / weeks**: mod weeks now honor their `hideFreeplay` flag. The mod
  week loader read the stale `PlayState.isStoryMode` static instead of the mode
  passed to `reloadWeekFiles`, so weeks hidden from Freeplay could still leak in
  after playing Story mode.
- **Freeplay**: selecting a song and pressing Enter no longer
  intermittently just plays the cancel sound. The song-library's per-frame
  metadata/rating streaming reassigned the global `Mods.currentModDirectory` to
  whatever song it was scanning and never restored it, so the wrong mod context
  could be live when you pressed Enter and the chart failed to load. The library
  now scopes and restores that global around each lookup, leaving the selection as
  its sole owner.
- **ClientPrefs**: setting `ClientPrefs.data.widescreen` from a script now applies
  to the live scale mode immediately (e.g. disabling widescreen for one song),
  instead of only changing the stored value. `widescreen` is now a property whose
  setter drives `FullScreenScaleMode` on desktop.
- **Libraries**: the entire Flixel and flixel-addons class surface is now kept
  out of dead-code elimination, so scripts can construct any of them by name
  (`import()`/reflection) without the class resolving to `nil`. Previously only
  types the engine itself referenced survived DCE, so classes like
  `FlxSkewedSprite` were unavailable to mods.
- **LuaProxy**: a Lua table of objects assigned to a Haxe field now translates
  correctly. Assigning a table literal such as `game.camGame.filters =
  {shaderFilter}` produced an array of `null` (and crashed the renderer) because
  the table-to-array conversion could not unwrap the proxy elements back to their
  live objects; scripts had to build a real array with `import('Array')` and
  `:push()` instead. Table elements are now unwrapped like every other argument,
  so the direct `{...}` assignment works and the `import('Array')` workaround is no
  longer needed.

- **Multikey centre notes**: the shared `noteSkins/square` atlas was missing from the
  repo, so classic (atlas) skins rendered **no centre note at all** on any keycount that
  has one -- the merge silently resolved to nothing. The atlas ships again, and a skin
  can now point `squareSheet` at its own instead.
- **Note colours on keycount change**: switching keycount recoloured the receptors but
  not the notes. The shared per-column palettes are seeded from the keycount palette but
  cached by column alone and were never invalidated, while receptors re-read the colours
  directly. The cache is now dropped when the keycount actually changes.
- **Splash scale**: a skin's `splashScale` did nothing on the default 4K layout -- the
  scale was only ever applied inside the multikey branch. It now applies at every
  keycount, with the multikey shrink layered on top.
- **Pixel splashes**: folder skins got no pixelated splash on pixel stages. The splash's
  pixel look comes from a shader, but folder skins hard-disabled it on the assumption
  they ship their own pixel art -- which for splashes they were never expected to. The
  shader now runs unless the skin actually ships a pixel splash, in which case it stays
  off so the art isn't pixelated twice.
- **Receptor drift on hit**: receptors shifted a few pixels after being hit, most visibly
  on pixel skins. A folder skin's frames are packed at their own individual sizes, so
  frames within one animation can differ in size; the centring was computed once when the
  animation started and went stale as it advanced. It is now refreshed whenever the
  current frame's size actually changes.
- **Classic hold alignment**: on atlas skins the hold trail sat ~2px right of its note
  head, because the head centres on its own art width while the trail centred on the
  nominal lane width (a 154px arrow at 0.7 is 107.8 wide against a 112px lane). The trail
  is now pulled onto the head; nothing else moves.
- **Hold layering**: `holdsOverHeads` drew every trail permanently on top of the note
  heads. A trail now only lifts above the receptor while it is actually being **held**,
  which is the moment it should read as passing over -- un-held trails stay behind their
  heads as before.
- **Note skin configs**: saving a skin no longer silently drops fields. The writer had a
  hardcoded whitelist that omitted `sheet` -- the field naming an atlas skin's sheet --
  so an atlas skin could never be saved correctly. `sheet`, `holdsOverHeads`,
  `headOverlap` and `fitColumnWidth` now round-trip.
- **Note skins in mods**: a folder skin living in a non-current mod reported its pixel art
  as missing (it rendered fine); the lookup didn't pin asset resolution to the skin's
  owning mod the way the renderers do.

### New
- **Freeplay Music Player**: rebuilt on SmidrUI, the song-preview player is now a persistent
  bar (draggable seek slider, Play/Pause, Reset, playback-rate stepper) with real
  touch controls, replacing the old Flixel overlay. The info panel above it now
  shrinks to its content instead of leaving a large empty gap. A new **Freeplay
  Song Preview** option (Visuals, off by default) auto-plays/switches the preview
  as you scroll the list, osu!/Etterna-style.
- **Rewritten crash handler**: the old "write a log, pop a native alert, quit"
  path was replaced with an in-engine crash screen. When a caught error kills the
  running state you now get a screen that lets you **try to continue** (drop back to
  the main menu instead of losing the whole session), **copy the report**, open the
  **crash folder**, or quit -- with a **Send Issue** button stubbed in for later. A
  crash-loop guard falls back to the old alert-and-exit if errors keep firing.
  - **Richer reports**: crash logs now capture the engine version, the OS and its
    version/build number, CPU architecture, desktop/mobile form factor, display
    resolution, and locale, plus the live state, current mod, song + difficulty, and
    memory alongside the stack. All of it is machine-generic (nothing that identifies
    the user), gathered once at startup, and every lookup is guarded so collecting that
    context can never crash on top of the original error.
  - **Script errors are recorded**: HScript / hscript-insanity and LuaProxy errors are
    fed into a rolling history that is folded into the next crash report. A bad script
    frequently corrupts state that hard-crashes a few frames later, so the report now
    shows the script activity that led up to it.
  - **Silent script crashes are caught**: HScript and Lua could previously take the
    whole game down with *no* log at all -- e.g. handing a bad shader/filter to the
    renderer faults deep in native code, which never reaches the normal error handler.
    A native signal / SEH handler now catches those hard crashes and still writes a
    report; because the recent-script-error history lives in memory that survives the
    fault, the log usually points straight at the offending script.

- **Rewritten Note Skin Editor**: the old single tab-box editor was replaced with a
  proper editor layout -- menu bar, activity rail, left dock and inspector, transport
  and status bar, matching the chart editor's chrome. On entry it asks whether to make
  a new skin or open an existing one; **File** handles both afterwards.
  - **Live simulated chart**: the preview is a looping generated pattern (taps, chords,
    jacks, sustains) scrolling down a *real* `NoteField` and auto-playing at the
    receptor line, with confirm animations and splashes. It runs the shipping gameplay
    path -- real receptors, pooling, spawn/reclaim and `follow` geometry -- so the
    preview cannot drift from what gameplay draws. A **Static** mode freezes it and
    cycles the receptor states for still inspection.
  - **Everything applies live**: every field restyles the running simulation in place;
    there is no Apply step and the pattern never stops scrolling.
  - **Atlas skins are first-class**: classic sparrow-atlas skins can now be previewed
    and edited at all (the old editor only handled folder skins), including their frame
    prefixes and the centre-lane atlas.
  - **Pixel art is its own tab**: the two interacting `pixel` / `pixelVariant` booleans
    are replaced by an explicit **pixel mode** (`none` / `always` / `variant`; the old
    booleans are still read, so existing skins are unaffected). The tab shows where each
    element's pixel art resolves from and whether it was found, and a **preview as pixel
    stage** toggle checks the pixel look without changing the skin.
  - **Pixel art baking**: generate a skin's `pixel/` art from its HD art instead of
    drawing it from scratch. Splash frames reproduce the pixel-splash *shader* (which
    quantises in place), while notes/strums/holds are downscaled by `scale / pixelScale`
    -- the factor that makes them occupy the same on-screen space. Both then get an
    alpha cull (anything under 50% opacity is dropped, the rest made fully opaque) and
    an optional median-cut palette reduction, which is what makes the result read as
    pixel art rather than a blurry miniature. Meant as a base to tidy up by hand.
- **New note skin options**: skins can now ship their own **note colours** (`noteColors`,
  falling back to your arrow colours; a new **Override Skin Colours** option in Visuals
  ignores them), set a per-skin **column gap** (`columnGap`, added on top of the engine's
  spacing and honoured at every keycount including 4K), declare whether they have a
  **hold end cap** (`hasHoldEnd`), force the **splash to follow the lane colour**
  (`splashSyncColor`), and point at their own **centre-lane atlas** for multikey
  (`squareSheet`) instead of the shared one.
- **Legacy note skin**: the classic 1.0.4 `NOTE_assets` sheet ships again as a selectable
  **Legacy** skin, and is the template new atlas skins are cloned from.

## Mobile specific
- **Substate**: closing a substate (e.g. Gameplay Changers) no longer also backs
  out of the parent menu. A finger still held on the Back button when the substate
  closed was re-read as a fresh press by the parent's touch pad on the resume
  frame; a pad regaining focus now ignores touches already held over its buttons.
- **Mobile**: the Benchmark menu now has on-screen navigation (up/down + accept/
  back), so it can be used without a keyboard. (Aborting a running suite still
  needs F8.)
- **Rewritten touch pad**: the on-screen menu gamepad was rebuilt with SmidrUI-styled
  buttons on a self-managed overlay, replacing the old flat sprites. It still
  drives `backend.Controls` through the same API (so every menu keeps working
  unchanged) and keeps true multitouch by hit-testing `FlxG.touches` itself. The
  gameplay lane Hitbox is unchanged.
- **Freeplay**: tapping the on-screen navigation pad no longer also click-selects
  the song row underneath it -- taps that land on a pad button are ignored by the
  list.
- **Chart editor**: the mobile editor's Events picker now lists custom mod events
  (`custom_events/*.txt`), not just the built-in ones.
- **Mods**: a mod's custom fonts now load. Mods live on external storage, which
  OpenFL can't load a font from by path on mobile, so a mod's `fonts/*.ttf`
  silently fell back to the default font ("not recognized"). Mod fonts are now
  registered from their bytes (the same way mod images/sounds already load).
- **Misc**: the mouse-only Legacy Chart Editor is hidden on mobile (it has no
  touch controls);

## Haxelibs
- **HaxeFlixel 6.2.0** (from 6.1.2): brings Flixel's sound-system refactor
  (music streaming, `loopCount` / `loopUntil` on sounds), the new
  `FlxMatrixSprite`, tilemap ray helpers (`rayAdvanced`, `forEachInRay`), and
  position converters between coordinate spaces on `FlxObject` / `FlxCamera`.
  Nothing in the engine or the scripting surface had to change: the `FlxSound`
  load methods kept their names and signatures, and the engine never used the
  generic `FlxRandom` / `FlxArrayUtil` methods that 6.2.0 removed. Scripts that
  construct Flixel or flixel-addons classes by name are unaffected, since that
  whole surface is still kept out of dead-code elimination.
- **hxcpp v4.3.148** (from v4.3.143): bug fixes only, covering `String` and
  reflection handling, the garbage collector, and sockets / process handling,
  plus a warning suppression that quiets the Android NDK build. The Windows and
  Unix setup scripts now pin the *same* hxcpp revision; previously only Windows
  was pinned, so Linux and macOS builds silently used whatever was newest.
- **flixel-animate** now tracks flixel 6.2.0.
- Every other dependency (Lime 8.3.2, OpenFL 9.5.2, flixel-addons 4.0.1, hxvlc
  2.3.0, hxdiscord_rpc 1.3.0, hscript 2.7.0) was already current and is
  unchanged.

## Notes for modders and developers
- **New Lua callback `setNoteRGB(r, g, b, part)`**: sets a spawning note's whole RGB
  palette in one call from `onSpawnNote`, replacing the nine `setProperty` writes it used
  to take. `part` is `all` (default) / `head` / `hold` / `body` / `tail`. Colours accept an
  int, a hex string (`"FF0000"`), or a colour name.
- **New skin fields**: `noteColors`, `columnGap`, `hasHoldEnd`, `splashSyncColor`,
  `squareSheet` and `pixelMode` (see above). `pixelMode` supersedes the `pixel` /
  `pixelVariant` booleans, which are still honoured, so existing skins need no changes.
- **Default skins** now declare `animated: false` for notes, strums and hold pieces
  (pressed/confirm stay animated), so those elements use only their first frame.
- Skins in `skin.tcfg` / `skin.json` are otherwise unchanged and load as before.

### Real Lua (raw mode) hardening
A batch of fixes to the object bridge that backs `import()` and `game:method()` / `game.field`
style scripts. Most are correctness gaps that failed silently, which is the worst way for a
scripting bug to behave.

- **Callbacks can no longer crash on script unload**: a Lua function handed to a Haxe API
  (an `FlxTween` ease/`onComplete`, an `FlxTimer` callback) that outlived the script used to
  fire into the already-freed Lua state -- a hard native crash with no log. Wrapped callbacks
  now check their state is still open and no-op if it isn't.
- **`debugPrint` works in raw mode**: it lived in the legacy callback block that raw mode skips,
  so it was `nil` -- and calling it aborted the script silently, in the exact mode where errors
  are hardest to see. It's now available in both modes (and stringifies its argument, so
  `debugPrint(someBool)` works).
- **`import()` reports failures**: a bad path, a class dropped by dead-code elimination, or one
  blocked by ModSecurity all returned a bare `nil` that surfaced later as "attempt to index a
  nil value" somewhere unrelated. It now warns at the point of failure (log, crash report, and
  on-screen debug text).
- **`==` between two proxies compares the objects**, not the wrapper handles, so
  `a.shader == mirror` is true when they're the same instance. Previously it was effectively
  always false for method returns and field reads.
- **Maps are indexable**: `someMap['tag']` / `someMap[1]` read and write entries, and `#someMap`
  reports the count. Only `Array` had element access before, so a `Map` was reachable only through
  `:get()` / `:set()`.
- **Class statics are writable**: `Conductor.bpm = 150` on an `import()`ed class used to raise an
  error (the class metatable had no write handler). Reads always worked; writes do now too.
- **Methods always return exactly one value**: a method returning null used to push *nothing*, so
  `nil` couldn't be handled positionally (`select('#', o:f())` was 0). A void return is now `nil`.
- **Haxe enums cross into Lua** instead of arriving as `nil`; `..` concatenation works on a proxy;
  cyclic tables (`t.self = t`) passed from a script no longer stack-overflow; a non-string table key
  no longer risks a crash; and iterating a large proxied array no longer pins a proxy per element.
---


# Release Notes: v1.3.0
Where v1.1 was about modernization and maintenance, v1.2 started some experimental stuff, and now v1.3.0 starts with new fork-original systems built on top of that base: a rewritten note runtime
and chart format, a brand-new chart editor, a redesigned Freeplay with real
difficulty ratings, a full scoring/profiles/replay stack, an in-engine osu!
beatmap converter, Android support, and a new UI framework underpinning every
editor and menu.

Backwards compatibility for existing Psych mods is preserved as much as possible, otherwise check the script converter/migration helper by pressing 8 in the Main Menu.

Modpacks can opt-in with `compatibilityMode`
or (`legacyMode`) flag to bridge legacy Lua/HScript mods onto the new note runtime.

---

## Highlights

- **Note System V2**: the note/strum runtime was rewritten with a decoupled
  data/drawable split and note pooling (opening a huge chart no longer allocates
  a sprite per note), on a new native **psych_v2** chart format. `SongChart` is
  now the primary `PlayState.SONG`; v1 charts load through a legacy compatibility
  layer, and data-driven strumlines (up to 3) carry their own camera target and
  character roles.
- **New Chart Editor**: a ground-up editor with pooled notes, per-section scroll
  speed, strumline character icons, GF/role charting, a Patterns rail, a per-song
  Metadata tab, dual waveforms, and a full touch (mobile) chart editor.
- **Redesigned Freeplay**: a threaded, cached song library with streamed
  difficulty ratings (a faithful Etterna **MinaCalc** port plus an osu!mania star
  engine), a classic list with new chrome, search / sort / group / favorites, and
  a song-info and difficulty flyout.
- *BETA*: **Scoring, Profiles and Replays**: pluggable scoring systems (Psych, Wife3,
  osu!mania, V-Slice), local player profiles with an unlimited highscore database,
  1:1 binary replays, and an osu!-style results screen with a hit-offset scatter
  and unstable-rate graph. A gameplay hit-error HUD rounds it out.
- *BETA*: **In-engine osu! converter**: `.osz`/`.osu` to psych_v2 with Scroll-Velocity
  events, quantization, storyboards (`.osb`, sample plus on-hit sounds),
  osu!std to mania conversion, and an osu!mania skin converter.
- *BETA*: **Android / Mobile**: a full arm64 port with touch controls, the system file
  picker (SAF), public-storage assets, the Game Mode API, adaptive icons,
  safe-area insets, and APK self-update.
- **New UI framework (SmidrUI)**: every editor, converter, and the Options menu
  rebuilt on it, plus opt-in desktop widescreen ("no black bars") scaling.

---

## New

### Note skins

- Three first-class skin types: **Modern/Folder** (individual images plus a
  `.tcfg` config), **Classic** (atlas-based, any name), and **Legacy**
  (mod-compat only).
- **BUGGY, FIX SOON** Per-asset independent coloring with a click-to-edit menu, link-gated element
  coloring, per-keycount overrides, and one-color modes.
- osu!-style fit-to-column-width sizing, configurable sustain-over-notehead
  layering, BPM-aware sustain scaling, high-res assets, and a "Force Selected
  Skin" option.
- **BETA / BUGGY AF**: **UI Skin system**: judgement / combo / countdown folder skins sharing the `.tcfg`
  format, with tween/ease config and custom visual rating tiers.

### Notes and scripting

- Native per-note Lua scripting against the v2 note fields.
- Custom-note skinning API (per-part atlas/image textures, RGB toggle, Lua
  callbacks) and per-note `multAlpha` / `multSpeed` visual overrides.
- Native multikey (1K to 9K) and per-section time-signature denominators.

### Converters and tools

- **Chart Converter**: migrates a mod's legacy / psych_v1 charts to psych_v2 and
  folds `events.json` in, backing up the originals.
- *BETA*: **Script Converter**: detects outdated Lua/HScript and auto-rewrites common
  idioms behind an opt-in button (callback plus note-field renames,
  `isSustainNote` to `isSustain()`), with `unspawnNotes` to `onSpawnNote`
  guidance. Highly adviced against auto rewriting currently, it's buggy and flawed, instead use it for reference.
- *BETA*: In-engine benchmark suites with frame-time and sync logging.

### Menus and miscellaneous

- *BETA*: Options rework on the new UI framework: two-depth category/setting
  navigation, search, a restart-to-apply prompt, and keyboard-focus highlighting.
- Self-updater (desktop and Android),
- Credits menu rework (multi-link entries, mod credit icons), an "Uncap FPS"
  option, native Windows title-bar theming, configurable OpenAL output buffering,
  WEBM video support, hxvlc 2.3.0 with a video precache API, and clang / clang-cl
  build support on Windows.

---

## Bugfixes / Optimizations

### Fixes

- **Sustains**: rewrote the trail geometry (up/down positioning, head / receptor
  / end poke), fixed folder-skin tails stretching, held-hold clip drift and gaps
  over the receptor, tail trimming before the next note, under-mode layering, and
  restored the old non-GH segmented scoring plus the head seam.
- **Chart editor**: Vortex receptor centering under folder skins, the atlas-char
  preview hitbox, a blank stacked-event placeholder on reopen, corrupt `[time,0]`
  event crashes, sustain-keybind stepper sync, the character loop-sing toggle,
  and late note pop-in with skipped hitsounds / vortex flashes (the note list is
  now sorted on load).
- **Notes and characters**: Change Character not singing / left idle on the swap
  step, the character sing-loop animation, the opponent receptor holding
  `confirm` through sustains, non-4K note-splash scaling, and symmetric strumline
  placement with correctly centered middlescroll.
- **Events**: firing on the new chart system, pending events on generate (an
  inverted guard), stacked events staying grouped across save/reload, and
  standalone `events.json` events no longer being dropped.
- **Loading**: multithreaded song-load softlocks (a load watchdog, thread cap,
  and single-task prep).
- **Note skins**: classic receptor and atlas-XML crashes, legacy `NOTE_assets`
  loading, folder plus pixel skin resolution, and a crash selecting current-mod
  skins.
- **osu!**: the hitsound sort coercing SV events to `[time,0]`, storyboard and
  video conversion crashes, and the stage-JSON write path.
- **Miscellaneous**: shaders surviving a failed GL compile (mobile), Credits
  mod-folder icons, the camGame aspect ratio and SmidrUI relayout on window
  resize, path-separator sanitizing, and guards for missing stage-sprite and
  legacy note-row fields.

### Optimizations

- **Conductor** reads native chart sections for timing (with native section
  denominators) instead of walking the legacy structure.
- **Note hot path**: allocation-free column hit resolution on key press, pooled
  RGB shader and splash-data reuse on recycle, a cached receptor scroll-axis
  vector (dropping per-frame trig), and gated `SustainSprite` `updateHitbox` /
  clipRect rebuilds.
- Trimmed per-frame script-callback overhead in PlayState.
- **Paths / assets**: a scoped bulk-scan cache for read-only asset scans and
  atlas reuse instead of re-reading descriptions.
- **Difficulty**: a smarter rating cache that recomputes only when necessary and
  invalidates when provider maths change.
- **ModSecurity**: faster script search and hashing.

---

## Notes for modders and developers

- Existing mods keep working for the most part, some functionality may need adapting: the v2 note runtime is always the running system,
  and a modpack opts into the legacy Lua/HScript surface with
  `compatibilityMode = true` (alias `legacyMode = true`) in its `pack.json`.
- The in-engine Script Converter and Chart Converter help migrate older mods to
  the native paths and the psych_v2 chart format.
- Note skins and UI skins share the `.tcfg` config format and discovery rules.
  See [note-skinning-guidelines.md](note-skinning-guidelines.md) and
  [ui-skinning-guidelines.md](ui-skinning-guidelines.md).
- For the note runtime rewrite, see [note-system-v2.md](note-system-v2.md). For
  the full per-commit technical history, see [FORK_CHANGES.md](FORK_CHANGES.md).
