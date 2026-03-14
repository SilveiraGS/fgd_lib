fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Forge Group Developer"
description "FGD Multi-Framework Integration Library"
version "1.0.3"

shared_scripts {
  "config.lua",
  "shared/main.lua"
}

client_scripts {
  "client/main.lua"
}

server_scripts {
  "@vrp/lib/Utils.lua",
  "server/main.lua"
}

client_exports {
  "GetFramework",
  "GetPlayerData",
  "RegisterTargetCircle",
  "Notify"
}

server_exports {
  "GetFramework",
  "GetPlayerId",
  "GetPlayerIdentity",
  "GetPlayerName",
  "GetMoney",
  "AddMoney",
  "RemoveMoney",
  "RemoveMoneyWithBankFallback",
  "GetPlayerVehicles",
  "GetVehiclesByPlayerId",
  "GiveVehicleKeys",
  "HasPermission",
  "HasAnyPermission"
}

escrow_ignore {
  "config.lua"
}
