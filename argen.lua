-- argen.
-- @eigen
--
--   arc
--         rythm
--                 generator
--
--    ▼ instructions below ▼
--
-- K1 + K2    - randomize
-- E1         - clock speed
-- E2         - transpose
-- E3         - filter freq
-- K3 + E3    - filter req
-- arc        - density
-- K1 + arc   - randomize
-- K3 + arc   - offset
--
-- original idea by @stretta



-- ------------------------------------------------------------------------
-- deps

local lattice = require("lattice")
local MusicUtil = require "musicutil"
local ControlSpec = require "controlspec"
local Formatters = require "formatters"


-- ------------------------------------------------------------------------
-- engine

engine.name = "Timber"
local Timber = include("timber/lib/timber_engine")

local function format_st(param)
  local formatted = param:get() .. " ST"
  if param:get() > 0 then formatted = "+" .. formatted end
  return formatted
end


-- ------------------------------------------------------------------------
-- conf

local fps = 15
local arc_fps = 15

local ARC_SEGMENTS = 64

local DENSITY_MAX = 10
local ARC_RAW_DENSITY_RESOLUTION = 1000


-- ------------------------------------------------------------------------
-- state

local a

local s_lattice

local patterns = {}
local sparse_patterns = {}
-- local pattern_shifts = {}

local raw_densities = {}

local is_firing = {}

local prev_pattern_refresh_t = {}


-- ------------------------------------------------------------------------
-- core helpers

local function rnd(x)
  if x == 0 then
    return 0
  end
  if (not x) then
    x = 1
  end
  x = x * 100000
  x = math.random(x) / 100000
  return x
end

local function srand(x)
  if not x then
    x = 0
  end
  math.randomseed(x)
end

local function cos(x)
  return math.cos(math.rad(x * 360))
end

local function sin(x)
  return -math.sin(math.rad(x * 360))
end


-- ------------------------------------------------------------------------
-- patterns

function gen_pattern(pattern)
  if pattern == nil then
    pattern = {}
  end

  srand(math.random(10000))

  for i=1,ARC_SEGMENTS do

    local v = 0

    if i%(ARC_SEGMENTS/4) == 0 then
      v = 1
    elseif i%(ARC_SEGMENTS/16) == 0 then
      v = 2
    elseif i%(ARC_SEGMENTS/32) == 0 then
      v = 4
    else
      v = math.random(DENSITY_MAX + 1) - 1
    end

    pattern[i] = v
    -- table.insert(pattern)
  end

  return pattern
end

function gen_empty_pattern(pattern)
  if pattern == nil then
    pattern = {}
  end
  for i=1,64 do
    pattern[i] = 0
  end
  return pattern
end


-- ------------------------------------------------------------------------
-- script lifecycle

local redraw_clock
local arc_redraw_clock
local arc_clock

local arc_delta

