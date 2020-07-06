function handle_color!(uniform_dict, instance_dict)
    color, udict = if haskey(uniform_dict, :color)
        to_value(uniform_dict[:color]), uniform_dict
    elseif haskey(instance_dict, :color)
        to_value(instance_dict[:color]), instance_dict
    else
        nothing, uniform_dict
    end
    if color isa Colorant || color isa AbstractVector{<: Colorant} || color === nothing
        delete!(uniform_dict, :colormap)
    elseif color isa AbstractArray{<:Real}
        udict[:color] = lift(x-> convert(Vector{Float32}, x), udict[:color])
        uniform_dict[:color_getter] = """
            vec4 get_color(){
                vec2 norm = get_colorrange();
                float normed = (color - norm.x) / (norm.y - norm.x);
                return texture(colormap, vec2(normed, 0));
            }
        """
    end
end

const IGNORE_KEYS = Set([
    :shading, :overdraw, :rotation, :distancefield, :markerspace, :fxaa,
    :visible, :transformation, :alpha, :linewidth, :transparency, :marker
])

function create_shader(scene::Scene, plot::MeshScatter)
    # Potentially per instance attributes
    per_instance_keys = (:rotations, :markersize, :color, :intensity)
    per_instance = filter(plot.attributes.attributes) do (k, v)
        k in per_instance_keys && !(isscalar(v[]))
    end
    per_instance[:offset] = plot[1]

    for (k, v) in per_instance
        per_instance[k] = Buffer(lift_convert(k, v, plot))
    end

    uniforms = filter(plot.attributes.attributes) do (k, v)
        (!haskey(per_instance, k)) && isscalar(v[])
    end

    uniform_dict = Dict{Symbol, Any}()
    for (k,v) in uniforms
        k in IGNORE_KEYS && continue
        uniform_dict[k] = lift_convert(k, v, plot)
    end

    if haskey(uniform_dict, :lightposition)
        eyepos = getfield(scene.camera, :eyeposition)
        uniform_dict[:lightposition] = lift(uniform_dict[:lightposition], eyepos, typ=Vec3f0) do pos, eyepos
            ifelse(pos == :eyeposition, eyepos, pos)::Vec3f0
        end
    end

    handle_color!(uniform_dict, per_instance)

    instance = normal_mesh(plot.marker[])

    if !hasproperty(instance, :uv)
        uniform_dict[:uv] = Vec2f0(0)
    end

    for key in (:view, :projection, :resolution, :eyeposition, :projectionview)
        uniform_dict[key] = getfield(scene.camera, key)
    end

    return InstancedProgram(
        WebGL(),
        lasset("particles.vert"),
        lasset("particles.frag"),
        instance,
        VertexArray(; per_instance...)
        ; uniform_dict...
    )
end


@enum Shape CIRCLE RECTANGLE ROUNDED_RECTANGLE DISTANCEFIELD TRIANGLE

primitive_shape(::Union{String, Char, Vector{Char}}) = Cint(DISTANCEFIELD)
primitive_shape(x::X) where X = Cint(primitive_shape(X))
primitive_shape(::Type{<: Circle}) = Cint(CIRCLE)
primitive_shape(::Type{<: Rect2D}) = Cint(RECTANGLE)
primitive_shape(::Type{T}) where T = error("Type $(T) not supported")
primitive_shape(x::Shape) = Cint(x)

using AbstractPlotting: to_spritemarker

