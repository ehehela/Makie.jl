GridLayout(parent, nrows::Int, ncols::Int; kwargs...) = GridLayout(nrows, ncols; parent=parent, kwargs...)
GridLayout(parent; kwargs...) = GridLayout(1, 1; parent=parent, kwargs...)
GridLayout(; kwargs...) = GridLayout(1, 1; kwargs...)

function GridLayout(nrows::Int, ncols::Int;
        parent = nothing,
        rowsizes = nothing,
        colsizes = nothing,
        addedrowgaps = nothing,
        addedcolgaps = nothing,
        alignmode = Inside(),
        equalprotrusiongaps = (false, false),
        halign::Union{Symbol, Node{Symbol}} = :center,
        valign::Union{Symbol, Node{Symbol}} = :center)

    if isnothing(rowsizes)
        rowsizes = [Auto() for _ in 1:nrows]
    # duplicate a single row size into a vector for every row
    elseif rowsizes isa ContentSize
        rowsizes = [rowsizes for _ in 1:nrows]
    elseif !(typeof(rowsizes) <: Vector{<: ContentSize})
        error("Row sizes must be one size or a vector of sizes, not $(typeof(rowsizes))")
    end

    if isnothing(colsizes)
        colsizes = [Auto() for _ in 1:ncols]
    # duplicate a single col size into a vector for every col
    elseif colsizes isa ContentSize
        colsizes = [colsizes for _ in 1:ncols]
    elseif !(typeof(colsizes) <: Vector{<: ContentSize})
        error("Column sizes must be one size or a vector of sizes, not $(typeof(colsizes))")
    end

    if isnothing(addedrowgaps)
        addedrowgaps = [Fixed(20) for _ in 1:nrows-1]
    elseif addedrowgaps isa GapSize
        addedrowgaps = [addedrowgaps for _ in 1:nrows-1]
    elseif !(typeof(addedrowgaps) <: Vector{<: GapSize})
        error("Row gaps must be one size or a vector of sizes, not $(typeof(addedrowgaps))")
    end

    if isnothing(addedcolgaps)
        addedcolgaps = [Fixed(20) for _ in 1:ncols-1]
    elseif addedcolgaps isa GapSize
        addedcolgaps = [addedcolgaps for _ in 1:ncols-1]
    elseif !(typeof(addedcolgaps) <: Vector{<: GapSize})
        error("Column gaps must be one size or a vector of sizes, not $(typeof(addedcolgaps))")
    end

    needs_update = Node(true)

    content = []

    valign = valign isa Symbol ? Node(valign) : valign
    halign = halign isa Symbol ? Node(halign) : halign

    onany(valign, halign) do v, h
        needs_update[] = true
    end

    GridLayout(
        parent, content, nrows, ncols, rowsizes, colsizes, addedrowgaps,
        addedcolgaps, alignmode, equalprotrusiongaps, needs_update, valign, halign)
end

function validategridlayout(gl::GridLayout)
    if gl.nrows < 1
        error("Number of rows can't be smaller than 1")
    end
    if gl.ncols < 1
        error("Number of columns can't be smaller than 1")
    end

    if length(gl.rowsizes) != gl.nrows
        error("There are $nrows rows but $(length(rowsizes)) row sizes.")
    end
    if length(gl.colsizes) != gl.ncols
        error("There are $ncols columns but $(length(colsizes)) column sizes.")
    end
    if length(gl.addedrowgaps) != gl.nrows - 1
        error("There are $nrows rows but $(length(addedrowgaps)) row gaps.")
    end
    if length(gl.addedcolgaps) != gl.ncols - 1
        error("There are $ncols columns but $(length(addedcolgaps)) column gaps.")
    end
end

function with_updates_suspended(f::Function, gl::GridLayout)
    gl.block_updates = true
    f()
    gl.block_updates = false
    gl.needs_update[] = true
end

parentlayout(gl::GridLayout) = gl.parent

function detach_parent!(gl::GridLayout)
    detach_parent!(gl, gl.parent)
    nothing
end

function detach_parent!(gl::GridLayout, parent::Scene)
    if isnothing(gl._update_func_handle)
        error("Trying to detach a Scene parent, but there is no update_func_handle. This must be a bug.")
    end
    Observables.off(pixelarea(parent), gl._update_func_handle)
    gl._update_func_handle = nothing
    gl.parent = nothing
    nothing
