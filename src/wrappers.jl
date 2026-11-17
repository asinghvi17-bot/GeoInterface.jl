"""
    Wrappers

Geometry, Feature, and FeatureCollection wrappers for constructing ad-hoc
geometry objects from any GeoInterface.jl compatible geometries, or
vectors of them.

These are not exported by default, due to the names being so common.
To bring them into your local scope, do:

```juila
using GeoInterface.Wrappers
```

Otherwise they can be accessed as:

```julia
GeoInterface.Polygon
```
"""
module Wrappers

import Extents

import ..GeoInterface: AbstractGeometryTrait, AbstractMultiPointTrait, PointTrait, LineTrait, LineStringTrait, LinearRingTrait,
       MultiPointTrait, PolygonTrait, MultiLineStringTrait, MultiCurveTrait, MultiPolygonTrait,
       AbstractCurveTrait, GeometryCollectionTrait, FeatureTrait, FeatureCollectionTrait, PointTuple3,
       PolyhedralSurfaceTrait, TriangleTrait, QuadTrait, PentagonTrait, HexagonTrait, RectangleTrait, TINTrait

import ..GeoInterface: isgeometry, isfeature, isfeaturecollection, is3d, ismeasured,
       trait, geomtrait, convert, x, y, z, m, extent, crs,
       getgeom, getpoint, getring, gethole, getcoord, coordinates,
       ngeom, npoint, nring, nhole, ncoord,
       nfeature, getfeature, geometry, properties

export WrapperGeometry, Point, Line, LineString, LinearRing, Polygon, MultiPoint, MultiPolygon, MultiLineString, MultiCurve,
    PolyhedralSurface, GeometryCollection, Feature, FeatureCollection

# TODO
# Triangle, Quad, Pentagon, Hexagon, TIN, Surface


# Implement interface

"""
    abstract type WrapperGeometry{Z,M,T}

Provides geometry wrappers that wrap any GeoInterface compatible
objects, or vectors or their child objects.

These can be useful for building custom geometries, in tests,
and in packages with no direct dependencies on specific geometry
types.

Parameters `Z` and `M` hold `Bool` values `true` or `false`
to indicate if a z dimension or measures are present. They are
usually detected from the wrapped object, but can be added manually
e.g. for `Tuple` or `Vector` points to have the third value used as
measures.
"""
abstract type WrapperGeometry{Z,M,T,C} end

isgeometry(::Type{<:WrapperGeometry}) = true
is3d(::AbstractGeometryTrait, ::WrapperGeometry{Z}) where Z = Z
ismeasured(::AbstractGeometryTrait, ::WrapperGeometry{<:Any,M})  where M = M
ncoord(::AbstractGeometryTrait, ::WrapperGeometry{Z, M}) where {Z, M} = 2 + Z + M

Base.parent(geom::WrapperGeometry) = geom.geom

function Base.:(==)(g1::WrapperGeometry, g2::WrapperGeometry)
    ngeom(g1) == ngeom(g2) && all(((a, b),) -> a == b, zip(getgeom(g1), getgeom(g2)))
end

# Interface methods
# With indexing
function getgeom(trait::AbstractGeometryTrait, geom::WrapperGeometry{<:Any,<:Any,T}, i) where T
    isgeometry(T) ? getgeom(trait, parent(geom), i) : parent(geom)[i]
end
function getgeom(trait::AbstractGeometryTrait, geom::WrapperGeometry{<:Any,<:Any,T}) where T
    isgeometry(T) ? getgeom(trait, parent(geom)) : parent(geom)
end

extent(::AbstractGeometryTrait, geom::WrapperGeometry) =
    isnothing(geom.extent) && isgeometry(parent(geom)) ? extent(parent(geom)) : geom.extent
crs(::AbstractGeometryTrait, geom::WrapperGeometry) =
    isnothing(geom.crs) && isgeometry(parent(geom)) ? crs(parent(geom)) : geom.crs
function ngeom(trait::AbstractGeometryTrait, geom::WrapperGeometry{<:Any,<:Any,T}) where T
    isgeometry(T) ? ngeom(parent(geom)) : length(parent(geom))
end

# Forward all 2-argument show calls to the 3-argument version
# with a "text/plain" MIME type.  This gives us a consistent target
# to implement the show methods.
Base.show(io::IO, geom::WrapperGeometry) = show(io, MIME"text/plain"(), geom)