function scatter_shader(scene::Scene, attributes)
    # Potentially per instance attributes
    per_instance_keys = (:offset, :rotations, :markersize, :color, :intensity, :uv_offset_width, :marker_offset)
    uniform_dict = Dict{Symbol, Any}()

    if haskey(attributes, :marker) && attributes[:marker][] isa Union{Vector{Char}, String}
        x = pop!(attributes, :marker)
        attributes[:uv_offset_width] = lift(x-> AbstractPlotting.glyph_uv_width!.(collect(x)), x)
        uniform_dict[:shape_type] = Cint(3)
    end

    per_instance = filter(attributes) do (k, v)
        k in per_instance_keys && !(isscalar(v[]))
    end
    for (k, v) in per_instance
        per_instance[k] = Buffer(lift_convert(k, v, nothing))
    end

    uniforms = filter(attributes) do (k, v)
        (!haskey(per_instance, k)) && isscalar(v[])
    end

    for (k, v) in uniforms
        k in IGNORE_KEYS && continue
        uniform_dict[k] = lift_convert(k, v, nothing)
    end

    get!(uniform_dict, :shape_type) do
        lift(x-> primitive_shape(to_spritemarker(x)), attributes[:marker])
    end
    if uniform_dict[:shape_type][] == 3
        atlas = AbstractPlotting.get_texture_atlas()
        uniform_dict[:distancefield] = Sampler(
            atlas.data,
            minfilter = :linear,
            magfilter = :linear,
            anisotropic = 16f0,
        )
        uniform_dict[:atlas_texture_size] = Float32(size(atlas.data, 1)) # Texture must be quadratic
    else
        uniform_dict[:atlas_texture_size] = 0f0
        uniform_dict[:distancefield] = Observable(false)
    end

    if !haskey(per_instance, :uv_offset_width)
        get!(uniform_dict, :uv_offset_width) do
            if haskey(attributes, :marker) && to_spritemarker(attributes[:marker][]) isa Char
                lift(x-> AbstractPlotting.glyph_uv_width!(to_spritemarker(x)), attributes[:marker])
            else
                Vec4f0(0)
            end
        end
    end

    space = get(uniforms, :markerspace, Observable(SceneSpace))
    uniform_dict[:use_pixel_marker] = map(space) do space
        space == Pixel
    end

    handle_color!(uniform_dict, per_instance)

    instance = VertexArray(uv_mesh(Rect2D(-0.5f0, -0.5f0, 1f0, 1f0)))

    for key in (:resolution,)#(:view, :projection, :resolution, :eyeposition, :projectionview)
        uniform_dict[key] = getfield(scene.camera, key)
    end

    if haskey(uniform_dict, :lightposition)
        eyepos = getfield(scene.camera, :eyeposition)
        uniform_dict[:lightposition] = lift(uniform_dict[:lightposition], eyepos, typ=Vec3f0) do pos, eyepos
            ifelse(pos == :eyeposition, eyepos, pos)::Vec3f0
        end
    end

    return InstancedProgram(
        WebGL(),
        lasset("simple.vert"),
        lasset("sprites.frag"),
        instance,
        VertexArray(; per_instance...)
        ; uniform_dict...
    )
end

function create_shader(scene::Scene, plot::Scatter)
    # Potentially per instance attributes
    per_instance_keys = (:offset, :rotations, :markersize, :color, :intensity, :marker_offset)
    per_instance = filter(plot.attributes.attributes) do (k, v)
        k in per_instance_keys && !(isscalar(v[]))
    end
    attributes = copy(plot.attributes.attributes)
    attributes[:offset] = plot[1]
    attributes[:billboard] = map(rot-> isa(rot, Billboard), plot.rotations)
    attributes[:pixelspace] = getfield(scene.camera, :pixel_space)
    delete!(attributes, :uv_offset_width)
    return scatter_shader(scene, attributes)
end



function to_gl_text(string, positions_per_char::AbstractVector{T}, textsize,
                    font, align, rot, model, j, l) where T <: VecTypes
    atlas = get_texture_atlas()
    N = length(T)
    positions, uv_offset_width, scale = Point{3, Float32}[], Vec4f0[], Vec2f0[]
    char_str_idx = iterate(string)
    offsets = Vec2f0[]
    broadcast_foreach(1:length(string), positions_per_char, textsize, font, align) do idx, pos, tsize, font, align
        char, str_idx = char_str_idx
        mpos = model * Vec4f0(to_ndim(Vec3f0, pos, 0f0)..., 1f0)
        push!(positions, to_ndim(Point{3, Float32}, mpos, 0))
        push!(uv_offset_width, glyph_uv_width!(atlas, char, font))
        glyph_bb, ext = FreeTypeAbstraction.metrics_bb(char, font, tsize)
        if isa(tsize, Vec2f0) # this needs better unit support
            push!(scale, tsize) # Vec2f0, we assume it's already in absolute size
        else
            push!(scale, widths(glyph_bb))
        end
        push!(offsets, minimum(glyph_bb))
        char_str_idx = iterate(string, str_idx)
    end
    return positions, offsets, uv_offset_width, scale
