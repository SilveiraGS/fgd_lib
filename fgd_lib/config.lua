FGDConfig = {
  -- Opcoes: "qbcore", "creative", "auto"
  Framework = "auto",

  QBCoreResource = "qb-core",
  CreativeResource = "vrp",

  VersionCheck = {
    Enabled = true,
    -- Pode ser um .txt com "1.0.1", JSON, ou o proprio fxmanifest.lua remoto
    Url = "https://raw.githubusercontent.com/SilveiraGS/fgd_lib/refs/heads/main/fgd_lib/fxmanifest.lua"
  },

  -- Se true, printa logs basicos no console
  Debug = false
}
