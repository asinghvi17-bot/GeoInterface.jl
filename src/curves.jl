# Internal, backend-independent utilities for curved geometries
# (SQL-MM / ISO 13249-3 CircularString, CompoundCurve, CurvePolygon, MultiCurve, MultiSurface).
#
# A curve is decomposed into a vector of segments, each either a straight polyline
# (`_LineSegment`) or a single three-point circular arc (`_ArcSegment`). Plotting
# extensions turn these into exact path primitives (Makie `BezierPath`) or into
# linearized point vectors (Plots.jl, non-linear transforms, 3D).
#
# Points are stored as `NTuple{N,Float64}` with N == 2 (XY) or N == 3 (XYZ).
# The arc itself is always defined in XY; Z is interpolated linearly in angle,
# piecewise through the middle control point (as PostGIS and GEOS do).

struct _LineSegment{N}
    points::Vector{NTuple{N,Float64}}
end

struct _ArcSegment{N}
    p0::NTuple{N,Float64}
    p1::NTuple{N,Float64}
    p2::NTuple{N,Float64}
end

const _CurveSegment{N} = Union{_LineSegment{N},_ArcSegment{N}}

_startpoint(s::_LineSegment) = first(s.points)
_startpoint(s::_ArcSegment) = s.p0
_endpoint(s::_LineSegment) = last(s.points)
_endpoint(s::_ArcSegment) = s.p2

_reverse(s::_LineSegment) = [_LineSegment(reverse(s.points))]
function _reverse(s::_ArcSegment{N}) where N
    s.p0 == s.p2 || return [_ArcSegment(s.p2, s.p1, s.p0)]
    # A single-arc full circle is always counter-clockwise, so reversing its points
    # changes nothing. Split it into two clockwise half circles instead.
    params = _arc_parameters(s.p0, s.p1, s.p2)
    isnothing(params) && return [s]
    cx, cy, r, a0, _, _ = params
    q(a, i) = N == 2 ? (cx + r * cos(a), cy + r * sin(a)) :
        (cx + r * cos(a), cy + r * sin(a), (s.p0[3] + s.p1[3]) / 2)
    return [_ArcSegment(s.p0, q(a0 - π / 2, 1), s.p1), _ArcSegment(s.p1, q(a0 - 3π / 2, 2), s.p2)]
end
_reverse_segments(segs::Vector{<:_CurveSegment{N}}) where N =
    _CurveSegment{N}[r for s in reverse(segs) for r in _reverse(s)]

_tuplepoint(p, ::Val{2}) = (Float64(x(p)), Float64(y(p)))
_tuplepoint(p, ::Val{3}) = (Float64(x(p)), Float64(y(p)), Float64(z(p)))

"""
    _curve_segments(geom, ::Val{N})::Vector{_CurveSegment{N}}

Decompose a single curve (LineString, LinearRing, CircularString or CompoundCurve)
into straight and circular-arc segments.
"""
_curve_segments(geom, v::Val) = _curve_segments(geomtrait(geom), geom, v)

function _curve_segments(::AbstractLineStringTrait, geom, v::Val{N}) where N
    pts = [_tuplepoint(p, v) for p in getpoint(geom)]
    return Base.isempty(pts) ? _CurveSegment{N}[] : _CurveSegment{N}[_LineSegment(pts)]
end
function _curve_segments(::CircularStringTrait, geom, v::Val{N}) where N
    pts = [_tuplepoint(p, v) for p in getpoint(geom)]
    n = Base.length(pts)
    n == 0 && return _CurveSegment{N}[]
    (n >= 3 && isodd(n)) || throw(ArgumentError("A CircularString must have an odd number (≥ 3) of points, got $n"))
    return _CurveSegment{N}[_ArcSegment(pts[i], pts[i+1], pts[i+2]) for i in 1:2:n-2]
end
function _curve_segments(::CompoundCurveTrait, geom, v::Val{N}) where N
    segs = _CurveSegment{N}[]
    for sub in getgeom(geom)
        trait = geomtrait(sub)
        trait isa AbstractCurveTrait || throw(ArgumentError(
            "CompoundCurve members must be curves (LineString or CircularString), got $trait. " *
            "GeoInterface expects `getgeom` on a CompoundCurve to return its sections, not its points."))
        append!(segs, _curve_segments(trait, sub, v))
    end
    return segs
end
_curve_segments(trait, geom, ::Val) = throw(ArgumentError("Can't decompose a $trait into curve segments"))