# We define all the types in a loop so we have standardised docs and behaviour
# without too much repetition of code.
# `child_trait` and `child_type` define the trait and type of child geometries
# a geometry can be constructed from.
# `length_check` limits some types to specific number of points, defined with a Fix2 or function
# `nesting` indicates how many layers of point vectors need to be used to construct the object.
for (geomtype, trait, childtype, child_trait, length_check, nesting) in (
        (:Line, :LineTrait, :Point, :PointTrait, ==(2), 1),
        (:LineString, :LineStringTrait, :Point, :PointTrait, >=(2), 1),
        (:LinearRing, :LinearRingTrait, :Point, :PointTrait, >=(3), 1),
        (:MultiPoint, :MultiPointTrait, :Point, :PointTrait, nothing, 1),
        (:Polygon, :PolygonTrait, :LinearRing, :AbstractCurveTrait, nothing, 2),
        (:MultiLineString, :MultiLineStringTrait, :LineString, :LineStringTrait, nothing, 2),
        (:MultiCurve, :MultiCurveTrait, :LineString, :AbstractCurveTrait, nothing, 2),
        (:MultiPolygon, :MultiPolygonTrait, :Polygon, :PolygonTrait, nothing, 3),
        (:GeometryCollection, :GeometryCollectionTrait, :AbstractGeometry, :AbstractGeometryTrait, nothing, nothing),
        (:PolyhedralSurface, :PolyhedralSurfaceTrait, :Polygon, :PolygonTrait, nothing, 3),
        # (:Triangle, :TriangleTrait, :LinearRingTrait, :LinearRing, ==(3), 2),
        # (:Quad, :QuadTrait, :LinearRingTrait, :LinearRing, ==(4), 2),
        # (:Pentagon, :PentagonTrait, :LinearRingTrait, :LinearRing, ==(5), 2),
        # (:Hexagon, :HexagonTrait, :LinearRingTrait, :LinearRing, ==(6), 2),
        # (:Rectangle, :RectangleTrait, :Point, :PointTrait, nothing, 1), ?
        # (:TIN, :TINTrait, :Triangle, :TriangleTrait, nothing, 3),
    )

    # Prepare docstring example
    childname = lowercase(string(childtype))
    example_child_geoms = if geomtype == :Polygon
        "interior, hole1, hole2"
    else
        join((string(childname, n) for n in 1:(isnothing(length_check) ? 3 : length_check.x)), ", ")
    end
    docstring = """
        $geomtype

        $geomtype(geom; [extent, crs])
        $geomtype{Z,M}(geom; [extent, crs])

    ## Arguments

    - `geom`: any object returning $trait from `GeoInterface.trait`, or a vector
        of objects returning $child_trait.

    ## Keywords
    
    - `extent`: an `Extents.Extent`, or `nothing`.
    - `crs`: a `GeoFormatTypes.GeoFormat`, or `nothing`.

    ## Type Parameters (optional)

    These are usually detected from the parent object properties.

    - `Z`: `true` or `false` if there is a z dimension.
    - `M`: `true` or `false` if there are measures.

    ## Examples

    ```julia
    geom = $geomtype(geometry)
    ```

    Or with child objects with [`$child_trait`](@ref):

    ```julia
    geom = $geomtype([$example_child_geoms])
    ```
    """
    @eval begin
        @doc $docstring
        struct $geomtype{Z,M,T,E<:Union{Nothing,Extents.Extent},C} <: WrapperGeometry{Z,M,T,C}
            geom::T
            extent::E
            crs::C
        end
        $geomtype(geom::$geomtype; kw...) =
            $geomtype(parent(geom); extent=geom.extent, crs=geom.crs, kw...)
        $geomtype(geom; kw...) = $geomtype{nothing,nothing}(geom; kw...)
        geomtrait(::$geomtype) = $trait()
        geointerface_geomtype(::$trait) = $geomtype
        # Here converting means wrapping
        convert(::Type{$geomtype}, ::$trait, geom) = $geomtype(geom)
        # But not if geom is already a WrapperGeometry
        convert(::Type{$geomtype}, ::$trait, geom::$geomtype) = geom
        
        function Base.show(io::IO, ::MIME"text/plain", geom::$geomtype{Z, M, T, E, C}; 
            show_mz::Bool = true, screen_ncols::Int = displaysize(io)[2]
        ) where {Z, M, T, E <: Union{Nothing,Extents.Extent}, C}
            compact = get(io, :compact, false)
            spacing = compact ? "" : " "
            show_mz &= !compact

            extent_str = ""
            crs_str = ""
            if !compact
                if !isnothing(geom.extent)
                    extent_str = ",$(spacing)extent$(spacing)=$(spacing)$(repr(MIME"text/plain"(), geom.extent))"
                end
                if !isnothing(geom.crs)
                    crs_str = ",$(spacing)crs$(spacing)=$(spacing)\"$(repr(MIME"text/plain"(), geom.crs))\""
                end
            end

            str = string($geomtype)
            if show_mz
                str *= "{$Z,$(spacing)$M}"
            end
            str *= "("
            limited = get(io, :limit, false)
            # keep track of how much space we've used + make sure we give this info to any child geoms so they don't go over the limit
            currently_used_space = textwidth(str) + textwidth(extent_str) + textwidth(crs_str)
            indexed = (compact || limited) && isgeometry(T)
            children = indexed ? nothing : getgeom(trait(geom), geom)
            root = indexed ? _Node(parent(geom)) : nothing
            # a foreign geometry is read to show it, so do not use more than a wide display allows
            available_space = (indexed ? min(screen_ncols, MAX_FOREIGN_WIDTH) : screen_ncols) - currently_used_space
            child(i) = indexed ? _child!(root, i) : _Node(children[i])
            if indexed || children isa AbstractVector
                n = indexed ? ngeom(geom) : length(children)
                bounded, _ = _children_str(child, n, compact, limited, available_space)
                # a foreign geometry with its own display is shown as is, if that fits
                own_str = indexed ? _own_str(root, available_space - 1) : nothing
                str *= something(own_str, bounded)
            else
                str *= _nice_geom_str(parent(geom), false, compact, screen_ncols - currently_used_space, limited)
            end

            str *= extent_str
            str *= crs_str
            
            str *= ")"
            print(io, str)
            return nothing
        end
    end

    @eval function $geomtype{Z,M}(geom::T; extent::E=nothing, crs::C=nothing) where {Z,M,T,E,C}
        Z isa Union{Bool,Nothing} || throw(ArgumentError("Z Parameter must be `true`, `false` or `nothing`"))
        M isa Union{Bool,Nothing} || throw(ArgumentError("M Parameter must be `true`, `false` or `nothing`"))

        # Is geom a single geometry ?
        if isgeometry(geom)
            if geomtrait(geom) isa $child_trait
                # If geom is a child_trait, then make geom a vector and call again
                return $geomtype([geom]; extent, crs)
            else
                # Wrap some geometry at the same level
                geomtrait(geom) isa $trait || _argument_error(T, $trait)
                Z1 = isnothing(Z) ? is3d(geom) : Z
                M1 = isnothing(M) ? ismeasured(geom) : M
                return $geomtype{Z1,M1,T,E,C}(geom, extent, crs)
            end

        # Otherwise wrap an array of child geometries
        elseif geom isa AbstractArray
            child = first(geom)
            children_match = findfirst(child -> !(geomtrait(child) isa $child_trait), geom)

            # Where the next level down is the child geometry
            if isnothing(children_match)
                if $(!isnothing(length_check))
                    $length_check(Base.length(geom)) || _length_error($geomtype, $length_check, geom)
                end
                Z1 = isnothing(Z) ? is3d(first(geom)) : Z
                M1 = isnothing(M) ? ismeasured(first(geom)) : M
                return $geomtype{Z1,M1,T,E,C}(geom, extent, crs)

            # Where we have nested points, as in `coordinates(geom)`
            else
                if child isa AbstractArray
                    if $nesting === 2
                        all(child2 -> geomtrait(child2) isa PointTrait, child) || _parent_type_error($geomtype, $child_trait, geom)
                        Z1 = isnothing(Z) ? is3d(first(child)) : Z
                        M1 = isnothing(M) ? ismeasured(first(child)) : M
                        childtype = $childtype
                        newgeom = childtype.(geom)
                        return $geomtype{Z1,M1,typeof(newgeom),E,C}(newgeom, extent, crs)
                    elseif $nesting === 3
                        all(child) do child2
                            child2 isa AbstractArray && all(child3 -> geomtrait(child3) isa PointTrait, child2)
                        end || _parent_type_error($geomtype, $child_trait, geom)
                        Z1 = isnothing(Z) ? is3d(first(first(child))) : Z
                        M1 = isnothing(M) ? ismeasured(first(first(child))) : M
                        childtype = $childtype
                        newgeom = childtype.(geom)
                        return $geomtype{Z1,M1,typeof(newgeom),E,C}(newgeom, extent, crs)
                    end
                end
                # Otherwise compain the nested child type is wrong
                _wrong_child_error($trait, $child_trait, geom[children_match])
            end
        else
            # Or complain the parent type is wrong
            _parent_type_error($geomtype, $child_trait, geom)
        end
    end