end

function to_gl_text(string, startpos::VecTypes{N, T}, textsize, font, aoffsetvec, rot, model, j, l) where {N, T}
    atlas = get_texture_atlas()
    positions = layout_text(string, startpos, textsize, font, aoffsetvec, rot, model, j, l)
    uv = Vec4f0[]
    scales = Vec2f0[]
    offsets = Vec2f0[]
    for (c, font, pixelsize) in zip(string, attribute_per_char(string, font), attribute_per_char(string, textsize))
        push!(uv, glyph_uv_width!(atlas, c, font))
        glyph_bb, extent = FreeTypeAbstraction.metrics_bb(c, font, pixelsize)
        push!(scales, widths(glyph_bb))
        push!(offsets, minimum(glyph_bb))
    end
    return positions, offsets, uv, scales
end

function create_shader(scene::Scene, plot::AbstractPlotting.Text)

    liftkeys = (:position, :textsize, :font, :align, :rotation, :model, :justification, :lineheight)
    args = getindex.(Ref(plot), liftkeys)
    gl_text = lift(plot[1], args...) do str, pos, tsize, font, align, rotation, model, j, l
        args = @get_attribute plot (position, textsize, font, align, rotation)
        to_gl_text(str, args..., model, j, l)
    end

    # unpack values from the one signal:
    positions, offset, uv_offset_width, scale = map((1, 2, 3, 4)) do i
        lift(getindex, gl_text, i)
    end
    # Sigh, we also allow inplace mutation without triggering
    # plot.rotation to update, so we need to update also on the string array (plot[1])
    rotation = lift(plot[1], plot.rotation) do str, rotation
        return to_rotation(rotation)
    end
    color = lift(plot[1], plot.color) do str, color
        return to_color(color)
    end

    return scatter_shader(scene, Dict(
        :shape_type => Observable(Cint(3)),
        :color => color,
        :rotations => rotation,
        :markersize => scale,
        :marker_offset => offset,
        :offset => positions,
        :uv_offset_width => uv_offset_width,
        :transform_marker => Observable(true),
        :billboard => Observable(false),
        :pixelspace => getfield(scene.camera, :pixel_space)
    ))
end

function draw_js(jsctx, jsscene, scene::Scene, plot::MeshScatter)
    program = create_shader(scene, plot)
    mesh = wgl_convert(scene, jsctx, program)
    resize_pogram(jsctx, program, mesh)
    map(plot.visible) do visible
        mesh.visible = visible
    end
    mesh.name = string(objectid(plot))
    debug_shader("meshscatter", program.program)
    jsscene.add(mesh)
end

function draw_js(jsctx, jsscene, scene::Scene, plot::AbstractPlotting.Text)
    program = create_shader(scene, plot)
    debug_shader("text", program.program)
    mesh = wgl_convert(scene, jsctx, program)
    resize_pogram(jsctx, program, mesh)
    map(plot.visible) do visible
        mesh.visible = visible
    end
    mesh.name = string(objectid(plot))
    update_model!(mesh, plot)
    jsscene.add(mesh)
end

function draw_js(jsctx, jsscene, scene::Scene, plot::Scatter)
    program = create_shader(scene, plot)
    mesh = wgl_convert(scene, jsctx, program)
    resize_pogram(jsctx, program, mesh)
    map(plot.visible) do visible
        mesh.visible = visible
    end
    debug_shader("scatter", program.program)
    mesh.name = string(objectid(plot))
    update_model!(mesh, plot)
    jsscene.add(mesh)
end


