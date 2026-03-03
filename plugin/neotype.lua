-- Auto-bootstrap NeoType with defaults so commands are always available.
pcall(function()
  require("neotype").setup({})
end)