"""
    _arc_parameters(p0, p1, p2)

Circle through three points, in XY. Returns `nothing` if the points are collinear
or coincident (the arc is then treated as the straight polyline `p0, p1, p2`, as
GDAL, GEOS and PostGIS do). Otherwise returns `(cx, cy, r, a0, a1, a2)` where the
angles are unwrapped so that `a0 ≤ a1 ≤ a2` for a counter-clockwise arc and
`a0 ≥ a1 ≥ a2` for a clockwise one. The sweep is `a2 - a0`.

If `p0 == p2` the arc is a full circle with `p1` diametrically opposite `p0`;
it is drawn counter-clockwise (like GDAL and PostGIS).
"""
function _arc_parameters(p0, p1, p2)
    x0, y0 = p0[1], p0[2]
    # Work relative to p0 for numerical stability
    bx, by = p1[1] - x0, p1[2] - y0
    cx, cy = p2[1] - x0, p2[2] - y0
    scale = max(abs(bx), abs(by), abs(cx), abs(cy))
    scale == 0 && return nothing # all points coincide
    if cx == 0 && cy == 0
        # Full circle: centre is midway between p0 and p1
        ux, uy = bx / 2, by / 2
        r = hypot(ux, uy)
        a0 = atan(-uy, -ux)
        return (x0 + ux, y0 + uy, r, a0, a0 + π, a0 + 2π)
    end
    d = 2 * (bx * cy - by * cx)
    # Same relative threshold idea as GDAL/PostGIS (1e-8), on scaled coordinates
    abs(d) <= 1e-8 * scale^2 && return nothing
    b2 = bx^2 + by^2
    c2 = cx^2 + cy^2
    ux = (cy * b2 - by * c2) / d
    uy = (bx * c2 - cx * b2) / d
    r = hypot(ux, uy)
    a0 = atan(-uy, -ux)
    a1 = atan(by - uy, bx - ux)
    a2 = atan(cy - uy, cx - ux)
    if d > 0 # counter-clockwise
        while a1 < a0; a1 += 2π; end
        while a2 < a1; a2 += 2π; end
    else # clockwise
        while a1 > a0; a1 -= 2π; end
        while a2 > a1; a2 -= 2π; end
    end
    return (x0 + ux, y0 + uy, r, a0, a1, a2)
end

"""
    _signed_area(segments)

Exact signed area enclosed by a closed sequence of segments
(positive = counter-clockwise), including the circular-segment area of each arc.
"""
function _signed_area(segs)
    A = 0.0
    shoelace(p, q) = (p[1] * q[2] - q[1] * p[2]) / 2
    for s in segs
        if s isa _LineSegment
            for i in 1:Base.length(s.points)-1
                A += shoelace(s.points[i], s.points[i+1])
            end
        else
            params = _arc_parameters(s.p0, s.p1, s.p2)
            if isnothing(params)
                A += shoelace(s.p0, s.p1) + shoelace(s.p1, s.p2)
            else
                _, _, r, a0, _, a2 = params
                θ = a2 - a0
                A += shoelace(s.p0, s.p2) + r^2 / 2 * (θ - sin(θ))
            end
        end
    end
    return A
end

"""
    _arc_nsegments(r, sweep; maxangle, tol)

Number of chords used to linearize an arc: at most `maxangle` radians per chord and,
if `tol` is given, a maximum chord-to-arc deviation of `tol` (in coordinate units).
"""
function _arc_nsegments(r, sweep; maxangle=deg2rad(4), tol=nothing)
    n = ceil(Int, abs(sweep) / maxangle)
    if !isnothing(tol) && tol < r
        n = max(n, ceil(Int, abs(sweep) / (2 * acos(1 - tol / r))))
    end
    return max(n, 2)
end

# Append the points of `seg` to `out`, without its start point.
function _linearize_segment!(out, s::_LineSegment; kw...)
    append!(out, @view s.points[2:end])
end
function _linearize_segment!(out::Vector{NTuple{N,Float64}}, s::_ArcSegment{N}; kw...) where N
    params = _arc_parameters(s.p0, s.p1, s.p2)
    if isnothing(params)
        push!(out, s.p1, s.p2)
        return out
    end
    cx, cy, r, a0, a1, a2 = params
    n = _arc_nsegments(r, a2 - a0; kw...)
    for i in 1:n-1
        a = a0 + (a2 - a0) * i / n
        if N == 2
            push!(out, (cx + r * cos(a), cy + r * sin(a)))
        else
            # Z: linear in angle, piecewise through the middle control point
            z = if (a - a1) * (a1 - a0) <= 0 && a1 != a0 # between a0 and a1
                s.p0[3] + (s.p1[3] - s.p0[3]) * (a - a0) / (a1 - a0)
            else
                s.p1[3] + (s.p2[3] - s.p1[3]) * (a - a1) / (a2 - a1)
            end
            push!(out, (cx + r * cos(a), cy + r * sin(a), z)[1:N])
        end
    end
    push!(out, s.p2) # end exactly on the control point
    return out
