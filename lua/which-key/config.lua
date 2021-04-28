local M = {}

M.namespace = vim.api.nvim_create_namespace("WhichKey")

---@class Options
local defaults = {
  builtin = true, -- register a list of builtin key mappings
  icons = { breadcrumb = "»", separator = "➜", group = "+" },
  plugins = {
    marks = true,
    registers = true,
    ["text-objects"] = true,
    operators = true,
    motions = true,
    misc = { windows = true, nav = true, z = true, g = true },
  },
  window = {
    border = "none", -- none, single, double, shadow
    position = "bottom", -- bottom, top
    margin = { 1, 0, 1, 0 }, -- extra window margin [top, right, bottom, left]
    padding = { 2, 2, 2, 2 }, -- extra window padding [top, right, bottom, left]
  },
  layout = { height = { min = 4, max = 25 }, width = { min = 20, max = 50 }, spacing = 3 },
}

---@type Options
M.options = {}

---@return Options
function M.setup(options) M.options = vim.tbl_deep_extend("force", {}, defaults, options or {}) end

M.setup()

return M