end

# The string for `n` children, and its width if the children were labeled with the name of a wrapper. How
# many children are shown, and so read, depends on that width, not on the label or display that is used.
function _children_str(child, n, compact, limited, width)
    n = Int(n) # backends may count with other integer types
    n == 0 && return "[]", 2
    spacing = compact ? "" : " "
    available = width - 2 # brackets
    child_width = fld(available, n)
    function render(i)
        node = child(i)
        geom = node.geom
        if (compact || limited) && !(geom isa WrapperGeometry) && isgeometry(geom)
            t = geomtrait(geom)
            if !(t isa PointTrait)
                name = _kind_name(t, geom)
                if !applicable(geointerface_geomtype, t)
                    # not a kind we wrap: reading its children may not be supported
                    bounded, bounded_width = name * "(…)", textwidth(name) + 3
                else
                    label_width = textwidth(string(@__MODULE__, ".", nameof(geointerface_geomtype(t))))
                    remaining = child_width - label_width - 2
                    nchildren = ngeom(t, geom)
                    if nchildren == 0
                        bounded, bounded_width = name * "([])", label_width + 4
                    elseif remaining <= 2
                        bounded, bounded_width = name * "(…)", label_width + 3
                    else
                        children, children_width = _children_str(k -> _child!(node, k), nchildren, compact, limited, remaining)
                        bounded, bounded_width = name * "(" * children * ")", label_width + children_width + 2
                    end
                end
                return something(_own_str(node, child_width), bounded), bounded_width
            end
        end
        shown = _nice_geom_str(geom, false, compact, child_width, limited)
        return shown, textwidth(shown)
    end
    first_child, first_width = render(1)
    n == 1 && return "[" * first_child * "]", first_width + 2

    visible = clamp(fld(available - 1, max(1, first_width)), 2, n)
    left, right = cld(visible, 2), fld(visible, 2)
    rendered = [(first_child, first_width)]
    for i in 2:left
        push!(rendered, render(i))
    end
    if visible < n
        elision = "…$(spacing)($(n - visible))$(spacing)…$(spacing)"
        push!(rendered, (elision, textwidth(elision)))
    end
    for i in (n - right + 1):n
        push!(rendered, render(i))
    end
    separator = "," * spacing
    return "[" * join(first.(rendered), separator) * "]", 2 + sum(last, rendered) + (length(rendered) - 1) * textwidth(separator)