end

"""
    _linearize_segments(segs; maxangle=deg2rad(4), tol=nothing)

Linearize a segment chain into a vector of point tuples.
The default of 4° per chord matches GDAL's `OGR_ARC_STEPSIZE` and GEOS's `maxStepDegrees`.
"""
function _linearize_segments(segs::Vector{<:_CurveSegment{N}}; kw...) where N
    out = NTuple{N,Float64}[]
    Base.isempty(segs) && return out
    push!(out, _startpoint(first(segs)))
    for s in segs
        _linearize_segment!(out, s; kw...)
    end
    return out
end

_curve_dims(geom) = is3d(geom) ? Val(3) : Val(2)

"""
    _curve_parts(geom)

Return the exact structure of any 1D or 2D geometry as nested segment vectors:

- curves (`LineString`, `CircularString`, `CompoundCurve`, ...): `(:curve, [segments])`
- `MultiCurve`/`MultiLineString`: `(:curves, [[segments], ...])`
- `CurvePolygon`/`Polygon`: `(:surface, [[exterior segments], [hole segments]...])`
- `MultiSurface`/`MultiPolygon`: `(:surfaces, [[[rings]...], ...])`
"""
_curve_parts(geom) = _curve_parts(geomtrait(geom), geom, _curve_dims(geom))
_curve_parts(t::AbstractCurveTrait, geom, v) = (:curve, _curve_segments(t, geom, v))
_curve_parts(::AbstractMultiCurveTrait, geom, v) =
    (:curves, [_curve_segments(g, v) for g in getgeom(geom)])
_curve_parts(::AbstractCurvePolygonTrait, geom, v) =
    (:surface, [_curve_segments(r, v) for r in getgeom(geom)])
_curve_parts(::AbstractMultiSurfaceTrait, geom, v) =
    (:surfaces, [last(_curve_parts(geomtrait(g), g, v)) for g in getgeom(geom)])
_curve_parts(t, geom, v) = throw(ArgumentError("Can't decompose a $t into curves"))

"""
    _orient_rings(rings)

Orient rings so that the exterior (first ring) is counter-clockwise and holes are
clockwise. This makes the result fill correctly under both the nonzero and the
even-odd fill rules.
"""
function _orient_rings(rings)
    return map(enumerate(rings)) do (i, ring)
        A = _signed_area(ring)
        ((i == 1 && A < 0) || (i > 1 && A > 0)) ? _reverse_segments(ring) : ring
    end
end

const _CurvedTraits = Union{CircularStringTrait,CompoundCurveTrait,MultiCurveTrait,CurvePolygonTrait,MultiSurfaceTrait}

"""
    _hascurves(geom)

Whether `geom` is, or contains, a curved geometry that needs the curve code path.
"""
_hascurves(geom) = geomtrait(geom) isa _CurvedTraits

# Bounding box diagonal of all control points in a (nested) segment structure.
function _control_diagonal(parts)
    xmin = ymin = Inf
    xmax = ymax = -Inf
    visit(s::_LineSegment) = foreach(visit, s.points)
    visit(s::_ArcSegment) = (visit(s.p0); visit(s.p1); visit(s.p2))
    visit(p::Tuple) = (xmin = min(xmin, p[1]); xmax = max(xmax, p[1]); ymin = min(ymin, p[2]); ymax = max(ymax, p[2]))
    visit(v::AbstractVector) = foreach(visit, v)
    visit(parts)
    return isfinite(xmin) ? hypot(xmax - xmin, ymax - ymin) : 0.0
end

"""
    _resolve_tolerance(tol, parts)

`tol === :auto` gives a chord-to-arc deviation of 1e-4 of the geometry's size:
about 0.1 px when the whole geometry fills a 1000 px plot.
"""
function _resolve_tolerance(tol, parts)
    tol === :auto || return tol
    d = _control_diagonal(parts)
    return d > 0 ? 1e-4 * d : nothing
end
