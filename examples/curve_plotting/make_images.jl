# Render the example images for the curved-geometry plotting prototype.
#
#   julia --project=<env with GeoInterface (dev), CairoMakie, Plots, ArchGDAL> make_images.jl
#
# Images are written to `images/` next to this file.
using CairoMakie
import GeoInterface as GI
using GeoInterface.Wrappers: LineString, LinearRing, Polygon
import ArchGDAL as AG
import Plots

include(joinpath(@__DIR__, "..", "..", "test", "curve_geoms.jl"))
using .CurveGeoms
CurveGeoms.enable_makie(Makie)
CurveGeoms.enable_plots(Plots.RecipesBase)

const MakieExt = Base.get_extension(GI, :GeoInterfaceMakieExt)
const OUT = joinpath(@__DIR__, "images")
mkpath(OUT)

# The geometries from GeoInterface.jl#227:
#   CURVEPOLYGON (CIRCULARSTRING (0 0, 1 1, 2 0, 3 -1, 4 0, 2 2, 0 0))
#   CURVEPOLYGON (CIRCULARSTRING (0 0, 1 1, 2 0, 3 -1, 4 0, 2 -2, 0 0))
ring_a = [(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (3.0, -1.0), (4.0, 0.0), (2.0, 2.0), (0.0, 0.0)]
ring_b = [(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (3.0, -1.0), (4.0, 0.0), (2.0, -2.0), (0.0, 0.0)]
a = TCurvePolygon([TCircularString(ring_a)])
b = TCurvePolygon([TCircularString(ring_b)])
wkt(r) = "CURVEPOLYGON (CIRCULARSTRING (" * join(("$(p[1]) $(p[2])" for p in r), ", ") * "))"

cs = TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (3.0, -1.0), (4.0, 0.0)])
cc = TCompoundCurve([
    LineString([(0.0, 0.0), (0.0, 1.0)]),
    TCircularString([(0.0, 1.0), (1.0, 2.0), (2.0, 1.0)]),
    LineString([(2.0, 1.0), (2.0, 0.0), (0.0, 0.0)]),
])
holed = TCurvePolygon([
    TCompoundCurve([
        TCircularString([(0.0, 0.0), (2.0, -1.0), (4.0, 0.0)]),
        LineString([(4.0, 0.0), (4.0, 3.0)]),
        TCircularString([(4.0, 3.0), (2.0, 4.0), (0.0, 3.0)]),
        LineString([(0.0, 3.0), (0.0, 0.0)]),
    ]),
    TCircularString([(1.0, 1.5), (2.0, 1.5), (1.0, 1.5)]),             # full-circle hole
    TCompoundCurve([TCircularString([(2.5, 1.0), (3.0, 1.5), (3.5, 1.0)]),  # D-shaped hole
                    LineString([(3.5, 1.0), (2.5, 1.0)])]),
])
mc = TMultiCurve([cs, TCircularString([(0.0, 1.5), (2.0, 2.5), (4.0, 1.5)])])

# 1. Overview: every type, drawn by CairoMakie as exact arcs -------------------------
fig = Figure(size=(1400, 380))
for (i, (g, title)) in enumerate([
        (cs, "CircularString\nplot → curvelines"),
        (cc, "CompoundCurve\nplot → curvelines"),
        (mc, "MultiCurve\nplot → curvelines"),
        (holed, "CurvePolygon with holes\nplot → poly"),
        (TMultiSurface([a, TCurvePolygon([TCircularString([(5.0, -1.0), (7.0, -1.0), (5.0, -1.0)])])]), "MultiSurface\nplot → poly")])
    ax = Axis(fig[1, i]; title, aspect=DataAspect())
    if GI.geomtrait(g) isa Union{GI.CurvePolygonTrait,GI.MultiSurfaceTrait}
        poly!(ax, g; color=(:steelblue, 0.6), strokecolor=:black, strokewidth=1.5)
    else
        plot!(ax, g; linewidth=2)
    end
end
save(joinpath(OUT, "01_overview.png"), fig; px_per_unit=1.5)
save(joinpath(OUT, "01_overview.svg"), fig)

