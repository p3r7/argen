-- argen. hot_cursor


-- ------------------------------------------------------------------------

local hot_cursor = {}

-- ------------------------------------------------------------------------
-- macro "all" cursor

local grid_all_rings = false

function hot_cursor.are_all()
  return grid_all_rings
end

function hot_cursor.all_set(v)
  grid_all_rings = v
end


-- ------------------------------------------------------------------------
-- single ring hot cursor

local grid_hot_cursors = {}

function hot_cursor.is(r)
  return grid_hot_cursors[r]
end

function hot_cursor.set(r, v)
  grid_hot_cursors[r] = v
end


-- ------------------------------------------------------------------------
-- combined state

local any_grid_hot_cursor = false
local nb_hot_cursor = 0

function hot_cursor.is_active(r)
  return (hot_cursor.are_all() or hot_cursor.is(r))
end

function hot_cursor.is_any_active()
  return any_grid_hot_cursor
end

function hot_cursor.recompute(force_all)
  local nb_arcs = tab.count(grid_hot_cursors)
  local nb_hot_cursor = 0
  for r=1,nb_arcs do
    if hot_cursor.is(r) then
      nb_hot_cursor = nb_hot_cursor + 1
    end
  end
  any_grid_hot_cursor = (nb_hot_cursor > 0)
  nb_hot_cursor = nb_hot_cursor

  local grid_all_hot_pressed = (nb_hot_cursor == nb_arcs)
  grid_all_rings = (force_all or grid_all_hot_pressed)
end


-- ------------------------------------------------------------------------
-- init

function hot_cursor.init(nb_arcs)
  for r=1,nb_arcs do
    grid_hot_cursors[r] = false
  end
end


-- ------------------------------------------------------------------------

return hot_cursor
