import GeoInterface as GI
using GeoInterface.Wrappers: LineString, Polygon, LinearRing
using Test
using Makie, CairoMakie
import Plots

include("curve_geoms.jl")
using .CurveGeoms
CurveGeoms.enable_makie(Makie)
CurveGeoms.enable_plots(Plots.RecipesBase)

const MakieExt = Base.get_extension(GI, :GeoInterfaceMakieExt)
const RecipesExt = Base.get_extension(GI, :GeoInterfaceRecipesBaseExt)

# Distance of every point to (cx, cy) should be r
oncircle(pts, cx, cy, r; atol=1e-12) = all(p -> isapprox(hypot(p[1] - cx, p[2] - cy), r; atol), pts)

@testset "Arc geometry" begin
    @testset "three-point arcs" begin
        # Clockwise half circle over the top
        cx, cy, r, a0, a1, a2 = GI._arc_parameters((0.0, 0.0), (1.0, 1.0), (2.0, 0.0))
        @test (cx, cy, r) == (1.0, 0.0, 1.0)
        @test a0 ≈ π && a1 ≈ π / 2 && a2 ≈ 0
        # Counter-clockwise half circle underneath
        cx, cy, r, a0, a1, a2 = GI._arc_parameters((0.0, 0.0), (1.0, -1.0), (2.0, 0.0))
        @test (cx, cy, r) == (1.0, 0.0, 1.0)
        @test a2 - a0 ≈ π
        # The middle point does not have to be the midpoint; sweeps > 180° work
        p1 = (1 + cos(-0.3), sin(-0.3))
        cx, cy, r, a0, a1, a2 = GI._arc_parameters((0.0, 0.0), p1, (1.0, 1.0))
        @test cx ≈ 1 && abs(cy) < 1e-12 && r ≈ 1
        @test a2 - a0 ≈ 3π / 2 # CCW from 180° through 360° to 90°
        @test a0 < a1 < a2
    end
    @testset "degenerate arcs" begin
        @test isnothing(GI._arc_parameters((0.0, 0.0), (1.0, 1.0), (2.0, 2.0))) # collinear
        @test isnothing(GI._arc_parameters((1.0, 1.0), (1.0, 1.0), (1.0, 1.0))) # coincident
        @test isnothing(GI._arc_parameters((0.0, 0.0), (0.0, 0.0), (2.0, 0.0))) # zero-length
        # Full circle: start == end, middle point diametrically opposite, drawn CCW
        cx, cy, r, a0, a1, a2 = GI._arc_parameters((0.0, 0.0), (2.0, 0.0), (0.0, 0.0))
        @test (cx, cy, r) == (1.0, 0.0, 1.0)
        @test a2 - a0 ≈ 2π
    end
    @testset "signed area and ring orientation" begin
        circle = GI._curve_segments(TCircularString([(0.0, 0.0), (2.0, 0.0), (0.0, 0.0)]), Val(2))
        @test GI._signed_area(circle) ≈ π
        @test GI._signed_area(GI._reverse_segments(circle)) ≈ -π
        @test oncircle(GI._linearize_segments(GI._reverse_segments(circle)), 1, 0, 1)
        # Half disk: CW arc over the top closed by a straight line
        halfdisk = GI._curve_segments(TCompoundCurve([
            TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]), LineString([(2.0, 0.0), (0.0, 0.0)])]), Val(2))
        @test GI._signed_area(halfdisk) ≈ -π / 2
        ext, hole = GI._orient_rings([halfdisk, circle])
        @test GI._signed_area(ext) > 0 && GI._signed_area(hole) < 0
    end
    @testset "linearization" begin
        segs = GI._curve_segments(TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]), Val(2))
        pts = GI._linearize_segments(segs)
        @test first(pts) == (0.0, 0.0) && last(pts) == (2.0, 0.0)
        @test Base.length(pts) == 46 # 180° / 4° = 45 chords
        @test oncircle(pts, 1, 0, 1)
        # Chord tolerance: max deviation r(1 - cos(θ/2)) ≤ tol
        tol = 1e-5
        pts = GI._linearize_segments(segs; tol)
        θ = π / (Base.length(pts) - 1)
        @test 1 - cos(θ / 2) <= tol
        # Collinear "arcs" are kept as straight polylines through the control points
        @test GI._linearize_segments(GI._curve_segments(TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)]), Val(2))) ==
            [(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)]
        # Z is interpolated linearly in angle, through the middle point
        segs3 = GI._curve_segments(TCircularString([(0.0, 0.0, 0.0), (1.0, 1.0, 10.0), (2.0, 0.0, 0.0)]), Val(3))
        pts3 = GI._linearize_segments(segs3)
        @test 9.5 < maximum(p -> p[3], pts3) <= 10
        @test pts3[2][3] ≈ 10 * 4 / 90 # 4° of the 90° from p0 to p1
        @test issorted([p[3] for p in pts3[1:23]])
        @test oncircle(pts3, 1, 0, 1)
        @test_throws ArgumentError GI._curve_segments(TCircularString([(0.0, 0.0), (1.0, 1.0)]), Val(2))
    end
