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
- `T` while hovering a hex: add or edit a terrain spawner value
- `R` while hovering a hex: add or edit a resource spawner value
- `P`: enter or leave province mode
- `N` in province mode: create a province using the selected territory color
- Enter in province mode: resume or finish painting the selected province
- Left/right drag while painting: assign tiles or erase province ownership
- `Ctrl+Z` in province mode: undo the last completed painting session
- `L` in province mode: show or hide the province panel

The province panel focuses and highlights a province when its row is clicked.
Click its color swatch to cycle its territory color, or `Name` to rename it.
Completed paint sessions can be undone; Escape restores every tile changed in
the active session. Province IDs must be unique and use letters, numbers,
underscores, or hyphens.
- Delete or Backspace while hovering a badge: remove it
- Enter, Y, or Yes: save changes to `data/map.lua`
- Escape, N, or No: cancel the save prompt
- Escape outside the prompt: quit

Spawner strings are stored in the `spawners` table in `data/map.lua`, keyed by
the same `"column,row"` coordinates used for painted tiles. Site strings use a
separate `sites` table and are not used for agent placement.
Terrain spawner strings use `terrain_spawners` and are not yet used by the game.
Resource spawner strings use `resource_spawners` and are not yet used by the game.

Palette PNGs are loaded dynamically from `assets/map_palette`. Each horizontal
band of solid color is exposed as a selectable swatch.
