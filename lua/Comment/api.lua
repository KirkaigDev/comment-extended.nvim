---@mod comment.api Core Lua API
---@brief [[
---This module provides the core lua APIs which is used by the default keybindings
---and <Plug> (Read |comment.plugmap|) mappings. These API can be used to setup your
---own custom keybindings or to even make your (un)comment function.
---@brief ]]

local config_import = require("Comment.config")
local utils = require("Comment.utils")
local opfunc = require("Comment.opfunc")
local extra = require("Comment.extra")

local meta, core = {}, {}

---API metamethods
---@param instance table
---@param comment_type CommentType
---@return table
function core.__index(instance, comment_type)
	local line_count_methods = {}
	local mode, type = instance.cmode, utils.ctype[comment_type]

	---To comment the current-line
	---NOTE:
	---In current-line linewise method, 'opmode' is not useful which is always equals to `char`
	---but we need 'nil' here which is used for current-line
	function line_count_methods.current(_, user_config)
		utils.catch(opfunc.opfunc, nil, user_config or config_import:get(), mode, type)
	end

	---To comment lines with a count
	function line_count_methods.count(count, user_config)
		utils.catch(opfunc.count, count or vim.api.nvim_get_vvar("count"), user_config or config_import:get(), mode, type)
	end

	---@private
	---To comment lines with a count, also dot-repeatable
	---WARN: This is not part of the API but anyone case use it, if they want
	function line_count_methods.count_repeat(_, count, user_config)
		line_count_methods.count(count, user_config)
	end

	return setmetatable({}, {
		__index = line_count_methods,
		__call = function(_, motion, user_config)
			utils.catch(opfunc.opfunc, motion, user_config or config_import:get(), mode, type)
		end,
	})
end

---@tag comment.api.toggle.linewise
---@tag comment.api.toggle.blockwise
---Provides API to toggle comments over a region, on current-line, or with a
---count using line or block comment string.
---
---Every function takes a {motion} argument, except '*.count()' function which
---takes an {count} argument, and an optional {config} parameter.
---@type table A metatable containing API functions
---@see comment.opfunc.OpMotion
---@see comment.config
---@usage [[
---local api = require('Comment.api')
---local config = require('Comment.config'):get()
---
---api.toggle.linewise(motion, config?)
---api.toggle.linewise.current(motion?, config?)
---api.toggle.linewise.count(count, config?)
---
---api.toggle.blockwise(motion, config?)
---api.toggle.blockwise.current(motion?, config?)
---api.toggle.blockwise.count(count, config?)
---
----- Toggle current line (linewise) using C-/
---vim.keymap.set('n', '<C-_>', api.toggle.linewise.current)
---
----- Toggle current line (blockwise) using C-\
---vim.keymap.set('n', '<C-\\>', api.toggle.blockwise.current)
---
----- Toggle lines (linewise) with dot-repeat support
----- Example: <leader>gc3j will comment 4 lines
---vim.keymap.set(
---    'n', '<leader>gc', api.call('toggle.linewise', 'g@'),
---    { expr = true }
---)
---
----- Toggle lines (blockwise) with dot-repeat support
----- Example: <leader>gb3j will comment 4 lines
---vim.keymap.set(
---    'n', '<leader>gb', api.call('toggle.blockwise', 'g@'),
---    { expr = true }
---)
---
---local esc = vim.api.nvim_replace_termcodes(
---    '<ESC>', true, false, true
---)
---
----- Toggle selection (linewise)
---vim.keymap.set('x', '<leader>c', function()
---    vim.api.nvim_feedkeys(esc, 'nx', false)
---    api.toggle.linewise(vim.fn.visualmode())
---end)
---
----- Toggle selection (blockwise)
---vim.keymap.set('x', '<leader>b', function()
---    vim.api.nvim_feedkeys(esc, 'nx', false)
---    api.toggle.blockwise(vim.fn.visualmode())
---end)
---@usage ]]
meta.toggle = setmetatable({ cmode = utils.cmode.toggle }, core)

---@tag comment.api.comment.linewise
---@tag comment.api.comment.blockwise
---Provides API to (only) comment a region, on current-line, or with a
---count using line or block comment string.
---
---Every function takes a {motion} argument, except '*.count()' function which
---takes an {count} argument, and an optional {config} parameter.
---@type table A metatable containing API functions
---@see comment.opfunc.OpMotion
---@see comment.config
---@usage [[
---local api = require('Comment.api')
---local config = require('Comment.config'):get()
---
---api.comment.linewise(motion, config?)
---api.comment.linewise.current(motion?, config?)
---api.comment.linewise.count(count, config?)
---
---api.comment.blockwise(motion, config?)
---api.comment.blockwise.current(motion?, config?)
---api.comment.blockwise.count(count, config?)
---@usage ]]
meta.comment = setmetatable({ cmode = utils.cmode.comment }, core)