end

# The kind of a foreign geometry, also for traits without a wrapper such as `CircularStringTrait`.
function _kind_name(t, geom)
    applicable(geointerface_geomtype, t) && return string(nameof(geointerface_geomtype(t)))
    t isa AbstractGeometryTrait && return chopsuffix(string(nameof(typeof(t))), "Trait")
    return string(nameof(typeof(geom)))
end

function _has_own_show(::Type{T}) where T
    (T <: Union{WrapperGeometry,AbstractArray,Tuple,NamedTuple} || !isgeometry(T)) && return false
    try
        # `text/plain` falls back to `show(io, x)`, so only look at that if there is no method for `text/plain`
        Base.moduleroot(parentmodule(which(show, Tuple{IO,MIME"text/plain",T}))) !== Base ||
            Base.moduleroot(parentmodule(which(show, Tuple{IO,T}))) !== Base
    catch # no or an ambiguous method: use the bounded display
        false
    end
end

# A geometry and the children of it read so far. Reading a child can be expensive (LibGEOS copies it),
# so within one `show` only the children the bounded display needs are read, and the check
# whether a display fits only looks at those.
mutable struct _Node
    geom::Any
    children::Union{Nothing,Dict{Int,_Node}}
end
_Node(geom) = _Node(geom, nothing)
function _child!(node::_Node, i::Int)
    isnothing(node.children) && (node.children = Dict{Int,_Node}())
    return get!(() -> _Node(getgeom(geomtrait(node.geom), node.geom, i)), node.children, i)
