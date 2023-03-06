-- argen.
-- @eigen
--
--   arc
--         rhythm
--                 generator
--
--    ▼ instructions below ▼
--
--   when arc detected:
-- arc        - density
-- K2 + arc   - quantize off
--              & speed control
-- K2 + K3
--    + arc   - quantize on
-- K3 + arc   - offset
-- K1 + arc   - randomize ring
-- K1 + K2    - randomize all
-- E1         - clock speed
-- E2         - transpose sample
-- E3         - filter freq
-- K2 + E3    - filter res
--
--   when no arc detected, a
-- cursor appears & allows
-- selecting 2 rings at a time,
-- w/ E2 / E3 acting as arc:
-- E1         - select rings
-- E2/E3      - density
-- K2 + E2/E3 - quantize off
--              & speed control
-- K2 + K3
--    + E2/E3 - quantize on
-- K3 + E2/E3 - offset
-- K1 + E1    - clock speed
-- K1 + K2    - randomize all
-- K1 + E2    - transpose sample
-- K1 + E3    - filter freq
--
-- original idea by @stretta



-- ------------------------------------------------------------------------
-- deps

local lattice = require "lattice"
local MusicUtil = require "musicutil"
local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local nb = include("argen/lib/nb/lib/nb")


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

local FPS = 15
local ARC_FPS = 15
local GRID_FPS = 15
local ARC_REFRESH_SAMPLES = 10
local UNQUANTIZED_SAMPLES = 128

local SCREEN_H = 64
local SCREEN_W = 128

local MAX_ARCS = 16

local INIT_POS = 1

-- local ARCS = 8
local ARCS = 4
local ARC_SEGMENTS = 64

local DENSITY_MAX = 10
local ARC_RAW_DENSITY_RESOLUTION = 1000

local MAX_BPM = 2000

local FAST_FIRING_DELTA = 0.02

-- ------------------------------------------------------------------------
-- state

local a = nil
local g = nil

local has_arc = false
local SCREEN_CURSOR_LEN = 2
local screen_cursor = 1
local grid_cursor = 1

local has_grid = false

local s_lattice

patterns = {}
sparse_patterns = {}

pos_quant = INIT_POS
unquantized_rot_pos = {}

-- NB: hisher resolution ring density values when setting via arc
local raw_densities = {}

local is_firing = {}
local last_firing = {}

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

function round(v)
  return math.floor(v+0.5)
end

local function cos(x)
  return math.cos(math.rad(x * 360))
end

local function sin(x)
  return -math.sin(math.rad(x * 360))
end

function bpm_to_fps(v)
  return v / 60
end

function fps_to_bpm(v)
  return v * 60
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

function gen_ring_pattern(r)
  gen_pattern(patterns[r])
  prev_pattern_refresh_t[r] = os.time()
end


-- ------------------------------------------------------------------------
-- script lifecycle

local redraw_clock
local grid_redraw_clock
local arc_redraw_clock
local arc_segment_refresh_clock
local arc_unquantized_clock

local arc_delta

function init()
  screen.aa(1)
  screen.line_width(1)

  s_lattice = lattice:new{}

  a = arc.connect(1)
  if a.name ~= "none" and a.device ~= nil then
    a.delta = arc_delta
    has_arc = true
  end

  g = grid.connect(1)
  if g.device ~= nil then
    g.key = grid_key
    has_grid = true
