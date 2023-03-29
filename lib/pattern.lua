-- argen. pattern


-- ------------------------------------------------------------------------

local pattern = {}


-- ------------------------------------------------------------------------
-- static conf

local DENSITY_MAX = 10

local ARC_SEGMENTS=64

local ARC_RAW_DENSITY_RESOLUTION = 1000


-- ------------------------------------------------------------------------
-- static fns

local function gen_pattern(pattern)
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

local function gen_empty_pattern(pattern)
  if pattern == nil then
    pattern = {}
  end
  for i=1,64 do
    pattern[i] = 0
  end
  return pattern
end

function pattern.rnd_density()
  local density = DENSITY_MAX
  for try=1,math.floor(DENSITY_MAX/2) do
    local d = math.random(DENSITY_MAX)
    if d < density then
      density = d
    end
  end
  return density
end


-- ------------------------------------------------------------------------
-- state

local patterns = {}
local sparse_patterns = {}
local raw_densities = {}

local prev_pattern_refresh_t = {}

function pattern.gen_for_ring(r)
  gen_pattern(patterns[r])
  prev_pattern_refresh_t[r] = os.time()
end

function pattern.was_ring_gen_recently(r)
  return (os.time() - prev_pattern_refresh_t[r] < 1)
end

-- REVIEW: should not do it in clock but on density change instead!
function pattern.recompute_parse_patterns()
  local nb_arcs = tab.count(patterns)
  for r=1,nb_arcs do
    for i=1,ARC_SEGMENTS do
      if params:get("ring_density_"..r) == 0 then
        sparse_patterns[r][i] = 0
      else
        if patterns[r][i] >= 1 and patterns[r][i] > (DENSITY_MAX - params:get("ring_density_"..r)) then
          sparse_patterns[r][i] = 1
        else
          sparse_patterns[r][i] = 0
        end
      end
    end
  end
end

function pattern.sparse_pattern_for_ring(r)
  return sparse_patterns[r]
end

function pattern.set(r, i, v)
  patterns[r][i] = v
end

function pattern.set_from_density(r, i, d)
  local v = DENSITY_MAX + 1 - d
  pattern.set(r, i, v)
end

function pattern.led(r, i)
  return round(util.linlin(0, DENSITY_MAX, 1, 8, patterns[r][i]))
end

function pattern.density_delta_from_arc(r, d)
  -- NB: it feels more natural to undo faster
  if d < 0 then
    d = d + d * 1/3
  end
  raw_densities[r] = util.clamp(raw_densities[r] + d, 0, ARC_RAW_DENSITY_RESOLUTION)
  return math.floor(util.linlin(0, ARC_RAW_DENSITY_RESOLUTION, 0, DENSITY_MAX, raw_densities[r]))
end

function pattern.make_density_cb(r)
  return function(v)
    -- NB: reset arc raw density counter
    if math.abs(util.linlin(0, ARC_RAW_DENSITY_RESOLUTION, 0, DENSITY_MAX, raw_densities[r]) - v) >= (1 * DENSITY_MAX / 10)  then
      raw_densities[r] = math.floor(util.linlin(0, DENSITY_MAX, 0, ARC_RAW_DENSITY_RESOLUTION, v))
    end
  end
end


-- ------------------------------------------------------------------------
-- params

function pattern.init(nb_arcs)
  for r=1,nb_arcs do
    patterns[r] = gen_pattern()
    sparse_patterns[r] = gen_empty_pattern()
    raw_densities[r] = 0
    prev_pattern_refresh_t[r] = 0
  end
end

function pattern.load_for_pset(pset_filename)
  local seqfiles = pset_filename .. ".argenseqs"
  if util.file_exists(seqfiles) then
    patterns = tab.load(seqfiles)
  end
end

function pattern.save_for_pset(pset_filename)
  tab.save(patterns, pset_filename .. ".argenseqs")
end

function pattern.delete_for_pset(pset_filename)
  os.execute("rm -f" .. pset_filename .. ".argenseqs")
end


-- ------------------------------------------------------------------------

return pattern
