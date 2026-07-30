# Release Notes: v1.3.1

A follow-up to v1.3.0. It started as a bug-fix pass over what was reported against
1.3.0, and grew a set of features on top: rebuilt Note Skin and Note Colours editors, a
new crash handler, offset calibration, the Freeplay music bar, characters for extra
strumlines, and scripting that reaches outside gameplay.

## General

### Breaking: the base game is now a modpack
Friday Night Funkin's own content left the engine. Weeks 1 to 7 and Weekend 1 ship as
an ordinary pack in `mods/Friday Night Funkin`, and their stages are scripted classes
rather than compiled ones. Disable it and the engine boots with no content at all.

The pack is isolated (no `runsGlobally`), so **a mod that used base-game assets it does
not ship will break** and has to bundle its own copy. What the engine still ships, and
therefore what you can still rely on, is the week 1 stage, `bf`/`gf`/`dad`/`bf-dead`
with their pixel variants, and the pixel UI/dialogue/game-over baseline. See
[base-game-pack.md](base-game-pack.md), which also documents how to write a stage as a
script and the dozen things the interpreter does not do for you.

Also gone with it: the `BASE_GAME_FILES` define, and `TankmenBG.animationNotes` (the
pico-speaker note list now lives only on the character that loaded it, as
`character.animationNotes`).

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
- **Note skin atlas cache**: a skin whose cached atlas outlived its bitmap could null-ref
  when reused, crashing anything that rebuilt receptors -- most visibly the Note Colours
  editor with a widescreen mod skin. GPU caching disposes a persisted graphic's CPU bitmap
  after upload, leaving the cached atlas pointing at nothing; the skin cache now detects a
  dead atlas and rebuilds it (falling back to a unique graphic), which fixes the crash for
  gameplay too.
- **Extra strumlines**: a third (or fourth, ...) strumline no longer renders invisibly when
  **Opponent Notes** is off. The receptor builder was told only whether a line was the
  player's, so it treated *everything* that wasn't as the opponent and applied that option's
  hide to extra lines too. Extra lines are their own role now and keep their own visibility,
  which is what the chart editor's **Render arrows in gameplay** toggle always implied.
- **Multikey strumlines**: a line with its own key count is laid out at that count instead of
  the song's. Column width and spacing came from a single global describing whichever key
  count was applied last, so on a chart mixing key counts every line but one was spaced
  wrong. Note splashes had the same bug and were sized from the same global.
- **Lua errors are no longer hidden**: a runtime error in a Lua script only reached the
  screen if that script had set `luaDebugMode`, and never reached the log file at all --
  and `FunkinLua.call` swallowed exceptions into a bare `trace`, so a failure could vanish
  from the in-game console entirely. Script failures now always report, to the console, the
  log and the on-screen overlay. Ordinary debug output keeps the `luaDebugMode` gate.
- **HScript hooks are no longer starved by Lua**: `callOnScripts` ran the Lua pass and only
  ran the HScript pass if Lua had returned nothing meaningful, so a single Lua script
  returning a value meant no HScript in that mod ever saw the event -- silently. Both
  languages now always run. See the dispatch notes below for the stop-value rules.
- **The script error overlay works everywhere**: it assumed `PlayState`, so an error in a
  menu had nowhere to go.

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
- **Offset calibration overhaul**: the old single-slider Note/Beat Delay screen is replaced by a
  two-tab calibration menu, built on SmidrUI over a framed preview viewport. **Audio Offset** still
  shifts note timing for judgement, and a new **Visual Offset** shifts only where notes appear relative
  to the receptors -- no effect on scoring -- so display lag can be corrected independently of audio
  sync. Each offset can be set three ways: the manual slider / arrow keys, a guided **Start Calibration**
  run, or (audio only) a **Detect Hardware** button that estimates the output latency from the active
  audio-buffer configuration.
  - **Audio calibration** plays a metronome beep with no visual aid and asks you to tap along.
  - **Visual calibration** drops a single note lane -- real note art landing on a real receptor with its
    confirm animation -- that you press as each note lands.
  - Either guided run is free tapping: sixteen presses are averaged into the offset, and the run always
    starts from a zeroed value so you calibrate from scratch.
  - **Modders**: `visualOffset` is a new `ClientPrefs` field, exposed to Lua as `visualOffset` (render
    only; it does not affect hit windows, scoring or replays).