end

  local OUT_VOICE_MODES = {"sample", "nb"}
  local ON_OFF = {"on", "off"}
  local OFF_ON = {"off", "on"}

  nb.voice_count = 4
  nb:init()

  params:add_option("flash", "Animation Flash ", OFF_ON)

  params:add_trigger("gen_all", "Randomize")
  params:set_action("gen_all",
                    function(v)
                      srand(os.time())
                      for r=1,ARCS do
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

  for r=1,ARCS do
    patterns[r] = gen_pattern()
    sparse_patterns[r] = gen_empty_pattern()
    raw_densities[r] = 0
    prev_pattern_refresh_t[r] = 0
    unquantized_rot_pos[r] = INIT_POS
    is_firing[r] = false
    last_firing[r] = 0.0

    params:add_group("Ring " .. r, 11)

    params:add_trigger("ring_gen_pattern_"..r, "Generate "..r)
    params:set_action("ring_gen_pattern_"..r,
                      function(v)
                      gen_ring_pattern(r)
    end)

    params:add{type = "number", id = "ring_density_"..r, name = "Density "..r, min = 0, max = DENSITY_MAX, default = 0}
    params:set_action("ring_density_"..r,
                      function(v)
                        -- NB: reset arc raw density counter
                        if math.abs(util.linlin(0, ARC_RAW_DENSITY_RESOLUTION, 0, DENSITY_MAX, raw_densities[r]) - v) >= (1 * DENSITY_MAX / 10)  then
                          raw_densities[r] = math.floor(util.linlin(0, DENSITY_MAX, 0, ARC_RAW_DENSITY_RESOLUTION, v))
                        end
                      end
    )
    params:add{type = "number", id = "ring_pattern_shift_"..r, name = "Pattern Shift "..r, min = -(ARC_SEGMENTS-1), max = (ARC_SEGMENTS-1), default = 0}

    params:add_option("ring_quantize_"..r, "Quantize "..r, ON_OFF)
    params:set_action("ring_quantize_"..r,
                      function(v)
                        if ON_OFF[v] == "on" then
                          params:hide("ring_bpm_"..r)
                        else
                          unquantized_rot_pos[r] = pos_quant
                          params:set("ring_bpm_"..r, params:get("clock_tempo"))
                          params:show("ring_bpm_"..r)
                        end
                        _menu.rebuild_params()
                      end
    )
    params:add{type = "number", id = "ring_bpm_"..r, name = "BPM "..r, min = -MAX_BPM, max = MAX_BPM, default = 20}
    params:hide("ring_bpm_"..r)

    params:add_option("ring_out_mode_"..r, "Out Mode "..r, OUT_VOICE_MODES)
    params:set_action("ring_out_mode_"..r,
                      function(v)
                        if OUT_VOICE_MODES[v] == "nb" then
                          params:show("ring_out_nb_voice_"..r)
                          params:show("ring_out_nb_note_"..r)
                          params:show("ring_out_nb_vel_"..r)
                          params:show("ring_out_nb_dur_"..r)
                        else
                          params:hide("ring_out_nb_voice_"..r)
                          params:hide("ring_out_nb_note_"..r)
                          params:hide("ring_out_nb_vel_"..r)
                          params:hide("ring_out_nb_dur_"..r)
                        end
                        _menu.rebuild_params()
                      end
    )
    nb:add_param("ring_out_nb_voice_"..r, "nb Voice "..r)
    params:add{type = "number", id = "ring_out_nb_note_"..r, name = "nb Note "..r, min = 0, max = 127, default = 60}
    params:add{type = "control", id = "ring_out_nb_vel_"..r, name = "nb Velocity "..r, controlspec = ControlSpec.new(0, 1, "lin", 0, 0.8, "")}
    params:add{type = "control", id = "ring_out_nb_dur_"..r, name = "nb Dur "..r, controlspec = ControlSpec.new(0, 1, "lin", 0, 0.2, "")}

    params:hide("ring_out_nb_voice_"..r)
    params:hide("ring_out_nb_note_"..r)
    params:hide("ring_out_nb_vel_"..r)
    params:hide("ring_out_nb_dur_"..r)
  end


  nb:add_player_params()

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
      local step_s = 1 / FPS
      while true do
        clock.sleep(step_s)
        redraw()
      end
  end)
  grid_redraw_clock = clock.run(
    function()
      local step_s = 1 / GRID_FPS
      while true do
        clock.sleep(step_s)
        grid_redraw()
      end
  end)
  arc_redraw_clock = clock.run(
    function()
      local step_s = 1 / ARC_FPS
      while true do
        clock.sleep(step_s)
        arc_redraw()
      end
  end)
  arc_segment_refresh_clock = clock.run(
    function()
      local step_s = 1 / ARC_REFRESH_SAMPLES
      while true do
        clock.sleep(step_s)
        arc_segment_refresh()
      end
  end)
  arc_unquantized_clock = clock.run(
    function()
      local step_s = 1 / UNQUANTIZED_SAMPLES
      while true do
        clock.sleep(step_s)
        arc_unquantized_trigger()
      end
  end)

  local sprocket = s_lattice:new_sprocket{
    action = arc_quantized_trigger,
    division = 1/32,
    enabled = true
  }
  s_lattice:start()
end