end

function detach_parent!(gl::GridLayout, parent::Node{<:Rect2D})
    if isnothing(gl._update_func_handle)
        error("Trying to detach a Rect Node parent, but there is no update_func_handle. This must be a bug.")
    end
    Observables.off(parent, gl._update_func_handle)
    gl._update_func_handle = nothing
    gl.parent = nothing
    nothing
end

function detach_parent!(gl::GridLayout, parent::GridLayout)
    if !isnothing(gl._update_func_handle)
        error("Trying to detach a GridLayout parent, but there is an update_func_handle. This must be a bug.")
    end
    gl.parent = nothing
    nothing
end

function detach_parent!(gl::GridLayout, parent::Nothing)
    if !isnothing(gl._update_func_handle)
        error("Trying to detach a Nothing parent, but there is an update_func_handle. This must be a bug.")
    end
    nothing
end

function attach_parent!(gl::GridLayout, parent::Scene)
    detach_parent!(gl)
    gl._update_func_handle = on(pixelarea(parent)) do px
        request_update(gl)
    end
    gl.parent = parent
    nothing
end

function attach_parent!(gl::GridLayout, parent::Nothing)
    detach_parent!(gl)
    gl.parent = parent
    nothing
end

function attach_parent!(gl::GridLayout, parent::GridLayout)
    detach_parent!(gl)
    gl.parent = parent
    nothing
end

function attach_parent!(gl::GridLayout, parent::Node{<:Rect2D})
    detach_parent!(gl)
    gl._update_func_handle = on(parent) do rect
        request_update(gl)
    end
    gl.parent = parent
    nothing
end

function request_update(gl::GridLayout)
    if !gl.block_updates
        request_update(gl, gl.parent)
    end
end

function request_update(gl::GridLayout, parent::Nothing)
    # do nothing, sometimes a GridLayout may be defined and only then inserted
    # into another, so I don't want to break those cases
    # this could on the other hand lead to people confused why nothing is happening

    # error("The GridLayout has no parent and therefore can't request an update.")
end

function request_update(gl::GridLayout, parent::Scene)
    sg = solve(gl, BBox(pixelarea(parent)[]))
    applylayout(sg)
end

function request_update(gl::GridLayout, parent::Node{<:Rect2D})
    sg = solve(gl, BBox(parent[]))
    applylayout(sg)
end

function request_update(gl::GridLayout, parent::GridLayout)
    parent.needs_update[] = true
end


function convert_contentsizes(n, sizes)::Vector{ContentSize}
    if isnothing(sizes)
        [Auto() for _ in 1:n]
    elseif sizes isa ContentSize
        [sizes for _ in 1:n]
    elseif sizes isa Vector{<:ContentSize}
        length(sizes) == n ? sizes : error("$(length(sizes)) sizes instead of $n")
    else
        error("Illegal sizes value $sizes")
    end
end

function convert_gapsizes(n, gaps)::Vector{GapSize}
    if isnothing(gaps)
        [Fixed(20) for _ in 1:n]
    elseif gaps isa GapSize
        [gaps for _ in 1:n]
    elseif gaps isa Vector{<:GapSize}
        length(gaps) == n ? gaps : error("$(length(gaps)) gaps instead of $n")
    else
        error("Illegal gaps value $gaps")
    end
end

function appendrows!(gl::GridLayout, n::Int; rowsizes=nothing, addedrowgaps=nothing)

    rowsizes = convert_contentsizes(n, rowsizes)
    addedrowgaps = convert_gapsizes(n, addedrowgaps)

    with_updates_suspended(gl) do
        gl.nrows += n
        append!(gl.rowsizes, rowsizes)
        append!(gl.addedrowgaps, addedrowgaps)
    end
end

function appendcols!(gl::GridLayout, n::Int; colsizes=nothing, addedcolgaps=nothing)

    colsizes = convert_contentsizes(n, colsizes)
    addedcolgaps = convert_gapsizes(n, addedcolgaps)

    with_updates_suspended(gl) do
        gl.ncols += n
        append!(gl.colsizes, colsizes)
        append!(gl.addedcolgaps, addedcolgaps)
    end
