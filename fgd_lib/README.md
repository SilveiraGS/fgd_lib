# fgd_lib

Biblioteca de integracao multi-framework para scripts da Forge Group Developer.

## Frameworks suportadas

- `qbcore`
- `creative` (base `vrp`)
- `auto` (detecta automaticamente)

## Configuracao

Edite `config.lua`:

```lua
FGDConfig = {
  Framework = "auto", -- "qbcore", "creative", "auto"
  QBCoreResource = "qb-core",
  CreativeResource = "vrp",
  Debug = true
}
```

## Exports (server)

- `exports.fgd_lib:GetFramework()`
- `exports.fgd_lib:GetPlayerId(source)`
- `exports.fgd_lib:GetPlayerIdentity(source)`
- `exports.fgd_lib:GetPlayerName(source)`
- `exports.fgd_lib:GetMoney(source, account)`
- `exports.fgd_lib:AddMoney(source, account, amount, reason)`
- `exports.fgd_lib:RemoveMoney(source, account, amount, reason)`
- `exports.fgd_lib:HasPermission(source, permission)`

### Exemplo

```lua
local playerId = exports.fgd_lib:GetPlayerId(source)
if not playerId then
  return
end

local identity = exports.fgd_lib:GetPlayerIdentity(source)
print("Jogador:", identity and identity.fullname or "desconhecido")
```

## Exports (client)

- `exports.fgd_lib:GetFramework()`
- `exports.fgd_lib:GetPlayerData()`

## Ordem de start recomendada

No `server.cfg`, inicie antes dos apps:

```cfg
ensure fgd_lib
ensure app-gov
ensure cnh-app
ensure zap-app
```

## Observacao

Se algum fork da framework usar nomes de funcoes diferentes, ajuste apenas `fgd_lib/server/main.lua` sem precisar mexer nos apps.