function init()
  screen.aa(1)
  screen.line_width(1)

  s_lattice = lattice:new{}

  a = arc.connect(1)
  a.delta = arc_delta

  params:add_trigger("gen_all", "Randomize")
  params:set_action("gen_all",
                    function(v)
                      srand(os.time())
                      for r=1,4 do
                        params:set("ring_gen_pattern_"..r, 1)
                        local density = DENSITY_MAX
                        for try=1,math.floor(DENSITY_MAX/2) do
                          local d = math.random(DENSITY_MAX)
                          if d < density then
                            density = d
                          end
                        end
                        params:set("ring_density_"..r, density)
                        params:set("ring_pattern_shift_"..r, 0)
                      end
  end)


  for r=1,4 do
    patterns[r] = gen_pattern()
    sparse_patterns[r] = gen_empty_pattern()
    raw_densities[r] = 0
    -- pattern_shifts[r] = 0
    prev_pattern_refresh_t[r] = 0
    is_firing[r] = false

    params:add_trigger("ring_gen_pattern_"..r, "Generate "..r)
    params:set_action("ring_gen_pattern_"..r,
                      function(v)
                      gen_pattern(patterns[r])
  end)


    params:add{type = "number", id = "ring_density_"..r, name = "Density "..r, min = 0, max = DENSITY_MAX, default = 0}
    params:add{type = "number", id = "ring_pattern_shift_"..r, name = "Pattern Shift "..r, min = -(ARC_SEGMENTS-1), max = (ARC_SEGMENTS-1), default = 0}


  end

  params:add{type = "control", id = "filter_freq", name = "Filter Cutoff", controlspec = ControlSpec.new(60, 20000, "exp", 0, 3000, "Hz"), formatter = Formatters.format_freq, action = function(v)
               for i = 1, 4 do
                 params:set('filter_freq_'..i, v)
               end
  end}

  params:add{type = "control", id = "filter_resonance", name = "Filter Resonance", controlspec = ControlSpec.new(0, 1, "lin", 0, 0.3, ""), action = function(v)
               for i = 1, 4 do
                 params:set('filter_resonance_'..i, v)
               end
  end}

  params:add{type = "number", id = "transpose", name = "Transpose", min = -48, max = 48, default = 0, formatter = format_st, action = function(v)
         for i = 1, 4 do
           params:set('transpose_'..i, v)
         end
  end}


  Timber.options.PLAY_MODE_BUFFER_DEFAULT = 4
  Timber.options.PLAY_MODE_STREAMING_DEFAULT = 3
  Timber.add_params()
  for i = 1, 4 do
    local extra_params = {
      {type = "option", id = "launch_mode_" .. i, name = "Launch Mode", options = {"Gate", "Toggle"}, default = 1, action = function(value)
         Timber.setup_params_dirty = true
      end},
    }
    -- params:add_separator()
    Timber.add_sample_params(i, true, extra_params)
    params:set('play_mode_' .. i, 3) -- "1-Shot" in options.PLAY_MODE_BUFFER
    --params:set('amp_env_sustain_' .. i, 0)
  end

  Timber.load_sample(1, _path.audio .. 'common/808/808-BD.wav')
  Timber.load_sample(2, _path.audio .. 'common/808/808-CH.wav')
  -- Timber.load_sample(2, _path.audio .. 'common/808/808-CY.wav')
  -- Timber.load_sample(2, _path.audio .. 'common/808/808-RS.wav')
  Timber.load_sample(3, _path.audio .. 'common/808/808-SD.wav')
  Timber.load_sample(4, _path.audio .. 'common/808/808-OH.wav')

  redraw_clock = clock.run(
    function()
      local step_s = 1 / fps
      while true do
        clock.sleep(step_s)
        redraw()
      end
  end)
  -- arc_redraw_clock = clock.run(
  --   function()
  --     local step_s = 1 / arc_fps
  --     while true do
  --       clock.sleep(step_s)
  --       arc_redraw()
  --     end
  -- end)
  arc_clock = clock.run(
    function()
      local step_s = 1 / 10
      while true do
        clock.sleep(step_s)
        arc_process()
      end
  end)

  local sprocket = s_lattice:new_sprocket{
    action = arc_redraw,
    division = 1/32,
    enabled = true
  }
  s_lattice:start()
end

function cleanup()
  clock.cancel(redraw_clock)
  -- clock.cancel(arc_redraw_clock)
  clock.cancel(arc_clock)
  s_lattice:destroy()
end


-- ------------------------------------------------------------------------
-- timber

local function is_timber_playing(sample_id)
  return tab.count(Timber.samples_meta[sample_id].positions) ~= 0
end

local function timber_play(sample_id)
  local vel = 1
  if is_timber_playing(sample_id) then
    engine.noteOff(sample_id)
  end
  engine.noteOn(sample_id, MusicUtil.note_num_to_freq(60), vel, sample_id)
end


-- ------------------------------------------------------------------------
-- arc

local pos = 1