- **Rewritten Note Colours editor**: the flixel colour menu was rebuilt on SmidrUI while keeping the
  live flixel preview. A left control panel -- keycount / element / channel (Main/Border/Shadow)
  selectors, an HSV colour picker with presets, copy/paste hex, and per-channel/per-lane reset --
  sits beside the right-hand preview: the lane strip and the note / hold / splash / static / pressed /
  confirm cells, all real gameplay sprites that recolour live as you edit. Clicking a lane on the strip
  retargets the whole preview to that column.
  - A new **Reset All Colours** dialog restores every colour to default, scoped to either the current
    keycount or all keycounts.
  - **One Colour for All** now actually takes effect from the editor (it edits the single shared
    colour instead of being ignored).
  - The editor degrades gracefully instead of crashing on a malformed mod skin -- the colour tools
    keep working even if a skin's preview fails to build.
- **Extra strumlines get their own characters**: a chart could always declare more strumlines,
  but an extra one could only reuse boyfriend, dad or gf -- there was nowhere for a fourth
  character to stand, so naming one got you nothing. Stages now declare **named positions**,
  and a strumline says which one its character uses.
  - A position is a `character` entry in the stage's `objects` list:
    `{ "type": "character", "name": "dj_booth", "x": 2750, "y": 1610 }`. It lives in `objects`
    on purpose -- that list is the **layer order**, so an extra character can sit behind or in
    front of stage pieces like anything else. Positions are written by hand for now; the stage
    editor round-trips them safely but has no UI to place one yet.
  - The chart editor's strumline panel gains a **Stage position** dropdown (the three built-ins
    plus whatever the song's stage declares) and **Offset X / Y** for a per-chart nudge.
  - `opponent`, `player` and `spectator` are ordinary named positions every stage has, so a
    line can deliberately borrow one. A line that doesn't pick one falls back to its role, so
    **every existing chart behaves exactly as before**.
  - The character sings that line's notes and the camera targets it, with no extra setup: a
    strumline already drove its character, there was just never a way to give it one.
  - Full guide: [docs/strumline-characters.md](strumline-characters.md).
- **Strumlines fit the screen**: lines now share the width in proportion to how much room each
  one actually needs, and when they can't all fit at natural size everything scales down
  together -- receptors, notes, hold trails and splashes -- so a crowded chart reads as a
  smaller strumline rather than a broken one. Anything that already fits is untouched, so
  existing songs are unchanged (the classic two-line split is still 25% / 75%). Under
  middlescroll the non-player lines spread out instead of stacking on the same spot.
- **Scripts can run in menus**: a new `scripts/global/` folder loads in **every state**, not
  just gameplay. Previously the only way to touch a menu was to script the whole state.
  `scripts/` is unchanged and stays gameplay-only. Global scripts get
  `onCreate`/`onDestroy`/`onUpdate`/`onUpdatePost`/`onBeatHit`/`onStepHit` plus a new
  `onStateChange(name)`, and in gameplay they additionally get every normal PlayState hook.
- **Scripted classes without scripted states**: a plain modpack -- nothing but songs -- can
  now keep a class library in `scripts/classes/` and reach it from the scripts it already has
  with `buildScripted(path)` / `scriptedClass(path)`, in Lua or HScript. Each mod gets its own
  class world, so two mods shipping the same type never collide. See
  [docs/scripted-classes.md](scripted-classes.md).
- **A script can choose where a song exits to**: `setExitTarget(name)` and `exitToState(name)`
  send the player to a built-in menu or one of the mod's own scripted states when the song
  ends or they back out, instead of the default Freeplay/Story menus. Works in a plain
  modpack, not only a launched one.

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
  gameplay lane Hitbox is a separate overlay (now customizable -- see below).
- **Freeplay**: tapping the on-screen navigation pad no longer also click-selects
  the song row underneath it -- taps that land on a pad button are ignored by the
  list.
- **Chart editor**: the mobile editor's Events picker now lists custom mod events
  (`custom_events/*.txt`), not just the built-in ones.
- **Mods**: a mod's custom fonts now load. Mods live on external storage, which
  OpenFL can't load a font from by path on mobile, so a mod's `fonts/*.ttf`
  silently fell back to the default font ("not recognized"). Mod fonts are now
  registered from their bytes (the same way mod images/sounds already load).
