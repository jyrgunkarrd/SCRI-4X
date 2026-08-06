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
- Enter, Y, or Yes: save changes to `data/map.lua`
- Escape, N, or No: cancel the save prompt
- Escape outside the prompt: quit

Palette PNGs are loaded dynamically from `assets/map_palette`. Each horizontal
band of solid color is exposed as a selectable swatch.
