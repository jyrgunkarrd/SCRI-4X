# SCRI 4X Map Editor

Launch the editor from the project directory:

```text
love . --map-editor
```

Controls:

- Left-drag: paint hexes with the selected color
- Right-drag: erase painted hexes
- Middle-drag / WASD / arrows / screen edge: pan
- Mouse wheel: zoom
- `[` / `]`: previous / next palette
- `,` / `.`: previous / next color in the current palette
- `E`: open the save confirmation
- `A` while hovering a hex: add or edit an agent spawner value
- `S` while hovering a hex: add or edit a site value
- Delete or Backspace while hovering a badge: remove it
- Enter, Y, or Yes: save changes to `data/map.lua`
- Escape, N, or No: cancel the save prompt
- Escape outside the prompt: quit

Spawner strings are stored in the `spawners` table in `data/map.lua`, keyed by
the same `"column,row"` coordinates used for painted tiles. Site strings use a
separate `sites` table and are not used for agent placement.

Palette PNGs are loaded dynamically from `assets/map_palette`. Each horizontal
band of solid color is exposed as a selectable swatch.
