-- argen. sample

local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local MusicUtil = require "musicutil"

local Timber = include("timber/lib/timber_engine")

hot_cursor = include("argen/lib/hot_cursor")
include("argen/lib/core")


-- ------------------------------------------------------------------------

local sample = {}


-- ------------------------------------------------------------------------
-- state - global control

local prev_global_transpose = 0


-- ------------------------------------------------------------------------
-- state - kits

local DEFAULT_KITS_FOLDERS = {
  "common/606",
  "common/808",
  "common/909",
  "blips/*",
}

local kits_folders = nil

local found_sample_kits = {}
local found_sample_kits_samples = {}
local found_samples = {}
local nb_found_sample_kits = 0
local nb_found_sample_kits_samples = {}
local nb_found_samples = 0
local last_sample_scan_ts = 0

function sample.rescan_kits()
  for _, d in ipairs(kits_folders) do
    found = scandirdir(_path.audio .. d)
    for _, d2 in ipairs(found) do
      nb_found_sample_kits = nb_found_sample_kits+1
      table.insert(found_sample_kits, d2)
      found_sample_kits_samples[d2] = {}
      nb_found_sample_kits_samples[d2] = 0
      for _, s in ipairs(util.scandir(d2)) do
        nb_found_samples = nb_found_samples+1
        nb_found_sample_kits_samples[d2] = nb_found_sample_kits_samples[d2]+1
        table.insert(found_samples, d2.."/"..s)
        table.insert(found_sample_kits_samples[d2], d2.."/"..s)
      end
    end
  end
  last_sample_scan_ts = os.time()
end

function sample.rescan_kits_maybe()
  if os.time() - last_sample_scan_ts > 60 then
    sample.rescan_kits()
  end
end

function sample.rnd_kit()
  return found_sample_kits[math.random(nb_found_sample_kits)]
end

function sample.rnd_sample_for_kit(kit)
  local si = math.random(nb_found_sample_kits_samples[kit])
  return found_sample_kits_samples[kit][si]
end

function sample.rnd_sample()
  local si = math.random(nb_found_samples)
  return found_samples[si]
end



-- ------------------------------------------------------------------------
-- formating

function sample.format_st(param)
  local formatted = param:get() .. " ST"
  if param:get() > 0 then formatted = "+" .. formatted end
  return formatted
end


-- ------------------------------------------------------------------------
-- params

function sample.init_global_params(nb_arcs)
  params:add{type = "control", id = "filter_freq", name = "Filter Cutoff", controlspec = ControlSpec.new(60, 20000, "exp", 0, 3000, "Hz"), formatter = Formatters.format_freq, action = function(v)
               for r=1,nb_arcs do
                 params:set('filter_freq_'..r, v)
               end
  end}

  params:add{type = "control", id = "filter_resonance", name = "Filter Resonance", controlspec = ControlSpec.new(0, 1, "lin", 0, 0.3, ""), action = function(v)
               for r=1,nb_arcs do
                 params:set('filter_resonance_'..r, v)
               end
  end}

  params:add{type = "number", id = "transpose", name = "Transpose", min = -48, max = 48, default = 0, formatter = sample.format_st, action = function(v)
               for r=1,nb_arcs do
                 local delta = v - prev_global_transpose
                 params:set('transpose_'..r, params:get('transpose_'..r) + delta)
               end
  end}
end

function sample.global_pitch_transpose_delta(nb_arcs, d)
  if hot_cursor.is_any_active() and not hot_cursor.are_all() then
    for r=1,nb_arcs do
      if hot_cursor.is_active(r) then
        params:set('transpose_'..r, params:get('transpose_'..r) + d)
      end
    end
  else
    prev_global_transpose = params:get("transpose")
    params:set("transpose", params:get("transpose") + d)
  end
end


function sample.init_playback_folders()
  local kits_conf_file_sans_ext = norns.state.data.."kits"
  local kits_conf_file = kits_conf_file_sans_ext .. ".lua"

  if not util.file_exists(kits_conf_file) then
    kits_folders = DEFAULT_KITS_FOLDERS
    tab_save(kits_folders, kits_conf_file)
    return
  end

  local kits_folders_tmp = require(kits_conf_file_sans_ext)
  if kits_folders_tmp == nil then
    print("Failed to load user conf of favorite kit folders")
    kits_folders = DEFAULT_KITS_FOLDERS
    return
  end
  kits_folders = kits_folders_tmp
end

function sample.init_params(nb_slots)
  Timber.options.PLAY_MODE_BUFFER_DEFAULT = 4
  Timber.options.PLAY_MODE_STREAMING_DEFAULT = 3
  Timber.add_params()
  for i = 1, nb_slots do
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
end

function sample.set_sefault_samples()
  Timber.load_sample(1, _path.audio .. 'common/808/808-BD.wav')
  Timber.load_sample(2, _path.audio .. 'common/808/808-CH.wav')
  -- Timber.load_sample(2, _path.audio .. 'common/808/808-CY.wav')
  -- Timber.load_sample(2, _path.audio .. 'common/808/808-RS.wav')
  Timber.load_sample(3, _path.audio .. 'common/808/808-SD.wav')
  Timber.load_sample(4, _path.audio .. 'common/808/808-OH.wav')
end

function sample.is_ring_outmode(r)
  return (params:string("ring_out_mode_"..r) == "sample")
end

function sample.is_any_ring_outmode(nb_arcs)
  for r=1,nb_arcs do
    if sample.is_ring_outmode(r) then
      return true
    end
  end
  return false
end

function sample.load_sample(slot_id, path)
  Timber.load_sample(slot_id, path)
end

function sample.is_playing(slot_id)
  return tab.count(Timber.samples_meta[slot_id].positions) ~= 0
end

function sample.play(slot_id)
  local vel = 1
  -- REVIEW: not sure explicit stop is really necessary
  if sample.is_playing(slot_id) then
    engine.noteOff(slot_id)
  end
  engine.noteOn(slot_id, MusicUtil.note_num_to_freq(60), vel, slot_id)
end

-- ------------------------------------------------------------------------

return sample
