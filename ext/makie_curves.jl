# Makie support for curved geometries (CircularString, CompoundCurve, CurvePolygon,
# MultiCurve, MultiSurface). Included from GeoInterfaceMakieExt.
#
# Each curved geometry is converted into a `CurvePath`, which carries
#   - an exact `Makie.BezierPath` (MoveTo / LineTo / EllipticalArc / ClosePath), and
#   - a linearized fallback (an outline polyline and, for surfaces, GeometryBasics
#     polygons with holes).
# Backends that can draw paths (CairoMakie, see GeoInterfaceCairoMakieExt) use the
# exact path when the transform allows it; everything else (GLMakie, WGLMakie,
# non-linear transforms, 3D, data limits, picking) uses the linearized fallback.

using GeoInterface: _LineSegment, _ArcSegment, _arc_parameters, _startpoint,
    _curve_parts, _orient_rings, _linearize_segments

# --- CurveLines: a `lines`-like recipe for curves ----------------------------------

"""
    curvelines(geom; kwargs...)

Plot a curved geometry as a line. Accepts all `lines` attributes. This is the
default plot type for CircularString, CompoundCurve and MultiCurve.

CairoMakie strokes the exact arc path when it can (2D, identity transform, single
color); otherwise the linearized outline is drawn with `lines`.
"""
Makie.@recipe CurveLines (curve,) begin
    Makie.documented_attributes(Makie.Lines)...
end

"""
    CurvePath

Exact path plus linearized fallback for a curved geometry. Construct with
[`curvepath`](@ref).
"""
struct CurvePath{N,P}
    "Exact path. Rings of surfaces are oriented exterior-CCW / holes-CW."
    bezier::Makie.BezierPath
    "Linearized outline, subpaths separated by NaN points."
    outline::Vector{GB.Point{N,Float64}}
    "Linearized polygons (for surfaces; open curves are closed on themselves)."
    polygons::P
    "Whether every subpath is closed (surfaces)."
    closed::Bool
end
is3d(::CurvePath{N}) where N = N == 3

_gbpoint(p::NTuple{N,Float64}) where N = GB.Point{N,Float64}(p)

function _push_bezier!(cmds, segs; close::Bool)
    isempty(segs) && return cmds
    p = _startpoint(first(segs))
    push!(cmds, Makie.MoveTo(p[1], p[2]))
    for s in segs
        if s isa _LineSegment
            for q in @view s.points[2:end]
                push!(cmds, Makie.LineTo(q[1], q[2]))
            end
        else
            params = _arc_parameters(s.p0, s.p1, s.p2)
            if isnothing(params) # collinear or degenerate: straight segments
                push!(cmds, Makie.LineTo(s.p1[1], s.p1[2]), Makie.LineTo(s.p2[1], s.p2[2]))
            else
                cx, cy, r, a0, _, a2 = params
                # Makie: a2 > a1 is counter-clockwise, a2 < a1 clockwise
                push!(cmds, Makie.EllipticalArc(Makie.Point2d(cx, cy), r, r, 0.0, a0, a2))
            end
        end
    end
    close && push!(cmds, Makie.ClosePath())
    return cmds
end

function _push_outline!(out, segs; kw...)
    isempty(segs) && return out
    isempty(out) || push!(out, eltype(out)(NaN))
    append!(out, map(_gbpoint, _linearize_segments(segs; kw...)))
    return out
end

function _gb_polygon(rings; kw...)
    pts = [map(_gbpoint, _linearize_segments(r; kw...)) for r in rings if !isempty(r)]
    isempty(pts) && return nothing
    return GB.Polygon(pts[1], pts[2:end])
end