end

# Test geometries
const cs = TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (3.0, -1.0), (4.0, 0.0)])
const cc = TCompoundCurve([TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)]), LineString([(2.0, 0.0), (4.0, 0.0)])])
# The geometry from GeoInterface.jl#227, plus a hole
const cpoly = TCurvePolygon([
    TCircularString([(0.0, 0.0), (1.0, 1.0), (2.0, 0.0), (3.0, -1.0), (4.0, 0.0), (2.0, 2.0), (0.0, 0.0)]),
    TCircularString([(2.6, 0.0), (3.4, 0.0), (2.6, 0.0)]),
])
const mc = TMultiCurve([cs, cc])
const ms = TMultiSurface([cpoly, Polygon([LinearRing([(5.0, 0.0), (6.0, 0.0), (6.0, 1.0), (5.0, 0.0)])])])

@testset "Makie: BezierPath conversion" begin
    cp = MakieExt.curvepath(cs)
    cmds = cp.bezier.commands
    @test cmds[1] isa Makie.MoveTo
    @test count(c -> c isa Makie.EllipticalArc, cmds) == 2
    @test !any(c -> c isa Makie.ClosePath, cmds)
    arc1 = cmds[2]
    @test arc1.c ≈ Point2d(1, 0) && arc1.r1 ≈ 1 && arc1.a1 ≈ π && arc1.a2 ≈ 0 # clockwise
    @test cmds[3].a2 - cmds[3].a1 ≈ π # second arc counter-clockwise
    # Compound curve: arc then line
    cmds = MakieExt.curvepath(cc).bezier.commands
    @test map(typeof, cmds) == [Makie.MoveTo, Makie.EllipticalArc, Makie.LineTo]
    # Curve polygon: two closed subpaths, exterior CCW and hole CW
    cmds = MakieExt.curvepath(cpoly).bezier.commands
    @test count(c -> c isa Makie.MoveTo, cmds) == 2
    @test count(c -> c isa Makie.ClosePath, cmds) == 2
    hole = filter(c -> c isa Makie.EllipticalArc && c.r1 ≈ 0.4, cmds)
    @test sum(c -> c.a2 - c.a1, hole) ≈ -2π # reversed full circle = two clockwise halves
    # Linearized fallbacks
    cp = MakieExt.curvepath(cpoly)
    @test cp.closed
    @test Base.length(cp.polygons.polygons) == 1
    @test Base.length(only(cp.polygons.polygons).interiors) == 1
    @test oncircle(only(cp.polygons.polygons).interiors[1], 3, 0, 0.4)
    @test count(p -> isnan(p[1]), cp.outline) == 1
    @test Base.length(MakieExt.curvepath(ms).polygons.polygons) == 2
    @test count(c -> c isa Makie.MoveTo, MakieExt.curvepath(mc).bezier.commands) == 2