function cleanup()
  clock.cancel(redraw_clock)
  clock.cancel(grid_redraw_clock)
  clock.cancel(arc_redraw_clock)
  clock.cancel(arc_segment_refresh_clock)
  clock.cancel(arc_unquantized_clock)
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
-- note trigger

function note_trigger(r)
  if params:string("ring_out_mode_"..r) == "sample" then
    timber_play(r)
  elseif params:string("ring_out_mode_"..r) == "nb" then
    local player = params:lookup_param("ring_out_nb_voice_"..r):get_player()
    local note = params:get("ring_out_nb_note_"..r)
    local vel = params:get("ring_out_nb_vel_"..r)
    local dur = params:get("ring_out_nb_dur_"..r)
    player:play_note(note, vel, dur)
  end
end


-- ------------------------------------------------------------------------
-- arc

function pos_2_radial_pos(pos, shift, i)
  if i == nil then i = 1 end
  local radial_pos = ((i + pos) + shift)
  while radial_pos < 0 do
    radial_pos = radial_pos + ARC_SEGMENTS
  end
  return radial_pos
end

function arc_quantized_trigger()

  pos_quant = pos_quant + 1
  if pos_quant > ARC_SEGMENTS then
      pos_quant = pos_quant % ARC_SEGMENTS
  end

  for r=1,ARCS do
    if params:string("ring_quantize_"..r) == "on" then
      is_firing[r] = false
      for i, v in ipairs(sparse_patterns[r]) do
        -- local radial_pos = (i + pos_quant) + params:get("ring_pattern_shift_"..r)
        -- while radial_pos < 0 do
        --   radial_pos = radial_pos + ARC_SEGMENTS
        -- end
        local radial_pos = pos_2_radial_pos(pos_quant, params:get("ring_pattern_shift_"..r), i)

        if v == 1 then
          if radial_pos % ARC_SEGMENTS == 1 then
            note_trigger(r)
            is_firing[r] = true
            last_firing[r] = os.clock()
          end
        end
      end
    end
  end
end

function arc_unquantized_trigger()
  for r=1,ARCS do
    if params:string("ring_quantize_"..r) == "off" then
      local is_already_firing = is_firing[r]
      is_firing[r] = false
      local bpm = params:get("ring_bpm_"..r)
      local step = bpm / UNQUANTIZED_SAMPLES
      step = step / 8
      unquantized_rot_pos[r] = (unquantized_rot_pos[r] + step) % ARC_SEGMENTS

      for i, v in ipairs(sparse_patterns[r]) do
        local radial_pos = (i + round(unquantized_rot_pos[r])) + params:get("ring_pattern_shift_"..r)
        while radial_pos < 0 do
          radial_pos = radial_pos + ARC_SEGMENTS
        end
        -- radial_pos = round(radial_pos)

        if v == 1 then
          if radial_pos % ARC_SEGMENTS == 1 then
            is_firing[r] = true
            if not is_already_firing then
              note_trigger(r)
              last_firing[r] = os.clock()
            end
          end
        end
      end
    end
  end
end

-- local pos = 1

function arc_redraw()
  a:all(0)

  for r=1,ARCS do

    local display_pos = 1

    if params:string("ring_quantize_"..r) == "on" then
      display_pos = pos_quant

      -- NB: this kinda works but is imprecise
      -- local step = (params:get("clock_tempo") * 2) / fps_to_bpm(ARC_FPS)
    else
      -- TODO: redo this
      -- local bpm_ratio = params:get("ring_bpm_"..r) / fps_to_bpm(ARC_FPS)
      -- local step = bpm_ratio
      -- local display_pos = pos_quant + step
      -- if display_pos > ARC_SEGMENTS then
      --   display_pos = display_pos % ARC_SEGMENTS
      -- end

      display_pos = round(unquantized_rot_pos[r])
    end

    for i, v in ipairs(sparse_patterns[r]) do
      local radial_pos = (i + display_pos) + params:get("ring_pattern_shift_"..r)
      while radial_pos < 0 do
        radial_pos = radial_pos + ARC_SEGMENTS
      end

      local l = 0
      if v == 1 then
        a:led(r, radial_pos, 3)
      end
    end

    if is_firing[r] or math.abs(os.clock() - last_firing[r]) < FAST_FIRING_DELTA then
      a:led(r, 1, 15)
    end

  end

  a:refresh()
end

