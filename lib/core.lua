

local inspect = include("argen/lib/inspect")


-- ------------------------------------------------------------------------
-- math

function rnd(x)
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

function srand(x)
  if not x then
    x = 0
  end
  math.randomseed(x)
end

function round(v)
  return math.floor(v+0.5)
end

function cos(x)
  return math.cos(math.rad(x * 360))
end

function sin(x)
  return -math.sin(math.rad(x * 360))
end

-- base1 modulo
function mod1(v, m)
  return ((v - 1) % m) + 1
end


-- ------------------------------------------------------------------------
-- playback speed

function bpm_to_fps(v)
  return v / 60
end

function fps_to_bpm(v)
  return v * 60
end


-- ------------------------------------------------------------------------
-- fs

-- basically `util.scandir` but only for subfolders
function scandirdir(directory)
  local i, t, popen = 0, {}, io.popen
  local pfile = popen('find '..directory..' -maxdepth 1 -type d')
  for filename in pfile:lines() do
    i = i + 1
    t[i] = filename
  end
  pfile:close()
  return t
end

function tab_save(t, filepath)
  local file, err = io.open(filepath, "wb")
  if err then return err end
  file:write("return "..inspect(t))
  file:close()
end

function file_ext(f)
  return f:match("^.+%.(.+)$")
end
