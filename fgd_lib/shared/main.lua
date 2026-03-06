FGD = FGD or {}

local function logDebug(msg)
  if IsDuplicityVersion() and FGDConfig and FGDConfig.Debug then
    print(("[fgd_lib] %s"):format(tostring(msg)))
  end
end

FGD._logDebug = logDebug

function FGD.GetConfiguredFramework()
  local cfg = FGDConfig or {}
  local fw = tostring(cfg.Framework or "auto"):lower()

  if fw == "qb" then fw = "qbcore" end
  if fw == "vrp" then fw = "creative" end

  if fw == "qbcore" or fw == "creative" then
    return fw
  end

  return "auto"
end

function FGD.DetectFramework()
  local cfg = FGDConfig or {}
  local selected = FGD.GetConfiguredFramework()

  if selected ~= "auto" then
    return selected
  end

  local qbState = GetResourceState(cfg.QBCoreResource or "qb-core")
  if qbState == "started" then
    return "qbcore"
  end

  local creativeState = GetResourceState(cfg.CreativeResource or "vrp")
  if creativeState == "started" then
    return "creative"
  end

  return "unknown"
end

FGD._lastFramework = nil

function FGD.GetFramework()
  local fw = FGD.DetectFramework()
  if FGD._lastFramework ~= fw then
    FGD._lastFramework = fw
    logDebug(("framework ativo: %s"):format(fw))
  end
  return fw
end