end

# Whether a geometry that is shown has at most `width` geometries, counting all siblings and nesting
# levels, each as at least one character. This only uses what has been read and counts, as reading a
# child of a foreign geometry can copy all of it. So a geometry of which children were not all shown is not
# known to be small. Curves and multipoints have points as children, which do not have to be read.
# The count is capped, so a very wide display does not let us print very large geometries in full.
const MAX_FIT_GEOMETRIES = 256
const MAX_FOREIGN_WIDTH = 1000
_may_fit(node::_Node, width::Int) = _may_fit!(Ref(min(width, MAX_FIT_GEOMETRIES)), node)
function _may_fit!(budget, node::_Node)
    (budget[] -= 1) >= 0 || return false
    t = geomtrait(node.geom)
    t isa PointTrait && return true
    t isa AbstractGeometryTrait || return false
    n = ngeom(t, node.geom)
    n <= budget[] || return false
    if t isa Union{AbstractCurveTrait,AbstractMultiPointTrait}
        budget[] -= n
        return true
    end
    n == 0 && return true
    children = node.children
    return !isnothing(children) && length(children) == n && all(i -> _may_fit!(budget, children[i]), 1:n)
end

# The text/plain display of a foreign geometry if it has its own and fits in `width`, else `nothing`.
# It is not shown compactly: for e.g. LibGEOS that is just `Polygon(...)`. Not being able to tell whether
# it fits, or a display that does not work here, is not an error: the bounded display is used.
function _own_str(node::_Node, width::Int)
    try
        width > 0 && _may_fit(node, width) || return nothing
        str = sprint(show, MIME"text/plain"(), node.geom; context = (:limit => true, :displaysize => (24, width)))
        # looking for a display is slower than showing, so only do so for what fits
        return textwidth(str) <= width && !('\n' in str) && _has_own_show(typeof(node.geom)) ? str : nothing
    catch e
        e isa InterruptException && rethrow()
        return nothing
    end
end

function _nice_geom_str(geom, show_mz::Bool, compact::Bool, width::Int, limited::Bool)
    buf = IOBuffer()
    io = compact || limited ? IOContext(buf, :compact => compact, :limit => limited, :displaysize => (24, max(1, width))) : buf
    show(io, MIME"text/plain"(), geom)
    return String(take!(buf))
end
# need a work around to pass the show_mz variable through - put string to a temp IOBuffer then read it
function _nice_geom_str(geom::WrapperGeometry, show_mz::Bool, compact::Bool, screen_ncols::Int, limited::Bool)
    buf = IOBuffer()
    io = IOContext(buf, :compact => compact, :limit => limited)
    show(io, MIME"text/plain"(), geom; show_mz = show_mz, screen_ncols = screen_ncols)
    return String(take!(buf))
end
# handle tuples/vectors explicitly
function _nice_geom_str(geom::AbstractVector, ::Bool, compact::Bool, ::Int, ::Bool)
    spacing = compact ? "" : " "
    str = "["
    str *= _add_elements_with_spacing(geom, spacing)
    str *= "]"
    return str
end
function _nice_geom_str(geom::Tuple, ::Bool, compact::Bool, ::Int, ::Bool)
    spacing = compact ? "" : " "
    str = "("
    str *= _add_elements_with_spacing(geom, spacing)
    str *= ")"
    return str
end

function _add_elements_with_spacing(itr, spacing::String = "")
    str = ""
    for x ∈ itr[1:end - 1]
        str *= "$(x),$(spacing)"
    end
    str *= "$(itr[end])"
end

@noinline _wrong_child_error(geomtype, C, child) = throw(ArgumentError("$geomtype must have child objects with trait $C, got $(typeof(child)) with trait $(geomtrait(child))"))
@noinline _argument_error(T, A) = throw(ArgumentError("$T does not have $A"))
@noinline _length_error(T, f, x) = throw(ArgumentError("Length of array must be $(f.f) $(f.x) for $T"))
@noinline _parent_type_error(trait, child_trait, geom) = throw(ArgumentError("Object $geom is not a $trait geometry or array of $child_trait child geometries"))
@noinline _not_a_point_error(geom) = throw(ArgumentError("Object $geom is not a PointTrait geometry"))