function arc_redraw()
  a:all(0)

  pos = (pos + 1)
  if pos > ARC_SEGMENTS then
    pos = pos % ARC_SEGMENTS
  end

  for r=1,4 do
    is_firing[r] = false
    for i, v in ipairs(sparse_patterns[r]) do
      local radial_pos = (i + pos) + params:get("ring_pattern_shift_"..r)
      while radial_pos < 0 do
        radial_pos = radial_pos + ARC_SEGMENTS
      end

    -- for i, v in ipairs(patterns[r]) do
      local l = 0
      if v == 1 then
        if radial_pos % ARC_SEGMENTS == 1 then
          l = 15
          is_firing[r] = true
          timber_play(r)
        else
          l = 3
        end
        a:led(r, radial_pos, l)
      end
    end

    -- a:led(r, 1, 15)
  end

  a:refresh()
end

function arc_process ()
  for r=1,4 do
    for i=1,ARC_SEGMENTS do
      if patterns[r][i] > 1 and patterns[r][i] > (DENSITY_MAX - params:get("ring_density_"..r)) then
      -- if patterns[r][i] == 1  then
        sparse_patterns[r][i] = 1
      else
        sparse_patterns[r][i] = 0
      end
    end
  end
end


-- ------------------------------------------------------------------------
-- controls

local k1 = false
local k2 = false
local k3 = false

function key(n, v)

  if n == 1 then
    k1 = (v == 1)
  end

  if n == 2 then
    k2 = (v == 1)
  end

  if n == 3 then
    k3 = (v == 1)
  end

  if k1 and k3 then
    params:set("gen_all", 1)
  end

end

function enc(n, d)
  if n == 1 then
    params:set("clock_tempo", params:get("clock_tempo") + d)
    return
  end

  if n == 2 then
    params:set("transpose", params:get("transpose") + d)
    return
  end

  if n == 3 then
    if k2 then
      params:set("filter_resonance", params:get("filter_resonance") + d/20)
    else
      params:set("filter_freq", params:get("filter_freq") + d * 50)
    end
    return
  end

end

arc_delta = function(r, d)
  if k1 then
    local now = os.time()
    if now - prev_pattern_refresh_t[r] > 1 then
      gen_pattern(patterns[r])
      prev_pattern_refresh_t[r] = now
    end
    return
  end

  if k3 then
    -- pattern_shifts[r] = math.floor(pattern_shifts[r] + d/5) % 64
    params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + d/5) % ARC_SEGMENTS)
    return
  end

  raw_densities[r] = util.clamp(raw_densities[r] + d, 0, ARC_RAW_DENSITY_RESOLUTION)
  params:set("ring_density_"..r, math.floor(util.linlin(0, ARC_RAW_DENSITY_RESOLUTION, 0, DENSITY_MAX, raw_densities[r])))
end



-- ------------------------------------------------------------------------
-- screen

function redraw()
  screen.clear()

  screen.move(1, 8)
  screen.text(params:get("clock_tempo") .. " BPM")

  screen.move(55, 8)
  screen.text(format_st(params:lookup_param("transpose")))

  screen.move(95, 8)
  screen.text(Formatters.format_freq(params:lookup_param("filter_freq")))

  screen.move(95, 16)
  screen.text("Q: "..params:get("filter_resonance"))

  local radius = 11
  for r=1,4 do

    local x = 128/4 * r - 2 * 3/4 * radius
    local y = 2*64/3

    local radius2 = radius
    if os.time() - prev_pattern_refresh_t[r] < 1 then
      radius2 = radius / 3
    end

    screen.move(x + radius2, y)
    screen.circle(x, y, radius2)
    if is_firing[r] then
      screen.fill()
    else
      screen.stroke()
    end

    for i=1,64 do
      if sparse_patterns[r][i] == 1 then
      local radial_pos = (i + pos) + params:get("ring_pattern_shift_"..r) + (ARC_SEGMENTS/4)
      while radial_pos < 0 do
        radial_pos = radial_pos + ARC_SEGMENTS
      end

        screen.pixel(x + (radius + 4) * cos(radial_pos/ARC_SEGMENTS) * -1, y + (radius + 4) * sin(radial_pos/ARC_SEGMENTS))
      end
    end

  end

  screen.update()
end