---@tag comment.api.uncomment.linewise
---@tag comment.api.uncomment.blockwise
---Provides API to (only) uncomment a region, on current-line, or with a
---count using line or block comment string.
---
---Every function takes a {motion} argument, except '*.count()' function which
---takes an {count} argument, and an optional {config} parameter.
---@type table A metatable containing API functions
---@see comment.opfunc.OpMotion
---@see comment.config
---@usage [[
---local api = require('Comment.api')
---local config = require('Comment.config'):get()
---
---api.uncomment.linewise(motion, config?)
---api.uncomment.linewise.current(motion?, config?)
---api.uncomment.linewise.count(count, config?)
---
---api.uncomment.blockwise(motion, config?)
---api.uncomment.blockwise.current(motion?, config?)
---api.uncomment.blockwise.count(count, config?)
---@usage ]]
meta.uncomment = setmetatable({ cmode = utils.cmode.uncomment }, core)

---Provides API to to insert comment on previous, next or at the end-of-line.
---Every function takes an optional {config} parameter.
---@type table A metatable containing API functions
---@see comment.config
---@usage [[
---local api = require('Comment.api')
---local config = require('Comment.config'):get()
---
---api.insert.linewise.above(config?)
---api.insert.linewise.below(config?)
---api.insert.linewise.eol(config?)
---
---api.insert.blockwise.above(config?)
---api.insert.blockwise.below(config?)
---api.insert.blockwise.eol(config?)
---@usage ]]
meta.insert = setmetatable({}, {
	__index = function(_, comment_type)
		return {
			above = function(user_config)
				utils.catch(extra.insert_above, utils.ctype[comment_type], user_config or config_import:get())
			end,
			below = function(user_config)
				utils.catch(extra.insert_below, utils.ctype[comment_type], user_config or config_import:get())
			end,
			eol = function(user_config)
				utils.catch(extra.insert_eol, utils.ctype[comment_type], user_config or config_import:get())
			end,
		}
	end,
})

---Wraps the given API function with 'lockmarks' to preserve marks/jumps
---@param fn_name string Name of API function
---@return fun(motion:OpMotion) #Callback function
---@see lockmarks
---@see comment.opfunc.OpMotion
---@usage [[
---local api = require('Comment.api')
---
---vim.keymap.set(
---    'n', '<leader>c', api.locked('toggle.linewise.current')
---)
---
---local esc = vim.api.nvim_replace_termcodes(
---    '<ESC>', true, false, true
---)
---vim.keymap.set('x', '<leader>c', function()
---    vim.api.nvim_feedkeys(esc, 'nx', false)
---    api.locked('toggle.linewise')(vim.fn.visualmode())
---end)
---
----- NOTE: `locked` method is just a wrapper around `lockmarks`
---vim.api.nvim_command([[
---    lockmarks lua require('Comment.api').toggle.linewise.current()
---]])
---@usage ]]
function meta.locked(fn_name)
	return function(motion)
		return vim.api.nvim_command(
			('lockmarks lua require("Comment.api").%s(%s)'):format(fn_name, motion and ("%q"):format(motion))
		)
	end
end

---Callback function which does the following
---  1. Sets 'operatorfunc' for dot-repeat
---  2. Preserves jumps and marks
---  3. Stores last cursor position
---@param fn_name string Name of the API function to call
---@param op_mode '"g@"'|'"g@$"' Operator-mode expression
---@return fun():string #Keymap RHS callback
---@see g@
---@see operatorfunc
---@usage [[
---local api = require('Comment.api')
---vim.keymap.set(
---    'n', 'gc', api.call('toggle.linewise', 'g@'),
---    { expr = true }
---)
---vim.keymap.set(
---    'n', 'gcc', api.call('toggle.linewise.current', 'g@$'),
---    { expr = true }
---)
---@usage ]]
function meta.call(fn_name, op_mode)
	return function()
		vim.o.operatorfunc = ("v:lua.require'Comment.api'.locked'%s'"):format(fn_name)
		config_import.position = config_import:get().sticky and vim.api.nvim_win_get_cursor(0) or nil
		return op_mode
	end
end

return meta
