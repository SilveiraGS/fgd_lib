local cachedQBCore = nil
local cachedVRP = nil
local NativeGetPlayerName = _G.GetPlayerName
local lastAnnouncedFramework = nil
local MONEY_DEBUG = GetConvar("fgd_money_debug", "false") == "true"

local function moneyDebug(message)
  if not MONEY_DEBUG then return end
  print(("^3[fgd_lib:money]^7 %s"):format(tostring(message or "")))
end

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

  -- Se recebeu HTML, provavelmente a URL nao e raw do arquivo.
  local lowerRaw = raw:lower()
  if lowerRaw:find("<!doctype html", 1, true) or lowerRaw:find("<html", 1, true) then
    return nil
  end

  -- Suporte a leitura direta do fxmanifest.lua (ex.: version "1.0.1")
  local fromFxManifest = raw:match("[\n\r]%s*version%s+[\"']([^\"']+)[\"']")
    or raw:match("^%s*version%s+[\"']([^\"']+)[\"']")
    or raw:match("version%s+[\"']([^\"']+)[\"']")
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
  local fromSemver = raw:match("([vV]?%d+%.%d+%.%d+)") or firstLine:match("([vV]?%d+%.%d+%.%d+)")
  if fromSemver then
    return normalizeVersion(fromSemver)
  end

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

  -- Normaliza links comuns do GitHub para formato raw.
  url = url:gsub("/refs/heads/", "/")
  local ghUser, ghRepo, ghBranch, ghPath = url:match("https://github%.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)")
  if ghUser and ghRepo and ghBranch and ghPath then
    url = ("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(ghUser, ghRepo, ghBranch, ghPath)
  end

  if url == "" or url:find("SEU_USUARIO", 1, true) then
    print("^3[fgd_lib]^7 VersionCheck ativo, mas URL nao configurada em config.lua")
    return
  end

  local localVersion = normalizeVersion(GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "0.0.0")

  local triedFallback = false
  local function requestVersion(requestUrl)
    PerformHttpRequest(requestUrl, function(statusCode, body)
      if statusCode == 404 and not triedFallback then
        triedFallback = true

        -- Fallback comum quando o repositorio tem a pasta fgd_lib/ na raiz.
        local candidate = requestUrl:gsub("/fxmanifest%.lua$", "/fgd_lib/fxmanifest.lua")
        if candidate ~= requestUrl then
          print(("^3[fgd_lib]^7 URL 404, tentando fallback: %s"):format(candidate))
          requestVersion(candidate)
          return
        end
      end

      if statusCode ~= 200 then
        print(("^3[fgd_lib]^7 Nao foi possivel verificar atualizacao (HTTP %s) | URL: %s"):format(tostring(statusCode), requestUrl))
        return
      end

      local remoteVersion = extractRemoteVersion(body)
      if not remoteVersion or remoteVersion == "" then
        print(("^3[fgd_lib]^7 Falha ao ler versao remota. Verifique o RAW do fxmanifest.lua | URL: %s"):format(requestUrl))
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

  requestVersion(url)
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

local function getResourceExportsAdapter(resourceName)
  if type(resourceName) ~= "string" or resourceName == "" then
    return nil
  end

  local state = GetResourceState(resourceName)
  if state ~= "started" then
    return nil
  end

  local ok, exportsObj = pcall(function()
    return exports[resourceName]
  end)

  if not ok or not exportsObj then
    return nil
  end

  local adapter = setmetatable({}, {
    __index = function(_, methodName)
      return function(...)
        local args = { ... }
        local success, result = pcall(function()
          local fn = exportsObj[methodName]
          if type(fn) ~= "function" then
            return nil
          end
          return fn(table.unpack(args))
        end)

        if success then
          return result
        end

        return nil
      end
    end
  })

  return adapter
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
  local configuredName = tostring(cfg.CreativeResource or "vrp")
  local candidates = {
    configuredName,
    "vrp",
    "creative",
    "creative_network",
    "creative-network"
  }

  local function tryProxyInterface(Proxy, resourceContext)
    if not Proxy or type(Proxy.getInterface) ~= "function" then
      return nil
    end

    local ok, iface = pcall(Proxy.getInterface, "vRP")
    if ok and iface then
      return iface
    end

    ok, iface = pcall(Proxy.getInterface, "vRP", resourceContext)
    if ok and iface then
      return iface
    end

    return nil
  end

  moneyDebug(("getVRP module type=%s"):format(type(module)))

  -- 1) Tenta interface Proxy pelos recursos candidatos.
  for _, resourceName in ipairs(candidates) do
    local Proxy = safeModule(resourceName, "lib/Proxy")
    local iface = tryProxyInterface(Proxy, resourceName)
    if iface then
      cachedVRP = iface
      moneyDebug(("getVRP interface carregada via module(%s)"):format(tostring(resourceName)))
      return cachedVRP
    end
  end

  -- 2) Proxy global (algumas builds expõem no _G).
  local globalProxy = rawget(_G, "Proxy")
  local iface = tryProxyInterface(globalProxy, configuredName)
  if iface then
    cachedVRP = iface
    moneyDebug("getVRP interface carregada via Proxy global")
    return cachedVRP
  end

  -- 3) Interface vRP global direta.
  local globalVRP = rawget(_G, "vRP")
  if type(globalVRP) == "table" then
    cachedVRP = globalVRP
    moneyDebug("getVRP interface carregada via vRP global")
    return cachedVRP
  end

  -- 4) Fallback por exports diretos dos recursos candidatos.
  -- Mantido apenas como ultimo recurso para cenarios custom.
  for _, resourceName in ipairs(candidates) do
    local adapter = getResourceExportsAdapter(resourceName)
    if adapter then
      cachedVRP = adapter
      moneyDebug(("getVRP interface carregada via exports(%s)"):format(tostring(resourceName)))
      return cachedVRP
    end
  end

  local states = {}
  for _, name in ipairs(candidates) do
    states[#states + 1] = ("%s=%s"):format(name, tostring(GetResourceState(name)))
  end
  moneyDebug(("getVRP falhou (candidates: %s)"):format(table.concat(states, ", ")))
  return nil
end

local function getQBPlayer(src)
  local QBCore = getQBCore()
  if not QBCore or not QBCore.Functions or not QBCore.Functions.GetPlayer then
    return nil
  end

  return QBCore.Functions.GetPlayer(src)
end

local function safeJsonDecode(payload)
  if type(payload) ~= "string" or payload == "" then
    return nil
  end

  if not json or type(json.decode) ~= "function" then
    return nil
  end

  local ok, decoded = pcall(json.decode, payload)
  if ok and type(decoded) == "table" then
    return decoded
  end

  return nil
end

local function normalizeQbCharinfo(value)
  if type(value) == "table" then
    return value
  end

  if type(value) == "string" then
    local decoded = safeJsonDecode(value)
    if type(decoded) == "table" then
      return decoded
    end
  end

  return {}
end

local function trimText(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function isCharacterSchemaDebugEnabled()
  local cfg = FGDConfig or {}
  return cfg.CharacterSchemaDebug == true
end

local function characterSchemaDebug(message)
  if not isCharacterSchemaDebugEnabled() then
    return
  end

  print(("^3[fgd_lib:characters]^7 %s"):format(tostring(message or "")))
end

local TABLE_EXISTS_CACHE = {}

local function queryRowsDb(query, params)
  if GetResourceState("oxmysql") == "started" then
    local ok, rows = pcall(function()
      local p = promise.new()
      exports.oxmysql:query(query, params or {}, function(result)
        p:resolve(result)
      end)
      return Citizen.Await(p)
    end)

    if ok and type(rows) == "table" then
      return rows
    end
  end

  if MySQL and MySQL.query and MySQL.query.await then
    local ok, rows = pcall(function()
      return MySQL.query.await(query, params or {})
    end)

    if ok and type(rows) == "table" then
      return rows
    end
  end

  return {}
end

local function hasTable(tableName)
  local key = trimText(tableName)
  if key == "" then
    return false
  end

  local cached = TABLE_EXISTS_CACHE[key]
  if cached ~= nil then
    return cached
  end

  local rows = queryRowsDb([[
    SELECT 1 AS ok
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ?
    LIMIT 1
  ]], { key })

  local exists = type(rows) == "table" and rows[1] ~= nil
  TABLE_EXISTS_CACHE[key] = exists
  return exists
end

local CHARACTERS_SCHEMA_CACHE = nil

local function pickSchemaColumn(byLower, candidates)
  for _, candidate in ipairs(candidates or {}) do
    local found = byLower[string.lower(tostring(candidate))]
    if found then
      return found
    end
  end

  return nil
end

local function getCharactersSchema()
  if CHARACTERS_SCHEMA_CACHE ~= nil then
    return CHARACTERS_SCHEMA_CACHE
  end

  if not hasTable("characters") then
    characterSchemaDebug("Tabela `characters` nao encontrada no banco atual.")
    CHARACTERS_SCHEMA_CACHE = false
    return nil
  end

  local rows = queryRowsDb("SHOW COLUMNS FROM `characters`", {})
  if type(rows) ~= "table" or #rows == 0 then
    characterSchemaDebug("Nao foi possivel ler colunas de `characters` (SHOW COLUMNS retornou vazio).")
    CHARACTERS_SCHEMA_CACHE = false
    return nil
  end

  local byLower = {}
  for _, row in ipairs(rows) do
    local field = trimText(row and row.Field)
    if field ~= "" then
      byLower[string.lower(field)] = field
    end
  end

  local schema = {
    idCol = pickSchemaColumn(byLower, { "id", "passport", "Passport", "user_id", "userid", "citizenid", "citizen_id" }),
    firstNameCol = pickSchemaColumn(byLower, { "Name", "name", "firstname", "first_name", "nome" }),
    lastNameCol = pickSchemaColumn(byLower, { "Lastname", "lastname", "name2", "last_name", "surname", "sobrenome" }),
    skinCol = pickSchemaColumn(byLower, { "Skin", "skin", "Ped", "ped", "model" }),
    sexCol = pickSchemaColumn(byLower, { "sex", "Sex", "sexo", "Sexo" })
  }

  if not schema.idCol then
    characterSchemaDebug("Falha ao mapear schema de `characters`: coluna de ID nao encontrada.")
    CHARACTERS_SCHEMA_CACHE = false
    return nil
  end

  characterSchemaDebug((
    "Schema detectado | id=%s | firstname=%s | lastname=%s | skin=%s | sex=%s"
  ):format(
    tostring(schema.idCol or "nil"),
    tostring(schema.firstNameCol or "nil"),
    tostring(schema.lastNameCol or "nil"),
    tostring(schema.skinCol or "nil"),
    tostring(schema.sexCol or "nil")
  ))

  CHARACTERS_SCHEMA_CACHE = schema
  return schema
end

local function mapCharacterSchemaRow(row)
  if type(row) ~= "table" then
    return nil
  end

  local id = trimText(row.id)
  if id == "" then
    return nil
  end

  local firstname = trimText(row.firstname)
  local lastname = trimText(row.lastname)
  local full = ((firstname or "") .. " " .. (lastname or "")):gsub("^%s+", ""):gsub("%s+$", "")

  return {
    id = id,
    firstname = firstname,
    lastname = lastname,
    fullname = full,
    skin = trimText(row.skin),
    sex = trimText(row.sex)
  }
end

local function queryCharacterByIdFlexible(characterId)
  local schema = getCharactersSchema()
  if not schema then
    return nil
  end

  local idValue = trimText(characterId)
  if idValue == "" then
    return nil
  end

  local firstExpr = schema.firstNameCol and ("`" .. schema.firstNameCol .. "`") or "''"
  local lastExpr = schema.lastNameCol and ("`" .. schema.lastNameCol .. "`") or "''"
  local skinExpr = schema.skinCol and ("`" .. schema.skinCol .. "`") or "''"
  local sexExpr = schema.sexCol and ("`" .. schema.sexCol .. "`") or "''"

  local query = ([[
    SELECT `%s` AS id, %s AS firstname, %s AS lastname, %s AS skin, %s AS sex
    FROM `characters`
    WHERE `%s` = ?
    LIMIT 1
  ]]):format(schema.idCol, firstExpr, lastExpr, skinExpr, sexExpr, schema.idCol)

  local row = querySingle(query, { idValue })
  return mapCharacterSchemaRow(row)
end

local function queryCharacterByNameFlexible(firstname, lastname)
  local schema = getCharactersSchema()
  if not schema or not schema.firstNameCol then
    return nil
  end

  local first = trimText(firstname)
  local last = trimText(lastname)
  if first == "" then
    return nil
  end

  local firstExpr = "`" .. schema.firstNameCol .. "`"
  local lastExpr = schema.lastNameCol and ("`" .. schema.lastNameCol .. "`") or "''"
  local skinExpr = schema.skinCol and ("`" .. schema.skinCol .. "`") or "''"
  local sexExpr = schema.sexCol and ("`" .. schema.sexCol .. "`") or "''"

  local row = nil
  if schema.lastNameCol and last ~= "" then
    local queryFull = ([[
      SELECT `%s` AS id, %s AS firstname, %s AS lastname, %s AS skin, %s AS sex
      FROM `characters`
      WHERE `%s` = ? AND `%s` = ?
      LIMIT 1
    ]]):format(schema.idCol, firstExpr, lastExpr, skinExpr, sexExpr, schema.firstNameCol, schema.lastNameCol)
    row = querySingle(queryFull, { first, last })
  end

  if not row then
    local queryFirst = ([[
      SELECT `%s` AS id, %s AS firstname, %s AS lastname, %s AS skin, %s AS sex
      FROM `characters`
      WHERE `%s` = ?
      LIMIT 1
    ]]):format(schema.idCol, firstExpr, lastExpr, skinExpr, sexExpr, schema.firstNameCol)
    row = querySingle(queryFirst, { first })
  end

  return mapCharacterSchemaRow(row)
end

function GetCharacterByPlayerId(playerId)
  return queryCharacterByIdFlexible(playerId)
end

function FindCharacterByName(firstname, lastname)
  return queryCharacterByNameFlexible(firstname, lastname)
end

local function mapVehicleRows(ownerId, rows, mapper)
  local out = {}
  for _, row in ipairs(rows or {}) do
    local entry = mapper(ownerId, row)
    if entry then
      out[#out + 1] = entry
    end
  end
  return out
end

local function fetchQbVehiclesByCitizenId(citizenId)
  local owner = trimText(citizenId)
  if owner == "" or not hasTable("player_vehicles") then
    return {}
  end

  local rows = queryRowsDb([[ 
    SELECT `citizenid`, `vehicle`, `plate`
    FROM `player_vehicles`
    WHERE `citizenid` = ?
    ORDER BY `id` DESC
  ]], { owner })

  return mapVehicleRows(owner, rows, function(id, row)
    local model = trimText(row.vehicle)
    if model == "" then
      return nil
    end

    return {
      Passport = id,
      Vehicle = model,
      Tax = 0,
      Plate = trimText(row.plate):upper()
    }
  end)
end

local function fetchCreativeVehiclesByPassport(passport)
  local owner = trimText(passport)
  if owner == "" or not hasTable("vehicles") then
    return {}
  end

  local rows = queryRowsDb([[ 
    SELECT `Passport`, `Vehicle`, `Tax`, `Plate`
    FROM `vehicles`
    WHERE `Passport` = ?
    ORDER BY `id` DESC
  ]], { owner })

  return mapVehicleRows(owner, rows, function(id, row)
    local model = trimText(row.Vehicle)
    if model == "" then
      return nil
    end

    return {
      Passport = trimText(row.Passport) ~= "" and trimText(row.Passport) or id,
      Vehicle = model,
      Tax = tonumber(row.Tax) or 0,
      Plate = trimText(row.Plate):upper()
    }
  end)
end

local function buildOwnerCandidates(ownerId)
  local normalized = trimText(ownerId)
  if normalized == "" then
    return {}
  end

  local out = { normalized }
  local digitsOnly = normalized:match("^(%d+)$")
  if digitsOnly then
    local numeric = tostring(tonumber(digitsOnly) or "")
    if numeric ~= "" and numeric ~= normalized then
      out[#out + 1] = numeric
    end
  end

  return out
end

function GetVehiclesByPlayerId(playerId)
  local ownerId = trimText(playerId)
  if ownerId == "" then
    return {}
  end

  local fw = FGD.GetFramework()
  local candidates = buildOwnerCandidates(ownerId)

  if fw == "qbcore" then
    for _, candidate in ipairs(candidates) do
      local rows = fetchQbVehiclesByCitizenId(candidate)
      if #rows > 0 then
        return rows
      end
    end
    return {}
  end

  if fw == "creative" then
    for _, candidate in ipairs(candidates) do
      local rows = fetchCreativeVehiclesByPassport(candidate)
      if #rows > 0 then
        return rows
      end
    end
    return {}
  end

  for _, candidate in ipairs(candidates) do
    local rows = fetchQbVehiclesByCitizenId(candidate)
    if #rows > 0 then
      return rows
    end
  end

  for _, candidate in ipairs(candidates) do
    local rows = fetchCreativeVehiclesByPassport(candidate)
    if #rows > 0 then
      return rows
    end
  end

  return {}
end

function GetPlayerVehicles(src)
  local playerId = GetPlayerId(src)
  if not playerId then
    return {}
  end

  return GetVehiclesByPlayerId(playerId)
end

local function getQbIdentityParts(src)
  local Player = getQBPlayer(src)
  if not Player or not Player.PlayerData then
    return nil, {}, nil
  end

  local pd = Player.PlayerData or {}
  local char = normalizeQbCharinfo(pd.charinfo)

  local citizenId = trimText(pd.citizenid)
  if citizenId == "" then
    citizenId = trimText(pd.license)
  end

  local firstname = trimText(char.firstname or char.firstName or char.name)
  local lastname = trimText(char.lastname or char.lastName or char.surname)

  return citizenId, char, {
    firstname = firstname,
    lastname = lastname
  }
end

local function toPositiveInteger(value)
  if value == nil then return nil end

  local t = type(value)
  if t == "number" then
    local n = math.floor(value)
    if n > 0 then return n end
    return nil
  end

  local raw = tostring(value)
  local digitsOnly = raw:match("^%d+$")
  if digitsOnly then
    local n = tonumber(digitsOnly)
    if n and n > 0 then
      return n
    end
  end

  return nil
end

local function resolveCreativePassport(src, vRP)
  local iface = vRP or getVRP()
  if not iface then
    moneyDebug(("resolveCreativePassport src=%s -> vRP interface indisponivel"):format(tostring(src)))
    return nil
  end

  local direct = callAny(iface, { "Passport", "GetPassport", "getUserId", "GetUserId" }, src)
  local passport = toPositiveInteger(direct)
  if passport then
    moneyDebug(("resolveCreativePassport src=%s -> direct=%s"):format(tostring(src), tostring(passport)))
    return passport
  end

  local player = Player(src)
  if player and player.state then
    local stateKeys = {
      "passport",
      "Passport",
      "user_id",
      "userId",
      "UserId"
    }

    for _, key in ipairs(stateKeys) do
      local value = toPositiveInteger(player.state[key])
      if value then
        moneyDebug(("resolveCreativePassport src=%s -> state[%s]=%s"):format(tostring(src), tostring(key), tostring(value)))
        return value
      end
    end
  end

  moneyDebug(("resolveCreativePassport src=%s -> falhou (direct=%s)"):format(tostring(src), tostring(direct)))
  return nil
end

local function isCreativeSuccess(result)
  if result == true then
    return true
  end

  if type(result) == "number" then
    return result > 0
  end

  return false
end

local function tryAnyCreativeSuccess(target, methods, ...)
  if not target then return false end

  for _, methodName in ipairs(methods) do
    local fn = target[methodName]
    if type(fn) == "function" then
      local ok, result = pcall(fn, ...)
      if ok and isCreativeSuccess(result) then
        return true
      end

      ok, result = pcall(fn, target, ...)
      if ok and isCreativeSuccess(result) then
        return true
      end
    end
  end

  return false
end

function GetFramework()
  return FGD.GetFramework()
end

function GetPlayerId(src)
  local fw = FGD.GetFramework()

  if fw == "qbcore" then
    local citizenId = getQbIdentityParts(src)
    if citizenId and citizenId ~= "" then
      return citizenId
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if vRP then
      local passport = resolveCreativePassport(src, vRP)
      if passport then return passport end
    end
  end

  -- Fallbacks centralizados para cenarios onde a deteccao de framework falha
  -- temporariamente (start order/resource custom), mas o jogador ja esta carregado.
  local qbPlayer = getQBPlayer(src)
  if qbPlayer and qbPlayer.PlayerData then
    local qbId = trimText(qbPlayer.PlayerData.citizenid)
    if qbId == "" then
      qbId = trimText(qbPlayer.PlayerData.license)
    end
    if qbId ~= "" then
      return qbId
    end
  end

  local vRP = getVRP()
  if vRP then
    local passport = resolveCreativePassport(src, vRP)
    if passport then
      return passport
    end
  end

  local player = Player(src)
  if player and player.state then
    local keys = {
      "id",
      "Id",
      "charid",
      "CharId",
      "passport",
      "Passport",
      "user_id",
      "userId",
      "UserId",
      "char_id",
      "character_id",
      "characterId",
      "citizenid",
      "citizenId",
      "CitizenId",
      "license"
    }

    for _, key in ipairs(keys) do
      local value = player.state[key]
      if value ~= nil and tostring(value) ~= "" then
        return value
      end
    end
  end

  return nil
end

function GetPlayerIdentity(src)
  local fw = FGD.GetFramework()
  local playerId = GetPlayerId(src)

  if fw == "qbcore" then
    local citizenId, _, names = getQbIdentityParts(src)
    if not names then
      return nil
    end

    local firstname = names.firstname or ""
    local lastname = names.lastname or ""
    local fullname = ((firstname or "") .. " " .. (lastname or "")):gsub("^%s+", ""):gsub("%s+$", "")

    return {
      id = citizenId ~= "" and citizenId or playerId,
      citizenid = citizenId ~= "" and citizenId or playerId,
      firstname = firstname,
      lastname = lastname,
      fullname = fullname,
      name = firstname,
      surname = lastname
    }
  end

  if fw == "creative" then
    local vRP = getVRP()
    if vRP and playerId then
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

    if playerId then
      local row = queryCharacterByIdFlexible(playerId)
      if row then
        return {
          id = row.id,
          firstname = row.firstname,
          lastname = row.lastname,
          fullname = row.fullname
        }
      end
    end
  end

  if playerId then
    local row = queryCharacterByIdFlexible(playerId)
    if row then
      return {
        id = row.id,
        firstname = row.firstname,
        lastname = row.lastname,
        fullname = row.fullname
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

local function callQbMoneyFunction(Player, methodName, ...)
  if not Player or not Player.Functions then
    return false, nil
  end

  local fn = Player.Functions[methodName]
  if type(fn) ~= "function" then
    return false, nil
  end

  -- QBCore/QBox podem expor closures com assinaturas diferentes.
  -- Testa todos formatos e so considera sucesso quando nao retorna false.
  local args = { ... }
  local account = tostring(args[1] or "")
  local amount = tonumber(args[2])
  local reason = args[3]

  local variants = {
    args
  }

  if account ~= "" and amount and amount > 0 then
    variants[#variants + 1] = { amount, account, reason }
    variants[#variants + 1] = { account, amount }
    variants[#variants + 1] = { amount, account }
  end

  local attempts = {}
  for _, variant in ipairs(variants) do
    attempts[#attempts + 1] = function() return fn(table.unpack(variant)) end
    attempts[#attempts + 1] = function() return fn(Player, table.unpack(variant)) end
    attempts[#attempts + 1] = function() return fn(Player.Functions, table.unpack(variant)) end
  end

  local hadCallableAttempt = false
  local lastResult = nil

  for _, runner in ipairs(attempts) do
    local ok, result = pcall(runner)
    if ok then
      hadCallableAttempt = true
      lastResult = result
      if result ~= false then
        return true, result
      end
    end
  end

  if hadCallableAttempt then
    return true, lastResult
  end

  return false, nil
end

local function isQbxCoreStarted()
  return GetResourceState("qbx_core") == "started"
end

local function callQbxMoney(methodName, ...)
  if not isQbxCoreStarted() then
    return false, nil
  end

  local args = { ... }

  local ok, result
  if methodName == "GetMoney" then
    ok, result = pcall(function()
      return exports.qbx_core:GetMoney(table.unpack(args))
    end)
  elseif methodName == "AddMoney" then
    ok, result = pcall(function()
      return exports.qbx_core:AddMoney(table.unpack(args))
    end)
  elseif methodName == "RemoveMoney" then
    ok, result = pcall(function()
      return exports.qbx_core:RemoveMoney(table.unpack(args))
    end)
  else
    return false, nil
  end

  if ok then
    return true, result
  end

  return false, nil
end

function GetMoney(src, account)
  local fw = FGD.GetFramework()
  local acc = tostring(account or "cash"):lower()

  if fw == "qbcore" then
    local okQbx, qbxValue = callQbxMoney("GetMoney", src, acc)
    if okQbx and qbxValue ~= nil then
      return tonumber(qbxValue) or 0
    end

    local Player = getQBPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.money then
      return tonumber(Player.PlayerData.money[acc]) or 0
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return 0 end

    local playerId = resolveCreativePassport(src, vRP)
    if not playerId then return 0 end

    if acc == "bank" then
      return tonumber(callAny(vRP, { "GetBank", "getBankMoney", "Bank" }, playerId)) or 0
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
    local okQbx, qbxResult = callQbxMoney("AddMoney", src, acc, value, reason or "fgd_lib")
    if okQbx and qbxResult ~= nil then
      return qbxResult ~= false
    end

    local Player = getQBPlayer(src)
    if Player and Player.Functions and Player.Functions.AddMoney then
      local ok, result = callQbMoneyFunction(Player, "AddMoney", acc, value, reason or "fgd_lib")
      if ok then return result ~= false end
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return false end

    local playerId = resolveCreativePassport(src, vRP)
    if not playerId then return false end

    if acc == "bank" then
      return tryAnyCreativeSuccess(vRP, { "GiveBank", "addBank" }, playerId, value)
    end

    return tryAnyCreativeSuccess(vRP, { "GiveMoney", "giveMoney", "GenerateItem" }, playerId, value)
  end

  return false
end

function RemoveMoney(src, account, amount, reason)
  local fw = FGD.GetFramework()
  local acc = tostring(account or "cash"):lower()
  local value = tonumber(amount) or 0
  if value <= 0 then return false end

  if fw == "qbcore" then
    local okQbx, qbxResult = callQbxMoney("RemoveMoney", src, acc, value, reason or "fgd_lib")
    if okQbx and qbxResult ~= nil then
      return qbxResult ~= false
    end

    local Player = getQBPlayer(src)
    if Player and Player.Functions and Player.Functions.RemoveMoney then
      local ok, result = callQbMoneyFunction(Player, "RemoveMoney", acc, value, reason or "fgd_lib")
      if ok then return result ~= false end
    end
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then return false end

    local playerId = resolveCreativePassport(src, vRP)
    if not playerId then
      moneyDebug(("RemoveMoney creative src=%s acc=%s amount=%s -> playerId invalido"):format(tostring(src), tostring(acc), tostring(value)))
      return false
    end

    if acc == "bank" then
      local ok = tryAnyCreativeSuccess(vRP, { "PaymentBank", "WithdrawBank", "tryWithdraw", "RemoveBank" }, playerId, value, false)
      moneyDebug(("RemoveMoney creative BANK src=%s passport=%s amount=%s result=%s"):format(tostring(src), tostring(playerId), tostring(value), tostring(ok)))
      return ok
    end

    local ok = tryAnyCreativeSuccess(vRP, { "Payment", "tryPayment", "TakeItem" }, playerId, value)
    moneyDebug(("RemoveMoney creative CASH src=%s passport=%s amount=%s result=%s"):format(tostring(src), tostring(playerId), tostring(value), tostring(ok)))
    return ok
  end

  return false
end

function RemoveMoneyWithBankFallback(src, amount, reason)
  local fw = FGD.GetFramework()
  local value = tonumber(amount) or 0
  if value <= 0 then return false end

  if fw == "qbcore" then
    local okQbxCash, qbxCash = callQbxMoney("GetMoney", src, "cash")
    local okQbxBank, qbxBank = callQbxMoney("GetMoney", src, "bank")
    if okQbxCash and okQbxBank then
      local cashBalance = tonumber(qbxCash) or 0
      local bankBalance = tonumber(qbxBank) or 0

      moneyDebug(("QBX Fallback src=%s amount=%s cash=%s bank=%s"):format(
        tostring(src),
        tostring(value),
        tostring(cashBalance),
        tostring(bankBalance)
      ))

      if (cashBalance + bankBalance) < value then
        moneyDebug(("QBX Fallback insuficiente src=%s total=%s amount=%s"):format(
          tostring(src),
          tostring(cashBalance + bankBalance),
          tostring(value)
        ))
        return false
      end

      local amountFromCash = math.min(value, math.max(0, cashBalance))
      local amountFromBank = value - amountFromCash

      if amountFromCash > 0 then
        local okCash, resultCash = callQbxMoney("RemoveMoney", src, "cash", amountFromCash, reason or "fgd_lib")
        moneyDebug(("QBX Remove cash src=%s amount=%s ok=%s result=%s"):format(
          tostring(src),
          tostring(amountFromCash),
          tostring(okCash),
          tostring(resultCash)
        ))
        if not (okCash and resultCash ~= false) then
          return false
        end
      end

      if amountFromBank > 0 then
        local okBank, resultBank = callQbxMoney("RemoveMoney", src, "bank", amountFromBank, reason or "fgd_lib")
        moneyDebug(("QBX Remove bank src=%s amount=%s ok=%s result=%s"):format(
          tostring(src),
          tostring(amountFromBank),
          tostring(okBank),
          tostring(resultBank)
        ))
        if not (okBank and resultBank ~= false) then
          if amountFromCash > 0 then
            callQbxMoney("AddMoney", src, "cash", amountFromCash, reason or "fgd_lib")
          end
          return false
        end
      end

      return true
    end

    local Player = getQBPlayer(src)
    if not Player or not Player.Functions then return false end

    -- Primeiro tenta remover da carteira
    local cashBalance = tonumber((Player.PlayerData and Player.PlayerData.money and Player.PlayerData.money.cash) or 0)
    if cashBalance >= value then
      local ok, result = callQbMoneyFunction(Player, "RemoveMoney", "cash", value, reason or "fgd_lib")
      return ok and result ~= false
    end

    -- Se não tem saldo em cash, tira quanto tiver de cash + o resto de bank
    local amountFromCash = math.max(0, cashBalance)
    local amountFromBank = value - amountFromCash

    if amountFromCash > 0 then
      local ok1, result1 = callQbMoneyFunction(Player, "RemoveMoney", "cash", amountFromCash, reason or "fgd_lib")
      if not (ok1 and result1 ~= false) then return false end
    end

    if amountFromBank > 0 then
      local ok2, result2 = callQbMoneyFunction(Player, "RemoveMoney", "bank", amountFromBank, reason or "fgd_lib")
      if not (ok2 and result2 ~= false) then
        -- Se falhou ao tirar do bank, devolve o que foi tirado da carteira
        if amountFromCash > 0 then
          callQbMoneyFunction(Player, "AddMoney", "cash", amountFromCash, reason or "fgd_lib")
        end
        return false
      end
    end

    return true
  end

  if fw == "creative" then
    local vRP = getVRP()
    if not vRP then
      moneyDebug(("Fallback creative src=%s amount=%s -> vRP indisponivel"):format(tostring(src), tostring(value)))
      return false
    end

    local playerId = resolveCreativePassport(src, vRP)
    if not playerId then
      moneyDebug(("Fallback creative src=%s amount=%s -> passport invalido"):format(tostring(src), tostring(value)))
      return false
    end

    local cashBalance = tonumber(callAny(vRP, { "GetMoney", "getMoney" }, playerId)) or -1
    local bankBalance = tonumber(callAny(vRP, { "GetBank", "getBankMoney", "Bank" }, playerId)) or -1
    moneyDebug(("Fallback creative src=%s passport=%s amount=%s cash=%s bank=%s reason=%s"):format(
      tostring(src),
      tostring(playerId),
      tostring(value),
      tostring(cashBalance),
      tostring(bankBalance),
      tostring(reason or "")
    ))

    -- Prioriza semantica do money.lua e tenta todas variacoes disponiveis.
    local fullOk = tryAnyCreativeSuccess(vRP, { "PaymentFull", "tryFullPayment" }, playerId, value, false)
    moneyDebug(("Fallback creative PaymentFull src=%s passport=%s amount=%s result=%s"):format(tostring(src), tostring(playerId), tostring(value), tostring(fullOk)))
    if fullOk then
      return true
    end

    local cashOk = tryAnyCreativeSuccess(vRP, { "Payment", "tryPayment", "TakeItem" }, playerId, value)
    moneyDebug(("Fallback creative Payment src=%s passport=%s amount=%s result=%s"):format(tostring(src), tostring(playerId), tostring(value), tostring(cashOk)))
    if cashOk then
      return true
    end

    local bankOk = tryAnyCreativeSuccess(vRP, { "PaymentBank", "WithdrawBank", "tryWithdraw", "RemoveBank" }, playerId, value, false)
    moneyDebug(("Fallback creative PaymentBank src=%s passport=%s amount=%s result=%s"):format(tostring(src), tostring(playerId), tostring(value), tostring(bankOk)))
    return bankOk
  end

  return false
end

local function normalizePermissionToken(permission)
  local raw = tostring(permission or "")
  local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then
    return nil, nil
  end

  local tokenType, tokenValue = trimmed:match("^([%w_%-]+)%s*:%s*(.+)$")
  if not tokenType then
    return nil, trimmed
  end

  tokenType = tokenType:lower()
  tokenValue = tostring(tokenValue or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if tokenValue == "" then
    return nil, nil
  end

  return tokenType, tokenValue
end

local function normalizePermissionInput(permissions)
  if type(permissions) == "table" then
    return permissions
  end

  if permissions == nil then
    return {}
  end

  local text = tostring(permissions)
  if text == "" then
    return {}
  end

  return { text }
end

local function getQbPlayerData(src)
  local player = getQBPlayer(src)
  if not player or not player.PlayerData then
    return nil
  end

  return player.PlayerData
end

local function hasQbTokenPermission(src, permission)
  local QBCore = getQBCore()
  local tokenType, tokenValue = normalizePermissionToken(permission)
  local fallbackValue = tostring(permission or "")

  if tokenType == "perm" or tokenType == "qbperm" then
    if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
      local ok, hasPerm = pcall(QBCore.Functions.HasPermission, src, tokenValue)
      if ok then return hasPerm == true end
    end
    return false
  end

  local pd = getQbPlayerData(src)
  if not pd then
    return false
  end

  local wanted = tostring(tokenValue or fallbackValue):lower()

  if tokenType == "job" then
    local jobName = tostring(pd.job and pd.job.name or ""):lower()
    return jobName ~= "" and jobName == wanted
  end

  if tokenType == "gang" then
    local gangName = tostring(pd.gang and pd.gang.name or ""):lower()
    return gangName ~= "" and gangName == wanted
  end

  if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
    local ok, hasPerm = pcall(QBCore.Functions.HasPermission, src, fallbackValue)
    if ok and hasPerm == true then
      return true
    end
  end

  local jobName = tostring(pd.job and pd.job.name or ""):lower()
  if jobName ~= "" and jobName == wanted then
    return true
  end

  local gangName = tostring(pd.gang and pd.gang.name or ""):lower()
  if gangName ~= "" and gangName == wanted then
    return true
  end

  return false
end

local function hasCreativeTokenPermission(src, permission)
  local vRP = getVRP()
  if not vRP then return false end

  local playerId = GetPlayerId(src)
  if not playerId then return false end

  local tokenType, tokenValue = normalizePermissionToken(permission)
  local fallbackValue = tostring(permission or "")

  local function isGranted(result)
    if result == true then
      return true
    end

    if type(result) == "number" then
      return result > 0
    end

    if type(result) == "string" then
      return result ~= "" and result ~= "0"
    end

    return false
  end

  if tokenType == "group" then
    return isGranted(callAny(vRP, { "HasGroup", "hasGroup" }, playerId, tokenValue))
  end

  if tokenType == "perm" then
    return isGranted(callAny(vRP, { "HasPermission", "hasPermission" }, playerId, tokenValue))
  end

  if isGranted(callAny(vRP, { "HasGroup", "hasGroup" }, playerId, fallbackValue)) then
    return true
  end

  if isGranted(callAny(vRP, { "HasPermission", "hasPermission" }, playerId, fallbackValue)) then
    return true
  end

  return false
end

function HasPermission(src, permission)
  local fw = FGD.GetFramework()
  local perm = tostring(permission or "")
  if perm == "" then return false end

  if fw == "qbcore" then
    return hasQbTokenPermission(src, perm)
  end

  if fw == "creative" then
    return hasCreativeTokenPermission(src, perm)
  end

  return false
end

function HasAnyPermission(src, permissions)
  local list = normalizePermissionInput(permissions)
  for _, permission in ipairs(list) do
    if HasPermission(src, permission) then
      return true
    end
  end

  return false
end

function GiveVehicleKeys(src, plate, vehicle)
  local playerSrc = tonumber(src) or 0
  local normalizedPlate = tostring(plate or ""):gsub("^%s+", ""):gsub("%s+$", "")

  if playerSrc <= 0 or normalizedPlate == "" then
    return false
  end

  -- Caminho preferencial para QBox (conforme config padrao do qbx_core).
  if GetResourceState("qbx_core") == "started" and GetResourceState("mri_Qcarkeys") == "started" then
    local ok, result = pcall(function()
      return exports.mri_Qcarkeys:GiveTempKeys(playerSrc, normalizedPlate)
    end)

    if ok then
      return result ~= false
    end
  end

  -- Fallback comum para ambientes qbx_vehiclekeys.
  if GetResourceState("qbx_vehiclekeys") == "started" then
    local ok, result = pcall(function()
      return exports.qbx_vehiclekeys:GiveKeys(playerSrc, normalizedPlate)
    end)

    if ok then
      return result ~= false
    end
  end

  -- Creative/VRP: no-op para nao quebrar comportamento existente.
  if FGD.GetFramework() == "creative" then
    return true
  end

  return false
end

exports("GetFramework", GetFramework)
exports("GetPlayerId", GetPlayerId)
exports("GetPlayerIdentity", GetPlayerIdentity)
exports("GetPlayerName", GetPlayerName)
exports("GetCharacterByPlayerId", GetCharacterByPlayerId)
exports("FindCharacterByName", FindCharacterByName)
exports("GetMoney", GetMoney)
exports("AddMoney", AddMoney)
exports("RemoveMoney", RemoveMoney)
exports("RemoveMoneyWithBankFallback", RemoveMoneyWithBankFallback)
exports("GetPlayerVehicles", GetPlayerVehicles)
exports("GetVehiclesByPlayerId", GetVehiclesByPlayerId)
exports("GiveVehicleKeys", GiveVehicleKeys)
exports("HasPermission", HasPermission)
exports("HasAnyPermission", HasAnyPermission)

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