end

function prependrows!(gl::GridLayout, n::Int; rowsizes=nothing, addedrowgaps=nothing)

    rowsizes = convert_contentsizes(n, rowsizes)
    addedrowgaps = convert_gapsizes(n, addedrowgaps)

    gl.content = map(gl.content) do spal
        span = spal.sp
        newspan = Span(span.rows .+ n, span.cols)
        SpannedLayout(spal.al, newspan, spal.side)
    end

    with_updates_suspended(gl) do
        gl.nrows += n
        prepend!(gl.rowsizes, rowsizes)
        prepend!(gl.addedrowgaps, addedrowgaps)
    end
end

function prependcols!(gl::GridLayout, n::Int; colsizes=nothing, addedcolgaps=nothing)

    colsizes = convert_contentsizes(n, colsizes)
    addedcolgaps = convert_gapsizes(n, addedcolgaps)

    gl.content = map(gl.content) do spal
        span = spal.sp
        newspan = Span(span.rows, span.cols .+ n)
        SpannedLayout(spal.al, newspan, spal.side)
    end

    with_updates_suspended(gl) do
        gl.ncols += n
        prepend!(gl.colsizes, colsizes)
        prepend!(gl.addedcolgaps, addedcolgaps)
    end
end

function deleterow!(gl::GridLayout, irow::Int)
    if !(1 <= irow <= gl.nrows)
        error("Row $irow does not exist.")
    end

    if gl.nrows == 1
        error("Can't delete the last row")
    end

    new_content = SpannedLayout[]
    to_remove = SpannedLayout[]
    for c in gl.content
        rows = c.sp.rows
        newrows = if irow in rows
            # range is one shorter now
            rows.start : rows.stop - 1
        elseif irow > rows.stop
            # content before deleted row stays the same
            rows
        else
            # content completely after is moved forward 1 step
            rows .- 1
        end
        if isempty(newrows)
            # the row span was just one row and now zero, remove the element
            push!(to_remove, c)
        else
            push!(new_content, SpannedLayout(c.al, Span(newrows, c.sp.cols), c.side))
        end
    end

    for c in to_remove
        detachfromparent!(c.al)
    end
    gl.content = new_content
    deleteat!(gl.rowsizes, irow)
    deleteat!(gl.addedrowgaps, irow == 1 ? 1 : irow - 1)
    gl.nrows -= 1
    gl.needs_update[] = true
end

function deletecol!(gl::GridLayout, icol::Int)
    if !(1 <= icol <= gl.ncols)
        error("Col $icol does not exist.")
    end

    if gl.ncols == 1
        error("Can't delete the last col")
    end

    new_content = SpannedLayout[]
    to_remove = SpannedLayout[]
    for c in gl.content
        cols = c.sp.cols
        newcols = if icol in cols
            # range is one shorter now
            cols.start : cols.stop - 1
        elseif icol > cols.stop
            # content before deleted col stays the same
            cols
        else
            # content completely after is moved forward 1 step
            cols .- 1
        end
        if isempty(newcols)
            # the col span was just one col and now zero, remove the element
            push!(to_remove, c)
        else
            push!(new_content, SpannedLayout(c.al, Span(c.sp.rows, newcols), c.side))
        end
    end

    for c in to_remove
        detachfromparent!(c.al)
    end
    gl.content = new_content
    deleteat!(gl.colsizes, icol)
    deleteat!(gl.addedcolgaps, icol == 1 ? 1 : icol - 1)
    gl.ncols -= 1
    gl.needs_update[] = true
end

