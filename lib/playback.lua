-- argen. playback


-- ------------------------------------------------------------------------

local playback = {}


-- ------------------------------------------------------------------------
-- const

-- REVIEW: idk if it should be 0 or 1...
local INIT_POS = 1


-- ------------------------------------------------------------------------
-- state - heads

local pos_quant = INIT_POS
local unquantized_rot_pos = {}

function playback.quant_head_advance(seq_len)
  pos_quant = pos_quant + 1
  if pos_quant > seq_len then
    -- REVIEW: this % might be wrong!
    pos_quant = pos_quant % seq_len
  end
end

function playback.unquant_head_advance(r, step, seq_len)
  -- REVIEW: this % might be wrong!
  unquantized_rot_pos[r] = (unquantized_rot_pos[r] + step) % seq_len
end


local function pos_2_radial_pos(pos, seq_len, shift, i)
  if i == nil then i = 1 end
  local radial_pos = ((i + pos) + shift)
  while radial_pos < 0 do
    radial_pos = radial_pos + seq_len
  end
  return radial_pos
end

function playback.quant_head_2_radial_pos(seq_len, shift, i)
  return pos_2_radial_pos(pos_quant, seq_len, shift, i)
end

function playback.sync_ring_unquant_head(r)
  unquantized_rot_pos[r] = pos_quant
end

function playback.ring_head_pos(r)
  if params:string("ring_quantize_"..r) == "on"  then
    return pos_quant
  else
    return round(unquantized_rot_pos[r])
  end
end


-- ------------------------------------------------------------------------
-- state - transport

local STARTED = "started"
local PAUSED = "paused"
local playback_status = STARTED

local was_stopped = false

local midi_in_transport = nil
local midi_out_transport = nil

function playback.is_running()
  return (playback_status == STARTED)
end

function playback.is_paused_or_stopepd()
  return (playback_status == PAUSED)
end

function playback.is_paused()
  return (playback.is_paused_or_stopepd() and not was_stopped)
end

function playback.is_stopped()
  return (playback.is_paused_or_stopepd() and was_stopped)
end


-- ------------------------------------------------------------------------
-- state - mutes

local mutes = {}

function playback.is_ring_muted(r)
  return mutes[r]
end

function playback.mute_ring(r)
  mutes[r] = true
end

function playback.unmute_ring(r)
  mutes[r] = false
end


-- ------------------------------------------------------------------------
-- transport

function playback.reset_heads()
  pos_quant = INIT_POS
  for r=1,tab.count(unquantized_rot_pos) do
    unquantized_rot_pos[r] = INIT_POS
  end
end

function playback.stop(is_originator)
    if is_originator == true and midi_out_transport ~= nil and params:string("midi_transport_in") == "on" then
    midi_out_transport:stop()
  end
  playback.reset_heads()
  playback_status = PAUSED
  was_stopped = true
end

function playback.pause(is_originator)
  if is_originator == true and midi_out_transport ~= nil and params:string("midi_transport_in") == "on" then
    midi_out_transport:stop()
  end
  playback_status = PAUSED
end

function playback.start(is_originator)
  if is_originator == true and midi_out_transport ~= nil and params:string("midi_transport_in") == "on" then
    if was_stopped then
      midi_out_transport:start()
    else
      midi_out_transport:continue()
    end
  end
  playback_status = STARTED
  was_stopped = false
end

function playback.restart(is_originator)
  if is_originator == true and midi_out_transport ~= nil and params:string("midi_transport_in") == "on" then
    midi_out_transport:start()
  end
  reset_playback_heads()
  playback_status = STARTED
end

local function midi_in_transport_event(data)
  if params:string("midi_transport_in") == "off" then
    return
  end

  local msg = midi.to_msg(data)

  if msg.type == "start" then
    playback.stop()
    playback.start()
  elseif msg.type == "stop" then
    playback.pause()
  elseif msg.type == "continue" then
    playback.start()
  end
end


-- ------------------------------------------------------------------------
-- params - tranport

function playback.init_transport()
  local OFF_ON = {"off", "on"}

  midi_in_transport = midi.connect(1)
  midi_in_transport.event = midi_in_transport_event

  params:add_group("Global Transport", 4)

  params:add_option("midi_transport_in", "MIDI Transport IN ", OFF_ON)
  params:set_action("midi_transport_in",
                    function(v)
                      if OFF_ON[v] == "on" then
                        params:show("midi_transport_in_device")
                      else
                        params:hide("midi_transport_in_device")
                      end
                      _menu.rebuild_params()
                    end
  )

  params:add{type = "number", id = "midi_transport_in_device", name = "MIDI Transport IN Dev", min = 1, max = 16, default = 1, action = function(value)
               midi_in_transport.event = nil
               midi_in_transport = midi.connect(value)
               midi_in_transport.event = midi_in_transport_event
  end}

  params:add_option("midi_transport_out", "MIDI Transport OUT ", OFF_ON)
  params:set_action("midi_transport_out",
                    function(v)
                      if OFF_ON[v] == "on" then
                        params:show("midi_transport_out_device")
                      else
                        params:hide("midi_transport_out_device")
                      end
                      _menu.rebuild_params()
                    end
  )

  params:add{type = "number", id = "midi_transport_out_device", name = "MIDI Transport OUT Dev", min = 1, max = 16, default = 1, action = function(value)
               midi_out_transport = midi.connect(value)
  end}

end


-- ------------------------------------------------------------------------
-- init

function playback.init(nb_arcs)
  for r=1,nb_arcs do
    mutes[r] = false
    unquantized_rot_pos[r] = INIT_POS
  end
end


-- ------------------------------------------------------------------------

return playback
