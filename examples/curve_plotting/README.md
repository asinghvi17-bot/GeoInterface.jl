# Curved geometry plotting prototype (GeoInterface.jl#227)

`make_images.jl` renders the images in `images/`, using the test geometry types in
`test/curve_geoms.jl` and ArchGDAL for the "linearize first" workaround.

| Image | What it shows |
|---|---|
| `01_overview.png` / `.svg` | CircularString, CompoundCurve and MultiCurve (`plot` → `curvelines`), plus CurvePolygon with a full-circle hole and a D-shaped hole, and MultiSurface (`plot` → `poly`). CairoMakie draws them as exact arcs. The SVG has `C` (cubic Bézier) path commands rather than polylines. |
| `02_before_after.png` | The two CURVEPOLYGONs from the issue, drawn four ways: control points as a polyline, `ArchGDAL.lineargeom` at 20°, the GDAL default of 4°, and this branch. The bottom row zooms in near (2, 2), with y stretched ×30. |
| `03_nonlinear_transform.png` | Why exact paths are only valid under affine transforms. With a log10 x axis, transforming Bézier control points gives the wrong shape (red), so this branch falls back to the linearized polygon. |
| `04_plots_gr.png` | Plots.jl (GR) using the linearizing recipes in `GeoInterfaceRecipesBaseExt`, including the `curve_maxangle` / `curve_tol` attributes. |
