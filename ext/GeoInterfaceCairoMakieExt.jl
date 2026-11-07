module GeoInterfaceCairoMakieExt

# Exact (unsampled) drawing of curved geometries in CairoMakie.
# `poly` fills/strokes the exact `BezierPath`, `curvelines` strokes it.
# Elliptical arcs become cubic Béziers in screen space (Cairo has no elliptical
# arc primitive in Makie's pipeline), which is what every vector renderer does.

import GeoInterface as GI
import Makie
import CairoMakie
using CairoMakie: Cairo

const MakieExt = Base.get_extension(GI, :GeoInterfaceMakieExt)
const CurvePath = MakieExt.CurvePath
const CurveLines = MakieExt.CurveLines

"""
    can_draw_exact(plot, scene)

Exact paths are only correct if every transformation between data space and the
screen maps Bézier curves to Bézier curves, i.e. is affine: identity
`transform_func` (no log axes, no map projections), an affine camera, data space,
no clip planes.
"""
function can_draw_exact(plot, scene)
    Makie.is_identity_transform(Makie.transform_func(plot)) || return false
    isempty(plot.clip_planes[]) || return false
    pv = Makie.camera(scene).projectionview[]
    all(iszero, pv[4, 1:3]) || return false
    return true
end

function CairoMakie.draw_poly(scene::Makie.Scene, screen::CairoMakie.Screen, poly, cp::CurvePath)
    if !MakieExt.is3d(cp) && can_draw_exact(poly, scene)
        return draw_paths(screen, poly, [cp.bezier])
    else
        return CairoMakie.draw_poly_as_mesh(scene, screen, poly)
    end
end
function CairoMakie.draw_poly(scene::Makie.Scene, screen::CairoMakie.Screen, poly, cps::AbstractVector{<:CurvePath})
    if !any(MakieExt.is3d, cps) && can_draw_exact(poly, scene)
        return draw_paths(screen, poly, [cp.bezier for cp in cps])
    else
        return CairoMakie.draw_poly_as_mesh(scene, screen, poly)
    end
end

_cairo_linestyle(linestyle, linewidth) = CairoMakie.to_cairo_linestyle(
    Makie.convert_attribute(linestyle, Makie.key"linestyle"()), linewidth)

# Fill and stroke exact paths. This mirrors CairoMakie's `draw_poly` for
# `BezierPath`s, which we can't call directly since it assumes the child plots of a
# standard `poly`.
function draw_paths(screen, poly, paths)
    ctx = screen.context
    space = poly.space[]
    model = poly.model[]
    shapes = map(b -> CairoMakie.project_shape(poly, space, b, model), paths)
    colors = CairoMakie.to_cairo_color(poly.color[], poly)
    strokecolors = CairoMakie.to_cairo_color(poly.strokecolor[], poly)
    Makie.broadcast_foreach(shapes, colors, strokecolors, poly.strokewidth[]) do shape, c, sc, sw
        Cairo.save(ctx)
        Cairo.new_path(ctx)
        # Rings are oriented (exterior CCW, holes CW), so either fill rule works
        Cairo.set_fill_type(ctx, Cairo.CAIRO_FILL_RULE_EVEN_ODD)
        for cmd in shape.commands
            CairoMakie.path_command(ctx, cmd)
        end
        CairoMakie.set_source(ctx, c)
        Cairo.fill_preserve(ctx)
        pattern = _cairo_linestyle(poly.linestyle[], sw)
        isnothing(pattern) || Cairo.set_dash(ctx, pattern)
        CairoMakie.set_source(ctx, sc)
        Cairo.set_line_width(ctx, sw)
        CairoMakie.set_miter_limit(ctx, CairoMakie.to_cairo_miter_limit(poly.miter_limit[]))
        Cairo.set_line_join(ctx, CairoMakie.to_cairo_joinstyle(poly.joinstyle[]))
        Cairo.set_line_cap(ctx, CairoMakie.to_cairo_linecap(poly.linecap[]))
        Cairo.stroke(ctx)
        Cairo.restore(ctx)
    end
    return
end

CairoMakie.is_cairomakie_atomic_plot(::CurveLines) = true

function CairoMakie.draw_plot(scene::Makie.Scene, screen::CairoMakie.Screen, plot::CurveLines)
    cp = plot.curve[]
    color = plot.color[]
    linewidth = plot.linewidth[]
    exact = !MakieExt.is3d(cp) && can_draw_exact(plot, scene) &&
        color isa Makie.Colorant && linewidth isa Real && plot.visible[]
    if !exact
        # Per-vertex colors, non-linear transforms, 3D: draw the linearized lines
        foreach(p -> CairoMakie.draw_plot(scene, screen, p), plot.plots)
        return
    end
    ctx = screen.context
    shape = CairoMakie.project_shape(plot, plot.space[], cp.bezier, plot.model[])
    Cairo.save(ctx)
    Cairo.new_path(ctx)
    for cmd in shape.commands
        CairoMakie.path_command(ctx, cmd)
    end
    pattern = _cairo_linestyle(plot.linestyle[], linewidth)
    isnothing(pattern) || Cairo.set_dash(ctx, pattern)
    CairoMakie.set_source(ctx, CairoMakie.to_cairo_color(color, plot))
    Cairo.set_line_width(ctx, linewidth)
    Cairo.set_line_cap(ctx, CairoMakie.to_cairo_linecap(plot.linecap[]))
    Cairo.set_line_join(ctx, CairoMakie.to_cairo_joinstyle(plot.joinstyle[]))
    CairoMakie.set_miter_limit(ctx, CairoMakie.to_cairo_miter_limit(plot.miter_limit[]))
    Cairo.stroke(ctx)
    Cairo.restore(ctx)
    return
end

end
