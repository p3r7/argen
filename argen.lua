-- argen.
-- @eigen
--
-- port of arc rythm generator by @stretta



-- ------------------------------------------------------------------------
-- engine

engine.name = "Timber"
local Timber = include("timber/lib/timber_engine")
local MusicUtil = require "musicutil"


-- ------------------------------------------------------------------------
-- conf

local fps = 15
local arc_fps = 15


-- ------------------------------------------------------------------------
-- state

local a

local patterns = {}
local sparse_patterns = {}

raw_densities = {}
densities = {}


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


-- ------------------------------------------------------------------------
-- patterns

function gen_pattern(pattern)
  if pattern == nil then
    pattern = {}
  end

  srand(math.random(10000))

  for i=1,64 do

    local v = 0

    if i%4 == 0 then
      v = 1
    else
      v = math.random(2) - 1
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

  a = arc.connect(1)
  a.delta = arc_delta

  for r=1,4 do
    patterns[r] = gen_pattern()
    sparse_patterns[r] = gen_empty_pattern()
    raw_densities[r] = 0
    densities[r] = 0
  end

  Timber.options.PLAY_MODE_BUFFER_DEFAULT = 4
  Timber.options.PLAY_MODE_STREAMING_DEFAULT = 3
  params:add_separator()
  Timber.add_params()
  for i = 1, 4 do
    local extra_params = {
      {type = "option", id = "launch_mode_" .. i, name = "Launch Mode", options = {"Gate", "Toggle"}, default = 1, action = function(value)
         Timber.setup_params_dirty = true
      end},
    }
    params:add_separator()
    Timber.add_sample_params(i, true, extra_params)
    params:set('play_mode_' .. i, 3) -- "1-Shot" in options.PLAY_MODE_BUFFER
    --params:set('amp_env_sustain_' .. i, 0)
  end

  Timber.load_sample(1, _path.audio .. 'common/808/808-BD.wav')
  Timber.load_sample(2, _path.audio .. 'common/808/808-CP.wav')
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
  arc_redraw_clock = clock.run(
    function()
      local step_s = 1 / arc_fps
      while true do
        clock.sleep(step_s)
        arc_redraw()
      end
  end)
  arc_clock = clock.run(
    function()
      local step_s = 1 / 10
      while true do
        clock.sleep(step_s)
        arc_process()
      end
  end)
end

function cleanup()
  clock.cancel(redraw_clock)
  clock.cancel(arc_redraw_clock)
  clock.cancel(arc_clock)
end


-- ------------------------------------------------------------------------

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
-- arc utils

local function arc_pos_to_rad(pos)
  -- NB: value of 40 is super empirical
  -- it depends of the overal length (64) but also the radius

  local tau = math.pi * 2
  return util.linlin(1, 64, 0, 40/tau, pos)
end

local function arc_segment_pos_bak(a, ring, from, to, level)

  if from < 0 then
    from = 64 + from
  end
  if to < 0 then
    to = 64 + to
  end

  local from_angle = arc_pos_to_rad(from)
  local to_angle = arc_pos_to_rad(to)

  -- if from_angle < to_angle then
    -- to_angle = to_angle + 1
  -- end

  a:segment(ring, from_angle, to_angle, level)
end

local function arc_segment_pos(a, ring, from, to, level)
  a:segment(ring, from/10, to/10, level)
end

-- ------------------------------------------------------------------------
-- arc

local pos = 1

function arc_redraw()
  a:all(0)

  pos = (pos + 1)
  if pos > 64 then
    pos = pos % 64
  end

  -- NB: can only do 1 arc:segment call / redraw frame!

  -- arc_segment_pos(a, 1, pos - 3, pos, 15)
  -- arc_segment_pos(a, 1, pos - 5, pos - 3, 10)
  -- arc_segment_pos(a, 1, pos - 10, pos - 5, 5)
  -- arc_segment_pos(a, 1, 59, 62, 15)

  for r=1,4 do
    for i, v in ipairs(sparse_patterns[r]) do
    -- for i, v in ipairs(patterns[r]) do
      local l = 0
      if v == 1 then
        if (i + pos) % 64 == 1 then
          l = 15
          timber_play(r)
        else
          l = 5
        end
        a:led(r, i + pos, l)
      end
    end

    -- a:led(r, 1, 15)
  end



  a:refresh()
end

arc_delta = function(r, d)
  raw_densities[r] = util.clamp(raw_densities[r] + d, 0, 1000)
  densities[r] = util.linlin(0, 1000, 0, 10, raw_densities[r])
end

local function matches_density(pos, density)
  for i=1,density do
    local mod = 10 - i + 1
    if mod >= 1 and pos % mod == 0 then
      return true
    end
  end

  return false
end

function arc_process ()
  for r=1,4 do
    for i=1,64 do
      if patterns[r][i] == 1 and matches_density(i, densities[r]) then
      -- if patterns[r][i] == 1  then
        sparse_patterns[r][i] = 1
      else
        sparse_patterns[r][i] = 0
      end
    end
  end
end


-- ------------------------------------------------------------------------
-- screen

function redraw()
  screen.clear()
  screen.update()
end
