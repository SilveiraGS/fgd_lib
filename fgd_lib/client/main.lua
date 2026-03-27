local function getQBCore()
  local cfg = FGDConfig or {}
  local resourceName = cfg.QBCoreResource or "qb-core"

  if GetResourceState(resourceName) ~= "started" then
    return nil
  end

  local ok, core = pcall(function()
    return exports[resourceName]:GetCoreObject()
  end)

  if not ok then
    return nil
  end

  return core
end

function GetFramework()
  return FGD.GetFramework()
end

function GetPlayerData()
  local fw = FGD.GetFramework()

  if fw == "qbcore" then
    local QBCore = getQBCore()
    if QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData then
      return QBCore.Functions.GetPlayerData()
    end
  end

  if fw == "creative" then
    local state = LocalPlayer and LocalPlayer.state or nil
    if state then
      return {
        source = GetPlayerServerId(PlayerId()),
        passport = state.passport or state.Passport or state.user_id or state.id,
        name = state.name or state.Name,
        lastname = state.lastname or state.Lastname,
        rawState = state
      }
    end
  end

  return nil
end

local function toVec3(value)
  if value == nil then
    return nil
  end

  local valueType = type(value)

  if valueType == "vector3" then
    return value
  end

  if valueType == "vector4" then
    return vec3(value.x + 0.0, value.y + 0.0, value.z + 0.0)
  end

  if valueType == "table" then
    local x = tonumber(value[1] or value.x)
    local y = tonumber(value[2] or value.y)
    local z = tonumber(value[3] or value.z)
    if x and y and z then
      return vec3(x, y, z)
    end
    return nil
  end

  -- vector3 como userdata / tipos leves: acesso .x/.y/.z pode falhar sem pcall.
  local ok, x, y, z = pcall(function()
    return tonumber(value.x), tonumber(value.y), tonumber(value.z)
  end)
  if ok and x and y and z then
    return vec3(x, y, z)
  end

  return nil
end

local function callTargetExport(resourceName, methodNames, options, ...)
  local opts = type(options) == "table" and options or {}
  local selfFirst = opts.selfFirst == true

  local state = GetResourceState(resourceName)
  if state ~= "started" then
    return false, ("resource_not_started:%s"):format(state)
  end

  local exportsObj = exports[resourceName]
  if not exportsObj then
    return false, "exports_unavailable"
  end

  local lastError = "method_not_found_or_failed"

  for _, methodName in ipairs(methodNames or {}) do
    local okLookup, fnOrErr = pcall(function()
      return exportsObj[methodName]
    end)

    if okLookup and type(fnOrErr) == "function" then
      local okCall, resultOrErr

      if selfFirst then
        okCall, resultOrErr = pcall(fnOrErr, exportsObj, ...)
        if okCall then
          return true, resultOrErr
        end

        okCall, resultOrErr = pcall(fnOrErr, ...)
        if okCall then
          return true, resultOrErr
        end
      else
        okCall, resultOrErr = pcall(fnOrErr, ...)
        if okCall then
          return true, resultOrErr
        end

        -- Alguns exports exigem chamada com self (equivalente a :method()).
        okCall, resultOrErr = pcall(fnOrErr, exportsObj, ...)
        if okCall then
          return true, resultOrErr
        end
      end

      lastError = tostring(resultOrErr)
    elseif not okLookup then
      lastError = tostring(fnOrErr)
    end
  end

  return false, lastError
end

function RegisterTargetCircle(zoneName, coords, radius, options)
  local name = tostring(zoneName or "")
  local center = toVec3(coords)
  local r = tonumber(radius) or 1.0
  local cfg = type(options) == "table" and options or {}
  local label = tostring(cfg.label or "Interagir")
  local distance = tonumber(cfg.distance) or 2.0
  local eventName = tostring(
    cfg.event or cfg.Event or cfg.clientEvent or cfg.ClientEvent or ""
  )
  local icon = tostring(cfg.icon or "fas fa-circle")

  if name == "" then
    return false, "invalid_params:name"
  end
  if not center then
    return false, "invalid_params:coords"
  end
  if eventName == "" then
    return false, "invalid_params:event"
  end

  local okOx, oxResult = callTargetExport("ox_target", {
    "addSphereZone",
    "AddSphereZone"
  }, {
    selfFirst = true
  }, {
      name = name,
      coords = center,
      radius = r,
      debug = cfg.debug == true,
      options = {
        {
          name = name .. ":option",
          icon = icon,
          label = label,
          distance = distance,
          canInteract = cfg.canInteract,
          onSelect = function()
            TriggerEvent(eventName)
          end
        }
      }
    })
  if okOx then
    return true, "ox_target"
  end

  if GetResourceState("qb-target") == "started" then
    local okQb = pcall(function()
      exports["qb-target"]:AddCircleZone(name, center, r, {
        name = name,
        useZ = true
      }, {
        options = {
          {
            type = "client",
            event = eventName,
            icon = icon,
            label = label,
            canInteract = cfg.canInteract
          }
        },
        distance = distance
      })
    end)
    if okQb then
      return true, "qb-target"
    end
  end

  -- Target legado (PolyZone): chamada direta via exports para evitar
  -- que o callTargetExport tente with/without-self e passe vec3 como radius.
  if GetResourceState("target") == "started" then
    local okLegacy = pcall(function()
      exports["target"]:AddCircleZone(name, center, r, {
        name = name,
        heading = 0.0,
        useZ = true
      }, {
        Distance = distance,
        options = {
          {
            event = eventName,
            label = label,
            tunnel = "client"
          }
        }
      })
    end)
    if okLegacy then
      return true, "target"
    end
  end

  return false, ("target_unavailable ox=false qb=false legacy=pcall_failed"):format()
end

function Notify(message, color, durationMs, title)
  local msg = tostring(message or "")
  if msg == "" then
    return false, "empty_message"
  end

  local tone = tostring(color or "azul")
  local duration = tonumber(durationMs) or 5000

  -- Compatibilidade com bases Creative/legacy.
  TriggerEvent("Notify", tone, msg, duration)

  -- Fallback preferencial para QBCore/QBox com ox_lib.
  if GetResourceState("ox_lib") == "started" then
    local typeMap = {
      verde = "success",
      vermelho = "error",
      amarelo = "warning",
      azul = "inform"
    }

    local ok = pcall(function()
      exports.ox_lib:notify({
        title = tostring(title or "Sistema"),
        description = msg,
        type = typeMap[tone] or "inform",
        duration = duration
      })
    end)

    if ok then
      return true, "ox_lib"
    end
  end

  return true, "legacy"
end

exports("GetFramework", GetFramework)
exports("GetPlayerData", GetPlayerData)
exports("RegisterTargetCircle", RegisterTargetCircle)
exports("Notify", Notify)