function resize_pogram(jsctx, program::InstancedProgram, mesh)
    real_size = Ref(length(program.per_instance))
    buffers = [v for (k, v) in pairs(program.per_instance)]
    resize = Observable(Set{Symbol}())
    update_buffer = Observable(["name", [], 0])
    onjs(jsctx, update_buffer, js"""function (val){
        const name = val[0];
        const flat = val[1];
        const len = val[2];
        const geometry = $(mesh).geometry
        const jsb = geometry.attributes[name]
        jsb.set(flat, 0)
        jsb.needsUpdate = true
        geometry.instanceCount = len
    }""")
    for (name, buffer) in pairs(program.per_instance)
        if buffer isa Buffer
            on(ShaderAbstractions.updater(buffer).update) do (f, args)
                # update to replace the whole buffer!
                if f === (setindex!) && args[1] isa AbstractArray && args[2] isa Colon
                    new_array = args[1]
                    flat = flatten_buffer(new_array)
                    len = length(new_array)
                    if real_size[] >= length(new_array)
                        update_buffer[] = [name, flat, len]
                    else
                        push!(resize[], name)
                        if (length(resize[]) == length(buffers)) || all(buffers) do buff
                                    length(new_array) == length(buff)
                                end
                            real_size[] = length(buffer)
                            resize[] = resize[]
                            empty!(resize[])
                        end
                    end
                end
            end
        end
    end
    on(resize) do new_data
        JSServe.fuse(jsctx) do
            js_vbo = jsctx.new.InstancedBufferGeometry()
            for (name, buff) in pairs(program.program.vertexarray)
                js_buff = JSBuffer(jsctx, buff)
                js_vbo.setAttribute(name, js_buff)
            end
            indices = GeometryBasics.faces(program.program.vertexarray)
            indices = reinterpret(UInt32, indices)
            js_vbo.setIndex(indices)
            js_vbo.instanceCount = length(program.per_instance)
            for (name, buff) in pairs(program.per_instance)
                js_buff = JSInstanceBuffer(jsctx, buff)
                js_vbo.setAttribute(name, js_buff)
            end
            js_vbo.boundingSphere = THREE.new.Sphere()
            # don't use intersection / culling
            js_vbo.boundingSphere.radius = 10000000000000f0
            mesh.geometry = js_vbo
            mesh.needsUpdate = true
        end
    end
end


function resize_pogram(jsctx, program::Program, mesh)
    real_size = Ref(length(program.vertexarray))
    buffers = [v for (k, v) in pairs(program.vertexarray)]
    resize = Observable(Set{Symbol}())
    update_buffer = Observable(["name", [], 0])
    onjs(jsctx, update_buffer, js"""function (val){
        const name = val[0];
        const flat = val[1];
        const len = val[2];
        const geometry = $(mesh).geometry
        const jsb = geometry.attributes[name]
        jsb.set(flat, 0)
        jsb.needsUpdate = true
        geometry.instanceCount = len
    }""")
    for (name, buffer) in pairs(program.vertexarray)
        if buffer isa Buffer
            on(ShaderAbstractions.updater(buffer).update) do (f, args)
                # update to replace the whole buffer!
                if f === (setindex!) && args[1] isa AbstractArray && args[2] isa Colon
                    new_array = args[1]
                    flat = flatten_buffer(new_array)
                    len = length(new_array)
                    if real_size[] >= length(new_array)
                        update_buffer[] = [name, flat, len]
                    else
                        push!(resize[], name)
                        if length(resize[]) == length(buffers)
                            real_size[] = length(buffer)
                            resize[] = resize[]
                            empty!(resize[])
                        end
                    end
                end
            end
        end
    end
    on(resize) do new_data
        JSServe.fuse(jsctx) do
            js_vbo = jsctx.new.BufferGeometry()
            for (name, buff) in pairs(program.vertexarray)
                js_buff = JSBuffer(jsctx, buff)
                js_vbo.setAttribute(name, js_buff)
            end
            indices = GeometryBasics.faces(program.vertexarray)
            indices = reinterpret(UInt32, indices)
            js_vbo.setIndex(indices)
            js_vbo.boundingSphere = THREE.new.Sphere()
            # don't use intersection / culling
            js_vbo.boundingSphere.radius = 10000000000000f0
            mesh.geometry = js_vbo
            mesh.needsUpdate = true
        end
    end
end
