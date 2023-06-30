


local checkpoint = {}

-- ------------------------------------------------------------------------
-- core

local function quote(s)
  return '"'..s:gsub('"', '\\"')..'"'
end

local function unquote(s)
  return s:gsub('^"', ''):gsub('"$', ''):gsub('\\"', '"')
end


-- ------------------------------------------------------------------------

local TMP_DIR = '/dev/shm/'

function checkpoint.create_dir()
  if norns.state.shortname == nil or norns.state.shortname == "" then
    return
  end
  local CHECKPOINT_DIR = TMP_DIR .. norns.state.shortname ..'/'

  util.make_dir(CHECKPOINT_DIR)
end

function checkpoint.clear_dir()
  if norns.state.shortname == nil or norns.state.shortname == "" then
    return
  end
  local CHECKPOINT_DIR = TMP_DIR .. norns.state.shortname ..'/'

  os.execute("rm -f " .. CHECKPOINT_DIR .. '*')
end

function checkpoint.init_dir()
  checkpoint.clear_dir()
  checkpoint.create_dir()
end


-- basically `ParamSet:write` but in tmpfs
function checkpoint.write(id)
  if norns.state.shortname == nil or norns.state.shortname == "" then
    return
  end
  local CHECKPOINT_DIR = TMP_DIR .. norns.state.shortname ..'/'

  local filename = CHECKPOINT_DIR .. id .. ".checkpoint"

  print("checkpoint >> write: "..filename)
  local fd = io.open(filename, "w+")
  if fd then
    io.output(fd)
    if name then io.write("-- "..name.."\n") end
    for _,param in ipairs(params.params) do
      if param.id and param.save and param.t ~= params.tTRIGGER and param.t ~= params.tSEPARATOR then
        io.write(string.format("%s: %s\n", quote(param.id), param:get()))
      end
    end
    io.close(fd)
    if params.action_write ~= nil then
      params.action_write(filename,name,pset_number)
    end

  else print("checkpoint: BAD FILENAME") end
end


-- basically `ParamSet:read`
function checkpoint.read(id)
  if norns.state.shortname == nil or norns.state.shortname == "" then
    return
  end
  local CHECKPOINT_DIR = TMP_DIR .. norns.state.shortname ..'/'

  local filename = CHECKPOINT_DIR .. id .. ".checkpoint"

  print("checkpoint >> read: " .. filename)

  local fd = io.open(filename, "r")
  if fd then
    io.close(fd)
    local param_already_set = {}
    for line in io.lines(filename) do
      if util.string_starts(line, "--") then
        params.name = string.sub(line, 4, -1)
      else
        local id, value = string.match(line, "(\".-\")%s*:%s*(.*)")

        if id and value then
          id = unquote(id)
          local index = params.lookup[id]

          if index and params.params[index] and not param_already_set[index] then
            if tonumber(value) ~= nil then
              params.params[index]:set(tonumber(value), silent)
            elseif value == "-inf" then
              params.params[index]:set(-math.huge, silent)
            elseif value == "inf" then
              params.params[index]:set(math.huge, silent)
            elseif value then
              params.params[index]:set(value, silent)
            end
            param_already_set[index] = true
          end
        end
      end
    end
    if params.action_read ~= nil then
      params.action_read(filename,silent,pset_number)
    end
  else
    print("checkpoint :: "..filename.." not read.")
  end
end


-- ------------------------------------------------------------------------

return checkpoint