- **Mobile settings tab**: the mobile-only options (control opacity, vibration, Pause
  button) moved out of their standalone substate into a proper **Mobile** category in the
  SmidrUI Options menu, alongside the new Hitbox settings below.
- **Customizable gameplay Hitbox**: the on-screen note lanes are now configurable --
  **style** (solid fill or outline), **width** / **height** / vertical **position** as
  fractions of the screen, per-lane **overlap** (how far a lane's touch area reaches into
  its neighbours), and resting / held **opacity**. **Lane colours** default to the note
  colour each lane plays (following the active skin and any colour overrides) or can be set
  per-lane in a dedicated colour editor.
- **Freeplay**: the music player no longer sits underneath the on-screen A/B
  buttons. The right column (song info panel plus the player bar) now stops above
  the pad on touch builds instead of ending at the screen edge.
- **Keyboard hints hidden**: the shortcut lines at the bottom of Freeplay and
  Options listed keys a phone doesn't have. They are desktop-only now, and Options
  gives the reclaimed space back to its panels.
- **Options**: the category rail scrolls. Mobile adds a **Mobile** category and
  uses taller, finger-sized rows, which pushed the last button out through the
  bottom of the rail panel; the rail is a scroll pane now and keyboard/controller
  selection scrolls itself into view.
- **Options**: changing **Audio Buffer** now says it needs a restart on Android
  too. Desktop already offered to relaunch on the way out; mobile applied the
  preference at startup but told you nothing, so the setting looked like it did
  nothing. The prompt can't relaunch an Android app, so it offers to close the
  game for a manual restart.
- **Misc**: the mouse-only Legacy Chart Editor is hidden on mobile (it has no
  touch controls);

### Touch editors

- **Touch-controls guide**: the "? GUIDE" modal fits its text. Every line is split
  into a gesture column and a description column, both word-wrapped, inside a
  scrollable panel sized to the safe area, instead of running off the right edge
  and past the bottom of the screen.
- **Unsaved changes are confirmed**: leaving any touch editor (rail EXIT or the
  Android back button) with unsaved edits now asks first -- **Save & Exit** /
  **Discard & Exit** / **Keep Editing** -- and so does anything that replaces the
  open document (New / Open, and switching menu-character slot). Save & Exit waits
  for the file picker to actually finish, so cancelling it keeps your work.
- **Action bar**: with many actions the floating bottom bar ran under the right
  thumb rail, leaving its last button (PLAY / CONFIRM / REMOVE) unreachable. Its
  buttons now shrink to fit between the rails.
- **Nudge buttons**: the offset arrows moved the character the wrong way in the
  Menu Character and Dialogue Portrait editors (the arrays they edit are draw
  offsets, which are subtracted, so the signs were reversed relative to the desktop
  editors' arrow keys). Dragging on the canvas in those two also did nothing at
  all: the handler read the gesture's absolute position as its frame delta and
  never claimed the press as a drag, so it was routed away as a camera pan.
- **Chart editor**: the rail's SAVE button became a **FILE** page (save, save-as,
  open, new, with the saved/unsaved state at the top), the strumlines page dropped
  its `-----` separator rows for plain spacing, and exiting with unsaved edits asks
  before leaving.
- **Week editor**: the longer field captions ("Week Before (unlocks after):") ran
  into their input boxes on the narrow drawer. Fields are stacked now, caption line
  above a full-width box. The preview also shows the week's **background art**
  (`menubackgrounds/menu_<name>`, the same lookup the Story Menu uses), fitted into
  the banner and updating as you type the asset name.
- **Character editor**: the animation list no longer keeps a stale purple highlight
  on whichever row was current when the page opened. Picking a row does not rebuild
  the page, and the rail button plus status strip already name the animation that is
  playing. Picking one now also **loads it into the fields** above the list (name,
  symbol/prefix, framerate, indices, looped), which used to keep showing whichever
  animation was current when the page opened -- so Add / Update silently edited the
  wrong animation.
- **Menu Character editor**: the slot button now edits **that slot's** character
  (loading `dad` / `bf` / `gf` from `images/menucharacters/`) and puts the other
  slots back to their stock look. It used to paste the file you were editing onto
  every slot you visited, so all three turned into the same character.
