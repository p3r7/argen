-- argen. varc


-- ------------------------------------------------------------------------

local varc = {}


-- ------------------------------------------------------------------------
-- redraw

local LEDS_OFFSET = 4

local function redraw_circle(x, y, radius, level, fill)
  screen.move(x + radius, y)
  screen.circle(x, y, radius)
  if fill then
    screen.fill()
  else
    screen.stroke()
  end
end

local function redraw_leds(x, y, radius, level, leds, offset)
  local segments = tab.count(leds)
  for i=1,segments do
    if leds[i] == 1 then
      local radial_pos = i + offset + (segments/4)
      screen.pixel(x + radius * cos(radial_pos/segments) * -1, y + radius * sin(radial_pos/segments))
    end
  end
end

function varc.redraw(x, y, radius, level, fill, leds, offset)
  screen.level(level)
  redraw_circle(x, y, radius, level, fill)
  redraw_leds(x, y, radius + LEDS_OFFSET, level, leds, offset)
end


-- ------------------------------------------------------------------------

return varc