function gridnest!(gl::GridLayout, rows::Indexables, cols::Indexables)

    newrows, newcols = adjust_rows_cols!(gl, rows, cols)

    subgl = GridLayout(
        length(newrows), length(newcols);
        parent = nothing,
        colsizes = gl.colsizes[newcols],
        rowsizes = gl.rowsizes[newrows],
        addedrowgaps = gl.addedrowgaps[newrows.start:(newrows.stop-1)],
        addedcolgaps = gl.addedcolgaps[newcols.start:(newcols.stop-1)],
    )

    # remove the content from the parent that is completely inside the replacement grid
    subgl.block_updates = true
    i = 1
    while i <= length(gl.content)
        spal = gl.content[i]

        if (spal.sp.rows.start >= newrows.start && spal.sp.rows.stop <= newrows.stop &&
            spal.sp.cols.start >= newcols.start && spal.sp.cols.stop <= newcols.stop)

            detachfromparent!(spal.al) # this deletes the alignable from its old parent already
            # which would happen anyway hidden in the next assignment, but makes the intent clearer
            subgl[spal.sp.rows .- (newrows.start - 1), spal.sp.cols .- (newcols.start - 1)] = spal.al
            continue
            # don't advance i because there's one piece of content less in the queue
            # and the next item is in the same position as the old removed one
        end
        i += 1
    end
    subgl.block_updates = false

    gl[newrows, newcols] = subgl

    subgl
end

function find_in_grid(obj, container::GridLayout)
    for i in 1:length(container.content)
        layout = container.content[i].al
        if layout isa ProtrusionLayout
            if layout.content === obj
                return i
            end
        end
    end
    nothing
end

function find_in_grid(layout::AbstractLayout, container::GridLayout)
    for i in 1:length(container.content)
        if container.content[i].al === layout
            return i
        end
    end
    nothing
end

function topmost_grid(gl::GridLayout)
    candidate = gl
    while true
        if candidate.parent isa GridLayout
            candidate = candidate.parent
        else
            return candidate
        end
    end
end

function find_in_grid_and_subgrids(obj, container::GridLayout)
    for i in 1:length(container.content)
        candidate = container.content[i].al
        # for non layout objects like LAxis we check if they are inside
        # any protrusion layout we find
        if candidate isa ProtrusionLayout
            if candidate.content === obj
                return container, i
            end
        elseif candidate isa GridLayout
            return find_in_grid_and_subgrids(obj, candidate)
        end
    end
    nothing, nothing
end

function find_in_grid_and_subgrids(layout::AbstractLayout, container::GridLayout)
    for i in 1:length(container.content)
        candidate = container.content[i].al
        if candidate === layout
            return container, i
        elseif candidate isa GridLayout
            return find_in_grid_and_subgrids(layout, candidate)
        end
    end
    nothing, nothing
end

function find_in_grid_tree(obj, container::GridLayout)
    topmost = topmost_grid(container)
    find_in_grid_and_subgrids(obj, topmost)
end

function detachfromgridlayout!(obj, gl::GridLayout)
    i = find_in_grid(obj, gl)
    if !isnothing(i)
        deleteat!(gl.content, i)
    end
end

function Base.show(io::IO, gl::GridLayout)

    println(io, "GridLayout[$(gl.nrows), $(gl.ncols)] with $(length(gl.content)) children")
    for (i, c) in enumerate(gl.content)
        rows = c.sp.rows
        cols = c.sp.cols
        al = c.al
        if i == 1
            println(io, " ┗━┳━ [$rows | $cols] $(typeof(al))")
        elseif i == length(gl.content)
            println(io, "   ┗━ [$rows | $cols] $(typeof(al))")
        else
            println(io, "   ┣━ [$rows | $cols] $(typeof(al))")
        end
    end

end

function colsize!(gl::GridLayout, i::Int, s::ContentSize)
    if !(1 <= i <= gl.ncols)
        error("Can't set size of invalid column $i.")
    end
    gl.colsizes[i] = s
    gl.needs_update[] = true
end

function rowsize!(gl::GridLayout, i::Int, s::ContentSize)
    if !(1 <= i <= gl.nrows)
        error("Can't set size of invalid row $i.")
    end
    gl.rowsizes[i] = s
    gl.needs_update[] = true
end

function colgap!(gl::GridLayout, i::Int, s::GapSize)
    if !(1 <= i <= (gl.ncols - 1))
        error("Can't set size of invalid column gap $i.")
    end
    gl.addedcolgaps[i] = s
    gl.needs_update[] = true
end

function rowgap!(gl::GridLayout, i::Int, s::GapSize)
    if !(1 <= i <= (gl.nrows - 1))
        error("Can't set size of invalid row gap $i.")
    end
    gl.addedrowgaps[i] = s
    gl.needs_update[] = true
end

