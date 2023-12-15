-- argen. varc


-- ------------------------------------------------------------------------

local varc = {}


-- ------------------------------------------------------------------------
-- redraw

local LEDS_OFFSET = 4

local function redraw_circle(x, y, radius, level, fill)
  if seamstress then
    screen.move(round(x), round(y))
    screen.circle(radius)
    if fill then
      screen.circle_fill(radius)
    else
      screen.circle(radius)
    end
  end
  if norns then
    screen.move(x + radius, y)
    screen.circle_fill(x, y, radius)
    if fill then
      screen.fill()
    else
      screen.stroke()
    end
  end
end

local function redraw_leds(x, y, radius, level, leds, offset)
  local segments = tab.count(leds)
  for i=1,segments do
    if leds[i] == 1 then
      local radial_pos = i + offset + (segments/4)
      if seamstress then
        screen.pixel(round(x + radius * cos(radial_pos/segments) * -1), round(y + radius * sin(radial_pos/segments)))
      else
        screen.pixel(x + radius * cos(radial_pos/segments) * -1, y + radius * sin(radial_pos/segments))
      end
    end
  end
  screen.stroke()
end

function varc.redraw(x, y, radius, level, fill, leds, offset)
  screen.level(level)
  screen.aa(1)
  redraw_circle(x, y, radius, level, fill)
  redraw_leds(x, y, radius + LEDS_OFFSET, level, leds, offset)
end


-- ------------------------------------------------------------------------

return varc
