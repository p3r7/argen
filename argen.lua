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
local pattern_time = require 'pattern_time'

local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local nb = include("argen/lib/nb/lib/nb")

hot_cursor = include("argen/lib/hot_cursor")
local pattern = include("argen/lib/pattern")
local varc = include("argen/lib/varc")
local playback = include("argen/lib/playback")
local sample = include("argen/lib/sample")
local oilcan = include("argen/lib/oilcan")

include("argen/lib/core")


-- ------------------------------------------------------------------------
-- engine

engine.name = "Timber"


-- ------------------------------------------------------------------------
-- conf

local FPS = 15
local ARC_FPS = 15
local VARC_RADIUS = 11
local GRID_FPS = 15
local ARC_REFRESH_SAMPLES = 10
local UNQUANTIZED_SAMPLES = 128

local SCREEN_H = 64
local SCREEN_W = 128

local MAX_ARCS = 16
-- local ARCS = 8
local ARCS = 4

local ARC_SEGMENTS = 64

local MAX_BPM = 2000

local FAST_FIRING_DELTA = 0.02

local is_firing = {}
local last_firing = {}


-- ------------------------------------------------------------------------
-- state

local a = nil
local g = nil

local SCREEN_CURSOR_LEN = 2
local screen_cursor = 1
local grid_cursor = 1
local play_btn_on = false

local has_arc = false
local has_grid = false

grid_all_rings_btn = false

local s_lattice

-- NB: higher resolution ring density values when setting via arc

local grid_shift = false
local shift_quant = 1

local NB_PATTERNS = 4
local NB_RECALLS = 4
local recalls = {}
local macros = {} -- NB: like mlr's patterns


-- ------------------------------------------------------------------------
-- script lifecycle

local redraw_clock
local grid_redraw_clock
local arc_redraw_clock
local arc_segment_refresh_clock
local arc_unquantized_clock

local arc_delta

function grid_connect_maybe(_g)
  if not has_grid then
    g = grid.connect()
    if g.device ~= nil then
      g.key = grid_key
      has_grid = true
    end
  end
end

function grid_remove_maybe(_g)
  if g.device.port == _g.port then
    -- current grid got deconnected
    has_grid = false
  end
end


function arc_connect_maybe(_a)
  if not has_arc then
    a = arc.connect()
    if a.name ~= "none" and a.device ~= nil then
      a.delta = arc_delta
      has_arc = true
    end
  end
end

function arc_remove_maybe(_a)
  if a.device.port == _a.port then
    -- current arc got deconnected
    has_arc = false
  end
end

grid.add = grid_connect_maybe
grid.remove = grid_remove_maybe

arc.add = arc_connect_maybe
arc.remove = arc_remove_maybe

params.action_read = function(filename, name, pset_number)
  pattern.load_for_pset(filename)
  -- for _, player in pairs(nb:get_players()) do
  -- 	player:stop_all()
  -- end
end

params.action_write = function(filename, name, pset_number)
  pattern.save_for_pset(filename)
end

params.action_delete = function(filename, name, pset_number)
  pattern.delete_for_pset(filename)
end



