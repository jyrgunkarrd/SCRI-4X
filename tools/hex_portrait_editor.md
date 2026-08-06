# Hex Portrait Editor

Run from the project root:

```powershell
& "C:\Program Files\LOVE\love.exe" . --portrait-tool
```

Place PNG, JPG, JPEG, BMP, or TGA source images in:

```text
assets/images/process_queue
```

512 x 512 transparent PNG exports are written to:

```text
assets/images/processed
```

Controls:

- Left-drag: pan the image
- Mouse wheel: zoom the image
- `E` or Enter: export the current crop
- Left / Right or `P` / `N`: previous / next source image
- `R`: reset framing and zoom
- `0`: center without changing zoom
- `O`: rescan the input directory
- Escape: quit