"""
This function solves a grid layout such that the "important lines" fit exactly
into a given bounding box. This means that the protrusions of all objects inside
the grid are not taken into account. This is needed if the grid is itself placed
inside another grid.
"""
function solve(gl::GridLayout, bbox::BBox)

    if gl.alignmode isa Outside
        pad = gl.alignmode.padding
        bbox = BBox(
            left(bbox) + pad.left,
            right(bbox) - pad.right,
            bottom(bbox) + pad.bottom,
            top(bbox) - pad.top)
    end

    # first determine how big the protrusions on each side of all columns and rows are
    maxgrid = RowCols(gl.ncols, gl.nrows)
    # go through all the layout objects placed in the grid
    for c in gl.content
        idx_rect = side_indices(c)
        mapsides(idx_rect, maxgrid) do side, idx, grid
            grid[idx] = max(grid[idx], protrusion(c, side))
        end
    end

    # for the outside alignmode
    topprot = maxgrid.tops[1]
    bottomprot = maxgrid.bottoms[end]
    leftprot = maxgrid.lefts[1]
    rightprot = maxgrid.rights[end]

    # compute what size the gaps between rows and columns need to be
    colgaps = maxgrid.lefts[2:end] .+ maxgrid.rights[1:end-1]
    rowgaps = maxgrid.tops[2:end] .+ maxgrid.bottoms[1:end-1]

    # determine the biggest gap
    # using the biggest gap size for all gaps will make the layout more even, but one
    # could make this aspect customizable, because it might waste space
    if gl.equalprotrusiongaps[2]
        colgaps = ones(gl.ncols - 1) .* (gl.ncols <= 1 ? 0.0 : maximum(colgaps))
    end
    if gl.equalprotrusiongaps[1]
        rowgaps = ones(gl.nrows - 1) .* (gl.nrows <= 1 ? 0.0 : maximum(rowgaps))
    end

    # determine the vertical and horizontal space needed just for the gaps
    # again, the gaps are what the protrusions stick into, so they are not actually "empty"
    # depending on what sticks out of the plots
    sumcolgaps = (gl.ncols <= 1) ? 0.0 : sum(colgaps)
    sumrowgaps = (gl.nrows <= 1) ? 0.0 : sum(rowgaps)

    # compute what space remains for the inner parts of the plots
    remaininghorizontalspace = if gl.alignmode isa Inside
        width(bbox) - sumcolgaps
    elseif gl.alignmode isa Outside
        width(bbox) - sumcolgaps - leftprot - rightprot
    end
    remainingverticalspace = if gl.alignmode isa Inside
        height(bbox) - sumrowgaps
    elseif gl.alignmode isa Outside
        height(bbox) - sumrowgaps - topprot - bottomprot
    end

    # compute how much gap to add, in case e.g. labels are too close together
    # this is given as a fraction of the space used for the inner parts of the plots
    # so far, but maybe this should just be an absolute pixel value so it doesn't change
    # when resizing the window
    addedcolgaps = map(gl.addedcolgaps) do cg
        if cg isa Fixed
            return cg.x
        elseif cg isa Relative
            return cg.x * remaininghorizontalspace
        else
            return 0.0 # for float type inference
        end
    end
    addedrowgaps = map(gl.addedrowgaps) do rg
        if rg isa Fixed
            return rg.x
        elseif rg isa Relative
            return rg.x * remainingverticalspace
        else
            return 0.0 # for float type inference
        end
    end

    # compute the actual space available for the rows and columns (plots without protrusions)
    spaceforcolumns = remaininghorizontalspace - ((gl.ncols <= 1) ? 0.0 : sum(addedcolgaps))
    spaceforrows = remainingverticalspace - ((gl.nrows <= 1) ? 0.0 : sum(addedrowgaps))

    colwidths, rowheights = compute_col_row_sizes(spaceforcolumns, spaceforrows, gl)

    # don't allow smaller widths than 1 px even if it breaks the layout (better than weird glitches)
    colwidths = max.(colwidths, ones(length(colwidths)))
    rowheights = max.(rowheights, ones(length(rowheights)))
    # # compute the column widths and row heights using the specified row and column ratios
    # colwidths = gl.colratios ./ sum(gl.colratios) .* spaceforcolumns
    # rowheights = gl.rowratios ./ sum(gl.rowratios) .* spaceforrows

    # this is the vertical / horizontal space between the inner lines of all plots
    finalcolgaps = colgaps .+ addedcolgaps
    finalrowgaps = rowgaps .+ addedrowgaps

    # compute the resulting width and height of the gridlayout and compute
    # adjustments for the grid's alignment (this will only matter if the grid is
    # bigger or smaller than the bounding box it occupies)

    gridwidth = sum(colwidths) + sum(finalcolgaps) +
        (gl.alignmode isa Outside ? (leftprot + rightprot) : 0.0)
    gridheight = sum(rowheights) + sum(finalrowgaps) +
        (gl.alignmode isa Outside ? (topprot + bottomprot) : 0.0)

    halign = gl.halign[]
    halign_offset = if halign == :left
        0.0
    elseif halign == :right
        width(bbox) - gridwidth
    elseif halign == :center
        (width(bbox) - gridwidth) / 2
    else
        error("Invalid grid layout halign $halign")
    end
    valign = gl.valign[]
    valign_offset = if valign == :top
        0.0
    elseif valign == :bottom
        gridheight - height(bbox)
    elseif valign == :center
        (gridheight - height(bbox)) / 2
    else
        error("Invalid grid layout valign $valign")
    end

    # compute the x values for all left and right column boundaries
    xleftcols = if gl.alignmode isa Inside
        halign_offset .+ left(bbox) .+ cumsum([0; colwidths[1:end-1]]) .+
            cumsum([0; finalcolgaps])
    elseif gl.alignmode isa Outside
        halign_offset .+ left(bbox) .+ cumsum([0; colwidths[1:end-1]]) .+
            cumsum([0; finalcolgaps]) .+ leftprot
    end
    xrightcols = xleftcols .+ colwidths

    # compute the y values for all top and bottom row boundaries
    ytoprows = if gl.alignmode isa Inside
        valign_offset .+ top(bbox) .- cumsum([0; rowheights[1:end-1]]) .-
            cumsum([0; finalrowgaps])
    elseif gl.alignmode isa Outside
        valign_offset .+ top(bbox) .- cumsum([0; rowheights[1:end-1]]) .-
            cumsum([0; finalrowgaps]) .- topprot
    end
    ybottomrows = ytoprows .- rowheights

    # now we can solve the content thats inside the grid because we know where each
    # column and row is placed, how wide it is, etc.
    # note that what we did at the top was determine the protrusions of all grid content,
    # but we know the protrusions before we know how much space each plot actually has
    # because the protrusions should be static (like tick labels etc don't change size with the plot)

    gridboxes = RowCols(
        xleftcols, xrightcols,
        ytoprows, ybottomrows
    )
    solvedcontent = map(gl.content) do c
        idx_rect = side_indices(c)
        bbox_cell = mapsides(idx_rect, gridboxes) do side, idx, gridside
            gridside[idx]
        end

        solving_bbox = bbox_for_solving_from_side(maxgrid, bbox_cell, idx_rect, c.side)

        solved = solve(c.al, solving_bbox)
        return SpannedLayout(solved, c.sp, c.side)
    end
    # return a solved grid layout in which all objects are also solved layout objects
    return SolvedGridLayout(
        bbox, solvedcontent,
        gl.nrows, gl.ncols,
        gridboxes
    )
