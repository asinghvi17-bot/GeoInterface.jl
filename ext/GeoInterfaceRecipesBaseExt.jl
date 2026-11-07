module GeoInterfaceRecipesBaseExt

using GeoInterface
using RecipesBase

const GI = GeoInterface

function GI._plots_apply_recipe(plotattributes, geom)
    @nospecialize
    series_list = RecipesBase.RecipeData[]
    RecipesBase.is_explicit(plotattributes, :label) || (plotattributes[:label] = :none)
    Base.push!(series_list, RecipesBase.RecipeData(plotattributes, (GeoInterface.trait(geom), geom)))
    return series_list
end

function GI._plots_apply_recipe_array(plotattributes, geom)
    @nospecialize
    series_list = RecipesBase.RecipeData[]
    RecipesBase.is_explicit(plotattributes, :label) || (plotattributes[:label] = :none)
    for g in Base.skipmissing(geom)
        Base.push!(series_list, RecipesBase.RecipeData(plotattributes, (GeoInterface.trait(g), g)))
    end
    return series_list
end

RecipesBase.@recipe function f(t::Union{GI.PointTrait,GI.MultiPointTrait}, geom)
    seriestype --> :scatter
    _coordvecs(t, geom)
end
RecipesBase.@recipe function f(t::Union{GI.AbstractLineStringTrait,GI.MultiLineStringTrait}, geom)
    seriestype --> :path
    _coordvecs(t, geom)
end
RecipesBase.@recipe function f(t::Union{GI.PolygonTrait,GI.MultiPolygonTrait,GI.LinearRingTrait}, geom)
    seriestype --> :shape
    _coordvecs(t, geom)
end
# Curved geometries. Plots.jl and its backends only draw polylines and filled
# polygons, so arcs are linearized here: at most `curve_maxangle` degrees per chord
# (default 4, as GDAL and GEOS), and at most `curve_tol` coordinate units between
# chord and arc (default `:auto`, 1e-4 of the geometry's size; `nothing` disables).
RecipesBase.@recipe function f(t::Union{GI.CircularStringTrait,GI.CompoundCurveTrait,GI.MultiCurveTrait}, geom)
    maxangle = pop!(plotattributes, :curve_maxangle, 4)
    tol = pop!(plotattributes, :curve_tol, :auto)
    seriestype --> :path
    _curve_coordvecs(geom; maxangle=deg2rad(maxangle), tol)
end
RecipesBase.@recipe function f(t::Union{GI.CurvePolygonTrait,GI.MultiSurfaceTrait}, geom)
    maxangle = pop!(plotattributes, :curve_maxangle, 4)
    tol = pop!(plotattributes, :curve_tol, :auto)
    seriestype --> :shape
    _curve_coordvecs(geom; maxangle=deg2rad(maxangle), tol)
end
RecipesBase.@recipe f(::GI.GeometryCollectionTrait, collection) = collect(getgeom(collection))
# Features
RecipesBase.@recipe f(t::GI.FeatureTrait, feature) = GI.geometry(feature)
RecipesBase.@recipe f(t::GI.FeatureCollectionTrait, fc) = collect(GI.getfeature(fc))

# Convert coordinates to the form used by Plots.jl
_coordvecs(::GI.PointTrait, geom) = [tuple(GI.coordinates(geom)...)]
function _coordvecs(::GI.MultiPointTrait, geom)
    n = GI.npoint(geom)
    # We use a fixed conditional instead of dispatch,
    # as `is3d` may not be known at compile-time
    if GI.is3d(geom)
        _geom2coordvecs!(ntuple(_ -> Array{Float64}(undef, n), 3)..., geom)
    else
        _geom2coordvecs!(ntuple(_ -> Array{Float64}(undef, n), 2)..., geom)
    end
end
function _coordvecs(::GI.AbstractLineStringTrait, geom)
    n = GI.npoint(geom)
    if GI.is3d(geom)
        vecs = ntuple(_ -> Array{Float64}(undef, n), 3)
        return _geom2coordvecs!(vecs..., geom)
    else
        vecs = ntuple(_ -> Array{Float64}(undef, n), 2)
        return _geom2coordvecs!(vecs..., geom)
    end
