local Keys = require("which-key.keys")
local config = require("which-key.config")
local Layout = require("which-key.layout")
local Util = require("which-key.util")

local highlight = vim.api.nvim_buf_add_highlight

---@class View
local M = {}

M.keys = ""
M.mode = "n"
M.auto = false
M.count = 0
M.buf = nil
M.win = nil

function M.is_valid()
  return M.buf and vim.api.nvim_buf_is_valid(M.buf) and vim.api.nvim_buf_is_loaded(M.buf) and
           vim.api.nvim_win_is_valid(M.win)
end

function M.show()
  if M.is_valid() then return end
  local opts = {
    relative = "editor",
    width = vim.o.columns - config.options.window.margin[2] - config.options.window.margin[4] -
      (config.options.window.border ~= "none" and 2 or 0),
    height = config.options.layout.height.min,
    focusable = false,
    anchor = "SW",
    border = config.options.window.border,
    row = vim.o.lines - config.options.window.margin[3] -
      (config.options.window.border ~= "none" and 2 or 0) - vim.o.cmdheight,
    col = config.options.window.margin[2],
    style = "minimal",
  }
  if config.options.window.position == "top" then
    opts.anchor = "NW"
    opts.row = config.options.window.margin[1]
  end
  M.buf = vim.api.nvim_create_buf(false, true)
  M.win = vim.api.nvim_open_win(M.buf, false, opts)
  -- vim.api.nvim_win_hide(M.win)
  vim.api.nvim_win_set_option(M.win, "winhighlight", "NormalFloat:WhichKeyFloat")
  vim.cmd [[autocmd! WinClosed <buffer> lua require("which-key.view").on_close()]]
end

function M.get_input(wait)
  while true do
    local n = wait and vim.fn.getchar() or vim.fn.getchar(0)
    if n == 0 then return end
    local c = (type(n) == "number" and vim.fn.nr2char(n) or n)

    -- Fix < characters
    if c == "<" then c = "<lt>" end

    if c == Util.t("<esc>") then
      M.on_close()
      return
    elseif c == Util.t("<c-d>") then
      M.scroll(false)
    elseif c == Util.t("<c-u>") then
      M.scroll(true)
    elseif c == Util.t("<bs>") then
      M.back()
    else
      M.keys = M.keys .. c
    end

    if wait then
      vim.defer_fn(function() M.on_keys({ auto = true }) end, 0)
      return
    end
  end
end

function M.scroll(up)
  local height = vim.api.nvim_win_get_height(M.win)
  local cursor = vim.api.nvim_win_get_cursor(M.win)
  if up then
    cursor[1] = math.max(cursor[1] - height, 1)
  else
    cursor[1] = math.min(cursor[1] + height, vim.api.nvim_buf_line_count(M.buf))
  end
  vim.api.nvim_win_set_cursor(M.win, cursor)
end

function M.on_close() M.hide() end

function M.hide()
  vim.api.nvim_echo({ { "" } }, false, {})
  M.hide_cursor()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
    M.buf = nil
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, { force = true })
    M.win = nil
  end
end

function M.show_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_add_highlight(buf, config.namespace, "Cursor", cursor[1] - 1, cursor[2],
                                 cursor[2] + 1)
end

function M.hide_cursor()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, config.namespace, 0, -1)
end

function M.back()
  local buf = vim.api.nvim_get_current_buf()
  local node = Keys.get_tree(M.mode, buf).tree:get(M.keys, -1) or
                 Keys.get_tree(M.mode).tree:get(M.keys, -1)
  if node then M.keys = node.prefix end
end

---@param path Node[]
function M.has_cmd(path)
  for _, node in pairs(path) do if node.mapping and node.mapping.cmd then return true end end
  return false
end

function M.execute(prefix, mode, buf)

  local global_node = Keys.get_tree(mode).tree:get(prefix)
  local buf_node = buf and Keys.get_tree(mode, buf).tree:get(prefix) or nil

  if global_node and global_node.mapping and Keys.is_hook(prefix, global_node.mapping.cmd) then
    return
  end
  if buf_node and buf_node.mapping and Keys.is_hook(prefix, buf_node.mapping.cmd) then return end

  local hooks = {}

  local function unhook(nodes, nodes_buf)
    for _, node in pairs(nodes) do
      if Keys.is_hooked(node.mapping.prefix, mode, nodes_buf) then
        table.insert(hooks, { node.mapping.prefix, nodes_buf })
        Keys.hook_del(node.mapping.prefix, mode, nodes_buf)
      end
    end
  end

  -- make sure we remove all WK hooks before executing the sequence
  -- this is to make existing keybindongs work and prevent recursion
  unhook(Keys.get_tree(mode).tree:path(prefix))
  unhook(buf and Keys.get_tree(mode, buf).tree:path(prefix) or {}, buf)

  -- fix <lt>
  prefix = prefix:gsub("<lt>", "<")
  if M.count and M.count ~= 0 then prefix = M.count .. prefix end

  -- feed the keys with remap
  vim.api.nvim_feedkeys(prefix, "m", true)

  -- defer hooking WK until after the keys were executed
  vim.defer_fn(
    function() for _, hook in pairs(hooks) do Keys.hook_add(hook[1], mode, hook[2]) end end, 0)
end

function M.open(keys, opts)
  opts = opts or {}
  M.keys = keys or ""
  M.mode = opts.mode or Util.get_mode()
  M.count = vim.api.nvim_get_vvar("count")
  M.show_cursor()
  M.on_keys(opts)
end

function M.on_keys(opts)
  -- eat queued characters
  M.get_input(false)
  local buf = vim.api.nvim_get_current_buf()

  local results = Keys.get_mappings(M.mode, M.keys, buf)

  --- Check for an exact match. Feedkeys with remap
  if results.mapping and not results.mapping.group and #results.mappings == 0 then
    M.hide()
    M.execute(M.keys, M.mode, buf)
    return
  end

  -- Check for no mappings found. Feedkeys without remap
  if #results.mappings == 0 then
    M.hide()
    -- only execute if an actual key was typed while WK was open
    if opts.auto then M.execute(M.keys, M.mode, buf) end
    return
  end

  local layout = Layout:new(results)

  if not M.is_valid() then M.show() end

  M.render(layout:layout(M.win))

  -- defer further eating on the main loop
  vim.defer_fn(function() M.get_input(true) end, 0)
end

---@param text Text
function M.render(text)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, text.lines)
  local height = #text.lines
  if height > config.options.layout.height.max then height = config.options.layout.height.max end
  vim.api.nvim_win_set_height(M.win, height)
  if vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_clear_namespace(M.buf, config.namespace, 0, -1)
  end
  for _, data in ipairs(text.hl) do
    highlight(M.buf, config.namespace, data.group, data.line, data.from, data.to)
  end
end

return M
