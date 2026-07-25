# Song packages

A **song package** is one folder that owns everything for a song: the audio, the charts, the metadata, the
events, the preload list, the dialogue and the song-specific scripts. It is addressed by its folder name --
the **songKey** -- which is the only thing the engine resolves paths through.

The song's **display name** is free-form. It no longer has to match the folder, the chart file names or the
score keys.

## Layout

The current layout puts everything beside the audio:

```
mods/<mod>/songs/<songKey>/
  Inst.ogg
  Voices-Player.ogg   Voices-Opponent.ogg   Voices-<suffix>.ogg
  chart-normal.json   chart-hard.json
  metadata-normal.json
  events-hard.json
  preload.json  dialogue.json
  <anything>.lua  <anything>.hx
```

The pre-package layout still loads exactly as before, and can be mixed with the new one:

```
mods/<mod>/songs/<songKey>/Inst.ogg          (audio)
mods/<mod>/data/<songKey>/<songKey>.json     (chart, default difficulty)
mods/<mod>/data/<songKey>/<songKey>-hard.json
mods/<mod>/data/<songKey>/metadata.json
```

## File names

Every per-song file has a **role** -- `chart`, `metadata`, `events`, `preload`, `dialogue` -- and takes an
optional `-<difficulty>` suffix:

| File | Meaning |
| --- | --- |
| `chart-hard.json` | the chart for Hard |
| `chart.json` | a package-wide chart, used by any difficulty that has no file of its own |
| `metadata-hard.json` | metadata for Hard; its fields override `metadata.json`'s |
| `events-hard.json` | events for Hard, instead of `events.json` |
| `<songKey>[-hard].json` | the pre-package chart naming, still accepted in either folder |

Two rules:

- **A suffixed file always wins over the un-suffixed one.** A stale `metadata.json` can never shadow a
  `metadata-hard.json`.
- **No un-suffixed file is required.** A package may consist purely of `<role>-<difficulty>.json` files.
  The un-suffixed file is only an optional package-wide default.

New saves (chart editor, Chart Converter, osu! converter) always write the difficulty into the name --
including the default one, which becomes `chart-normal.json`.

## Resolution order

For role `R` at difficulty `D`, most specific first, then location:

1. `songs/<key>/R-<D>.json` -> `songs/<key>/<key>-<D>.json` -> `data/<key>/R-<D>.json` -> `data/<key>/<key>-<D>.json`
2. `songs/<key>/R.json` -> `songs/<key>/<key>.json` -> `data/<key>/R.json` -> `data/<key>/<key>.json`

Step 2 is only reached when step 1 found nothing. Each candidate goes through the usual mod -> shared
precedence. All of this lives in [`backend.SongPaths`](../source/backend/SongPaths.hx); nothing else in the
engine should build a per-song path by hand.

## Identity vs display name

| | Comes from | Used for |
| --- | --- | --- |
| `songKey` | the package folder | audio, charts, metadata, events, preload, dialogue, song scripts, highscore keys, favorites |
| display name | `metadata[-diff].json` `songName`, else the chart's `song` field, else the folder | Freeplay list, results screen, Discord presence |

In code, `SongChart.songKey()` gives the folder and `SongChart.song` is the display name. A chart may declare
`metadata.folder` in its psych_v2 metadata to point at a package other than the folder it sits in; it is
written only when it can't be derived from the display name.

Charts load through `Song.loadChartFor(songKey, difficultyName)` (or `Song.getChartFor` for a non-destructive
read). Week files name their songs by songKey, exactly as they always did -- for existing content the folder
and the old display-derived name are the same string, so nothing has to change.

## Migrating an existing mod

The in-engine **Chart Converter** does it: it converts each `data/<song>/` folder to psych_v2, folds any
standalone `events.json` into the charts, then moves the whole folder into `songs/<song>/` beside the audio,
renaming charts to `chart-<difficulty>.json`. Originals are mirrored into `chartConvertERBackup/` first. A
song whose mod has no `songs/<song>/` audio folder has nothing to co-locate with and is left in place.
