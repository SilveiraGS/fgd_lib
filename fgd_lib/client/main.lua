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

exports("GetFramework", GetFramework)
exports("GetPlayerData", GetPlayerData)
