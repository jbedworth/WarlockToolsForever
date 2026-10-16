# Warlock Tools Forever logo

Original vector artwork: a glowing violet pentacle edged in gold, its star's
points meeting the circle, with a small soul gem at its heart, on a rich
dark-brown background. It shares its frame and colors with the Weapon Sets
Forever and Weapon Skills Forever logos. The design has no font or
external-image dependencies.

- `warlock-tools-forever-logo.svg`: editable, resolution-independent source.
- `warlock-tools-forever-logo.png`: 1024 x 1024 PNG master.
- `warlock-tools-forever-logo-512.png`: 512 x 512 PNG for square project images.

The PNGs are rendered from the SVG with headless Chrome, for example:

```sh
chrome --headless=new --hide-scrollbars --window-size=1024,1024 --force-device-scale-factor=0.5 --screenshot=warlock-tools-forever-logo-512.png warlock-tools-forever-logo.svg
```

Use these files for project pages and distribution branding. Keep this directory
out of the runtime release ZIP; the TOC uses a built-in client icon.

This artwork is covered by the repository's MIT License. Copyright (c) 2026
John Bedworth. Include the applicable license notice with distributed copies.