# 2. Before / after on the geometries from the issue ---------------------------------
# "before" options: on main `plot(curvepolygon)` throws a MethodError. The usual
# workarounds are linearizing first (LibGEOS.curveToLine, ArchGDAL.lineargeom),
# or (wrongly) treating the control points as a polyline.
fig = Figure(size=(1400, 800))
lin_a = AG.lineargeom(AG.fromWKT(wkt(ring_a)))          # GDAL default: 4° per chord
lin_b = AG.lineargeom(AG.fromWKT(wkt(ring_b)))
coarse_a = AG.lineargeom(AG.fromWKT(wkt(ring_a)), 20)   # 20° per chord
coarse_b = AG.lineargeom(AG.fromWKT(wkt(ring_b)), 20)
naive(r) = Polygon([LinearRing(r)])
cols = [
    ("control points as a polyline\n(treating CircularString as LineString)", (ax, g, r, l, c) -> poly!(ax, naive(r); color=g, strokecolor=:black, strokewidth=1)),
    ("main + workaround: ArchGDAL.lineargeom(g, 20°)\n(linearize before plotting)", (ax, g, r, l, c) -> poly!(ax, c; color=g, strokecolor=:black, strokewidth=1)),
    ("main + workaround: ArchGDAL.lineargeom(g)\n(GDAL default, 4° per chord)", (ax, g, r, l, c) -> poly!(ax, l; color=g, strokecolor=:black, strokewidth=1)),
    ("this branch: plot(curvepolygon)\n(exact arcs, no sampling)", (ax, g, r, l, c) -> poly!(ax, g === :tomato ? a : b; color=g, strokecolor=:black, strokewidth=1)),
]
for (j, (title, f)) in enumerate(cols)
    ax = Axis(fig[1, j]; title, aspect=DataAspect())
    f(ax, :tomato, ring_a, lin_a, coarse_a)
    f(ax, (:steelblue, 0.7), ring_b, lin_b, coarse_b)
    # zoomed view of the top of the big arc
    axz = Axis(fig[2, j]; title="zoom near (2, 2), y stretched ×30",
        limits=(1.8, 2.2, 1.993, 2.0015))
    f(axz, :tomato, ring_a, lin_a, coarse_a)
    j == 4 && scatter!(axz, [(2.0, 2.0)]; color=:black, markersize=6)
end
rowsize!(fig.layout, 2, Relative(0.3))
Label(fig[0, :], "CURVEPOLYGON examples from GeoInterface.jl#227 (on main, plot(curvepolygon) throws a MethodError)"; fontsize=18)
save(joinpath(OUT, "02_before_after.png"), fig; px_per_unit=1.5)

# 3. Where exact paths are not valid: non-linear transforms -------------------------
fig = Figure(size=(1100, 420))
g = TCurvePolygon([TCircularString([(1.0, 5.0), (5.0, 9.0), (9.0, 5.0), (5.0, 1.0), (1.0, 5.0)])])
ax1 = Axis(fig[1, 1]; title="linear axes: exact path", aspect=1)
poly!(ax1, g; color=(:steelblue, 0.6), strokecolor=:black, strokewidth=1.5)
ax2 = Axis(fig[1, 2]; title="xscale=log10: Bézier control points\ntransformed (raw BezierPath, wrong)", xscale=log10, aspect=1)
poly!(ax2, MakieExt.curvepath(g).bezier; color=(:red, 0.5), strokecolor=:red, strokewidth=1.5)
lines!(ax2, g; color=:black, linewidth=1) # true shape for reference
ax3 = Axis(fig[1, 3]; title="xscale=log10: this branch falls back\nto the linearized polygon (correct)", xscale=log10, aspect=1)
poly!(ax3, g; color=(:steelblue, 0.6), strokecolor=:black, strokewidth=1.5)
save(joinpath(OUT, "03_nonlinear_transform.png"), fig; px_per_unit=1.5)

# 4. Plots.jl (GR): adaptive linearization in the recipe -----------------------------
Plots.gr()
p1 = Plots.plot(a; title="CurvePolygon (#227)", aspect_ratio=:equal, fillalpha=0.6)
Plots.plot!(p1, b; fillalpha=0.6)
p2 = Plots.plot(cs; title="CircularString", aspect_ratio=:equal, lw=2)
Plots.plot!(p2, cc; lw=2)
p3 = Plots.plot(a; title="curve_maxangle=30, curve_tol=nothing", aspect_ratio=:equal,
    curve_maxangle=30, curve_tol=nothing, fillalpha=0.6)
p4 = Plots.plot(holed; title="CurvePolygon with holes\n(Plots fills rings separately)", aspect_ratio=:equal, fillalpha=0.6)
Plots.savefig(Plots.plot(p1, p2, p3, p4; layout=(1, 4), size=(1400, 380), legend=false), joinpath(OUT, "04_plots_gr.png"))

println("Wrote images to ", OUT)