function arc_segment_refresh()
  for r=1,ARCS do
    for i=1,ARC_SEGMENTS do
      if params:get("ring_density_"..r) == 0 then
        sparse_patterns[r][i] = 0
      else
        if patterns[r][i] > 1 and patterns[r][i] > (DENSITY_MAX - params:get("ring_density_"..r)) then
          sparse_patterns[r][i] = 1
        else
          sparse_patterns[r][i] = 0
        end
      end
    end
  end
end


-- ------------------------------------------------------------------------
-- grid

function grid_redraw()
  g:all(0)

  local r = grid_cursor

  local pos
  if params:string("ring_quantize_"..r) == "on"  then
    pos = pos_quant
  else
    pos = round(unquantized_rot_pos[r])
  end

  for x=1, math.min(g.cols, 8) do
    for y=1, g.rows do
      local i_head = x + ((y-1) * 8)
      local i = ARC_SEGMENTS - i_head
      i = (i - params:get("ring_pattern_shift_"..r)) % 64
      while i < 0 do
        i = i + ARC_SEGMENTS
      end

      local v = sparse_patterns[r][i]
      local led_v = 0
      if v == 1 then
        led_v = round(util.linlin(0, DENSITY_MAX, 1, 8, patterns[r][i]))
      end

      if pos == i_head then
        if led_v > 1 then
          led_v = 15
        else
          led_v = 5
        end
      end
      g:led(x, y, led_v)
    end
  end
  g:refresh()
end

function grid_key(x, y, z)
  local r = grid_cursor

  -- pattern edit
  if z >= 1 then
    if x <= math.min(g.cols, 8) then
      local i = ARC_SEGMENTS - (x + ((y-1) * 8))
      i = (i - params:get("ring_pattern_shift_"..r)) % 64

      local v = sparse_patterns[r][i]
      if v == 1 then
        patterns[r][i] = 0
      else
        if params:get("ring_density_"..r) > 0 then
          -- FIXME: buggy for ring_density_<r> set to max
          patterns[r][i] = DENSITY_MAX + 1 - params:get("ring_density_"..r)
        end
      end
    end
  end

end

-- ------------------------------------------------------------------------
-- controls

local k1 = false
local k2 = false
local k3 = false

local k2_k3 = false
local k3_k2 = false

function key(n, v)

  -- combo of modifiers
  if n == 2 then
    if k3 then
      k3_k2 = (v == 1)
    end
  end
  if n == 3 then
    if k2 then
      k2_k3 = (v == 1)
    end
  end

  -- single modifiers
  if n == 1 then
    k1 = (v == 1)
  end

  if n == 2 then
    k2 = (v == 1)
  end

  if n == 3 then
    k3 = (v == 1)
  end

  if not k2 or not k3 then
    k2_k3 = false
    k3_k2 = false
  end

  if k1 and k3 then
    params:set("gen_all", 1)
  end

end

function enc_no_arc(r, d)
  grid_cursor = r

  if k2_k3 then
    params:set("ring_quantize_"..r, 1) -- on
    return true
  end

  if k2 then
    params:set("ring_quantize_"..r, 2) -- off
    params:set("ring_bpm_"..r, math.floor(params:get("ring_bpm_"..r) + d * 5))
    return true
  end

  if k3 then
    params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + d) % ARC_SEGMENTS)
    return true
  end

  local sign = math.floor(d/math.abs(d))
  params:set("ring_density_"..r, params:get("ring_density_"..r) + sign)
  return true

end

function enc(n, d)
  if n == 1 then
    if not has_arc then
      if k1 then
        params:set("clock_tempo", params:get("clock_tempo") + d)
      else
        local sign = math.floor(d/math.abs(d))
        screen_cursor = util.clamp(screen_cursor + sign, 1, ARCS - SCREEN_CURSOR_LEN + 1)
      end
    else
      params:set("clock_tempo", params:get("clock_tempo") + d)
    end
    return
  end

  if n == 2 then
    if not has_arc then
      if k1 then
        params:set("transpose", params:get("transpose") + d)
      else
        local has_effect = enc_no_arc(screen_cursor, d)
        if has_effect then
          return
        end
      end
    else
      params:set("transpose", params:get("transpose") + d)
    end
    return
  end

  if n == 3 then
    if not has_arc then
      if k1 then
          params:set("filter_freq", params:get("filter_freq") + d * 50)
      else
        local has_effect = enc_no_arc(screen_cursor+1, d)
        if has_effect then
          return
        end
      end
    end

    if k2 then
      params:set("filter_resonance", params:get("filter_resonance") + d/20)
    else
      params:set("filter_freq", params:get("filter_freq") + d * 50)
    end
    return
  end

