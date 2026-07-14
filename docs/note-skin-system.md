# The Note Skin System

Extensive reference for how note skins work in this engine: the three skin **kinds**
(folder / classic / legacy), how one is chosen at runtime, what each can and can't do, and how the
whole thing stays decoupled from the note runtime.

This is the **architecture / reference** document. If you just want to *build* a skin (every field,
all animation behavior, setup and configuration), read the companion how-to:
[making-note-skins.md](making-note-skins.md) (folder **and** classic).

---

## Contents

- [1. The big picture](#1-the-big-picture)
- [2. Who picks the skin](#2-who-picks-the-skin)
  - [2.1 Which name is active](#21-which-name-is-active)
  - [2.2 Folder vs classic](#22-folder-vs-classic)
  - [2.3 Where skins are found (search roots)](#23-where-skins-are-found-search-roots)
  - [2.4 How skins are listed (the Options dropdown)](#24-how-skins-are-listed-the-options-dropdown)
- [3. Folder skins (the modern kind)](#3-folder-skins-the-modern-kind)
  - [3.1 What a folder skin is](#31-what-a-folder-skin-is)
  - [3.2 How FolderNoteSkin builds a sprite](#32-how-foldernoteskin-builds-a-sprite)
  - [3.3 Elements a folder skin can define](#33-elements-a-folder-skin-can-define)
  - [3.4 Key to file resolution](#34-key-to-file-resolution)
  - [3.5 What folder skins can do that classic can't](#35-what-folder-skins-can-do-that-classic-cant)
- [4. Targeting: per-lane / per-keycount resolution](#4-targeting-per-lane--per-keycount-resolution)
- [5. Coloring (colorable) and the RGB shader](#5-coloring-colorable-and-the-rgb-shader)
- [6. Pixel-art handling](#6-pixel-art-handling)
- [7. Classic skins (atlas-based)](#7-classic-skins-atlas-based)
  - [7.1 How a classic sheet is located](#71-how-a-classic-sheet-is-located)
  - [7.2 Optional classic config](#72-optional-classic-config)
  - [7.3 What classic skins do automatically](#73-what-classic-skins-do-automatically)
  - [7.4 Per-note texture overrides (all modes)](#74-per-note-texture-overrides-all-modes)
  - [7.5 What classic skins can't do (vs folder)](#75-what-classic-skins-cant-do-vs-folder)
- [8. Legacy skins (compatibility only)](#8-legacy-skins-compatibility-only)
  - [8.1 When it runs](#81-when-it-runs)
  - [8.2 What it does](#82-what-it-does)
  - [8.3 Limitations of legacy skins](#83-limitations-of-legacy-skins)
- [9. Quick comparison](#9-quick-comparison)
- [10. Source map](#10-source-map)

---

## 1. The big picture

A "note skin" decides the **look** of five on-screen things:

- the **note head** (the falling tap note),
- the **sustain body** (the held trail) and its **tail** (end cap),
- the **receptor** and its `static` / `pressed` / `confirm` states (the arrows at the top of the
  lane),
- the **note splash** (the burst on a perfect hit).

The critical design rule: **the gameplay/drawable layer never references a texture, an atlas, or a
config file.** A note (`objects/notes/NoteSprite.hx`), a sustain (`SustainSprite.hx`) and a receptor
(`Receptor.hx`) are *bare* `FlxSprite`s. They ask a skin provider to "dress" them, and the provider
sets their frames, animations, scale and antialiasing. Everything the drawable still needs that
*isn't* part of a bare sprite (lane offsets, per-role colorability, splash overrides) comes back in a
small `NoteVisual` value object.

That provider is an **`INoteSkin`** ([source/backend/noteskin/INoteSkin.hx](../source/backend/noteskin/INoteSkin.hx)):

```haxe
interface INoteSkin {
    function applyNote(spr, rgb, column, keyCount, animName):NoteVisual;
    function applySustain(body, bodyRGB, tail, tailRGB, column, keyCount):NoteVisual;
    function applyReceptor(spr, rgb, column, keyCount, lastAnim):NoteVisual;
    function isPixel():Bool;
}
```

There are exactly **two** implementations of that interface, plus a third **legacy** path that is
*not* part of the interface and only runs for opted-in compatibility mods:

| Kind | Class | Backing assets | Who renders it |
|---|---|---|---|
| **Folder** (modern) | `backend.noteskin.FolderNoteSkin` | a folder of **individual images** + a `skin.tcfg`/`skin.json` config | the v2 drawables |
| **Classic** | `backend.noteskin.ClassicNoteSkin` | a **sparrow atlas** (`.png` + `.xml`), optionally + a config | the v2 drawables |
| **Legacy** | `legacy.LegacyNoteSkin` | a sparrow atlas (same as classic) | the **legacy** `LegacyNote`/`LegacyStrumNote` runtime only, and only under `compatibilityMode` |

`FolderNoteSkin` and `ClassicNoteSkin` are the **current, always-running** system. `LegacyNoteSkin`
is a deprecated quarantine of the pre-rewrite renderer, wired only as a fallback for the legacy note
objects when a modpack turns on compatibility. **A normal, modern play session never touches
`LegacyNoteSkin`.**

---

## 2. Who picks the skin

Two static classes cooperate:

- **`backend.NoteSkinConfig`** - the **data / discovery** brain. Locates skin files, parses configs,
  caches everything, resolves per-lane/per-keycount fields, and decides *which skin name is active*.
- **`backend.noteskin.NoteSkinService`** - the **provider facade**. Given the active name, hands back
  the right `INoteSkin` (a `FolderNoteSkin` or the shared `ClassicNoteSkin`), cached.

The drawables only ever call `NoteSkinService.current()`. Everything below is what that call resolves
to.

### 2.1 Which name is active

*(`NoteSkinConfig.activeSkin()`)*

Resolution order (first match wins):

1. **Editor override.** `NoteSkinConfig.editorOverride` - set by the Note Skin Editor / chart-editor
   preview so it can force a specific skin regardless of prefs. `null` in normal play.
2. **The selected skin** (`selectSkin()`):
   - If **Force Selected Skin** (`ClientPrefs.data.forceNoteSkin`) is **off** and the chart declares
     an `arrowSkin`, that wins - but only if it resolves to a folder skin. (A chart `arrowSkin` that
     names a *classic* atlas is left to the classic path; see §2.2.)
   - Else the player's **Note Skin** option (`ClientPrefs.data.noteSkin`, prefixed `noteSkins/`), if
     it names a folder skin.
   - Else, if a **mod ships a classic `NOTE_assets` sheet** (and the skin isn't forced), the classic
     path is used (returns `null` here so the service falls through to `ClassicNoteSkin`). This is
     what lets a mod's full-sheet legacy skin still apply by default.
   - Else the built-in **`noteSkins/Default`** folder skin.
3. **Pixel-stage auto-swap.** On a pixel stage, if the selected skin isn't already pixel-capable and
   the song didn't explicitly pick a classic `arrowSkin`, `activeSkin()` swaps in the first skin
   flagged `pixelVariant: true` (preferring `Default`) so its pixel art is used. See §6.

### 2.2 Folder vs classic

*(`NoteSkinService.current()`)*

Once a name is active, the *kind* is decided **by asset layout, not by the name**:

```haxe
if (active != null && isFolderSkin(active) && !isClassicSkin(active))
    return folderSkin;       // FolderNoteSkin
return classic(activeClassicSkin());   // ClassicNoteSkin
```

- **`isFolderSkin(name)`** → a `skin.tcfg`/`skin.json` file resolves for it.
- **`isClassicSkin(name)`** → a **sparrow sheet** resolves for it (`classicSheet()` found a `.png`).

So the rule is:

> A skin that has a config file **and no atlas** is a **folder** skin. Anything backed by a sparrow
> atlas - **even if it also ships a config** - is a **classic** skin (the config just *tunes* the
> classic renderer).

This is why a classic skin can carry a `skin.tcfg`: the presence of the `.png`+`.xml` atlas routes it
to `ClassicNoteSkin`, and the config is read via `classicConfig()` to supply frame-prefix routing,
offsets, colorable flags, fps, etc.

### 2.3 Where skins are found (search roots)

`NoteSkinConfig.locateSkinFile()` looks for `images/<name>/skin.{tcfg,json}` in this order, and
**base game is scanned first so a mod can't shadow a base skin**:

1. `assets/shared/images/noteSkins/...` (base game).
2. The **current mod** (if its assets are allowed).
3. Every **global** mod.
4. The bare `mods/` root (`mods/images/noteSkins/...`).
5. Every other **enabled** mod.

Because a skin can live in *any* enabled mod's folder, the config remembers the owning **root** and
pins asset resolution to it at apply time (`activeSkinPinRoot()`), so the skin's own images resolve
from wherever the skin lives - not only from the current/global mod. Under **Force Selected Skin**,
the pin is stricter (base-only or that-mod-only) so another mod can't override individual arrows.

### 2.4 How skins are listed (the Options dropdown)

`OptionsCatalog.visualsRows()` builds the **Note Skins** dropdown from two sources merged:

- `images/noteSkins/list.txt` across all mods (`Mods.mergeAllTextsNamed`) - this is how **loose
  classic sheets** are surfaced (an auto-scan would otherwise list internal sheets like
  `NOTE_assets`/`square`).
- `NoteSkinConfig.list()` - every **folder skin** (`skin.tcfg`/`json`) *and* every **foldered
  classic** atlas skin found by directory scan.

The default (`ClientPrefs.defaultData.noteSkin`) is always inserted first; a saved value that no
longer exists resets to default.

---

## 3. Folder skins (the modern kind)

A folder skin is a directory of **individual PNGs** plus one `skin.tcfg` (or `skin.json`) describing
how to assemble them. Rendered by **`FolderNoteSkin`**. This is the most capable and the recommended
format for new skins.

### 3.1 What a folder skin *is*

```
images/noteSkins/MySkin/
├── skin.tcfg          # the config (primary format; skin.json also works)
├── noteArrow.png      # note head (cardinal lanes)
├── noteCenter.png     # note head (odd-keycount center lane)
├── strumArrow.png     # receptor static
├── pressArrow1.png    # receptor pressed (animated sequence)
├── pressArrow2.png
├── confirmArrow1.png  # receptor confirm (animated sequence)
├── confirmArrow2.png
├── confirmArrow3.png
├── holdBody.png       # sustain body
├── holdEnd.png        # sustain tail
├── splash1.png        # note splash (optional; sequence or single)
├── ...
├── pixel/             # optional pixel-art variants (see §6)
└── noteArrow@2x.png   # optional HD variant (auto-detected, half-scaled)
```

**No atlas, no XML.** Every element is a plain image key that the engine resolves to files (§3.4).

### 3.2 How `FolderNoteSkin` builds a sprite

For each of `applyNote` / `applySustain` / `applyReceptor`:

1. Load the merged config for the current key count (`NoteSkinConfig.forCurrentKeys`).
2. Resolve the per-column **image key** for the element (`resolveColumn` / `columnKey`) - this walks
   the targeting rules (§4).
3. Resolve that key to a **frame list** (`resolveFrames`) - single image, numbered sequence, `@2x`,
   or pixel variant.
4. Build a tiny throwaway atlas from those frames (`applyAnims`) and add the standard animation
   (`note` / `hold`+`end` / `static`+`pressed`+`confirm`), applying per-cardinal **rotation** if
   `rotate` is on.
5. Compute **scale** (`scale` x keycount factor, or `fitColumnWidth`), set antialiasing, center, and
   fill in a `NoteVisual` (offsets, colorability, pixel flag).

**Anything a folder skin can't resolve falls back to `ClassicNoteSkin`** - but that fallback only
produces art when a classic sparrow atlas is actually available (a chart `arrowSkin`, a mod's
`noteSkins/NOTE_assets` sheet, or the `pixelUI/` sheets on a pixel stage). The base game ships **no
loose `noteSkins/NOTE_assets` sheet** on a normal stage, so an element the folder skin omits with no
classic atlas present renders **blank** (the receptor `pressed`/`confirm` states are the exception:
they reuse the skin's own `strums` frames when omitted). Treat `notes`, `strums`, `holdBody`, and
`holdEnd` as the required set for a self-contained skin, and only rely on the classic fallback when you
know an atlas is present.

### 3.3 Elements a folder skin can define

| Config element (tcfg key) | Internal field | Meaning |
|---|---|---|
| `notes` | `notes` | note head |
| `strums` | `strums` | receptor static |
| `pressed` | `pressed` | receptor pressed state |
| `confirm` | `confirm` | receptor confirm state |
| `holdBody` | `holds` | sustain body |
| `holdEnd` | `ends` | sustain tail |
| `splash` | `splash` | note splash |

(The `.tcfg` parser remaps `holdBody`→`holds` and `holdEnd`→`ends`; `skin.json` uses `holds`/`ends`
directly.)

### 3.4 Key to file resolution

Every image reference is a **key**, not a filename. `NoteSkinConfig.frameKeys` resolves it:

1. **Single image**: `<key>.png` (or `<key>@2x.png`).
2. **Numbered sequence**: `<key><sep><N>.png` where `<sep>` ∈ `{"", "-", "_"}`, `<N>` is zero-padded
   to **1-4 digits**, starting at index **0 or 1**. The engine probes every combination and uses
   whichever contiguous run exists (`confirmArrow1..3`, `splash0001..`, `note_0..`, etc.).

`@2x` files are detected per-file and downscaled by 0.5 at load (`resolveImage` returns a `factor`).
Pixel variants are resolved by `resolveFrames` when in pixel mode (§6).

### 3.5 What folder skins can do that classic can't

- **Mix element sources freely** - every element is its own image(s); you never repack an atlas.
- **Per-column independent art** via `col1..colN` keys (multikey-friendly).
- **Per-lane / per-target `fps`, `scale`, `antialiasing`, offsets, colorable** - all can be a scalar
  *or* a per-lane object.
- **Auto-rotation** of a single base arrow into all cardinal directions (`rotate` + `directionAngles`
  / `columnAngles`), so one `noteArrow.png` covers left/down/up/right.
- **Per-keycount override sections** (`4K:`, `6K:`, ...) that merge over the base.
- **`@2x` HD assets** and **pixel-art variants** (`pixel/` subfolder or `-pixel` suffix) with
  `pixelVariant` auto-selection on pixel stages.
- **Folder-native splashes** resolved exactly like notes (single/sequence/`@2x`/pixel), recolored
  per-lane.
- **osu!mania-style `fitColumnWidth`** - fit each element to the lane column width instead of scaling
  by native pixels, decoupling receptor size from note size.
- **Layout tweaks**: `holdsOverHeads`, `headOverlap`, `holdAntialiasing`. (Note: the skin's `holdAlpha`
  is **not** read by the modern sustain, which dims to a fixed `0.6`; it is honored only by the legacy
  compat renderer and the editor preview. See the field reference for the full caveat.)

Full field-by-field reference (every value + animation): [making-note-skins.md](making-note-skins.md).

---

## 4. Targeting: per-lane / per-keycount resolution

This machinery is shared by both folder and classic skins (classic uses it to pick XML prefixes).

A field can be a **scalar** (applies to every lane) or a **per-lane object**. When per-lane, a lane is
matched in this priority (`resolveColumn` / `rawForColumn`):

1. **Column-index key** - `"0"`, `"1"`, ... (0-based). In `.tcfg` you write `col1`, `col2`, ...
   (**1-indexed**), which the parser rewrites to the 0-based internal index. Column-index keys win,
   which is how you disambiguate lanes that share a direction name in multikey.
2. **Direction name** - `left` / `down` / `up` / `right`.
3. **Center / square** - `center` (tcfg) → `square` (internal), the odd-keycount middle lane.
4. **`arrow`** - the catch-all for any cardinal lane not otherwise specified.

The per-keycount **direction table** comes from `Mania.noteAnimations`:

| Keys | Lane directions (col1 → colN) |
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

**Rotation.** For folder skins, `directionAngles` (default `[-90,180,0,90]` for L/D/U/R) rotates a
single base arrow per cardinal direction. `columnAngles` (indexed by column) overrides that per lane,
which you need when two lanes share a direction name but must face differently (e.g. 6K's two "left"
lanes). Per-column *array* images and center lanes are assumed pre-oriented (angle 0) unless
`columnAngles` says otherwise. Set `rotate: false` if your art is already drawn facing each way.

**Per-keycount sections.** A top-level `<N>K:` block is a **field-level override merge** over the base
config (`mergeOverride`), applied only when the chart uses that many keys. It's not a deep patch - if
you override `images.notes` in a `4K:` block, provide every lane you need there.

---

## 5. Coloring (`colorable`) and the RGB shader

Note art is usually shipped as white/greyscale line art and **tinted per-lane at runtime** by an RGB
palette shader (not a texture swap). `colorable` controls this per element.

Two independent gates decide whether an element is actually tinted with the *note color* in a real
game (`NoteSkinConfig.linkedColorable`):

1. The **skin allows** it: `colorable.<element>: true`. The defaults are subtle: if the `colorable`
   group is **omitted entirely, nothing is colorable**; if the group is present, an unlisted element is
   colorable **except `strums`** (receptors are usually pre-colored, so `strums` is only ever colorable
   when set to `true` explicitly). A bare `colorable: true` means "all except `strums`."
2. The **player links** it: the matching *"Link ... to note color"* option is on
   (`linkSplashColor` / `linkSustainColor` / `linkPressedColor` / `linkConfirmColor` /
   `linkStrumColor`).

When an element is colorable but **not linked**, it uses its **independent per-asset color** from the
in-game Note Colors menu instead (`Mania.getAssetColors`), which supports per-keycount overrides. The
receptor recolors **per animation state** (`static`/`pressed`/`confirm` each have their own colorable
flag - `NoteVisual.colorPerAnim`), resolved in `Receptor.playAnim`.

Per-column palettes themselves come from `Mania.getColors` / `composeShared` (cardinal arrows from the
player's arrow palette, extra columns from configurable extra slots, with a one-color and a
per-keycount-override mode).

---

## 6. Pixel-art handling

Three interacting flags:

- **`pixel: true`** - the skin **always** renders as pixel art (antialiasing off, pixel proportions),
  regardless of stage.
- **`pixelVariant: true`** - the skin renders pixel art **only on a pixel-art stage**, and it becomes
  eligible for the **pixel-stage auto-swap**: on a pixel stage, if the selected skin isn't already
  pixel-capable, `activeSkin()` substitutes the first `pixelVariant` skin (preferring `Default`) so
  pixel art is used even if the player picked a non-pixel skin. A song that explicitly chose a classic
  `arrowSkin` is left alone (it brings its own `pixelUI/` sheet).
- **`pixelScale`** - the scale used *instead of* `scale` while in pixel mode (low-res pixel art
  usually needs a bigger zoom). Per-lane allowed; falls back to `scale`.

**Where pixel frames come from** (`pixelFrameKeys`, tried in order, else fall back to base art):

1. A `pixel/` subfolder mirroring names: `pixel/noteArrow.png`.
2. `pixel/` + per-frame `-pixel` suffix: `pixel/confirmArrow1-pixel.png`.
3. A `-pixel` suffix on the key itself: `noteArrow-pixel.png` (single) or `confirmArrow1-pixel.png`
   (sequence).

For **classic** skins on a pixel stage, `ClassicNoteSkin` instead loads a `pixelUI/<skin>` grid sheet
(4x5 for notes/receptors, `<skin>ENDS` 4x2 for sustains) and indexes frames by direction - the
original pixel-note convention.

---

## 7. Classic skins (atlas-based)

A classic skin is a **sparrow atlas** - a packed `<name>.png` + `<name>.xml` - using the vanilla
NOTE_assets frame-prefix convention (`arrowLEFT`, `left press`, `left confirm`, `purple0`,
`purple hold piece`, `purple hold end`, `square`, ...). Rendered by **`ClassicNoteSkin`**. This is the
format vanilla FNF and most existing mods ship, and it remains **fully supported** by the modern
runtime.

### 7.1 How a classic sheet is located

*(`classicSheet()`)*

For a name, the engine tries these in order and uses the first `.png` that exists:

1. A config-declared **`sheet`** inside the folder: `<name>/<sheet>`.
2. A **loose** sheet: `<name>.png` (e.g. `noteSkins/MyArrows.png`).
3. A **foldered, self-named** sheet: `<name>/<lastPathComponent>.png`.
4. A **foldered default**: `<name>/NOTE_assets.png`.

So a classic skin can be a single loose `.png`+`.xml`, or a folder containing an atlas under any of
those names. On a pixel stage the classic renderer prepends `pixelUI/`.

### 7.2 Optional classic config

*(`classicConfig()`)*

A classic skin **may** ship a `skin.tcfg`/`skin.json` (foldered `<name>/skin.*`, or a loose sibling
`<name>.tcfg` next to the sheet). Because an atlas resolves for it, it stays a *classic* skin; the
config just **tunes the classic renderer**:

- **`sheet`** - names the atlas file inside the folder (classic-only field).
- **Frame-prefix routing** - `notes` / `strums` / `pressed` / `confirm` / `holds` / `ends` values
  become the **XML frame prefix** for that role/column instead of the standard NOTE_assets prefix
  (`routePrefix`). This lets a classic atlas with non-standard prefix names still map correctly, and
  lets you point specific columns at specific prefixes.
- **`antialiasing`**, **`fps`**, **`offsets`** (`noteOffsets`/`strumOffsets`/`holdOffsets`),
  **`colorable`** - same fields as folder skins, honored where the classic path supports them.
- **`keys`** (per-keycount overrides) - applied via `withCurrentKeys`.

Without a config, a bare classic sheet renders with the standard prefixes and default settings - i.e.
exactly like vanilla.

### 7.3 What classic skins do automatically

- **Multikey square merge** (`mergeSquare`) - for non-4K key counts, if the skin's atlas lacks the
  center/`square` frames, the shared `noteSkins/square` atlas is merged in so multikey still renders a
  center note. A skin that ships its own square keeps it.
- **Pixel stages** - swaps to the `pixelUI/<skin>` and `<skin>ENDS` grid sheets and indexes frames by
  direction (the classic pixel convention), no config needed.
- **Chart `arrowSkin` / user postfix** - `resolveSkin` honors the chart's `arrowSkin`, a
  location-flexible `NOTE_assets` default, and the user's note-skin postfix
  (`-<lowercased_pref>`), matching legacy behavior byte-for-byte.

### 7.4 Per-note texture overrides (all modes)

Independent of the skin kind, an individual note can override its head (and sustain) texture - the v2
equivalent of the legacy `Note.reloadNote(texture)`:

- `ClassicNoteSkin.applyNoteTexture(spr, column, keyCount, texture)` - re-skins one note head from an
  explicit sheet.
- `ClassicNoteSkin.applySustainTexture(body, tail, ...)` - the sustain counterpart.
- `ClassicNoteSkin.applyElement(spr, column, keyCount, role, source, asImage)` - the granular
  primitive behind runtime note-skinning Lua callbacks: skins **one** element (head / body / tail)
  from either a sparrow atlas or a single static image, so a script can set each part independently
  and even mix atlas + image parts like a folder skin.

These are driven by `NoteData.texture` (from a note type's `texture` property, or, in compat, the
`unspawnNotes` write-through). *Sustain* custom textures via note data are head-only for now.

### 7.5 What classic skins **can't** do (vs folder)

- No mixing of per-element **individual images** - everything is packed frames in one atlas (you must
  repack the XML to change art).
- No engine-side **auto-rotation** of a single base arrow - the atlas must contain each direction's
  frames (or use the square-merge for multikey).
- No `@2x`/`pixel/`/`-pixel` **per-file** variant resolution - pixel art comes from the `pixelUI/`
  grid convention only.
- No **folder-native splashes** - splashes fall back to the `noteSplashes/` atlas / engine default.
- **`fitColumnWidth`**, per-file sequences, and the full per-lane targeting for *art* are folder-skin
  features (classic can still route prefixes and take per-lane offsets/fps/colorable via a config).

---

## 8. Legacy skins (compatibility only)

The renderer class is `legacy.LegacyNoteSkin`.

`legacy.LegacyNoteSkin` is the **pre-rewrite** classic renderer, quarantined in `source/legacy/` and
marked `@:deprecated`. It is **not** an `INoteSkin` and is **not** used by the modern runtime. It
exists solely as the texture loader for the **legacy note objects** (`legacy.LegacyNote` /
`legacy.LegacyStrumNote`), which only run when a modpack opts into compatibility.

### 8.1 When it runs

Only when a pack sets **`compatibilityMode = true`** (alias `legacyMode = true`) in its `pack.json`
(read via `Mods.noteCompatibilityMode()`). In that mode `PlayState` constructs
`legacy.NoteCompatLayer`, an adapter-over-v2 mirror, and the legacy note/strum objects call
`LegacyNoteSkin.reloadNote` / `reloadStrum` to build their looks. **In a non-compat session it never
runs** - play is byte-for-byte the v2 path.

### 8.2 What it does

A faithful copy of the old building logic:

- `reloadStrum` - classic receptor build: loads the strum's sparrow/pixel sheet, adds
  `static`/`pressed`/`confirm` (and the old `green`/`red`/`blue`/`purple` color anims), sizes and
  centers it. Pixel stages use the `pixelUI/` grid; multikey merges the `square` atlas.
- `reloadNote` - classic note/sustain build: loads the note's sparrow/pixel/multikey sheet, adds head
  or hold/end anims, applies the pixel sustain-offset math, sizes and centers.

It is effectively the same rendering `ClassicNoteSkin` now performs, but operating directly on the
legacy `FlxSprite`-subclass note objects rather than on bare sprites via the interface.

### 8.3 Limitations of legacy skins

- **Sparrow atlas only.** If handed a folder skin (individual images, no atlas), it **bails with a
  log error** rather than rendering - `Paths.getSparrowAtlas` returns null and it refuses to NPE.
  Folder skins simply don't exist for the legacy path; they render through the v2 objects instead.
- **No folder-skin features at all** - no per-file `@2x`/pixel resolution, no `fitColumnWidth`, no
  per-lane art targeting beyond the classic prefix convention, no folder-native splash, no
  `skin.tcfg` routing/offsets/colorable. It only understands the vanilla NOTE_assets/`pixelUI` layout.
- **Deprecated and gated.** Every method is `@:deprecated`; it is not part of the supported skin API
  and exists purely so `compatibilityMode` packs keep rendering exactly as they did pre-rewrite.
- **Never coupled into new loops.** Per project policy, legacy stays on its own paths in
  `source/legacy/`; it is not branched inline in the v2 note/field hot paths.

> **Do not author new skins for the legacy path.** A "legacy skin" is just a classic sparrow atlas
> being rendered by the old code for a compat modpack. For new content, ship a **folder** skin (or a
> **classic** atlas, which the modern `ClassicNoteSkin` renders with full support).

---

## 9. Quick comparison

| Capability | Folder | Classic | Legacy |
|---|---|---|---|
| Backing assets | individual PNGs + config | sparrow atlas (+ optional config) | sparrow atlas |
| Renderer | `FolderNoteSkin` | `ClassicNoteSkin` | `LegacyNoteSkin` (compat only) |
| Part of `INoteSkin` | Yes | Yes | No |
| Runs in normal play | Yes | Yes | No (compat modpacks only) |
| Per-file `@2x` HD | Yes | No | No |
| Per-file pixel variants | Yes (`pixel/`, `-pixel`) | No (`pixelUI/` grid) | No (`pixelUI/` grid) |
| Auto-rotate one base arrow | Yes | No | No |
| Per-lane / per-keycount art | Yes | prefix routing + per-lane cfg | No |
| Numbered image sequences | Yes | No (atlas frames) | No (atlas frames) |
| `fitColumnWidth` (osu-style) | Yes | No | No |
| Folder-native splashes | Yes | No | No |
| Multikey square auto-merge | via classic fallback | Yes | Yes |
| Falls back to classic for missing parts | Yes | - | - |
| Config file | `skin.tcfg` / `skin.json` | optional | none |

---

## 10. Source map

| File | Role |
|---|---|
| [INoteSkin.hx](../source/backend/noteskin/INoteSkin.hx) | the provider interface |
| [NoteVisual.hx](../source/backend/noteskin/NoteVisual.hx) | non-sprite look details returned by a provider |
| [NoteSkinService.hx](../source/backend/noteskin/NoteSkinService.hx) | folder-vs-classic facade, `current()` |
| [NoteSkinConfig.hx](../source/backend/NoteSkinConfig.hx) | discovery, parsing, caching, targeting, active-skin resolution, splashes |
| [FolderNoteSkin.hx](../source/backend/noteskin/FolderNoteSkin.hx) | modern folder-skin renderer |
| [ClassicNoteSkin.hx](../source/backend/noteskin/ClassicNoteSkin.hx) | atlas/pixel/multikey renderer + per-note texture primitives |
| [LegacyNoteSkin.hx](../source/legacy/LegacyNoteSkin.hx) | deprecated pre-v2 renderer (compat only) |
| [Mania.hx](../source/backend/Mania.hx) | keycount tables (directions, sizes, colors, square atlas) |
| [config/TcfgParser.hx](../source/backend/config/TcfgParser.hx) | `.tcfg` → `NoteSkinData` parser (field remaps) |

See also: [making-note-skins.md](making-note-skins.md) (how-to) and
[note-skinning-guidelines.md](note-skinning-guidelines.md) (folder `skin.tcfg` field reference).
