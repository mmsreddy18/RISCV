# Block diagram

`rv32imc_block_diagram.*` shows the core as built with `BP_ENABLE=0` (no branch predictor) and
`FAST_REDIRECT=0`: 4 stages, single issue, OBI-style instruction and data ports.

* `.drawio`  editable in draw.io / diagrams.net (File > Open)
* `.svg`, `.pdf`  vector, for papers (grayscale); `.png` 3.5x raster preview
* `_color` variants use the standard draw.io pastel palette
* `make_diagram.py` regenerates the .svg and .drawio from one description; `render.py` makes PNG/PDF (needs playwright)