end

arc_delta = function(r, d)
  grid_cursor = r

  if k1 then
    if os.time() - prev_pattern_refresh_t[r] > 1 then
      gen_ring_pattern(r)
    end
    return
  end

  if k2_k3 then
    params:set("ring_quantize_"..r, 1) -- on
    return
  end

  if k2 then
    params:set("ring_quantize_"..r, 2) -- off
    params:set("ring_bpm_"..r, math.floor(params:get("ring_bpm_"..r) + d))
    return
  end

  if k3 then
    -- pattern_shifts[r] = math.floor(pattern_shifts[r] + d/5) % 64
    params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + d/7) % ARC_SEGMENTS)
    return
  end

  -- NB: it feels better to undo faster
  if d < 0 then
    d = d + d * 1/3
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
  local MAX_ARCS_PER_LINE = 8
  for r=1,ARCS do

    local r2 = r
    while r2 > MAX_ARCS_PER_LINE do
      r2 = r2 - MAX_ARCS_PER_LINE
    end

    local y_ratio = 2/3
    if ARCS > MAX_ARCS_PER_LINE then
      if r <= MAX_ARCS_PER_LINE then
        y_ratio = 1/2
      else
        y_ratio = 3/4
      end
    end
    local y = y_ratio * SCREEN_H

    local nb_arcs_in_col = ARCS
    while r > MAX_ARCS_PER_LINE and nb_arcs_in_col > MAX_ARCS_PER_LINE do
      nb_arcs_in_col = nb_arcs_in_col - MAX_ARCS_PER_LINE
    end
    nb_arcs_in_col = math.min(nb_arcs_in_col, MAX_ARCS_PER_LINE)

    local x = SCREEN_W/nb_arcs_in_col * r2 - 2 * 3/nb_arcs_in_col * radius

    local radius2 = radius
    if os.time() - prev_pattern_refresh_t[r] < 1 then
      radius2 = radius / 3
    end

    screen.move(x + radius2, y)
    screen.circle(x, y, radius2)
    if (is_firing[r] or math.abs(os.clock() - last_firing[r]) < FAST_FIRING_DELTA) and params:string("flash") == "on" then
      screen.fill()
    else
      screen.stroke()
    end

    if params:string("ring_quantize_"..r) == "off" then
      screen.pixel(x, y)
    end

    screen.aa(0)
    screen.line_width(1.5)
    screen.level(5)
    if not has_arc then
      if r >= screen_cursor and r < screen_cursor + SCREEN_CURSOR_LEN  then
        screen.move(x - radius2 - 3, y + radius2 + 5)
        screen.line(x + radius2 + 3, y + radius2 + 5)
        screen.stroke()
      end
    end

    if has_grid then
      if r == grid_cursor then
        screen.move(x - radius2 - 1, y + radius2 + 8)
        screen.line(x + radius2 + 1, y + radius2 + 8)
        screen.stroke()
      end
    end
    screen.aa(1)
    screen.line_width(1)
    screen.level(15)

    for i=1,ARC_SEGMENTS do

      if params:string("ring_quantize_"..r) == "on" then
        display_pos = pos_quant

        -- NB: this kinda works but is imprecise
        -- local step = (params:get("clock_tempo") * 2) / fps_to_bpm(FPS)
      else
        -- TODO: redo this
        -- local bpm_ratio = params:get("ring_bpm_"..r) / fps_to_bpm(FPS)
        -- local step = bpm_ratio
        -- local display_pos = pos_quant + step
        -- if display_pos > ARC_SEGMENTS then
        --   display_pos = display_pos % ARC_SEGMENTS
        -- end

        display_pos = round(unquantized_rot_pos[r])

      end

      if sparse_patterns[r][i] == 1 then
      local radial_pos = (i + display_pos) + params:get("ring_pattern_shift_"..r) + (ARC_SEGMENTS/4)
      while radial_pos < 0 do
        radial_pos = radial_pos + ARC_SEGMENTS
      end

        screen.pixel(x + (radius + 4) * cos(radial_pos/ARC_SEGMENTS) * -1, y + (radius + 4) * sin(radial_pos/ARC_SEGMENTS))
      end
    end

  end

  screen.update()
end
