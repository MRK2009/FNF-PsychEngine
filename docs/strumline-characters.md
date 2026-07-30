# Extra strumline characters

A chart can have as many strumlines as you like, each with its own key count, notes and character.
This is how you give one a character of its own, and where that character stands.

## The short version

The **stage owns positions**, the **chart owns bindings**. A stage declares named places a character
can stand; a strumline says which one its character uses. That way the same chart still works on a
different stage, and moving the art means editing the stage once rather than every chart set on it.

## Declaring a position in the stage

A position is a `character` entry in the stage's `objects` list:

```json
{
  "objects": [
    { "type": "sprite",    "name": "backWall", "image": "club/wall" },
    { "type": "character", "name": "dj_booth", "x": 2750, "y": 1610 },
    { "type": "dad" },
    { "type": "boyfriend" }
  ]
}
```

It lives in `objects` rather than a separate list on purpose: **the list order is the layer order**,
exactly as it already is for `dad`/`gf`/`boyfriend`. Putting `dj_booth` before `backWall` renders
that character behind the wall. A character you cannot layer is not much use.

| Key | Meaning |
|---|---|
| `type` | Must be `"character"`. |
| `name` | What a strumline refers to. Cannot be `opponent`, `player`, `spectator`, `dad`, `gf` or `boyfriend`. |
| `x`, `y` | Where the character stands. |
| `scrollFactor` | Optional `[x, y]` parallax, like any other object. |

Positions are written by hand for now. The stage editor loads and saves them without damaging
them, but has no UI for placing one yet — the easiest way to find coordinates is to position a
character in the editor, note the numbers, and put them here.

### The three built-in positions

Every stage has `opponent`, `player` and `spectator` without declaring them — they are the existing
`opponent` / `boyfriend` / `girlfriend` coordinates under names a strumline can use. You do not need
to change anything for a normal stage.

## Binding a strumline to it

In the chart editor, click a strumline's chip and use **Stage position**. It lists the three
built-ins plus every `character` position the song's stage declares. **Offset X / Y** nudge that
line's character off the position, for a showcase tweak that shouldn't mean editing the stage.

In the chart file:

```json
"strumlines": [
  { "id": "opponent", "type": 0, "characters": ["dad"],  "keyCount": 4 },
  { "id": "player",   "type": 1, "characters": ["bf"],   "keyCount": 4 },
  { "id": "dj",       "type": 2, "characters": ["pico"], "keyCount": 4,
    "anchor": "dj_booth", "offset": [0, -20] }
]
```

Both keys are optional and only written when set, so a chart that never touches them saves exactly
as it did before.

**A line with no `anchor` derives one from its role** — `player` for a Player line, `opponent` for a
CPU line, `spectator` for an Extra. Every chart written before this behaves identically.

## What you get

The character spawns at the position, layers where its stage object sits, and sings that
strumline's notes. If a section's camera target points at the line, the camera follows that
character. None of that needed new wiring: a strumline already drove its character, there just was
never a way to have one.

Two strumlines naming the same character on the same position share one character rather than
stacking two copies.

If a chart names a position the stage does not declare, the character falls back to the spectator
position and a warning goes to the log, rather than vanishing or landing at `0, 0`.

## Screen space

Strumlines share the screen in proportion to how much room each one needs, so a 4-key line next to a
9-key line no longer gets an equal half and overlaps its neighbour. Lines of the same key count lay
out exactly as they always did — the classic two-line split is still 25% / 75%.

**When they don't all fit, everything shrinks to make room.** The note skin decides how big a note
is for its key count; the layout then applies a uniform scale on top so the whole set fits the
screen. Receptors, notes, hold trails and splashes all take the same factor, so a fitted strumline
looks like a smaller version of itself rather than a broken one.

Lines that already fit are **not touched at all** — the factor is exactly 1, so every existing song
is byte-for-byte the same on screen.

At 1280 wide:

| Setup | Columns | Natural width | Result |
|---|---|---|---|
| `4 + 4` (classic) | 8 | 896px | untouched |
| `9 + 9` | 18 | 1073px | untouched |
| `4 + 4 + 4` | 12 | 1344px | scaled to 94% |
| `6 + 6 + 6` | 18 | 1764px | scaled to 71% |

> Columns are not the whole story — width is. Two 9-key lines and three 6-key lines are both 18
> columns, but the 9-key lanes are drawn much narrower, so the first fits untouched and the second
> shrinks to 71%.

The chart editor still warns when you go past roughly what fits at full size, so you know a line
you just added will be scaled down before you play it.
