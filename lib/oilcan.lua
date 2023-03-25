-- argen. oilcan

local mod = require 'core/mods'


-- ------------------------------------------------------------------------

local oilcan = {}


-- ------------------------------------------------------------------------
-- static conf

local OILKITS_DIR = _path.data.."oilcan/"

oilcan.OILKIT_LEN = 8


-- ------------------------------------------------------------------------
-- general

function oilcan.is_loaded()
  return mod.is_loaded('oilcan')
end


-- ------------------------------------------------------------------------
-- state - kits

local found_oilkits = {}
local nb_found_oilkits = 0

local last_oilkit_scan_ts = 0

function oilcan.rescan_oilkits()
  found_oilkits = util.scandir(OILKITS_DIR)
  nb_found_oilkits = tab.count(found_oilkits)
  -- TODO: only keep those ending in .oilkit

  if nb_found_oilkits == 0 then
    print("no Oilcan kit found!")
    return
  end

  last_oilkit_scan_ts = os.time()
end

function oilcan.rnd_oilkit_id()
  return math.random(nb_found_oilkits)
end

function oilcan.rnd_oilkit()
  local kit_id = oilcan.rnd_oilkit_id()
  return oilcan.oilkit_id_to_name(kit_id)
end

function oilcan.oilkit_id_to_name(id)
  return found_oilkits[id]
end

function oilcan.rnd_oilkit_note()
  return math.random(oilcan.OILKIT_LEN)
end


-- ------------------------------------------------------------------------
-- params

function oilcan.is_ring_outmode(r)
  return (params:string("ring_out_mode_"..r) == "nb"
    and util.string_starts(params:string("ring_out_nb_voice_"..r), "Oilcan "))
end

function oilcan.is_any_ring_outmode(nb_arcs)
  for r=1,nb_arcs do
    if oilcan.is_ring_outmode(r) then
      return true
    end
  end
  return false
end

function oilcan.get_voice_param_option_id(r, voice_id)
  local nb_voices = params:lookup_param("ring_out_nb_voice_"..r).options
  return tab.key(nb_voices, "Oilcan "..voice_id)
end

function oilcan.reset_all_rings_voice(nb_arcs, force)
  if force == nil then
    force = false
  end

  if not mod.is_loaded('oilcan') then
    return
  end

  if os.time() - last_oilkit_scan_ts > 60 then
    oilcan.rescan_oilkits()
  end

  for r=1,nb_arcs do
    local do_set_ring = false
    if force then
      do_set_ring = (params:string("ring_out_mode_"..r) == "nb")
    else
      do_set_ring = oilcan.is_ring_outmode(r)
    end

    if do_set_ring then
      params:set("ring_out_nb_voice_"..r, oilcan.get_voice_param_option_id(r, r))
      params:set("oilcan_target_file_"..r, OILKITS_DIR..found_oilkits[mod1(r, nb_found_oilkits)])
    end
  end
end

function oilcan.assign_all_rings_oilkit(nb_arcs, kit_id)
  for r=1,nb_arcs do
    if oilcan.is_ring_outmode(r) then
      params:set("ring_out_nb_voice_"..r, oilcan.get_voice_param_option_id(r, r))
    end
  end
end


-- ------------------------------------------------------------------------

return oilcan
