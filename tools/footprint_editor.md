# Footprint editor

Launch the project with:

```text
love . --footprint-editor
```

The editor presents a 50 by 50 hex canvas, scans `assets/images/footprint_loader`,
and exports Lua definition files
to `data/footprints` as `<image_name>_footprint.lua`.

## Controls

- Left mouse drag: position the image
- Mouse wheel: scale the image around the pointer
- Right mouse drag: add footprint cells; begin on a painted cell to erase
- Plus/Minus: zoom the editor canvas in or out
- C: enter an HTML hex color for the footprint
- Ctrl+V or Command+V: paste a color while the color prompt is open
- Left/Right or P/N: previous/next image
- R: reset the image transform
- O: rescan the input directory
- E: export
- Escape: quit

## Export coordinates

Footprint cells are axial `{ q, r }` offsets from the blue origin hex. Image
`x_hex` and `y_hex` are position offsets measured in hex-radius units, and
`scale_per_hex` is the image scale divided by the editor hex radius. At runtime,
multiply each of these values by the map's hex radius to reconstruct the same
image-to-footprint relationship at any map hex size.

The exported `color` is normalized RGBA. `src/sys/footprint_sys.lua` loads that
value and draws footprint polygons after the map grid, so they cover grid lines.
Its `draw` function also places the image above the footprint using the exported
transform.