- **Dialogue editor**: the Character field actually reloads the portrait json now
  (it only re-applied the old one, so a retyped name did nothing until you changed
  line), the status strip names the animation the portrait is really playing
  (unnamed playback picks a *random* animation, so the strip could name a different
  one), and the line's **Text** is a multiline wrapping box at the bottom of the
  drawer instead of a single-line field.
- **Dialogue Portrait editor**: no longer crashes on entry. Loading the portrait ran
  all the way down to the status strip before the editor chrome existed, which
  null-referenced and killed the state immediately.
- **Dialogue Portrait editor**: the red/blue offset ghosts were drawn permanently,
  three portraits stacked on top of each other with no way to turn them off. They are
  now an opt-in overlay on a **GHOSTS** rail page (per-ghost toggles and an opacity
  slider, like the character editor's ghost), off by default. The portrait itself now
  carries the offsets you are editing and plays the pose the mode selects, so nudging
  and dragging move the real thing instead of only a ghost.

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

### Chart and stage format
Both additions are optional and written only when set, so a chart or stage that never uses
them saves byte-for-byte identical to before.

- **Stage `objects`** accepts `{"type": "character", "name": ..., "x": ..., "y": ...}` (plus
  the usual `scrollFactor`), declaring a named position a strumline's character can stand on.
  Its slot in the list is its layer. `opponent`, `player`, `spectator`, `dad`, `gf` and
  `boyfriend` are reserved names.
- **`strumlines[]`** accepts `anchor` (a position name) and `offset` (`[dx, dy]` on top of it).
  Absent means "derive from the line's role", which is what every existing chart does.

### Script dispatch
Behaviour changes here can affect existing scripts. The starvation fix in particular means
HScript hooks that previously never ran now do. Full reference:
[docs/script-hooks-and-dispatch.md](script-hooks-and-dispatch.md).

- **Both languages always run.** Stopping is per language: `Function_StopLua` ends the Lua
  pass, `Function_StopHScript` the HScript pass, `Function_StopAll` both. `Function_Stop`
  keeps its own meaning -- it cancels the engine's action and skips the other language, but
  does **not** stop the rest of its own, so a script cancelling a note hit can't hide that hit
  from a sibling script that only counts it.
- **Consistent hook names**: the eight hooks that predate the `onX` convention (`goodNoteHit`,
  `noteMiss`, `preUpdateScore`, ...) still work and always will -- they're the names the engine
  dispatches. Each now also accepts the consistent spelling (`onGoodNoteHit`, `onNoteMiss`,
  `onUpdateScorePre`, ...), bound when your script loads. Declare either.
- **Faster dispatch**: a script no longer pays for hooks it doesn't declare (Lua globals are
  looked up once and cached, not on every dispatch), hook returns are classified once instead
  of string-compared per script, and calling an HScript hook no longer allocates.
- **Map access is uniform**: `getProperty('someMap.key')` reads and writes map entries without
  `allowMaps`, matching what direct proxy access already did. The parameter is still accepted
  everywhere, so no call site changes; it just isn't needed. A map entry can no longer shadow
  a map's own `get`/`set`/`keys`, which is the reason the two APIs disagreed. `game.someVar`
  through the proxy also picks up script variables now instead of silently reading `nil`.
- **Blocked packages**: resolving a class by name (`import()`, `createInstance`,
  `getPropertyFromClass`, `callMethodFromClass`, `addHaxeLibrary`) now rejects the `sys`,
  `cpp`, `neko`, `java` and `llua` packages outright, not just individually blocklisted
  classes -- the process, the filesystem, native handles, and the raw Lua state behind your
  own interpreter. Everything else the engine compiles stays reachable. HScript's `import`
  is gated the same way.
- **The mod source scan is a trust prompt, not a sandbox.** It reads source text, so a name
  built at runtime walks straight past it; it exists so a mod that obviously wants your
  filesystem has to say so first, and so a mod changing after you trusted it asks again. The
  boundary that actually holds is the binding layer above. This was previously documented as
  "the primary gate", which overstated it.

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
- **A throwing property getter surfaces its error** instead of being swallowed to `nil`. Reading a
  field that doesn't exist still returns `nil` as before -- this only affects a getter that actually
  raises, which used to fail invisibly and reappear as an unrelated `nil` later.
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