end
function _coordvecs(::GI.MultiLineStringTrait, geom)
    function loop!(vecs, geom)
        i1 = 1
        for line in GI.getgeom(geom)
            i2 = i1 + GI.npoint(line) - 1
            vvecs = map(v -> view(v, i1:i2), vecs)
            _geom2coordvecs!(vvecs..., line)
            map(v -> v[i2 + 1] = NaN, vecs)
            i1 = i2 + 2
        end
        return vecs
    end
    n = GI.npoint(geom) + GI.ngeom(geom)
    if GI.is3d(geom)
        vecs = ntuple(_ -> Array{Float64}(undef, n), 3)
        return loop!(vecs, geom)
    else
        vecs = ntuple(_ -> Array{Float64}(undef, n), 2)
        return loop!(vecs, geom)
    end
end
function _coordvecs(::GI.LinearRingTrait, geom)
    points = GI.getpoint(geom)
    if GI.is3d(geom)
        return getcoord.(points, 1), getcoord.(points, 2), getcoord.(points, 3)
    else
        return getcoord.(points, 1), getcoord.(points, 2)
    end
end
function _coordvecs(::GI.PolygonTrait, geom)
    ring = first(GI.getgeom(geom)) # currently doesn't plot holes
    points = GI.getpoint(ring)
    if GI.is3d(geom)
        return getcoord.(points, 1), getcoord.(points, 2), getcoord.(points, 3)
    else
        return getcoord.(points, 1), getcoord.(points, 2)
    end
end
function _coordvecs(::GI.MultiPolygonTrait, geom)
    function loop!(vecs, geom)
        i1 = 1
        for ring in GI.getring(geom)
            i2 = i1 + GI.npoint(ring) - 1
            range = i1:i2
            vvecs = map(v -> view(v, range), vecs)
            _geom2coordvecs!(vvecs..., ring)
            map(v -> v[i2 + 1] = NaN, vecs)
            i1 = i2 + 2
        end
        return vecs
    end
    n = GI.npoint(geom) + GI.nring(geom)
    if GI.is3d(geom)
        vecs = ntuple(_ -> Array{Float64}(undef, n), 3)
        return loop!(vecs, geom)
    else
        vecs = ntuple(_ -> Array{Float64}(undef, n), 2)
        return loop!(vecs, geom)
    end
end


_coordvec(n) = Array{Float64}(undef, n)

# Linearize any curve or surface into NaN-separated coordinate vectors.
# Like the MultiPolygon recipe, rings are separate NaN-separated subpaths
# (Plots.jl shapes have no notion of holes).
function _curve_coordvecs(geom; maxangle, tol)
    kind, parts = GI._curve_parts(geom)
    kw = (; maxangle, tol=GI._resolve_tolerance(tol, parts))
    chains = if kind === :curve
        [parts]
    elseif kind === :curves
        parts
    elseif kind === :surface
        GI._orient_rings(parts)
    else
        reduce(vcat, map(GI._orient_rings, parts); init=eltype(eltype(parts))[])
    end
    N = GI.is3d(geom) ? 3 : 2
    vecs = ntuple(_ -> Float64[], N)
    for chain in chains
        isempty(chain) && continue
        isempty(vecs[1]) || foreach(v -> push!(v, NaN), vecs)
        for p in GI._linearize_segments(chain; kw...)
            foreach(i -> push!(vecs[i], p[i]), 1:N)
        end
    end
    return vecs
end

function _geom2coordvecs!(xs, ys, geom)
    for (i, p) in enumerate(GI.getpoint(geom))
        xs[i] = GI.x(p)
        ys[i] = GI.y(p)
    end
    return xs, ys
end
function _geom2coordvecs!(xs, ys, zs, geom)
    for (i, p) in enumerate(GI.getpoint(geom))
        xs[i] = GI.x(p)
        ys[i] = GI.y(p)
        zs[i] = GI.z(p)
    end
    return xs, ys, zs
end

# Enable Plots.jl for GeoInterface wrappers
GeoInterface.@enable_plots RecipesBase GeoInterface.WrapperGeometry
GeoInterface.@enable_plots RecipesBase GeoInterface.Feature
GeoInterface.@enable_plots RecipesBase GeoInterface.FeatureCollection

end