"""
    curvepath(geom; maxangle = deg2rad(4), tol = :auto)::CurvePath

Convert a (possibly curved) GeoInterface geometry into a [`CurvePath`](@ref).
`maxangle` and `tol` control the linearized fallback only: at most `maxangle`
radians per chord, and at most `tol` coordinate units between chord and arc
(`:auto` = 1e-4 of the geometry's size, `nothing` = angle only).
"""
function curvepath(geom; maxangle=deg2rad(4), tol=:auto)
    kind, parts = _curve_parts(geom)
    kw = (; maxangle, tol=GI._resolve_tolerance(tol, parts))
    N = GI.is3d(geom) ? 3 : 2
    cmds = Makie.PathCommand[]
    outline = GB.Point{N,Float64}[]
    surfaces = if kind === :curve
        _push_bezier!(cmds, parts; close=false)
        _push_outline!(outline, parts; kw...)
        [[parts]]
    elseif kind === :curves
        foreach(c -> _push_bezier!(cmds, c; close=false), parts)
        foreach(c -> _push_outline!(outline, c; kw...), parts)
        [[c] for c in parts]
    else
        surfaces = kind === :surface ? [parts] : parts
        surfaces = map(_orient_rings, surfaces)
        for rings in surfaces, ring in rings
            _push_bezier!(cmds, ring; close=true)
            _push_outline!(outline, ring; kw...)
        end
        surfaces
    end
    polys = filter(!isnothing, [_gb_polygon(rings; kw...) for rings in surfaces])
    polygons = GB.MultiPolygon(isempty(polys) ? [GB.Polygon([GB.Point{N,Float64}(NaN)])] : polys)
    isempty(cmds) && push!(cmds, Makie.MoveTo(NaN, NaN))
    return CurvePath{N,typeof(polygons)}(Makie.BezierPath(cmds), outline, polygons, !(kind in (:curve, :curves)))
end

function _merge(cps::AbstractVector{<:CurvePath{N}}) where N
    cmds = Makie.PathCommand[]
    outline = GB.Point{N,Float64}[]
    for cp in cps
        append!(cmds, cp.bezier.commands)
        isempty(outline) || isempty(cp.outline) || push!(outline, GB.Point{N,Float64}(NaN))
        append!(outline, cp.outline)
    end
    polygons = GB.MultiPolygon(reduce(vcat, [cp.polygons.polygons for cp in cps]))
    return CurvePath{N,typeof(polygons)}(Makie.BezierPath(cmds), outline, polygons, all(cp -> cp.closed, cps))
end

# --- Conversions from GeoInterface geometries -------------------------------------

# `poly(curvepolygon)` keeps the exact path; `lines(curvepolygon)` / `scatter` get the
# linearized outline.
_convert_curve_arguments(::Type{<:Makie.Poly}, geom) = (curvepath(geom),)
_convert_curve_arguments(::Type{<:CurveLines}, geom) = (curvepath(geom),)
_convert_curve_arguments(t, geom) = (curvepath(geom).outline,)

function _convert_curve_array_arguments(::Type{<:Makie.Poly}, geoms)
    return ([curvepath(g) for g in geoms],)
end
_convert_curve_array_arguments(::Type{<:CurveLines}, geoms) = (_merge([curvepath(g) for g in geoms]),)
_convert_curve_array_arguments(t, geoms) = (_merge([curvepath(g) for g in geoms]).outline,)

# --- CurveLines conversions and plot! -----------------------------------------------

Makie.convert_arguments(::Type{<:CurveLines}, cp::CurvePath) = (cp,)
function Makie.convert_arguments(::Type{<:CurveLines}, geom)
    GI.isgeometry(geom) || error("curvelines expects a GeoInterface geometry, got $(typeof(geom))")
    return (curvepath(geom),)
end
function Makie.convert_arguments(::Type{<:CurveLines}, geoms::AbstractVector)
    all(g -> ismissing(g) || GI.isgeometry(g), geoms) ||
        error("curvelines expects GeoInterface geometries")
    return (_merge([curvepath(g) for g in skipmissing(geoms)]),)
end

function Makie.plot!(p::CurveLines)
    Makie.map!(cp -> cp.outline, p, [:curve], :curve_outline)
    Makie.lines!(p, Makie.Attributes(p), p.curve_outline)
    return p
end

# --- Poly with a CurvePath -----------------------------------------------------------

const _CurvePathArg = Union{CurvePath,AbstractVector{<:CurvePath}}

# Generic backends: draw the linearized polygons (holes included). CairoMakie
# intercepts this before the children are drawn, see GeoInterfaceCairoMakieExt.
function Makie.plot!(p::Makie.Poly{<:Tuple{<:_CurvePathArg}})
    Makie.map!(p, [:polygon], :curve_polygons) do cp
        cp isa CurvePath ? cp.polygons : [c.polygons for c in cp]
    end
    Makie.poly!(p, Makie.Attributes(p), p.curve_polygons)
    return p
end