end


dirlength(gl::GridLayout, c::Col) = gl.ncols
dirlength(gl::GridLayout, r::Row) = gl.nrows

function dirgaps(gl::GridLayout, dir::GridDir)
    starts = zeros(Float32, dirlength(gl, dir))
    stops = zeros(Float32, dirlength(gl, dir))
    for c in gl.content
        sp = span(c, dir)
        start = sp.start
        stop = sp.stop
        starts[start] = max(starts[start], protrusion(c, startside(dir)))
        stops[stop] = max(stops[stop], protrusion(c, stopside(dir)))
    end
    starts, stops
end

dirsizes(gl::GridLayout, c::Col) = gl.colsizes
dirsizes(gl::GridLayout, r::Row) = gl.rowsizes

"""
Determine the size of a grid layout along one of its dimensions.
`Row` measures from bottom to top and `Col` from left to right.
The size is dependent on the alignmode of the grid, `Outside` includes
protrusions and paddings.
"""
function determinedirsize(gl::GridLayout, gdir::GridDir)
    sum_dirsizes = 0

    sizes = dirsizes(gl, gdir)

    for idir in 1:dirlength(gl, gdir)
        # width can only be determined for fixed and auto
        sz = sizes[idir]
        dsize = determinedirsize(idir, gl, gdir)

        if isnothing(dsize)
            # early exit if a colsize can not be determined
            return nothing
        end
        sum_dirsizes += dsize
    end

    dirgapsstart, dirgapsstop = dirgaps(gl, Col())

    forceequalprotrusiongaps = gl.equalprotrusiongaps[gdir isa Row ? 1 : 2]

    dirgapsizes = if forceequalprotrusiongaps
        innergaps = dirgapsstart[2:end] .+ dirgapsstop[1:end-1]
        m = maximum(innergaps)
        innergaps .= m
    else
        innergaps = dirgapsstart[2:end] .+ dirgapsstop[1:end-1]
    end

    inner_gapsizes = dirlength(gl, gdir) > 1 ? sum(dirgapsizes) : 0

    addeddirgapsizes = gdir isa Row ? gl.addedrowgaps : gl.addedcolgaps

    addeddirgaps = dirlength(gl, gdir) == 1 ? 0 : sum(addeddirgapsizes) do c
        if c isa Fixed
            c.x
        elseif c isa Relative
            error("Auto grid size not implemented with relative gaps")
        end
    end

    inner_size_combined = sum_dirsizes + inner_gapsizes + addeddirgaps
    return if gl.alignmode isa Inside
        inner_size_combined
    elseif gl.alignmode isa Outside
        paddings = if gdir isa Row
            gl.alignmode.padding.top + gl.alignmode.padding.bottom
        else
            gl.alignmode.padding.left + gl.alignmode.padding.right
        end
        inner_size_combined + dirgapsstart[1] + dirgapsstop[end] + paddings
    end
