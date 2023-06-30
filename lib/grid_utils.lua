
local grid_utils = {}

-- -------------------------------------------------------------------------
-- deps

include("argen/lib/core")


-- -------------------------------------------------------------------------
-- hw identification

grid_utils.nb_levels = function(g)
  if util.string_starts(g.name, 'monome 64 m64')
    or util.string_starts(g.name, 'monome 128 m128')
    or util.string_starts(g.name, 'monome 256 m256') then
    return 1
  else
    return 15
  end
end


-- -------------------------------------------------------------------------
-- leds

grid_utils.lclamp = function(g, l, lreso, t)
  if t == nil then t = 15 end
  if lreso == nil then lreso = grid_utils.nb_levels(g) end

  if lreso == 15 then
    return l
  end

  -- REVIEW: crappy code, redo it better
  -- threshold takes over too much the grid reso
  local in_g_reso = util.linlin(0, t, 0, lreso, l)
  local in_15_reso = util.clamp(round(util.linlin(0, lreso, 0, 15, in_g_reso)), 0, 15)

  return in_15_reso
end

grid_utils.led = function(g, x, y, l, lreso, t)
  g:led(x, y, grid_utils.lclamp(g, l, lreso, t))
end

-- -------------------------------------------------------------------------

return grid_utils
