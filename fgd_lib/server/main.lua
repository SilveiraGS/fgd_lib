local cachedQBCore = nil
local cachedVRP = nil
local NativeGetPlayerName = _G.GetPlayerName
local lastAnnouncedFramework = nil

local function normalizeVersion(version)
  local v = tostring(version or "")
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  v = v:gsub("^[vV]", "")
  return v
end

local function extractRemoteVersion(body)
  local raw = tostring(body or "")
  raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then return nil end

  -- Suporte a leitura direta do fxmanifest.lua (ex.: version "1.0.1")
  local fromFxManifest = raw:match("[\n\r]%s*version%s+[\"']([^\"']+)[\"']")
    or raw:match("^%s*version%s+[\"']([^\"']+)[\"']")
  if fromFxManifest and fromFxManifest ~= "" then
    return normalizeVersion(fromFxManifest)
  end

  if raw:sub(1, 1) == "{" and json and json.decode then
    local ok, parsed = pcall(json.decode, raw)
    if ok and type(parsed) == "table" then
      local ver = parsed.version or parsed.tag_name or parsed.latest
      if ver then
        return normalizeVersion(ver)
      end
    end
  end

  -- Se vier texto puro, usa a primeira linha.
  local firstLine = raw:match("([^\r\n]+)") or raw
  return normalizeVersion(firstLine)
end

