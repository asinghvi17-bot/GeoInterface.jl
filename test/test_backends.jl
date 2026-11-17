using Test
import GeoInterface as GI
import ArchGDAL, LibGEOS

# Wrapped geometries of real backends, which copy a geometry when a child of it is read
@testset "display of wrapped ArchGDAL and LibGEOS geometries" begin
    show_with(x, props...) = sprint(io -> show(IOContext(io, props...), MIME"text/plain"(), x))
    line(n) = "(" * join(("$i $(i % 5)" for i in 1:n), ",") * ")"
    fastest(f) = (f(); minimum(@elapsed(f()) for _ in 1:5))

    for (name, read) in (("LibGEOS", LibGEOS.readgeom), ("ArchGDAL", ArchGDAL.fromWKT))
        @testset "$name" begin
            # small geometries show their own display, also in containers
            triangle = GI.Polygon(read("POLYGON ((0 0, 1 0, 1 1, 0 0))"))
            for x in (triangle, [triangle], [triangle triangle], Dict(:a => triangle), (a = triangle,))
                @test occursin("POLYGON ((0 0", show_with(x, :displaysize => (24, 120), :limit => true))
            end

            # children that are not shown are not read, which would copy them
            multi = read("MULTILINESTRING(" * join([fill("(0 0,1 1)", 4); line(300_000); fill("(0 0,1 1)", 5)], ",") * ")")
            wrapped = GI.MultiLineString(multi)
            copying = fastest(() -> GI.getgeom(multi, 5))
            for props in ((:limit => true,), (:compact => true,))
                shown = show_with(wrapped, :displaysize => (24, 80), props...)
                @test occursin("…", shown)
                @test fastest(() -> show_with(wrapped, :displaysize => (24, 80), props...)) < copying / 5
            end

            # and not those around which collections are nested
            nested = read("GEOMETRYCOLLECTION(" ^ 20 * "LINESTRING" * line(100_000) * ")" ^ 20)
            wrapped = GI.GeometryCollection(nested)
            copying = fastest(() -> GI.getgeom(nested, 1))
            @test fastest(() -> show_with(wrapped, :displaysize => (24, 50), :limit => true)) < copying
        end
    end

    # not all children of a geometry can be read
    @testset "ArchGDAL curves" begin
        curve = GI.GeometryCollection([ArchGDAL.fromWKT("CIRCULARSTRING (0 0,1 1,2 0)")])
        for cols in (40, 80, 200), props in ((:limit => true,), (:compact => true,)), x in (curve, [curve], [curve curve], Dict(:a => curve), (a = curve,))
            @test occursin(r"CircularString|CIRCULARSTRING", show_with(x, :displaysize => (24, cols), props...))
        end
    end
end