"""
    Point
    Point(geom)
    Point{Z,M}(geom)
    Point(; X, Y, [Z, M])

## Arguments

- `geom`: any object returning `PontTrait` from `GeoInterface.trait`.

## Parameters (optional)

These can be used to force points to be interpreted with
measures or z dimension.

- `Z`: `true` or `false` if there is a z dimension.
- `M`: `true` or `false` if there are measures.

# Example

```jldoctest
using GeoInterface
using GeoInterface.Wrappers
point = Point{false,true}([1, 2, 3])
@assert GeoInterface.ismeasured(point) == true
@assert GeoInterface.is3d(point) == false
GeoInterface.m(point)
# output
3
```
"""
struct Point{Z,M,T,C} <: WrapperGeometry{Z,M,T,C}
    geom::T
    crs::C
end
function Point{Z,M}(geom::T; crs::C=nothing) where {Z,M,T,C}
    expected_coords = 2 + Z + M
    ncoord(geom) == expected_coords || _coord_length_error(Z, M, ncoord(geom))
    Point{Z,M,T,C}(geom, crs)
end
Point(x::Real, y::Real, args::Real...; crs=nothing) = Point((x, y, args...); crs)
Point{Z,M}(x::Real, y::Real, args::Real...; crs=nothing) where {Z,M} = Point{Z,M}((x, y, args...); crs)
function Point(; X::Real, Y::Real, Z::Union{Real,Nothing}=nothing, M::Union{Real,Nothing}=nothing, crs=nothing)
    p = (; X, Y)
    if !isnothing(Z)
        p = merge(p, (; Z))
    end
    if !isnothing(M)
        p = merge(p, (; M))
    end
    return Point(p; crs)
end
function Point(geom::T; crs::C=nothing) where {T,C}
    geomtrait(geom) isa PointTrait || _not_a_point_error(geom)
    if is3d(geom) && ismeasured(geom)
        return Point{true,true,T,C}(geom, crs)
    elseif is3d(geom)
        return Point{true,false,T,C}(geom, crs)
    elseif ismeasured(geom)
        return Point{false,true,T,C}(geom, crs)
    else
        return Point{false,false,T,C}(geom, crs)
    end
end
Point(point::Point{Z,M,T}; crs::C=crs(point)) where {Z,M,T,C} = 
    Point{Z,M,T,C}(parent(point), crs)

geointerface_geomtype(::PointTrait) = Point

isgeometry(::Type{<:Point}) = true
geomtrait(geom::Point) = PointTrait()
ncoord(trait::PointTrait, geom::Point) = ncoord(trait, parent(geom))
getcoord(trait::PointTrait, geom::Point, i::Integer) = getcoord(trait, parent(geom), i)
convert(::Type{Point}, ::PointTrait, geom) = Point(geom)
convert(::Type{Point}, ::PointTrait, geom::Point) = geom
extent(trait::PointTrait, geom::Point) = extent(trait, parent(geom)) 

ngeom(::PointTrait, geom::Point) = error("`GI.ngeom` on a Point is not allowed!  To get the number of dimensions use `GI.ncoord` instead.")
getgeom(::PointTrait, geom::Point) = error("`GI.getgeom` on a Point is not allowed!  To get the number of dimensions use `GI.getcoord` instead, or `GI.x, GI.y, GI.z, GI.t`")
getgeom(::PointTrait, geom::Point, i) = error("`GI.getgeom` on a Point is not allowed!  To get the number of dimensions use `GI.getcoord` instead, or `GI.x, GI.y, GI.z, GI.t`")

coordtype(::Point{<:Any,<:Any,<:AbstractArray{T}}) where T = T 
coordtype(::Point{<:Any,<:Any,<:NTuple{<:Any,T}}) where T = T 
coordtype(::Point{<:Any,<:Any,<:NamedTuple{<:Any,<:NTuple{<:Any,T}}}) where T = T 
coordtype(p::Point) = coordtype(parent(p))

x(trait::PointTrait, geom::Point) = x(trait, parent(geom))
y(trait::PointTrait, geom::Point) = y(trait, parent(geom))
z(trait::PointTrait, geom::Point{true}) = z(trait, parent(geom))
z(trait::PointTrait, geom::Point{false}) = _no_z_error()
m(trait::PointTrait, geom::Point{<:Any,false}) = _no_m_error()
m(trait::PointTrait, geom::Point{<:Any,true}) = m(trait, parent(geom))
# Special-case vector and tuple points so we can force them to be measured while not 3d
m(trait::PointTrait, geom::Point{false,true,<:PointTuple3}) = parent(geom)[3]
m(trait::PointTrait, geom::Point{false,true,<:Vector{<:Real}}) = parent(geom)[3]

