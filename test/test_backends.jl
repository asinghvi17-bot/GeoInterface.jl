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

            # without a width, as PrettyTables has, it is as bounded as with a small one
            unlimited = (:limit => true, :displaysize => (-1, -1))
            @test length(show_with(triangle, unlimited...)) < 200
            @test length(show_with(GI.Polygon(read("POLYGON (" * "(0 0," * join(("$(i % 7) $(i % 11)" for i in 1:20_000), ",") * ",0 0))")), unlimited...)) < 200

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

    # an empty point has coordinates, but no values to show
    @testset "ArchGDAL empty point" begin
        point = ArchGDAL.fromWKT("POINT EMPTY")
        for props in ((:limit => true,), (:compact => true,)), x in (GI.MultiPoint([point]), GI.GeometryCollection([point]))
            shown = show_with(x, :displaysize => (24, 120), props...)
            @test occursin(props == (:limit => true,) ? "POINT EMPTY" : "Geometry:", shown) # as shown by itself
            @test !occursin("(0.0, 0.0)", shown)
        end
    end

    # not all children of a geometry can be read
    @testset "ArchGDAL curves" begin
        curve = GI.GeometryCollection([ArchGDAL.fromWKT("CIRCULARSTRING (0 0,1 1,2 0)")])
        for cols in (40, 80, 200), props in ((:limit => true,), (:compact => true,)), x in (curve, [curve], [curve curve], Dict(:a => curve), (a = curve,))
            @test occursin(r"CircularString|CIRCULARSTRING", show_with(x, :displaysize => (24, cols), props...))
        end
    end

    # counting the parts of a compound curve reads all of it, so that is not done to show it
    @testset "ArchGDAL compound curves" begin
        compound(n) = GI.MultiCurve([ArchGDAL.fromWKT("COMPOUNDCURVE (" * join(("($i 0,$(i + 1) 0)" for i in 1:n), ",") * ")")])
        small, large = compound(100), compound(30_000)
        for props in ((:limit => true,), (:compact => true,), (:limit => true, :compact => true))
            @test occursin("CompoundCurve", show_with(large, :displaysize => (24, 160), props...))
            show_with(small, props...); show_with(large, props...)
            @test @allocated(show_with(large, :displaysize => (24, 160), props...)) < 2 * @allocated(show_with(small, :displaysize => (24, 160), props...))
        end
        @test fastest(() -> show_with(large, :displaysize => (24, 160), :limit => true)) < 20 * fastest(() -> show_with(small, :displaysize => (24, 160), :limit => true))
    end
end