function init()
  screen.aa(1)
  screen.line_width(1)

  s_lattice = lattice:new{}

  grid_connect_maybe()
  arc_connect_maybe()

  local OUT_VOICE_MODES = {"sample", "nb"}
  local RANDOMIZE_MODES = {"ptrn", "ptrn+kit", "ptrn+smpl"}
  local ON_OFF = {"on", "off"}
  local OFF_ON = {"off", "on"}

  nb.voice_count = ARCS
  nb:init()

  params:add_option("flash", "Animation Flash", OFF_ON)

  params:add_option("gen_all_mode", "Randomize Mode", RANDOMIZE_MODES)

  params:add_trigger("all_oilcan", "Init All Oilcan")
  params:set_action("all_oilcan",
                    function(v)
                        if not oilcan.is_loaded() then
                          return
                        end
                        for r=1,ARCS do
                          params:set("ring_out_mode_"..r, tab.key(OUT_VOICE_MODES, "nb"))
                        end
                        oilcan.reset_all_rings_voice(ARCS, true)
  end)
  params:add_trigger("all_sample", "Init All Sample")
  params:set_action("all_sample",
                    function(v)
                      for r=1,ARCS do
                        params:set("ring_out_mode_"..r, tab.key(OUT_VOICE_MODES, "sample"))
                      end
  end)

  params:add_trigger("gen_all", "Randomize")
  params:set_action("gen_all",
                    function(v)
                      srand(os.time())

                      local any_sample = sample.is_any_ring_outmode(ARCS)
                      local any_oilcan = oilcan.is_any_ring_outmode(ARCS)

                      if params:string("gen_all_mode") == "ptrn+smpl"
                        or params:string("gen_all_mode") == "ptrn+kit" then
                        if any_sample then
                          sample.rescan_kits_maybe()
                        end
                      end

                      local kit
                      if params:string("gen_all_mode") == "ptrn+kit" then
                        if any_sample then
                          kit = sample.rnd_kit()
                          print("Loading sample kit: "..kit)
                        elseif any_oilcan then
                          oilcan.reset_all_rings_voice(ARCS)
                          local kit_id = oilcan.rnd_oilkit_id()
                          kit = oilcan.oilkit_id_to_name(kit_id)
                          oilcan.assign_all_rings_oilkit(ARCS, kit_id)
                          print("Loading oilkit: "..kit)
                        end
                      elseif params:string("gen_all_mode") == "ptrn+smpl" then
                        if oilcan.is_any_ring_outmode(ARCS) then
                          oilcan.reset_all_rings_voice(ARCS)
                        end
                      end


                      for r=1,ARCS do
                        -- reset individual ring params

                        params:set("ring_pattern_shift_"..r, 0)

                        if params:string("ring_out_mode_"..r) == "sample" then
                          params:set('transpose_'..r, params:get('transpose'))
                        end

                        -- and randomize others
                        params:set("ring_gen_pattern_"..r, 1)
                        params:set("ring_density_"..r, pattern.rnd_density())

                        if params:string("gen_all_mode") == "ptrn+kit" then
                          if sample.is_ring_outmode(r) then
                            sample.load_sample(r, sample.rnd_sample_for_kit(kit))
                          elseif oilcan.is_ring_outmode(r) then
                            params:set("ring_out_nb_note_"..r, oilcan.rnd_oilkit_note())
                          end
                        elseif params:string("gen_all_mode") == "ptrn+smpl" then
                          if sample.is_ring_outmode(r) then
                            sample.load_sample(r, sample.rnd_sample())
                          elseif oilcan.is_ring_outmode(r) then
                            params:set("ring_out_nb_note_"..r, oilcan.rnd_oilkit_note())
                          end
                        end
                      end


                    -- end
  end)

  playback.init(ARCS)
  playback.reset_heads()
  hot_cursor.init(ARCS)
  pattern.init(ARCS)

  for r=1,ARCS do
    is_firing[r] = false
    last_firing[r] = 0.0

    params:add_group("Ring " .. r, 11)

    params:add_trigger("ring_gen_pattern_"..r, "Generate "..r)
    params:set_action("ring_gen_pattern_"..r,
                      function(v)
                      pattern.gen_for_ring(r)
    end)


    params:add{type = "number", id = "ring_density_"..r, name = "Density "..r, min = 0, max = DENSITY_MAX, default = 0}
    params:set_action("ring_density_"..r, pattern.make_density_cb(r))
    params:add{type = "number", id = "ring_pattern_shift_"..r, name = "Pattern Shift "..r, min = -(ARC_SEGMENTS-1), max = (ARC_SEGMENTS-1), default = 0}

    params:add_option("ring_quantize_"..r, "Quantize "..r, ON_OFF)
    params:set_action("ring_quantize_"..r,
                      function(v)
                        if ON_OFF[v] == "on" then
                          params:hide("ring_bpm_"..r)
                        else
                          playback.sync_ring_unquant_head(r)
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


  sample.init_global_params(ARCS)

  nb:add_player_params()

  playback.init_transport()

  sample.init_params(ARCS)

  -- --------------------------------
  -- voice init

  sample.set_sefault_samples()
  oilcan.reset_all_rings_voice(ARCS)


  -- --------------------------------

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
        pattern.recompute_parse_patterns()
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
-- note trigger

function note_trigger(r)
  if sample.is_ring_outmode(r) then
    sample.play(r)
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
  if playback.is_paused_or_stopepd() then
    return
  end

  playback.quant_head_advance(ARC_SEGMENTS)

  for r=1,ARCS do
    if params:string("ring_quantize_"..r) == "on" then
      is_firing[r] = false
      for i, v in ipairs(pattern.sparse_pattern_for_ring(r)) do
        -- local radial_pos = (i + pos_quant) + params:get("ring_pattern_shift_"..r)
        -- while radial_pos < 0 do
        --   radial_pos = radial_pos + ARC_SEGMENTS
        -- end

        -- local radial_pos = playback.quant_head_2_radial_pos
        local radial_pos = playback.quant_head_2_radial_pos(ARC_SEGMENTS, params:get("ring_pattern_shift_"..r), i)

        if v == 1 then
          if radial_pos % ARC_SEGMENTS == 1 and not playback.is_ring_muted(r) then
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
  if playback.is_paused_or_stopepd() then
    return
  end

  for r=1,ARCS do
    if params:string("ring_quantize_"..r) == "off" then
      is_firing[r] = false

      local prev_pos = playback.ring_head_pos(r)

      local bpm = params:get("ring_bpm_"..r)
      local step = bpm / UNQUANTIZED_SAMPLES
      step = step / 8
      playback.unquant_head_advance(r, step, ARC_SEGMENTS)

      local pos = playback.ring_head_pos(r)

      if math.floor(pos) == math.floor(prev_pos) then
        goto NEXT
      end

      for i, v in ipairs(pattern.sparse_pattern_for_ring(r)) do
        local radial_pos = (i + round(pos)) + params:get("ring_pattern_shift_"..r)
        while radial_pos < 0 do
          radial_pos = radial_pos + ARC_SEGMENTS
        end

        if v == 1 then
          if radial_pos % ARC_SEGMENTS == 1 and not playback.is_ring_muted(r) then
            note_trigger(r)
            is_firing[r] = true
            last_firing[r] = os.clock()
          end
        end
      end

      ::NEXT::
    end
  end
end

-- local pos = 1

function arc_redraw()
  a:all(0)

  for r=1,ARCS do

    local display_pos = playback.ring_head_pos(r)

    for i, v in ipairs(pattern.sparse_pattern_for_ring(r)) do
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




-- ------------------------------------------------------------------------
-- grid

function grid_redraw()
  g:all(0)

  -- --------------------------------
  -- left pane - pattern editor

  local r = grid_cursor

  local pos = playback.ring_head_pos(r)

  for x=1, math.min(g.cols, 8) do
    for y=1, g.rows do
      local i_head = x + ((y-1) * 8)
      local i = ARC_SEGMENTS - i_head
      i = mod1(i - params:get("ring_pattern_shift_"..r), 64)
      while i < 0 do
        i = i + ARC_SEGMENTS
      end

      local v = pattern.sparse_pattern_for_ring(r)[i]
      local led_v = 0
      if v == 1 then
        led_v = pattern.led(r, i)
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

  -- --------------------------------
  -- right pane - advanced controls

  if g.cols > 8 then
    local l = 2

    -- (quantized) pattern shift
    l = (shift_quant == 1) and 5 or 2
    g:led(12, 1, l) -- 1
    l = (shift_quant == 2) and 5 or 2
    g:led(13, 1, l) -- 2
    l = (shift_quant == 4) and 5 or 2
    g:led(14, 1, l) -- 4
    l = (shift_quant == 8) and 5 or 2
    g:led(15, 1, l) -- 8
    l = (shift_quant == 16) and 5 or 2
    g:led(16, 1, l) -- 16
    -- -/+
    g:led(13, 2, 2) -- -
    g:led(15, 2, 2) -- +

    -- stop / pause / start
    l = 2
    if playback.is_running() then l = 5 end
    g:led(13, 5, l) -- start
    l = 2
    if playback.is_paused() then l = 5 end
    g:led(14, 5, l) -- pause
    l = 2
    if playback.is_stopped() then l = 5 end
    g:led(15, 5, l) -- stop

    -- ring select
    --  - all
    l = 3
    if hot_cursor.are_all() then l = 5 end
    g:led(9, 7, l)
    --  - independant
    local x_start = 11
    for r=1,ARCS do
      local x = x_start + r - 1
      local l = 2
      if grid_cursor == r then
        if hot_cursor.is_active(r) then
          l = 10
        else
          l = 5
        end
      elseif hot_cursor.is_active(r) then
        l = 4
      end
      g:led(x, 7, l)
    end
  end

  g:refresh()
end


function grid_key(x, y, z)
  local r = grid_cursor

  -- --------------------------------
  -- left pane - pattern editor

  if x <= math.min(g.cols, 8) then
    if z >= 1 then
      local i = ARC_SEGMENTS - (x + ((y-1) * 8))
      i = mod1(i - params:get("ring_pattern_shift_"..r), 64)

      local v = pattern.sparse_pattern_for_ring(r)[i]
      if v == 1 then
        pattern.set(r, i, 0)
      else
        if params:get("ring_density_"..r) > 0 then
          -- FIXME: buggy for ring_density_<r> set to max
          pattern.set_from_density(r, i, params:get("ring_density_"..r))
        end
      end
    end
  end

  -- --------------------------------
  -- right pane - advanced controls

  -- pattern shift
  if x == 16 and y == 1 then
    -- shift 16
    grid_shift = (z >= 1)
    if grid_shift then
      shift_quant = 16
    else
      shift_quant = 1
    end
  elseif x == 15 and y == 1 then
    -- shift 8
    grid_shift = (z >= 1)
    if grid_shift then
      shift_quant = 8
    else
      shift_quant = 1
    end
  elseif x == 14 and y == 1 then
      -- shift 4
      grid_shift = (z >= 1)
      if grid_shift then
        shift_quant = 4
      else
        shift_quant = 1
      end
  elseif x == 13 and y == 1 then
    -- shift 2
    grid_shift = (z >= 1)
    if grid_shift then
      shift_quant = 2
    else
      shift_quant = 1
    end
  elseif x == 12 and y == 1 then
    -- shift 1
    grid_shift = (z >= 1)
    shift_quant = 1
  end

  if x == 13 and y == 2 and z >= 1 then
    if hot_cursor.are_all() then
      for r2=1,ARCS do
        params:set("ring_pattern_shift_"..r2, math.floor(params:get("ring_pattern_shift_"..r2) - 1 * shift_quant) % ARC_SEGMENTS)
      end
    else
      params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) - 1 * shift_quant) % ARC_SEGMENTS)
    end
  elseif x == 15 and y == 2 and z >= 1 then
    if hot_cursor.are_all() then
      for r2=1,ARCS do
        params:set("ring_pattern_shift_"..r2, math.floor(params:get("ring_pattern_shift_"..r2) + 1 * shift_quant) % ARC_SEGMENTS)
      end
    else
      params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + 1 * shift_quant) % ARC_SEGMENTS)
    end
  end

  -- start/pause/stop
  if x == 13 and y == 5 then
    play_btn_on = (z >= 1)

    if play_btn_on then
      playback.start(true)
    end
  elseif x == 14 and y == 5 and (z >= 1)then
    playback.pause(true)
  elseif x == 15 and y == 5 and (z >= 1) then
    if play_btn_on then
      playback.restart(true)
    else
      playback.stop(true)
    end
  end

  -- ring select / mute
  --  - all
  local is_grid_all_k = false
  if x == 9 and y == 7 then
    grid_all_rings_btn = (z >= 1)
  end

  --  - independant
  local x_start = 11
  local is_curr_key_cursor_sel = false
  for r=1,ARCS do
    local rx = x_start + r - 1
    if rx == x and y == 7 then
      is_curr_key_cursor_sel = true
      local pressed = (z >= 1)
      if pressed then
        if not hot_cursor.is_any_active() then
          grid_cursor = r
        end
      end
      hot_cursor.set(r, pressed)
    end
  end

  -- recompute global state
  hot_cursor.recompute(grid_all_rings_btn)

  for r=1,ARCS do
    playback.unmute_ring(r)
    if play_btn_on and hot_cursor.is_active(r) then
      playback.mute_ring(r)
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

  if grid_shift then
    local sign = math.floor(d/math.abs(d))
    params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + sign * shift_quant) % ARC_SEGMENTS)
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
        sample.global_pitch_transpose_delta(ARCS, d)
      else
        local has_effect = enc_no_arc(screen_cursor, d)
        if has_effect then
          return
        end
      end
    else
      sample.global_pitch_transpose_delta(ARCS, d)
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

