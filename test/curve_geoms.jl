# Minimal curved geometry types implementing GeoInterface, for tests and examples.
# GeoInterface has no wrappers for CircularString/CompoundCurve/CurvePolygon/MultiSurface yet.
module CurveGeoms

import GeoInterface as GI
export TCircularString, TCompoundCurve, TCurvePolygon, TMultiCurve, TMultiSurface

struct TCircularString{P}
    points::Vector{P}
end
struct TCompoundCurve{S}
    sections::Vector{S}
end
struct TCurvePolygon{R}
    rings::Vector{R}
end
struct TMultiCurve{C}
    curves::Vector{C}
end
struct TMultiSurface{S}
    surfaces::Vector{S}
end

for (T, trait, field) in (
        (:TCircularString, :CircularStringTrait, :points),
        (:TCompoundCurve, :CompoundCurveTrait, :sections),
        (:TCurvePolygon, :CurvePolygonTrait, :rings),
        (:TMultiCurve, :MultiCurveTrait, :curves),
        (:TMultiSurface, :MultiSurfaceTrait, :surfaces),
    )
    @eval begin
        GI.isgeometry(::Type{<:$T}) = true
        GI.geomtrait(::$T) = GI.$trait()
        GI.ngeom(::GI.$trait, g::$T) = length(g.$field)
        GI.getgeom(::GI.$trait, g::$T, i::Integer) = g.$field[i]
        GI.is3d(::GI.$trait, g::$T) = GI.is3d(first(GI.getpoint(g)))
        GI.ismeasured(::GI.$trait, g::$T) = false
    end
end
# A CircularString's children are its points; compound/polygon/multi types nest
GI.npoint(::GI.CircularStringTrait, g::TCircularString) = length(g.points)
GI.getpoint(::GI.CircularStringTrait, g::TCircularString, i::Integer) = g.points[i]
GI.getpoint(::GI.CircularStringTrait, g::TCircularString) = g.points
GI.is3d(::GI.CircularStringTrait, g::TCircularString) = length(first(g.points)) == 3
GI.is3d(t::GI.CompoundCurveTrait, g::TCompoundCurve) = GI.is3d(first(g.sections))
GI.is3d(t::GI.CurvePolygonTrait, g::TCurvePolygon) = GI.is3d(first(g.rings))
GI.is3d(t::GI.MultiCurveTrait, g::TMultiCurve) = GI.is3d(first(g.curves))
GI.is3d(t::GI.MultiSurfaceTrait, g::TMultiSurface) = GI.is3d(first(g.surfaces))

# Enable plotting for these types (the same macros packages like LibGEOS use)
function enable_makie(Makie)
    for T in (TCircularString, TCompoundCurve, TCurvePolygon, TMultiCurve, TMultiSurface)
        @eval GI.@enable_makie $Makie $T
    end
end
function enable_plots(RecipesBase)
    for T in (TCircularString, TCompoundCurve, TCurvePolygon, TMultiCurve, TMultiSurface)
        @eval GI.@enable_plots $RecipesBase $T
    end
end

end
