fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Forge Group Developer"
description "FGD Multi-Framework Integration Library"
version "1.0.1"

shared_scripts {
  "config.lua",
  "shared/main.lua"
}

client_scripts {
  "client/main.lua"
}

server_scripts {
  "server/main.lua"
}

client_exports {
  "GetFramework",
  "GetPlayerData"
}

server_exports {
  "GetFramework",
  "GetPlayerId",
  "GetPlayerIdentity",
  "GetPlayerName",
  "GetMoney",
  "AddMoney",
  "RemoveMoney",
  "HasPermission"
}

escrow_ignore {
  "config.lua"
}