function Base.:(==)(g1::Point, g2::Point)
    x(g1) == x(g2) && y(g1) == y(g2) && is3d(g1) == is3d(g2) && ismeasured(g1) == ismeasured(g2) || return false
    if is3d(g1)
        z(g1) == z(g2) || return false
    end
    if ismeasured(g1)
        m(g1) == m(g2) || return false
    end
    return true
end
Base.:(!=)(g1::Point, g2::Point) = !(g1 == g2)

function Base.show(io::IO, ::MIME"text/plain", point::Point{Z, M, T, C}; show_mz::Bool = true, screen_ncols::Int = displaysize(io)[2]) where {Z,M,T,C}
    print(io, "Point")
    this_crs = crs(point)

    compact = get(io, :compact, false)
    spacing = compact ? "" : " "

    if !compact && show_mz
        print(io, "{$Z, $M}")
    end
    print(io, "(")
    trait = geomtrait(point)
    print(io, "($(x(trait, point)),$(spacing)$(y(trait, point))")
    if Z
        print(io, ",$(spacing)$(z(trait, point))")
    end
    if M
        print(io, ",$(spacing)$(m(trait, point))")
    end
    print(io, ")")

    if !compact && !isnothing(this_crs)
        print(io, ",$(spacing)crs$(spacing)=$(spacing)")
        print(io, "\"")
        show(io, MIME"text/plain"(), this_crs)
        print(io, "\"")
    end
    print(io, ")")

    return nothing
end

@noinline _coord_length_error(Z, M, l) =
    throw(ArgumentError("Number of coordinates must be $(2 + Z + M) when `Z` is $Z and `M` is $M. Got $l"))
@noinline _no_z_error() = throw(ArgumentError("Point has no `Z` coordinate"))
@noinline _no_m_error() = throw(ArgumentError("Point has no `M` coordinate"))

"""
    Feature(geometry; [properties, crs, extent])

A Feature wrapper.

## Arguments

- `geometry`: any GeoInterface compatible geometry object, or `nothing`.

## Keywords

- `properties`: any object that defines `propertynames` and `getproperty`
- `crs`: Any GeoFormatTypes.jl crs type, or `nothing`
- `extent`: An Extents.jl `Extent` or `nothing`

## Example

```julia
feature = Feature(geom; properties=(a=1, b="2"), crs=EPSG(4326))
```
"""
struct Feature{T,C,E<:Union{Extents.Extent,Nothing}}
    parent::T
    crs::C
    extent::E
end
function Feature(f::Feature; crs=crs(f), extent=f.extent, properties=nothing)
    isnothing(properties) || @info "`properties` keyword not used when wrapping a feature"
    Feature(parent(f), crs, extent)
end
function Feature(geometry=nothing; properties=(;), crs=nothing, extent=nothing)
    if isnothing(geometry) || isgeometry(geometry)
        # Wrap a NamedTuple feature
        Feature((; geometry, properties...), crs, extent)
    else
        throw(ArgumentError("object must be a feature, geometry or `nothing`. Got $(typeof(geometry))"))
    end
end

function Base.show(io::IO, mime::MIME"text/plain", f::Feature; show_mz::Bool=true)
    compact = get(io, :compact, false)
    spacing = compact ? "" : " "
    print(io, "Feature(")
    geom = geometry(f)
    if geom isa WrapperGeometry
        show(io, mime, geom; show_mz)
    else
        show(io, mime, geom)
    end
    non_geom_props = filter(!=(:geometry), propertynames(f.parent))
    if !isempty(non_geom_props)
        print(io, ",$(spacing)properties$(spacing)=$(spacing)(")
        for (i, property) ∈ enumerate(non_geom_props)
            print(io, "$(property)$(spacing)=$(spacing)")
            show(io, getproperty(f.parent, property))
            if i != length(non_geom_props)
                print(io, ",$(spacing)")
            end
        end
        print(io, ")")
    end
    if !compact
        if !isnothing(f.extent)
            print(io, ", extent$(spacing)=$(spacing)")
            show(io, MIME"text/plain"(), f.extent)
        end
        if !isnothing(f.crs)
            print(io, ", crs$(spacing)=$(spacing)\"")
            show(io, MIME"text/plain"(), f.crs)
            print(io, "\"")
        end
    end
    print(io, ")")
