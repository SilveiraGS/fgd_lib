FGDConfig = {
  -- Opcoes: "qbcore", "creative", "auto"
  Framework = "auto",

  QBCoreResource = "qb-core",
  CreativeResource = "vrp",

  VersionCheck = {
    Enabled = true,
  
    Url = " https://raw.githubusercontent.com/SilveiraGS/fgd_lib/main/fgd_lib/fxmanifest.lua"
  },

  Debug = false

  -- Debug especifico para diagnosticar mapeamento de colunas da tabela `characters`.
  -- Quando true, imprime no console quais colunas foram detectadas automaticamente.
  CharacterSchemaDebug = false
}