end

"""
Determine the size of a grid layout if it's placed as a spanned layout with
a `Side` inside another grid layout.
"""
function determinedirsize(gl::GridLayout, gdir::GridDir, side::Side)
    if gdir isa Row
        @match side begin
            si::Union{Inner, Top, Bottom, TopLeft, TopRight, BottomLeft, BottomRight} =>
                ifnothing(determinedirsize(gl, gdir), nothing)
            si::Union{Left, Right} => nothing
        end
    else
        @match side begin
            si::Union{Inner, Left, Right, TopLeft, TopRight, BottomLeft, BottomRight} =>
                ifnothing(determinedirsize(gl, gdir), nothing)
            si::Union{Top, Bottom} => nothing
        end
    end
end


"""
Determine the size of one row or column of a grid layout.
"""
function determinedirsize(idir, gl, dir::GridDir)

    sz = dirsizes(gl, dir)[idir]

    if sz isa Fixed
        # fixed dir size can simply be returned
        return sz.x
    elseif sz isa Relative
        # relative dir size can't be inferred
        return nothing
    elseif sz isa Auto
        # auto dir size can either be determined or not, depending on the
        # trydetermine flag
        !sz.trydetermine && return nothing

        dirsize = nothing
        for c in gl.content
            # content has to be single span to be determinable in size
            singlespanned = span(c, dir).start == span(c, dir).stop == idir

            # content has to be placed with Inner side, otherwise it's protrusion
            # content
            is_inner = c.side isa Inner

            if singlespanned && is_inner
                s = determinedirsize(c.al, dir, c.side)
                if !isnothing(s)
                    dirsize = isnothing(dirsize) ? s : max(dirsize, s)
                end
            end
        end
        return dirsize
    end
    nothing
end