end

Base.parent(f::Feature) = f.parent

isfeature(::Type{<:Feature}) = true
trait(::Feature) = FeatureTrait()
geometry(f::Feature) = geometry(parent(f))
properties(f::Feature) = properties(parent(f))
extent(f::Feature) =
    isfeature(parent(f)) && isnothing(f.extent) ? extent(parent(f)) : f.extent
crs(f::Feature) =
    isfeature(parent(f)) && isnothing(f.crs) ? crs(parent(f)) : f.crs

"""
    FeatureCollection(features; [crs, extent])

A FeatureCollection wrapper.

## Arguments

- `features`: an `AbstractArray` of GeoInterface compatible features.
    Iterables are accepted but will be collected to an `Array`.

## Keywords

- `crs`: Any GeoFormatTypes.jl crs type, or `nothing`
- `extent`: An Extents.jl `Extent` or `nothing`

## Examples

```julia
fc = FeatureCollection([feature1, feature2, feature3];
    crs=EPSG(4326), extent=Extent(X=(11.0, 34.0), Y=(45.7, 78.0))
)
```

Or wrap another `FeatureColection`, e.g. if it has no crs attached:

```julia
fc = FeatureCollection(featurecollection, crs=EPSG(4326))
```
"""
struct FeatureCollection{P,C,E}
    parent::P
    crs::C
    extent::E
end
function FeatureCollection(fc::FeatureCollection; crs=crs(fc), extent=extent(fc))
    FeatureCollection(parent(fc), crs, extent)
end
function FeatureCollection(parent; crs=nothing, extent=nothing)
    if isfeaturecollection(parent)
        FeatureCollection(parent, crs, extent)
    elseif isfeature(parent)
        # If `parent` is a single feature, wrap it in a featurecollection
        FeatureCollection(
            [parent], 
            isnothing(crs) ? Wrappers.crs(parent) : crs, 
            isnothing(extent) ? Wrappers.extent(parent) : extent
        )
    else
        features = (parent isa AbstractArray) ? parent : collect(parent) 
        all(f -> isfeature(f), features) || _child_feature_error()
        FeatureCollection(parent, crs, extent)
    end
end

function Base.show(io::IO, ::MIME"text/plain", fc::FeatureCollection)
    print(io, "FeatureCollection(")
    compact = get(io, :compact, false)
    spacing = compact ? "" : " "
    features = _parent_is_fc(fc) ? getfeature(trait(fc), parent(fc)) : parent(fc)
    print(io, "[")
    for (i, f) ∈ enumerate(features)
        show(io, MIME"text/plain"(), f; show_mz = !compact)
        if i != length(features)
            print(io, ",$(spacing)")
        end
    end
    print(io, "]")
    if !compact
        if !isnothing(fc.crs)
            print(io, ",$(spacing)crs$(spacing)=$(spacing)\"")
            show(io, MIME"text/plain"(), fc.crs)
            print(io, "\"")
        end
        if !isnothing(fc.extent)
            print(io, ",$(spacing)extent$(spacing)=$(spacing)")
            show(io, MIME"text/plain"(), fc.extent)
        end
    end
    print(io, ")")
    return nothing
end

Base.parent(fc::FeatureCollection) = fc.parent

_child_feature_error() = throw(ArgumentError("child objects must be features"))

isfeaturecollection(fc::Type{<:FeatureCollection}) = true
trait(fc::FeatureCollection) = FeatureCollectionTrait()

nfeature(t::FeatureCollectionTrait, fc::FeatureCollection) =
    _parent_is_fc(fc) ? nfeature(t, parent(fc)) : length(parent(fc))
getfeature(t::FeatureCollectionTrait, fc::FeatureCollection) =
    _parent_is_fc(fc) ? getfeature(t, parent(fc)) : parent(fc)
getfeature(t::FeatureCollectionTrait, fc::FeatureCollection, i::Integer) =
    _parent_is_fc(fc) ? getfeature(t, parent(fc), i) : parent(fc)[i]
extent(fc::FeatureCollection) =
    (isnothing(fc.extent) && _parent_is_fc(fc)) ? extent(parent(fc)) : fc.extent
crs(fc::FeatureCollection) =
    (isnothing(fc.crs) && _parent_is_fc(fc)) ? crs(parent(fc)) : fc.crs

_parent_is_fc(x) = isfeaturecollection(parent(x))

end # module