arc_delta_single = function(r, d)
  if k1 then
    if not pattern.was_ring_gen_recently(r) then
      pattern.gen_for_ring(r)
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

  if grid_shift then
    local sign = math.floor(d/math.abs(d))
    params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + sign * shift_quant) % ARC_SEGMENTS)
    return true
  end
  if k3 then
    -- pattern_shifts[r] = math.floor(pattern_shifts[r] + d/5) % 64
    params:set("ring_pattern_shift_"..r, math.floor(params:get("ring_pattern_shift_"..r) + d/7) % ARC_SEGMENTS)
    return
  end
  params:set("ring_density_"..r, pattern.density_delta_from_arc(r, d))
end

arc_delta = function(r, d)
  if hot_cursor.are_all() then
    for r=1,ARCS do
      arc_delta_single(r, d)
    end
  else
    grid_cursor = r
    arc_delta_single(r, d)
  end
end


-- ------------------------------------------------------------------------
-- screen

function redraw()
  screen.clear()

  screen.move(1, 8)
  screen.text(params:get("clock_tempo") .. " BPM")

  screen.move(55, 8)
  screen.text(sample.format_st(params:lookup_param("transpose")))

  screen.move(95, 8)
  screen.text(Formatters.format_freq(params:lookup_param("filter_freq")))

  screen.move(95, 16)
  screen.text("Q: "..params:get("filter_resonance"))

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

    local x = SCREEN_W/nb_arcs_in_col * r2 - 2 * 3/nb_arcs_in_col * VARC_RADIUS

    local radius = VARC_RADIUS
    if pattern.was_ring_gen_recently(r) then
      radius = VARC_RADIUS / 3
    end

    local level = 15
    if playback.is_ring_muted(r) then
      level = 5
    end

    local fill = ((is_firing[r] or math.abs(os.clock() - last_firing[r]) < FAST_FIRING_DELTA) and params:string("flash") == "on")

    local offset = playback.ring_head_pos(r) + params:get("ring_pattern_shift_"..r)

    varc.redraw(x, y, radius, level, fill, pattern.sparse_pattern_for_ring(r), offset)

    if params:string("ring_quantize_"..r) == "off" then
      screen.pixel(x, y)
    end

    screen.level(15)

    screen.aa(0)
    screen.line_width(1.5)
    screen.level(5)
    if not has_arc then
      if r >= screen_cursor and r < screen_cursor + SCREEN_CURSOR_LEN  then
        screen.move(x - radius - 3, y + radius + 5)
        screen.line(x + radius + 3, y + radius + 5)
        screen.stroke()
      end
    end

    if has_grid then
      if r == grid_cursor then
        screen.move(x - radius - 1, y + radius + 8)
        screen.line(x + radius + 1, y + radius + 8)
        screen.stroke()
      end
    end
    screen.aa(1)
    screen.line_width(1)
    screen.level(15)

    local display_pos = playback.ring_head_pos(r)
  end

  screen.update()
end