function compute_col_row_sizes(spaceforcolumns, spaceforrows, gl)
    # the space for columns and for rows is divided depending on the sizes
    # stored in the grid layout

    # rows / cols with Auto size must have single span content that
    # can report its own size, otherwise they can't determine their own size
    # alternatively, if there is only one Auto row / col it can get the rest
    # that remains after the other specified sizes are subtracted

    # rows / cols with Fixed size get that size

    # rows / cols with Relative size get that fraction of the available space

    colwidths = zeros(gl.ncols)
    rowheights = zeros(gl.nrows)

    # store sizes in arrays with indices so we can keep track of them
    icsizes = collect(enumerate(gl.colsizes))
    irsizes = collect(enumerate(gl.rowsizes))

    filtersize(T::Type) = isize -> isize[2] isa T

    fcsizes = filter(filtersize(Fixed), icsizes)
    frsizes = filter(filtersize(Fixed), irsizes)

    relcsizes = filter(filtersize(Relative), icsizes)
    relrsizes = filter(filtersize(Relative), irsizes)

    acsizes = filter(filtersize(Auto), icsizes)
    arsizes = filter(filtersize(Auto), irsizes)

    aspcsizes = filter(filtersize(Aspect), icsizes)
    asprsizes = filter(filtersize(Aspect), irsizes)

    determined_acsizes = map(acsizes) do (i, c)
        (i, determinedirsize(i, gl, Col()))
    end
    det_acsizes = filter(tup -> !isnothing(tup[2]), determined_acsizes)
    nondets_c = filter(tup -> isnothing(tup[2]), determined_acsizes)
    nondet_acsizes = map(nondets_c) do (i, noth)
        i, gl.colsizes[i]
    end

    determined_arsizes = map(arsizes) do (i, c)
        (i, determinedirsize(i, gl, Row()))
    end
    det_arsizes = filter(tup -> !isnothing(tup[2]), determined_arsizes)
    nondets_r = filter(tup -> isnothing(tup[2]), determined_arsizes)
    nondet_arsizes = map(nondets_r) do (i, noth)
        i, gl.rowsizes[i]
    end

    # assign fixed sizes first
    map(fcsizes) do (i, f)
        colwidths[i] = f.x
    end
    map(frsizes) do (i, f)
        rowheights[i] = f.x
    end

    # next relative sizes
    map(relcsizes) do (i, r)
        colwidths[i] = r.x * spaceforcolumns
    end
    map(relrsizes) do (i, r)
        rowheights[i] = r.x * spaceforrows
    end

    # next determinable auto sizes
    map(det_acsizes) do (i, x)
        colwidths[i] = x
    end
    map(det_arsizes) do (i, x)
        rowheights[i] = x
    end

    # next aspect sizes
    map(aspcsizes) do (i, asp)
        index = asp.index
        ratio = asp.ratio
        rowsize = gl.rowsizes[index]
        rowheight = if rowsize isa Union{Fixed, Relative, Auto}
            if rowsize isa Auto
                if !isempty(nondet_arsizes) && any(x -> x[1] == index, nondet_arsizes)
                    error("Can't use aspect ratio with an undeterminable Auto size")
                end
            end
            rowheights[index]
        else
            error("Aspect size can only work in conjunction with Fixed, Relative, or determinable Auto, not $(typeof(gl.rowsizes[index]))")
        end
        colwidths[i] = rowheight * ratio
    end

    map(asprsizes) do (i, asp)
        index = asp.index
        ratio = asp.ratio
        colsize = gl.colsizes[index]
        colwidth = if colsize isa Union{Fixed, Relative, Auto}
            if colsize isa Auto
                if !isempty(nondet_acsizes) && any(x -> x[1] == index, nondet_acsizes)
                    error("Can't use aspect ratio with an undeterminable Auto size")
                end
            end
            colwidths[index]
        else
            error("Aspect size can only work in conjunction with Fixed, Relative, or determinable Auto, not $(typeof(gl.rowsizes[index]))")
        end
        rowheights[i] = colwidth * ratio
    end

    # next undeterminable auto sizes
    if !isempty(nondet_acsizes)
        remaining = spaceforcolumns - sum(colwidths)
        nondet_acsizes
        sumratios = sum(nondet_acsizes) do (i, c)
            c.ratio
        end
        map(nondet_acsizes) do (i, c)
            colwidths[i] = remaining * c.ratio / sumratios
        end
    end
    if !isempty(nondet_arsizes)
        remaining = spaceforrows - sum(rowheights)
        sumratios = sum(nondet_arsizes) do (i, r)
            r.ratio
        end
        map(nondet_arsizes) do (i, r)
            rowheights[i] = remaining * r.ratio / sumratios
        end
    end

    colwidths, rowheights
end
