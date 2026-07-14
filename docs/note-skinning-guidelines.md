# Note Skinning Guidelines (moved)

This document has been folded into two more complete references. Everything that used to live here
(canvas sizes, file naming, the full `skin.tcfg` format, animation, splashes, recoloring) now lives in
the authoring guide, with every configurable value documented and corrected against the current code.

- **[making-note-skins.md](making-note-skins.md)** - the complete authoring & configuration guide for
  **folder** and **classic** skins: canvas/pivot/scaling, file naming, every `skin.tcfg` field, full
  animation support, splashes, `@2x`, pixel variants, per-keycount sections, and a full field reference
  table.
- **[note-skin-system.md](note-skin-system.md)** - the architecture reference: the three skin kinds
  (folder / classic / legacy), how a skin is discovered and picked at runtime, and how the skin layer
  stays decoupled from the note runtime.

The judgement-UI equivalent (combo / ratings / countdown skins) is unchanged and still lives in
[ui-skinning-guidelines.md](ui-skinning-guidelines.md).