local function compareVersions(a, b)
  local va = normalizeVersion(a)
  local vb = normalizeVersion(b)

  if va == vb then
    return 0
  end

  local function split(version)
    local out = {}
    for part in tostring(version):gmatch("([^.]+)") do
      out[#out + 1] = tonumber(part) or 0
    end
    return out
  end

  local pa = split(va)
  local pb = split(vb)
  local maxLen = math.max(#pa, #pb)

  for i = 1, maxLen do
    local na = pa[i] or 0
    local nb = pb[i] or 0

    if na > nb then return 1 end
    if na < nb then return -1 end
  end

  return 0
end

local function checkForUpdates()
  local cfg = FGDConfig or {}
  local vcfg = cfg.VersionCheck or {}
  if vcfg.Enabled == false then
    return
  end

  local url = tostring(vcfg.Url or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if url == "" or url:find("SEU_USUARIO", 1, true) then
    print("^3[fgd_lib]^7 VersionCheck ativo, mas URL nao configurada em config.lua")
    return
  end

  local localVersion = normalizeVersion(GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "0.0.0")

  PerformHttpRequest(url, function(statusCode, body)
    if statusCode ~= 200 then
      print(("^3[fgd_lib]^7 Nao foi possivel verificar atualizacao (HTTP %s)"):format(tostring(statusCode)))
      return
    end

    local remoteVersion = extractRemoteVersion(body)
    if not remoteVersion or remoteVersion == "" then
      print("^3[fgd_lib]^7 Falha ao ler versao remota")
      return
    end

    local cmp = compareVersions(localVersion, remoteVersion)
    if cmp < 0 then
      print(("^1[fgd_lib]^7 Versao desatualizada. Local: ^3%s^7 | Github: ^2%s^7"):format(localVersion, remoteVersion))
      print("^3[fgd_lib]^7 Atualize o recurso para evitar incompatibilidades.")
      return
    end

    if cmp == 0 then
      print(("^2[fgd_lib]^7 Versao atualizada: ^3%s^7"):format(localVersion))
      return
    end

    -- Local maior que remoto (build de dev/local)
    print(("^2[fgd_lib]^7 Versao local (%s) acima da remota (%s)"):format(localVersion, remoteVersion))
  end, "GET", "", { ["Accept"] = "application/json, text/plain" })
end

local function printFrameworkStatusServer(framework)
  local fw = tostring(framework or "unknown"):lower()

  if fw == lastAnnouncedFramework then
    return
  end

  lastAnnouncedFramework = fw

  if fw == "qbcore" then
    print("^2[fgd_lib]^7 Framework detectada: ^3QBCore^7")
    return
  end

  if fw == "creative" then
    print("^2[fgd_lib]^7 Framework detectada: ^3Creative^7")
    return
  end

  print("^1[fgd_lib]^7 Framework nao detectada, contate o desenvolvedor")
end

local function callAny(target, methods, ...)
  if not target then return nil end
  for _, methodName in ipairs(methods) do
    local fn = target[methodName]
    if type(fn) == "function" then
      local ok, result = pcall(fn, ...)
      if ok and result ~= nil then return result end

      -- Some framework functions are declared with ':' and require self.
      ok, result = pcall(fn, target, ...)
      if ok and result ~= nil then return result end
    end
  end
  return nil
end

local function safeModule(resource, path)
  if type(module) ~= "function" then
    return nil
  end

  local ok, result = pcall(module, resource, path)
  if ok then
    return result
  end

  return nil
end

local function getQBCore()
  if cachedQBCore then return cachedQBCore end

  local cfg = FGDConfig or {}
  local resourceName = cfg.QBCoreResource or "qb-core"
  if GetResourceState(resourceName) ~= "started" then
    return nil
  end

  local ok, core = pcall(function()
    return exports[resourceName]:GetCoreObject()
  end)

  if ok and core then
    cachedQBCore = core
    return cachedQBCore
  end

  return nil
end

local function getVRP()
  if cachedVRP then return cachedVRP end

  local cfg = FGDConfig or {}
  local resourceName = cfg.CreativeResource or "vrp"
  if GetResourceState(resourceName) ~= "started" then
    return nil
  end

  local Proxy = safeModule("vrp", "lib/Proxy")
  if Proxy and type(Proxy.getInterface) == "function" then
    local ok, iface = pcall(Proxy.getInterface, "vRP")
    if ok and iface then
      cachedVRP = iface
      return cachedVRP
    end
  end

  return nil
end

local function getQBPlayer(src)
  local QBCore = getQBCore()
  if not QBCore or not QBCore.Functions or not QBCore.Functions.GetPlayer then
    return nil
  end

  return QBCore.Functions.GetPlayer(src)
end

function GetFramework()
  return FGD.GetFramework()
end

function GetPlayerId(src)
  local fw = FGD.GetFramework()

  if fw == "qbcore" then
    local Player = getQBPlayer(src)
    if Player and Player.PlayerData then
      return Player.PlayerData.citizenid or Player.PlayerData.license
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if vRP then
      local passport = callAny(vRP, { "Passport", "getUserId" }, src)
      if passport then return passport end
    end
  end

  return nil
end

function GetPlayerIdentity(src)
  local fw = FGD.GetFramework()
  local playerId = GetPlayerId(src)

  if fw == "qbcore" then
    local Player = getQBPlayer(src)
    if not Player or not Player.PlayerData then
      return nil
    end

    local pd = Player.PlayerData
    local char = pd.charinfo or {}

    return {
      id = playerId,
      firstname = char.firstname or "",
      lastname = char.lastname or "",
      fullname = ((char.firstname or "") .. " " .. (char.lastname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    }
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP or not playerId then
      return nil
    end

    local identity = callAny(vRP, { "Identity", "getUserIdentity" }, playerId)
    if type(identity) == "table" then
      local firstname = identity.name or identity.firstname or identity.Name or ""
      local lastname = identity.name2 or identity.lastname or identity.Lastname or ""
      local fullname = tostring(identity.fullname or identity.Fullname or "")
      if fullname == "" then
        fullname = ((firstname or "") .. " " .. (lastname or "")):gsub("^%s+", ""):gsub("%s+$", "")
      end

      return {
        id = playerId,
        firstname = firstname,
        lastname = lastname,
        fullname = fullname
      }
    end
  end

  return nil
end

function GetPlayerName(src)
  local identity = GetPlayerIdentity(src)
  if identity and identity.fullname and identity.fullname ~= "" then
    return identity.fullname
  end

  if type(NativeGetPlayerName) == "function" then
    return NativeGetPlayerName(src)
  end

  return nil
end

function GetMoney(src, account)
  local fw = FGD.GetFramework()
  local acc = tostring(account or "cash"):lower()

  if fw == "qbcore" then
    local Player = getQBPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.money then
      return tonumber(Player.PlayerData.money[acc]) or 0
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return 0 end

    local playerId = GetPlayerId(src)
    if not playerId then return 0 end

    if acc == "bank" then
      return tonumber(callAny(vRP, { "GetBank", "getBankMoney" }, playerId)) or 0
    end

    return tonumber(callAny(vRP, { "GetMoney", "getMoney" }, playerId)) or 0
  end

  return 0
end

function AddMoney(src, account, amount, reason)
  local fw = FGD.GetFramework()
  local acc = tostring(account or "cash"):lower()
  local value = tonumber(amount) or 0
  if value <= 0 then return false end

  if fw == "qbcore" then
    local Player = getQBPlayer(src)
    if Player and Player.Functions and Player.Functions.AddMoney then
      local ok, result = pcall(Player.Functions.AddMoney, Player.Functions, acc, value, reason or "fgd_lib")
      if ok then return result ~= false end
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return false end

    local playerId = GetPlayerId(src)
    if not playerId then return false end

    if acc == "bank" then
      return callAny(vRP, { "GiveBank", "addBank" }, playerId, value) ~= nil
    end

    return callAny(vRP, { "GiveMoney", "giveMoney" }, playerId, value) ~= nil
  end

  return false
end

function RemoveMoney(src, account, amount, reason)
  local fw = FGD.GetFramework()
  local acc = tostring(account or "cash"):lower()
  local value = tonumber(amount) or 0
  if value <= 0 then return false end

  if fw == "qbcore" then
    local Player = getQBPlayer(src)
    if Player and Player.Functions and Player.Functions.RemoveMoney then
      local ok, result = pcall(Player.Functions.RemoveMoney, Player.Functions, acc, value, reason or "fgd_lib")
      if ok then return result ~= false end
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return false end

    local playerId = GetPlayerId(src)
    if not playerId then return false end

    if acc == "bank" then
      local bank = tonumber(callAny(vRP, { "GetBank", "getBankMoney" }, playerId)) or 0
      if bank < value then return false end
      return callAny(vRP, { "WithdrawBank", "tryWithdraw" }, playerId, value) ~= nil
    end

    local cash = tonumber(callAny(vRP, { "GetMoney", "getMoney" }, playerId)) or 0
    if cash < value then return false end
    return callAny(vRP, { "Payment", "tryPayment", "tryFullPayment" }, playerId, value) ~= nil
  end

  return false
end

function HasPermission(src, permission)
  local fw = FGD.GetFramework()
  local perm = tostring(permission or "")
  if perm == "" then return false end

  if fw == "qbcore" then
    local QBCore = getQBCore()
    if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
      local ok, hasPerm = pcall(QBCore.Functions.HasPermission, src, perm)
      if ok then return hasPerm == true end
    end
    return false
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return false end

    local playerId = GetPlayerId(src)
    if not playerId then return false end

    return callAny(vRP, { "HasGroup", "HasPermission", "hasPermission" }, playerId, perm) == true
  end

  return false
end

exports("GetFramework", GetFramework)
exports("GetPlayerId", GetPlayerId)
exports("GetPlayerIdentity", GetPlayerIdentity)
exports("GetPlayerName", GetPlayerName)
exports("GetMoney", GetMoney)
exports("AddMoney", AddMoney)
exports("RemoveMoney", RemoveMoney)
exports("HasPermission", HasPermission)

CreateThread(function()
  -- Aguarda um pouco para dar tempo das dependencias iniciarem e imprime o status.
  Wait(500)
  printFrameworkStatusServer(FGD.DetectFramework())
  checkForUpdates()
end)

AddEventHandler("onResourceStart", function(resourceName)
  local cfg = FGDConfig or {}
  local qbResource = cfg.QBCoreResource or "qb-core"
  local creativeResource = cfg.CreativeResource or "vrp"

  if resourceName ~= qbResource and resourceName ~= creativeResource and resourceName ~= GetCurrentResourceName() then
    return
  end

  if resourceName == qbResource then
    cachedQBCore = nil
  elseif resourceName == creativeResource then
    cachedVRP = nil
  end

  printFrameworkStatusServer(FGD.DetectFramework())
end)