end

@testset "Makie: plotting" begin
    @test Makie.plottype(cs) == MakieExt.CurveLines
    @test Makie.plottype(cc) == MakieExt.CurveLines
    @test Makie.plottype(mc) == MakieExt.CurveLines
    @test Makie.plottype(cpoly) == Makie.Poly
    @test Makie.plottype(ms) == Makie.Poly

    fig = Figure()
    for (i, g) in enumerate((cs, cc, mc, cpoly, ms))
        ax = Axis(fig[1, i])
        @test Makie.plot!(ax, g) isa Makie.AbstractPlot
    end
    ax = Axis(fig[2, 1])
    @test poly!(ax, cpoly; color=:orange, strokewidth=2) isa Makie.Poly
    @test lines!(ax, cpoly) isa Makie.Lines   # linearized outline
    @test lines!(ax, cs) isa Makie.Lines
    cpoly2 = TCurvePolygon([TCircularString([(5.0, 0.0), (6.0, 0.0), (5.0, 0.0)])])
    @test poly!(Axis(fig[2, 2]), [cpoly, cpoly2]; color=[:red, :blue]) isa Makie.Poly
    @test MakieExt.curvelines!(Axis(fig[2, 3]), [cs, cc]; color=:black) isa MakieExt.CurveLines
    @test Makie.plot!(Axis(fig[2, 4]; xscale=log10), TCircularString([(1.0, 1.0), (2.0, 2.0), (3.0, 1.0)])) isa MakieExt.CurveLines
    # Data limits come from the linearized geometry
    ax = Axis(fig[2, 5]); Makie.plot!(ax, cpoly)
    lims = Makie.data_limits(ax.scene.plots[end])
    @test minimum(lims)[1] ≈ 0 atol = 1e-9
    @test maximum(lims)[2] ≈ 2 atol = 1e-3

    # CairoMakie draws exact paths: the SVG contains cubic Béziers (C), not hundreds of L
    mktempdir() do dir
        f = Figure()
        poly(f[1, 1], cpoly)
        Makie.plot(f[1, 2], cs)
        path = joinpath(dir, "curves.svg")
        save(path, f)
        svg = read(path, String)
        paths = [m.captures[1] for m in eachmatch(r"d=\"(M [^\"]*)\"", svg)]
        curvy = filter(d -> count(==('C'), d) >= 4 && count(==('L'), d) == 0 && Base.length(d) > 200, paths)
        @test Base.length(curvy) >= 2

        # Under a non-linear transform the exact path is not valid: fall back to linearized
        f = Figure()
        Makie.plot(f[1, 1], cs; axis=(; yscale=Makie.pseudolog10))
        save(path, f)
        svg = read(path, String)
        @test any(m -> count(==('L'), m.match) > 50, eachmatch(r"d=\"M [^\"]*\"", svg))
    end
end

@testset "Plots: linearized recipes" begin
    xs, ys = RecipesExt._curve_coordvecs(cs; maxangle=deg2rad(4), tol=nothing)
    @test Base.length(xs) == 91 # two 180° arcs at 4°
    @test oncircle(collect(zip(xs[1:46], ys[1:46])), 1, 0, 1)
    xs, ys = RecipesExt._curve_coordvecs(cpoly; maxangle=deg2rad(4), tol=:auto)
    @test count(isnan, xs) == 1 # exterior + hole
    for g in (cs, cc, mc, cpoly, ms)
        @test Plots.plot(g) isa Plots.Plot
    end
    @test Plots.plot(cpoly; curve_maxangle=1, curve_tol=nothing) isa Plots.Plot
    @test Plots.plot([cpoly, cpoly]) isa Plots.Plot
end
