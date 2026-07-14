# Making Note Skins: Setup & Configuration

The complete, no-shortcuts authoring reference for the two skin kinds you build for the modern
runtime:

- **Folder skins** (Part A): individual images plus a `skin.tcfg`. The recommended, most flexible
  format. Every configurable value and all animation behavior is documented here.
- **Classic skins** (Part B): a sparrow atlas (`.png` + `.xml`), optionally with a config to tune it.

Part C is a one-glance field reference; Part D is a folder-vs-classic decision cheatsheet.

The third kind, **legacy** skins, is not something you author: it's just a classic atlas rendered by
the old code for `compatibilityMode` modpacks. For architecture (how a skin is discovered and picked
at runtime, and how the three kinds relate), read [note-skin-system.md](note-skin-system.md).

---

## Contents

- [Part A: Folder Note Skins](#part-a-folder-note-skins)
  - [A.1 Create the skin folder](#a1-create-the-skin-folder)
  - [A.2 Required and optional elements](#a2-required-and-optional-elements)
  - [A.3 Canvas and sprite sizes](#a3-canvas-and-sprite-sizes)
  - [A.4 How the engine scales your art](#a4-how-the-engine-scales-your-art)
  - [A.5 Pivots and centering](#a5-pivots-and-centering)
  - [A.6 File naming: single image or sequence](#a6-file-naming-single-image-or-sequence)
  - [A.7 The skin.tcfg format](#a7-the-skintcfg-format)
  - [A.8 Targeting lanes and columns](#a8-targeting-lanes-and-columns)
  - [A.9 The images group](#a9-the-images-group)
  - [A.10 The general group](#a10-the-general-group)
  - [A.11 The animated group](#a11-the-animated-group)
  - [A.12 The colorable group and recoloring](#a12-the-colorable-group-and-recoloring)
  - [A.13 The offsets group](#a13-the-offsets-group)
  - [A.14 Animation support in depth](#a14-animation-support-in-depth)
  - [A.15 Splashes](#a15-splashes)
  - [A.16 HD @2x assets](#a16-hd-2x-assets)
  - [A.17 Pixel-art variants](#a17-pixel-art-variants)
  - [A.18 Per-keycount sections](#a18-per-keycount-sections)
  - [A.19 Select and test your skin](#a19-select-and-test-your-skin)
- [Part B: Classic Note Skins](#part-b-classic-note-skins)
  - [B.1 When to make a classic skin](#b1-when-to-make-a-classic-skin)
  - [B.2 The atlas and frame prefixes](#b2-the-atlas-and-frame-prefixes)
  - [B.3 Where a classic sheet can live](#b3-where-a-classic-sheet-can-live)
  - [B.4 Listing a classic skin in Options](#b4-listing-a-classic-skin-in-options)
  - [B.5 The optional tuning config](#b5-the-optional-tuning-config)
  - [B.6 Pixel classic skins](#b6-pixel-classic-skins)
  - [B.7 Per-note texture overrides](#b7-per-note-texture-overrides)
  - [B.8 Classic animation](#b8-classic-animation)
- [Part C: Full field reference](#part-c-full-field-reference)
- [Part D: Folder vs classic cheatsheet](#part-d-folder-vs-classic-cheatsheet)

---

## Part A: Folder Note Skins

A folder skin is a directory of **individual PNGs** plus one `skin.tcfg` (or `skin.json`) describing
how to assemble them. It is rendered by `backend.noteskin.FolderNoteSkin`.

### A.1 Create the skin folder

Base game:

```
assets/shared/images/noteSkins/<YourSkin>/
```

In a mod (recommended for distribution):

```
mods/<YourMod>/images/noteSkins/<YourSkin>/
```

The folder name **is** the skin's display name. It can live in **any** enabled mod: the engine scans
the base game first, then the current, global, and enabled mods, and pins asset resolution to whichever
source owns the skin (so its own images always resolve from the right place). Full discovery order is
in [note-skin-system.md](note-skin-system.md#23-where-skins-are-found-search-roots).

### A.2 Required and optional elements

A folder skin can define seven elements. Four are **required** for a self-contained skin, three are
**optional** and degrade gracefully:

| Element | Required? | If omitted |
|---|---|---|
| Note head (`notes`) | Required | Falls back to the classic renderer (see below). |
| Receptor (`strums`) | Required | Falls back to the classic renderer. |
| Sustain body (`holdBody`) | Required (with tail) | Whole sustain falls back to the classic renderer. |
| Sustain tail (`holdEnd`) | Required (with body) | Whole sustain falls back to the classic renderer. |
| Receptor pressed (`pressed`) | Optional | Reuses the receptor's own `strums` (static) frames. |
| Receptor confirm (`confirm`) | Optional | Reuses `pressed` (which itself falls back to `strums`). |
| Note splash (`splash`) | Optional | Uses the engine's built-in splash (or a `noteSplashes/` atlas). |

**Why the four are required, and why the fallback isn't a safety net.** Any element a folder skin
can't resolve falls back to `ClassicNoteSkin`, but that fallback only produces art when a **classic
sparrow atlas is actually present** (a chart `arrowSkin`, a mod that ships `noteSkins/NOTE_assets.png`,
or, on a pixel stage, the `pixelUI/` sheets). **The base game ships no loose `noteSkins/NOTE_assets`
sheet on a normal stage.** So a skin that omits `holdBody`/`holdEnd` has nothing to fall back to and
its sustains render **blank**. Note that `holdBody` and `holdEnd` are required **together**:
`FolderNoteSkin.applySustain` needs both keys, and if either is null the entire sustain (body and tail)
drops to the classic fallback.

`pressed`, `confirm`, and `splash` are the genuinely optional ones because their fallbacks never need a
classic atlas: `pressed`/`confirm` reuse the skin's own static frames, and `splash` has an engine
default.

Minimal self-contained skin:

```
noteArrow.png
strumArrow.png
holdBody.png
holdEnd.png
skin.tcfg
```

```
images:
    notes:
        arrow: noteArrow
    strums:
        arrow: strumArrow
    holdBody: holdBody
    holdEnd: holdEnd

general:
    scale: 0.7
```

Add `pressed`, `confirm`, and `splash` for a polished skin. Everything else in Part A is refinement on
top of this.

### A.3 Canvas and sprite sizes

All sizes are in the **1x reference frame: one lane cell = 160x160 pixels**. Author your art as if the
engine drew a lane 160 px wide with no scaling. That's the frame every bundled skin (and the classic
pre-folder assets) uses. The engine shrinks everything per key count at render time; you never account
for that, you keep `scale: 0.7` (the default) and it lines up. Section A.4 explains the math.

"Canvas" is the full image size; "sprite" is the drawn art inside it. Leave a few pixels of breathing
room rather than running art edge to edge.

| Element | Canvas (max) | Sprite (recommended) | Notes |
|---|---|---|---|
| Strum / receptor | 160x160 | ~156 px wide | The static receptor at the top of the lane. |
| Note head | 160x160 | matches the strum | The falling note. |
| Pressed | 160x160 | ~152 px, slightly smaller than the strum | 1-3 frames; plays while a key is held with no note under it. |
| Confirm | 256x256 | varies (glow/burst) | 1-3 frames; starts a bit bigger than the strum and settles to strum size on the last frame. |
| Hold body | 160 px wide | 50-146 px wide, any height | Stretched vertically by the engine, so height matches nothing. |
| Hold end (tail) | same as body | same as body | Required alongside the body (see A.2). |
| Note splash | independent of note size | your call | Has its own `splashScale` (A.15). |

The bundled Default skin's real files (trimmed to content, hence a touch under canvas):
`noteArrow.png`/`strumArrow.png` 157x154, `pressArrow1.png` 152x148, `confirmArrow1.png` 256x256,
`holdBody.png` 50x20, `holdEnd.png` 50x22.

### A.4 How the engine scales your art

Two numbers multiply, calibrated so the 160 px frame "just works":

- **Lane spacing** is `160 x` a per-keycount factor (`Mania.noteSizes`):
  1K `0.9`, 2K `0.85`, 3K `0.8`, **4K `0.7`**, 5K `0.66`, 6K `0.6`, 7K `0.5`, 8K `0.42`, 9K `0.36`.
  So a 4K lane is 112 px wide on screen, a 9K lane ~58 px.
- **Your art's scale** is `skin.tcfg`'s `scale` times that keycount factor **relative to 4K**
  (`scale x noteSizes[kc-1] / noteSizes[4K-1]`). With the default `scale: 0.7`, art authored at 160 px
  renders at exactly 112 px in 4K (filling the lane) and shrinks in step with the lanes on higher key
  counts automatically.

So with `scale: 0.7`, **on-screen size = your authored size x the keycount factor**. Draw once at 1x
and every key count comes out right. To author at a different canvas (say 320 px), compensate in
`scale` so `canvas x scale = 112` at 4K (320 x 0.35). Keep `scale` (and `pixelScale`) one number per
element at most, never per-frame: you can't mix pre-scaled and un-scaled frames within one element.

The alternative sizing model, `fitColumnWidth`, ignores native pixels entirely and fits each element to
the lane column; see its row in A.10.

### A.5 Pivots and centering

If you draw a skin as a symbol animation (Adobe Animate, or anything exporting a Sparrow/Starling
atlas) rather than hand-placed PNGs, keep every frame of one element on the **same pivot** or the
sprite drifts as it plays.

| Frame | Trimmed size | Pivot | Reading |
|---|---|---|---|
| `noteArrow0000` | 157x157 | (78.5, 78.5) | Dead center; notes/strums are single, unanimated frames. |
| `strumArrow0000` | 157x157 | (78.5, 78.5) | Same canvas and pivot as the note, so scale/rotation line up. |
| `pressArrow0000..0003` | 157x157 | (78.5, 78.5) | Same size/pivot across all frames; nothing shifts as it plays. |
| `confirmArrow0000..0003` | 222x222 in a 228x228 canvas | (112.55, 112.55) | Bigger canvas (the "grows in, settles" burst), still centered frame to frame. |
| `holdBody0000` | 50x20 | (0, 0) | Sustains pivot **top-left**; the engine stretches this along the lane, it never rotates in place. |
| `holdEnd0000` | 50x22 | (0, 0) | Same top-left pivot as the body. |

Pick one canvas size per element, center every animated frame of that element identically (top-left for
hold body/tail, dead-center for everything that rotates), and only change canvas size *between*
elements, never *within* one element's frame sequence.

### A.6 File naming: single image or sequence

Every image reference in `skin.tcfg` (e.g. `noteArrow`) is a **key**, not a literal filename. The
resolver (`NoteSkinConfig.frameKeys`) turns a key into files in this order:

1. **Single image:** `<key>.png` (or `<key>@2x.png`). One frame.
2. **Numbered sequence:** `<key><sep><N>.png`, where:
   - `<sep>` is empty, `-`, or `_`;
   - `<N>` is zero-padded to **1, 2, 3, or 4 digits**;
   - the run starts at index **0 or 1**.
   The engine probes every combination (`4,3,2,1` digit padding x `0,1` start x the three separators)
   and uses whichever contiguous run of files exists: `confirmArrow1.png,confirmArrow2.png,...`,
   `splash0001.png,splash0002.png,...`, `note_0.png,note_1.png,...`, and so on.

You never declare which case applies: name your files consistently and point `skin.tcfg` at the shared
prefix. Whether a resolved sequence actually **plays** as an animation (vs. holding frame 1) is a
separate decision made by the `animated` group (A.11).

A missing file resolves to "no frames," not an error, and triggers the classic fallback (A.2). If an
element silently doesn't appear, re-check the exact filename against these rules (case-sensitivity, the
separator, the padding, the start index) before assuming the config is wrong.

### A.7 The skin.tcfg format

`.tcfg` ("tabbed config") is the primary format; a plain `skin.json` with the same field names (matching
the internal shape 1:1) is a fallback, checked second. Rules:

- Indentation defines nesting. Use tabs **or** spaces, but don't mix them within one block.
- `key: value` on a line is a leaf (a setting). `key:` with indented lines beneath it is a group.
- Lines starting with `#` (or `###`) are comments; blank lines are ignored.
- Values: `true`/`false` become booleans, `[a, b]` becomes an array, plain numbers become Int/Float,
  anything else is a string. Quoting a string value (`'...'` or `"..."`) is optional; keys are never
  quoted.

The five groups are **`images`**, **`general`**, **`animated`**, **`colorable`**, **`offsets`**, plus
optional per-keycount **`<N>K:`** sections. The `.tcfg` parser remaps some names to internal fields as
it reads (documented per group below):

| In `.tcfg` | Internal / `skin.json` field |
|---|---|
| `holdBody` (under `images`/`animated`/`colorable`) | `holds` |
| `holdEnd` (under `images`/`animated`/`colorable`) | `ends` |
| `center` (a target key) | `square` |
| `col<N>` (a target key, 1-indexed) | `"<N-1>"` (0-indexed) |
| `hi-res` (under `general`) | `hiRes` |
| `offsets.notes` / `.strums` / `.holdBody` / `.holdEnd` / `.splash` | `noteOffsets` / `strumOffsets` / `holdOffsets` / `endOffsets` / `splashOffsets` |

Two working references ship with the engine and are the best starting point:
[Default/skin.tcfg](../assets/shared/images/noteSkins/Default/skin.tcfg) (a real skin) and
[Default/skin.example.tcfg](../assets/shared/images/noteSkins/Default/skin.example.tcfg) (every field,
commented, with a key-count section). `skin.json` examples: the bundled `Chip` and `Future` skins.

### A.8 Targeting lanes and columns

Almost every image and setting can be a single value (applies to every lane) or a **per-lane
breakdown**. When per-lane, indent target keys underneath. A lane is matched in this priority order:

| Target key | Meaning | Priority |
|---|---|---|
| `col<N>` | One specific column, **1-indexed** (`col1` = first lane). | Highest (wins ties). |
| direction name (`left`/`down`/`up`/`right`) | Every lane facing that way. | Middle. |
| `center` | The middle lane on an odd key count (internally `square`). | For the center lane only. |
| `arrow` | Every cardinal lane not otherwise specified. | Lowest (catch-all). |

`col<N>` keys win, which is how you disambiguate lanes that share a direction name in multikey. A bare,
non-indented value (`arrow: noteArrow`) applies to every lane.

A column's direction name comes from the chart's key count (`Mania.noteAnimations`):

| Keys | Lane directions (col1 -> colN) |
|---|---|
| 1K | square |
| 2K | left, right |
| 3K | left, square, right |
| 4K | left, down, up, right |
| 5K | left, down, square, up, right |
| 6K | left, up, right, left, down, right |
| 7K | left, up, right, square, left, down, right |
| 8K | left, down, up, right, left, down, up, right |
| 9K | left, down, up, right, square, left, down, up, right |

("square" is the engine's internal name for a center lane; it's what `center` targets.) Because several
key counts repeat a direction name (6K has two "left" lanes), use `col<N>` when two same-named lanes
need different art or rotation.

### A.9 The images group

Declares the image key for each element. `notes`, `strums`, `pressed`, `confirm` take
`arrow`/`center`/`col<N>` targets; `holdBody`, `holdEnd`, `splash` are flat keys.

```
images:
    notes:
        arrow: noteArrow      # cardinal lanes
        center: noteCenter    # odd-keycount center lane
    strums:
        arrow: strumArrow
        center: strumCenter
    pressed:
        arrow: pressArrow
        center: pressCenter
    confirm:
        arrow: confirmArrow
    holdBody: holdBody
    holdEnd: holdEnd
    splash: splash
```

Per the fallback rules in A.2: omit `pressed`/`confirm`/`splash` freely; keep `notes`, `strums`,
`holdBody`, `holdEnd`.

You can also point an element at a **per-column list** by giving an array, or an object keyed by column
index / direction / `arrow` / `center`. Column-index and array entries are treated as pre-oriented
(rotation angle 0) unless you also supply `columnAngles`; see A.10 (`rotate`) and A.14 (rotation).

### A.10 The general group

Flat settings (no per-element sub-groups), though many individual fields accept a per-lane object via
`arrow`/`center`/`col<N>` where the "Per-lane" column says yes.

| Field | Type | Per-lane | Default | Applies to | Meaning |
|---|---|---|---|---|---|
| `rotate` | Bool | no | `true` | folder | Whether cardinal-lane art is auto-rotated per `directionAngles`. Set `false` if your art is already drawn facing each direction. |
| `directionAngles` | `[left, down, up, right]` | no | `[-90, 180, 0, 90]` | folder | Rotation (degrees) baked into the base art per cardinal direction. Center/`square` lanes are never rotated. |
| `columnAngles` | array by column | per column | unset | folder | Per-column angle override, beats `directionAngles`. Use it when two lanes share a direction name (e.g. both "left" lanes in 6K) but must face differently. Also lets array/column-index images rotate. |
| `fps` | Int | yes | `24` | folder + classic | Animation playback rate for this skin's sequences. Per-lane lets each lane animate at its own speed. |
| `scale` | Float | yes | `0.7` | folder | Note/strum/hold size multiplier (times the keycount factor; see A.4). |
| `pixelScale` | Float | yes | falls back to `scale` | folder | Size multiplier used **instead of** `scale` while rendering as pixel art (low-res art usually wants a bigger zoom). Only consulted in pixel mode. |
| `fitColumnWidth` | Bool or Float | no | unset (off) | folder | osu!mania sizing: scale each element uniformly so its unscaled frame width fills the lane column (`160 x noteSizes[kc]`) instead of scaling native pixels. `true` fills the whole column; a number is a fraction (`0.9` leaves a gap). Overrides `scale`/`pixelScale` when set, and decouples receptor size from note size. |
| `antialiasing` | Bool | yes | the player's **Antialiasing** option | folder + classic | Smoothing for non-pixel art. Forced **off** whenever the skin renders as pixel art, regardless of this value. |
| `holdAntialiasing` | Bool | no | falls back to `antialiasing` | folder + legacy | Smoothing for the hold **body and tail** specifically. When set, it overrides `antialiasing` for the sustain. |
| `holdAlpha` | Float | yes | see note | legacy + editor preview | Opacity of the hold body while missed/released. **Not applied by the modern gameplay sustain**, which uses a fixed `0.6` (a script can override it per note via `note.multAlpha`). Honored by the `compatibilityMode` renderer (default `0.6` there) and the Note Skin Editor preview. Kept for compatibility and forward use. |
| `holdsOverHeads` | Bool | no | the global **Sustains Over Notes** option | folder | Draw hold trails **above** the note heads instead of below. Overrides the global option for this skin. |
| `headOverlap` | Float | no | engine default (`0`) | folder | How far an **un-held** hold's head-side edge tucks past the note centre under the head, as a fraction of the note width. Closes the head/body seam. Keep it below the head's scaled half-width or the trail pokes past a shrunk head. |
| `pixel` | Bool | no | `false` | folder | Force this skin to **always** render as pixel art (antialiasing off, pixel proportions), on any stage. |
| `pixelVariant` | Bool | no | `false` | folder | Render as pixel art **only on a pixel stage**, and make this skin eligible for the pixel-stage auto-swap (A.17). |
| `splashScale` | Float | no | `1` | folder | Note-splash size multiplier (A.15). |
| `splashFps` | Int or `[min, max]` | no | `[22, 26]` | folder | Splash animation rate; a `[min, max]` range picks a random rate per splash (matching vanilla's variation). |
| `hi-res` / `hiRes` | Bool | no | auto | folder | Documentation hint that the skin ships `@2x` assets. `@2x` files are detected per-file regardless; this flag changes nothing at runtime. |
| `sheet` | String | no | unset | **classic only** | Names the atlas file inside a classic skin folder (Part B). Ignored by folder skins. |

Notes on the corrected defaults above:

- **`antialiasing`** does not default to `true`; it defaults to the player's global Antialiasing
  setting. Set it explicitly only to override the player per element/lane.
- **`holdAlpha`** is the one field whose bundled-skin value (the Default skin ships `0.5`) does not
  reach modern gameplay: the v2 sustain dims to a fixed `0.6`. Treat it as legacy/editor-only for now.
- **`holdsOverHeads`** and **`headOverlap`** are the layout knobs that the v2 sustain genuinely reads;
  `holdAntialiasing` too.

### A.11 The animated group

Per-element booleans deciding whether a resolved multi-frame sequence **plays** or shows only its first
frame. Elements: `notes`, `strums`, `pressed`, `confirm`, `holdBody`, `holdEnd`.

- **Whole group omitted** -> every element animates (default `true`). Single-frame elements are
  unaffected either way.
- **Element set to `false`** -> a multi-frame sequence for that element resolves but only frame 1 is
  shown (`NoteSkinConfig.staticFrame`).
- **Element set to `true`** (or absent while the group exists) -> it animates.

The common vanilla-like setup is **static notes and receptors, animated pressed and confirm**:

```
animated:
    notes: false
    strums: false
    pressed: true
    confirm: true
    holdBody: false
    holdEnd: false
```

This group is folder-only. Classic skins always play their atlas prefixes (Part B). See A.14 for how
these flags interact with fps, looping, and the per-element animation names.

### A.12 The colorable group and recoloring

Note art is normally shipped as white/greyscale line art and **tinted per-lane at runtime** by an RGB
palette shader (not a texture swap). `colorable` controls this per element:
`notes`, `strums`, `pressed`, `confirm`, `holdBody`, `holdEnd`, `splash`.

**The defaults are subtle, so read carefully:**

- **Whole `colorable` group omitted** -> **nothing is colorable** (every element renders with its own
  fixed colors; the shader never touches it). If you want recoloring, you must include the group.
- **`colorable: true`** as a bare boolean -> every element colorable **except `strums`** (receptors
  stay their own color).
- **Group present, an element absent** -> that element is colorable (except `strums`, which is
  `false`).
- **Element set explicitly** -> that value.

So `strums` is always the exception: it is only ever colorable if you set `strums: true` explicitly.

**Two gates decide whether an element is actually tinted with the note color in a real game**
(`NoteSkinConfig.linkedColorable`):

1. The skin allows it (`colorable.<element>: true`, per the rules above).
2. The player has the matching **"Link ... to note color"** option on: `linkSplashColor`,
   `linkSustainColor` (covers `holdBody`/`holdEnd`), `linkPressedColor`, `linkConfirmColor`,
   `linkStrumColor`.

When an element is colorable but **not linked**, it uses its **independent per-asset color** from the
in-game Note Colors menu instead (`Mania.getAssetColors`, per-keycount-aware). That menu is a player
preference, not a skin field. If your art is already fully colored, set that element's `colorable` to
`false` so the shader leaves it alone.

```
colorable:
    notes: true
    strums: false
    pressed: true
    confirm: true
    holdBody: true
    holdEnd: true
    splash: true
```

### A.13 The offsets group

Per-element `[x, y]` pixel nudges, applied on top of the automatic lane centering. Each element accepts
either one `[x, y]` pair for every lane, or a per-lane breakdown (an object of `arrow`/`center`/`col<N>`
each holding an `[x, y]`, or an array of `[x, y]` pairs indexed by column).

| `offsets` key | Internal field | Applies to |
|---|---|---|
| `notes` | `noteOffsets` | note head |
| `strums` | `strumOffsets` | receptor (all states) |
| `holdBody` | `holdOffsets` | the whole sustain (body + tail) in the folder renderer |
| `holdEnd` | `endOffsets` | **legacy/compat only** (see note) |
| `splash` | `splashOffsets` | note splash |

**Important:** the modern folder renderer applies `holdOffsets` to the entire sustain (body and tail
share it) and does **not** read `endOffsets` separately. `endOffsets` is only honored by the
`compatibilityMode`/legacy sustain path, where it overrides `holdOffsets` for the tail piece. For a
folder skin targeting the modern runtime, use `holdBody` (`holdOffsets`) to nudge holds; `holdEnd`
(`endOffsets`) has no effect in normal play.

```
offsets:
    notes: [0, 0]
    strums: [0, 0]
    holdBody: [0, 0]
    splash: [0, 0]
    notes:
        col2: [0, 2]
        col3: [0, 2]
```

### A.14 Animation support in depth

This section covers exactly how a folder skin animates, end to end.

**1. Resolving frames.** A key resolves to a frame list per A.6 (single image or numbered sequence,
`@2x`- and `pixel/`-aware). The list is then filtered by the `animated` flag: if the element is
`animated: false` and has more than one frame, only frame 1 is kept (`staticFrame`).

**2. Building the sprite.** The kept frames are packed into a small in-memory atlas
(`NoteSkinConfig.applyAnims` -> `build`) and a named animation is added to the sprite. Cardinal-lane
rotation is **baked into each frame bitmap** at build time (not applied as a live sprite angle), so a
single `noteArrow.png` becomes correctly-facing left/down/up/right frames. Center/`square` lanes and
per-column/array images are not rotated unless `columnAngles` says so.

**3. Per-element animation names, looping, and fps:**

| Element | Anim name | Loops? | fps |
|---|---|---|---|
| Note head | `note` | no | `fps` for the lane (default 24) |
| Hold body | `hold` | **yes** | `fps` for the lane |
| Hold tail | `end` | **yes** | `fps` for the lane |
| Receptor static | `static` | no | `fps` for the lane |
| Receptor pressed | `pressed` | no | `fps` for the lane |
| Receptor confirm | `confirm` | no | `fps` for the lane **if it has >1 frame, otherwise 24** |

The hold body and tail loop so a long sustain keeps animating for its whole duration. The note head and
receptor states play once. The confirm state has a special rule: a multi-frame confirm plays at the
lane `fps`, but a single-frame confirm is added at 24 fps (a harmless constant, since one frame doesn't
animate).

**4. What animates in practice.** Any element can be an animated sequence, including `notes` and
`strums`, not just `pressed`/`confirm`. To animate the note head, ship `noteArrow1.png,
noteArrow2.png, ...`, point `images.notes.arrow` at `noteArrow`, and set `animated.notes: true`. To
control speed, set `fps` (globally or per-lane). Example, animate the note head at 12 fps on the outer
lanes only:

```
general:
    fps:
        col1: 12
        col2: 24
        col3: 24
        col4: 12
animated:
    notes: true
```

**5. Note on `confirmFPS`.** Some older `skin.json` files (the bundled `Chip`/`Future` skins) carry a
`confirmFPS` key. It is **not** a recognized field and is ignored; use `fps` (which drives every
element, including confirm, subject to the single-frame rule above).

**6. Per-note graphic overrides.** Independent of the skin's animation, a note type's `texture` (or a
script) can swap a single note's head/hold sheet at runtime; that override is rendered by the classic
renderer's per-element path (Part B.7), not the folder animation machinery.

### A.15 Splashes

Point `images.splash` at a key like any note. The engine resolves it as **folder-native frames first**
(a single image, numbered sequence, `@2x`, or `pixel/` variant, exactly like other elements). If that
resolves, the splash plays as part of your skin, recolored per-lane via the arrow palette unless
`colorable.splash: false`. If it does **not** resolve as folder-native frames, `splash` is instead
treated as a legacy sparrow-atlas name (a packed `.png`/`.xml`), for skins ported from the pre-folder
splash system. Omit `splash` to use the engine's own default splash.

Splash-specific settings:

- **`general.splashScale`** (default `1`): splash size multiplier, independent of note sizing.
- **`general.splashFps`** (default `[22, 26]`): playback rate; a `[min, max]` range randomizes per
  splash. A single Int fixes the rate.
- **`offsets.splash`** (`splashOffsets`): per-lane `[x, y]` nudge.
- **`colorable.splash`** + the player's **Link Splash Color** option: gate per-lane recoloring (A.12).

For the player to see a skin's own splash, the **Note Splashes** option must be set to **"From
Noteskin"** (the default defers to the active skin's splash).

### A.16 HD @2x assets

Ship any image at double resolution and suffix the filename `@2x` (e.g. `noteArrow@2x.png`, alongside
or instead of `noteArrow.png`). The engine detects `@2x` per file and downscales it by half at load
(the same convention osu! skins use). You don't declare this anywhere; it's picked up per file. The
`general.hi-res` flag is only a human-readable hint.

For sequences, `@2x` goes **after the frame number**, at the very end: `confirmArrow1@2x.png`,
`splash0001@2x.png`, never `confirmArrow@2x1.png`. It also stacks last with the `-pixel` suffix:
`confirmArrow1-pixel@2x.png`.

### A.17 Pixel-art variants

A skin can ship a pixel-art version of its assets for pixel-art stages. Provide it two ways, checked in
this order (`NoteSkinConfig.pixelFrameKeys`):

1. A **`pixel/` subfolder** mirroring the same names: `pixel/noteArrow.png` (or, for a sequence with
   per-frame pixel suffixes, `pixel/confirmArrow1-pixel.png`).
2. A **`-pixel` suffix** on the file itself: `noteArrow-pixel.png` (single) or `confirmArrow1-pixel.png`
   (sequence, suffix after the number).

Two flags control when pixel art is used:

- **`pixel: true`** -> always render as pixel art (any stage). Antialiasing is forced off.
- **`pixelVariant: true`** -> render pixel art **only on a pixel stage**, and make this skin eligible
  for the **pixel-stage auto-swap**: on a pixel stage, if the player's selected skin isn't already
  pixel-capable, the engine substitutes the first `pixelVariant` skin (preferring `Default`) so pixel
  art is shown even if the player picked a non-pixel skin. A song that explicitly chose a classic
  `arrowSkin` is left alone.

Pixel art usually needs a bigger on-screen zoom than HD art; set `pixelScale` (A.10) for that. When in
pixel mode, antialiasing is off regardless of the `antialiasing` field.

### A.18 Per-keycount sections

A top-level block named `<N>K` (e.g. `4K:`, `6K:`) is merged **on top of** the base config, but only
when the chart actually uses that many keys. Use it for genuinely different art or settings per key
count (not just per-lane within one key count):

```
4K:
    images:
        notes:
            col1: noteLEFT
            col2: noteDOWN
            col3: noteUP
            col4: noteRIGHT
    general:
        fps:
            col1: 12
            col2: 24
            col3: 24
            col4: 12
    offsets:
        notes:
            col2: [0, 2]
            col3: [0, 2]
```

A key-count section can contain any of the five groups and only needs to redeclare the fields it
overrides; everything else still falls back to the base config.

> **Warning:** a key-count section is a **field-level override merge** (`mergeOverride`), not a deep
> patch of nested per-lane objects. If you override `images.notes` inside a `4K:` block, provide every
> lane you care about there; a `col2` set at the base level does **not** keep applying once
> `4K.images.notes` exists.

### A.19 Select and test your skin

- Pick it in **Options > Note Skins**, or set `"arrowSkin": "<YourSkin>"` in a chart's metadata (the
  chart's choice wins unless the player has **Force Selected Skin** on).
- Open the **Note Skin Editor** (editors menu) for a live preview across key counts, states, and pixel
  mode. Note the editor preview honors some fields (like `holdAlpha`) that the gameplay sustain does
  not; trust in-game behavior for final tuning.
- Test with **Downscroll** on and on a **pixel-art stage**: both exercise different code paths
  (rotation/geometry and pixel resolution respectively).
- If an element is missing, re-check A.6 (filename resolution) before the config; a missing file is a
  silent fallback, not an error.

---

## Part B: Classic Note Skins

A classic skin is a **sparrow atlas** (a packed `<name>.png` + matching `<name>.xml`) using the vanilla
NOTE_assets frame-prefix convention. It is rendered by `backend.noteskin.ClassicNoteSkin` with full
support; this is the format vanilla FNF and most existing mods ship.

### B.1 When to make a classic skin

Choose classic when:

- You already have a NOTE_assets-style atlas (porting an existing mod skin).
- You want a single packed sheet rather than loose files.
- You don't need folder-only features: `@2x`, per-file pixel variants, auto-rotation of one arrow,
  numbered image sequences, `fitColumnWidth`, folder-native splashes, or per-file per-lane art.

Otherwise prefer a folder skin (Part A); it's more flexible.

### B.2 The atlas and frame prefixes

Author the atlas at the same **160 px reference frame**. The `.xml` must contain the frames the renderer
looks up by prefix. For 4K (the standard case):

| Role | Frame prefix (per direction) |
|---|---|
| Receptor static | `arrowLEFT`, `arrowDOWN`, `arrowUP`, `arrowRIGHT` |
| Receptor pressed | `left press`, `down press`, `up press`, `right press` |
| Receptor confirm | `left confirm`, `down confirm`, `up confirm`, `right confirm` |
| Note head | `purple0`, `blue0`, `green0`, `red0` (color = column) |
| Hold body | `purple hold piece`, `blue hold piece`, `green hold piece`, `red hold piece` |
| Hold end | `purple hold end`, `blue hold end`, `green hold end`, `red hold end` |

These are Sparrow/Starling animation prefixes (numbered frames like `purple0000`, `purple0001` under the
`purple0` lookup); export from Adobe Animate or any tool that produces a Sparrow atlas.

For **multikey** (non-4K), the renderer uses per-column direction names from the table in A.8 and, if
your atlas lacks the center/`square` frames, **auto-merges** the shared `noteSkins/square` atlas so a
center note still renders (`mergeSquare`). Ship your own `square`/`arrowSQUARE` frames to override that.

### B.3 Where a classic sheet can live

`NoteSkinConfig.classicSheet` resolves a name by trying, in order, and uses the first `.png` that
exists:

1. A config-declared `sheet` inside the folder: `<name>/<sheet>.png`.
2. A **loose** sheet: `noteSkins/<name>.png` (+ `.xml`).
3. A **foldered, self-named** sheet: `noteSkins/<name>/<name>.png`.
4. A **foldered default**: `noteSkins/<name>/NOTE_assets.png`.

So both layouts are valid:

```
# Loose:
images/noteSkins/MyArrows.png
images/noteSkins/MyArrows.xml

# Foldered:
images/noteSkins/MyArrows/MyArrows.png   (or NOTE_assets.png)
images/noteSkins/MyArrows/MyArrows.xml
```

On a pixel stage the classic renderer prepends `pixelUI/` (B.6).

### B.4 Listing a classic skin in Options

**Loose** classic sheets are **not** auto-scanned into the dropdown (that would list internal sheets
like `square`). Add the skin name to a `list.txt`:

```
# assets/shared/images/noteSkins/list.txt   (or mods/<YourMod>/images/noteSkins/list.txt)
MyArrows
```

`list.txt` files are merged across all mods. **Foldered** classic skins are picked up by the directory
scan automatically (listing them in `list.txt` is harmless).

### B.5 The optional tuning config

A classic skin may ship a `skin.tcfg`/`skin.json` (foldered `<name>/skin.*`, or a loose sibling
`<name>.tcfg` next to the sheet). Because an atlas resolves for it, the skin stays **classic**; the
config only **tunes** the renderer. Fields the classic path reads:

- **`sheet`** (classic-only): names the atlas file inside the folder.
- **Frame-prefix routing:** the `notes`/`strums`/`pressed`/`confirm`/`holdBody`/`holdEnd` values become
  the **XML frame prefix** for that role/column, replacing the standard NOTE_assets prefix
  (`routePrefix`). This maps an atlas with non-standard prefix names, and lets specific columns point at
  specific prefixes.
- **`antialiasing`** (per-lane), **`fps`** (per-lane, drives the note/hold anim rate), **`offsets`**
  (`noteOffsets`/`strumOffsets`/`holdOffsets`), and **`colorable`**: honored where the classic path
  supports them.
- **`keys`** (per-keycount `<N>K:` sections): applied for the active key count.

```
# images/noteSkins/MyArrows/skin.tcfg  (or a loose MyArrows.tcfg)
general:
    sheet: MyArrows
    antialiasing: false
    fps: 24
images:
    notes:
        arrow: myNote        # look up "myNote<dir>" frames instead of "<color>0"
    strums:
        arrow: myStrum
    pressed:
        arrow: myPress
    confirm:
        arrow: myConfirm
    holdBody: myHold
    holdEnd: myEnd
colorable:
    notes: true
    strums: false
    pressed: true
    confirm: true
offsets:
    notes: [0, 0]
    strums: [0, 0]
    holdBody: [0, 0]
```

Without a config, a bare sheet renders with the standard NOTE_assets prefixes and default settings, i.e.
exactly like vanilla. That's the point: existing atlases just work. (Folder-only fields such as
`rotate`, `pixelVariant`, `fitColumnWidth`, `holdsOverHeads`, `headOverlap`, `animated`, `@2x`/`pixel/`
resolution, and folder-native splashes do nothing on a classic skin.)

### B.6 Pixel classic skins

On a pixel stage, `ClassicNoteSkin` loads grid sheets instead of a sparrow atlas:

- `pixelUI/<skin>.png`: a **4x5** grid (columns = direction, rows = state) for notes and receptors.
- `pixelUI/<skin>ENDS.png`: a **4x2** grid (top row = hold piece, bottom = end cap) for sustains.

Ship those beside your HD atlas to support pixel stages; no config changes are needed. Frame indices are
fixed by the grid convention, and the pixel receptor's pressed/confirm animations use built-in frame
lists and rates (e.g. pressed `[4,8]` at 12 fps, confirm `[12,16]` at 24 fps).

### B.7 Per-note texture overrides

Independent of the skin, a note type's `texture` property (or a script) can override a single note's
head and hold sheet at runtime:

- `ClassicNoteSkin.applyNoteTexture` re-skins one note head from an explicit sheet.
- `ClassicNoteSkin.applySustainTexture` does the same for the hold body + tail.
- `ClassicNoteSkin.applyElement` is the granular primitive behind runtime note-skinning script
  callbacks: it skins **one** element (head / body / tail) from either a sparrow atlas or a single
  static image, so a script can set each part independently and even mix atlas + image parts like a
  folder skin.

These work in all modes, driven by `NoteData.texture` (from a note type's `texture`, or, in compat, the
`unspawnNotes` write-through). This is how custom-note art is applied without changing the whole skin.

### B.8 Classic animation

Classic skins always play their atlas prefixes (there is no `animated` group). Animation details:

- **Note head:** anim `note`, non-looping; fps from the config's `fps` for the lane, or the atlas
  default if no config.
- **Hold body / tail:** anims `hold` / `end`, **looping**, at the config `fps` (default 24).
- **Receptor static / pressed / confirm:** anims `static` / `pressed` / `confirm`, non-looping; pressed
  and confirm play at 24 fps.
- **Pixel receptors:** fixed frame-index lists per direction with per-state rates (see B.6).

---

## Part C: Full field reference

Every `skin.tcfg` field, its group, whether it accepts a per-lane object, its default, and which
renderer consumes it. (Folder = the modern `FolderNoteSkin`; Classic = `ClassicNoteSkin`; Legacy = the
`compatibilityMode` renderer.)

| Field (`.tcfg`) | Group | Per-lane | Default | Folder | Classic | Legacy |
|---|---|---|---|:---:|:---:|:---:|
| `notes` | images | yes | required | yes | yes (routes prefix) | yes |
| `strums` | images | yes | required | yes | yes (routes prefix) | yes |
| `pressed` | images | yes | reuses `strums` | yes | yes (routes prefix) | yes |
| `confirm` | images | yes | reuses `pressed` | yes | yes (routes prefix) | yes |
| `holdBody` | images | flat key | required | yes | yes (routes prefix) | yes |
| `holdEnd` | images | flat key | required | yes | yes (routes prefix) | yes |
| `splash` | images | per-lane object | engine default | yes | no | no |
| `rotate` | general | no | `true` | yes | no | no |
| `directionAngles` | general | no | `[-90,180,0,90]` | yes | no | no |
| `columnAngles` | general | per column | unset | yes | no | no |
| `fps` | general | yes | `24` | yes | yes | yes |
| `scale` | general | yes | `0.7` | yes | no (uses `noteSizes`) | no |
| `pixelScale` | general | yes | -> `scale` | yes (pixel mode) | no | no |
| `fitColumnWidth` | general | no | off | yes | no | no |
| `antialiasing` | general | yes | player AA option | yes | yes | yes |
| `holdAntialiasing` | general | no | -> `antialiasing` | yes | no | yes |
| `holdAlpha` | general | yes | fixed `0.6` in v2 | no (fixed 0.6) | no | yes |
| `holdsOverHeads` | general | no | global option | yes | n/a | n/a |
| `headOverlap` | general | no | `0` | yes | n/a | n/a |
| `pixel` | general | no | `false` | yes | (implicit on pixel stage) | (implicit) |
| `pixelVariant` | general | no | `false` | yes | no | no |
| `splashScale` | general | no | `1` | yes | no | no |
| `splashFps` | general | no | `[22,26]` | yes | no | no |
| `hi-res` / `hiRes` | general | no | hint only | (informational) | - | - |
| `sheet` | general | no | unset | no | yes | no |
| `notes`/`strums`/`pressed`/`confirm`/`holdBody`/`holdEnd` | animated | per element | `true` | yes | no | no |
| `notes`/`strums`/`pressed`/`confirm`/`holdBody`/`holdEnd`/`splash` | colorable | per element | see A.12 | yes | yes (partial) | yes |
| `notes` (`noteOffsets`) | offsets | yes | `[0,0]` | yes | yes | yes |
| `strums` (`strumOffsets`) | offsets | yes | `[0,0]` | yes | yes | yes |
| `holdBody` (`holdOffsets`) | offsets | yes | `[0,0]` | yes (whole trail) | yes | yes |
| `holdEnd` (`endOffsets`) | offsets | yes | -> `holdOffsets` | no | no | yes (tail) |
| `splash` (`splashOffsets`) | offsets | yes | `[0,0]` | yes | no | no |
| `<N>K:` (per-keycount) | top-level | - | none | yes | yes | yes |

---

## Part D: Folder vs classic cheatsheet

| You want... | Use |
|---|---|
| Loose, editable individual images | Folder |
| `@2x` HD art / per-file pixel variants | Folder |
| One base arrow auto-rotated to all directions | Folder |
| Numbered animation sequences from loose files | Folder |
| Animated note heads or receptors (not just pressed/confirm) | Folder |
| osu!mania column-fit sizing (`fitColumnWidth`) | Folder |
| Folder-native, per-lane recolored splashes | Folder |
| Sustains-over-heads / seam tuning per skin | Folder |
| To reuse an existing NOTE_assets atlas as-is | Classic |
| A single packed sheet, vanilla-compatible | Classic |
| To tune an atlas (prefix routing / offsets / fps / colorable) | Classic + config |

Both are first-class in the modern runtime. When in doubt, start from a copy of the bundled
[Default folder skin](../assets/shared/images/noteSkins/Default/) and edit. For how skins are discovered
and picked at runtime, and the legacy-skin limitations, see [note-skin-system.md](note-skin-system.md).
