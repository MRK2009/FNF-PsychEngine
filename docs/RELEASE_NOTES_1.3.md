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
