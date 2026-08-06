---@mod comment.ft Language/Filetype detection
---@brief [[
---This module is the core of filetype and commentstring detection and uses the
---|lua-treesitter| APIs to accurately detect filetype and gives the corresponding
---commentstring, stored inside the plugin, for the filetype/langauge.
---
---Compound (dot-separated) filetypes are also supported i.e. 'ansible.yaml',
---'ios.swift' etc. The commentstring resolution will be done from left to right.
---For example, If the filetype is 'ansible.yaml' then 'ansible' commenstring will
---be used if found otherwise it'll fallback to 'yaml'. Read `:h 'filetype'`
---@brief ]]

local config = require("Comment.config")

---Common commentstring shared b/w multiple languages
local cstr = {
	cxx_l = "//%s",
	cxx_b = "/*%s*/",
	dbl_hash = "##%s",
	dash = "--%s",
	dash_bracket = "--[[%s]]",
	handlebars = "{{!--%s--}}",
	hash = "#%s",
	hash_bracket = "#[[%s]]",
	haskell_b = "{-%s-}",
	fsharp_b = "(*%s*)",
	html = "<!--%s-->",
	latex = "%%s",
	semicolon = ";%s",
	lisp_l = ";;%s",
	lisp_b = "#|%s|#",
	twig = "{#%s#}",
	vim = '"%s',
	lean_b = "/-%s-/",
	ruby_block = "=begin%s=end",
}

---Lang table that contains commentstring (linewise/blockwise) for multiple filetypes
---Structure = { filetype = { linewise, blockwise } }
---@type table<string,string[]>
local lang_cstr_table = setmetatable({
	applescript = { cstr.hash },
	arduino = { cstr.cxx_l, cstr.cxx_b },
	asm = { cstr.hash },
	astro = { cstr.html },
	autohotkey = { cstr.semicolon, cstr.cxx_b },
	bash = { cstr.hash },
	beancount = { cstr.semicolon },
	bib = { cstr.latex },
	blueprint = { cstr.cxx_l }, -- Blueprint doesn't have block comments
	c = { cstr.cxx_l, cstr.cxx_b },
	cabal = { cstr.dash },
	cairo = { cstr.cxx_l },
	cmake = { cstr.hash, cstr.hash_bracket },
	conf = { cstr.hash },
	conkyrc = { cstr.dash, cstr.dash_bracket },
	coq = { cstr.fsharp_b, cstr.fsharp_b },
	cpp = { cstr.cxx_l, cstr.cxx_b },
	cs = { cstr.cxx_l, cstr.cxx_b },
	css = { cstr.cxx_b, cstr.cxx_b },
	cuda = { cstr.cxx_l, cstr.cxx_b },
	cue = { cstr.cxx_l },
	dart = { cstr.cxx_l, cstr.cxx_b },
	dhall = { cstr.dash, cstr.haskell_b },
	dnsmasq = { cstr.hash },
	dosbatch = { "REM%s" },
	dot = { cstr.cxx_l, cstr.cxx_b },
	dts = { cstr.cxx_l, cstr.cxx_b },
	editorconfig = { cstr.hash },
	eelixir = { cstr.html, cstr.html },
	elixir = { cstr.hash },
	elm = { cstr.dash, cstr.haskell_b },
	elvish = { cstr.hash },
	faust = { cstr.cxx_l, cstr.cxx_b },
	fennel = { cstr.semicolon },
	fish = { cstr.hash },
	fsharp = { cstr.cxx_l, cstr.fsharp_b },
	func = { cstr.lisp_l },
	gdb = { cstr.hash },
	gdscript = { cstr.hash },
	gdshader = { cstr.cxx_l, cstr.cxx_b },
	gitignore = { cstr.hash },
	gleam = { cstr.cxx_l },
	glsl = { cstr.cxx_l, cstr.cxx_b },
	gnuplot = { cstr.hash, cstr.hash_bracket },
	go = { cstr.cxx_l, cstr.cxx_b },
	gomod = { cstr.cxx_l },
	graphql = { cstr.hash },
	groovy = { cstr.cxx_l, cstr.cxx_b },
	handlebars = { cstr.handlebars, cstr.handlebars },
	haskell = { cstr.dash, cstr.haskell_b },
	haxe = { cstr.cxx_l, cstr.cxx_b },
	hcl = { cstr.hash, cstr.cxx_b },
	heex = { cstr.html, cstr.html },
	html = { cstr.html, cstr.html },
	htmldjango = { cstr.html, cstr.html },
	hyprlang = { cstr.hash },
	idris = { cstr.dash, cstr.haskell_b },
	idris2 = { cstr.dash, cstr.haskell_b },
	ini = { cstr.hash },
	jai = { cstr.cxx_l, cstr.cxx_b },
	java = { cstr.cxx_l, cstr.cxx_b },
	javascript = { cstr.cxx_l, cstr.cxx_b },
	javascriptreact = { cstr.cxx_l, cstr.cxx_b },
	jq = { cstr.hash },
	jsonc = { cstr.cxx_l },
	jsonnet = { cstr.cxx_l, cstr.cxx_b },
	julia = { cstr.hash, "#=%s=#" },
	kdl = { cstr.cxx_l, cstr.cxx_b },
	kotlin = { cstr.cxx_l, cstr.cxx_b },
	lean = { cstr.dash, cstr.lean_b },
	lean3 = { cstr.dash, cstr.lean_b },
	lidris = { cstr.dash, cstr.haskell_b },
	lilypond = { cstr.latex, "%{%s%}" },
	lisp = { cstr.lisp_l, cstr.lisp_b },
	lua = { cstr.dash, cstr.dash_bracket },
	luau = { cstr.dash, cstr.dash_bracket },
	make = { cstr.hash },
	markdown = { cstr.html, cstr.html },
	mbsyncrc = { cstr.dbl_hash },
	mermaid = { "%%%s" },
	meson = { cstr.hash },
	metalua = { cstr.dash, cstr.dash_bracket },
	mojo = { cstr.hash },
	nextflow = { cstr.cxx_l, cstr.cxx_b },
	nim = { cstr.hash, "#[%s]#" },
	nix = { cstr.hash, cstr.cxx_b },
	nu = { cstr.hash },
	objc = { cstr.cxx_l, cstr.cxx_b },
	objcpp = { cstr.cxx_l, cstr.cxx_b },
	ocaml = { cstr.fsharp_b, cstr.fsharp_b },
	odin = { cstr.cxx_l, cstr.cxx_b },
	openscad = { cstr.cxx_l, cstr.cxx_b },
	php = { cstr.cxx_l, cstr.cxx_b },
	plantuml = { "'%s", "/'%s'/" },
	prisma = { cstr.cxx_l },
	proto = { cstr.cxx_l, cstr.cxx_b },
	puppet = { cstr.hash },
	purescript = { cstr.dash, cstr.haskell_b },
	python = { cstr.hash }, -- Python doesn't have block comments
	quarto = { cstr.html, cstr.html },
	r = { cstr.hash }, -- R doesn't have block comments
	racket = { cstr.lisp_l, cstr.lisp_b },
	rasi = { cstr.cxx_l, cstr.cxx_b },
	readline = { cstr.hash },
	reason = { cstr.cxx_l, cstr.cxx_b },
	rego = { cstr.hash },
	remind = { cstr.hash },
	rescript = { cstr.cxx_l, cstr.cxx_b },
	robot = { cstr.hash }, -- Robotframework doesn't have block comments
	ron = { cstr.cxx_l, cstr.cxx_b },
	ruby = { cstr.hash, cstr.ruby_block },
	rust = { cstr.cxx_l, cstr.cxx_b },
	sbt = { cstr.cxx_l, cstr.cxx_b },
	scala = { cstr.cxx_l, cstr.cxx_b },
	scheme = { cstr.lisp_l, cstr.lisp_b },
	scss = { cstr.cxx_b, cstr.cxx_b },
	sh = { cstr.hash },
	solidity = { cstr.cxx_l, cstr.cxx_b },
	sql = { cstr.dash, cstr.cxx_b },
	stata = { cstr.cxx_l, cstr.cxx_b },
	supercollider = { cstr.cxx_l, cstr.cxx_b },
	svelte = { cstr.html, cstr.html },
	swayconfig = { cstr.hash },
	swift = { cstr.cxx_l, cstr.cxx_b },
	sxhkdrc = { cstr.hash },
	systemd = { cstr.hash },
	systemverilog = { cstr.cxx_l, cstr.cxx_b },
	tablegen = { cstr.cxx_l, cstr.cxx_b },
	teal = { cstr.dash, cstr.dash_bracket },
	template = { cstr.dbl_hash },
	terraform = { cstr.hash, cstr.cxx_b },
	tex = { cstr.latex },
	tidal = { cstr.dash, cstr.haskell_b },
	tmux = { cstr.hash },
	toml = { cstr.hash },
	twig = { cstr.twig, cstr.twig },
	typescript = { cstr.cxx_l, cstr.cxx_b },
	typescriptreact = { cstr.cxx_l, cstr.cxx_b },
	typst = { cstr.cxx_l, cstr.cxx_b },
	v = { cstr.cxx_l, cstr.cxx_b },
	vala = { cstr.cxx_l, cstr.cxx_b },
	verilog = { cstr.cxx_l },
	vhdl = { cstr.dash },
	vifm = { cstr.vim },
	vim = { cstr.vim },
	vue = { cstr.html, cstr.html },
	wgsl = { cstr.cxx_l, cstr.cxx_b },
	xdefaults = { "!%s" },
	xml = { cstr.html, cstr.html },
	xonsh = { cstr.hash }, -- Xonsh doesn't have block comments
	yaml = { cstr.hash },
	yuck = { cstr.lisp_l },
	zig = { cstr.cxx_l }, -- Zig doesn't have block comments
}, {
	-- Support for compound filetype i.e. 'ios.swift', 'ansible.yaml' etc.
	__index = function(this, key)
		local base, fallback = string.match(key, "^(.-)%.(.*)")
		if not (base or fallback) then
			return nil
		end
		return this[base] or this[fallback]
	end,
})

local meta = {}

---Sets a commentstring(s) for a filetype/language
---@param lang string Filetype/Language of the buffer
---@param val string|string[]
---@return table self Returns itself
---@usage [[
---local ft = require('Comment.ft')
---
-----1. Using method signature
----- Set only line comment or both
----- You can also chain the set calls
---ft.set('yaml', '#%s').set('javascript', {'//%s', '/*%s*/'})
---
----- 2. Metatable magic
---ft.javascript = {'//%s', '/*%s*/'}
---ft.yaml = '#%s'
---
----- 3. Multiple filetypes
---ft({'go', 'rust'}, {'//%s', '/*%s*/'})
---ft({'toml', 'graphql'}, '#%s')
---@usage ]]
function meta.set(lang, val)
	lang_cstr_table[lang] = type(val) == "string" and { val } or val --[[ @as string[] ]]
	return meta
end

---Get line/block/both commentstring(s) for a given filetype
---@param lang string Filetype/Language of the buffer
---@param type? integer See |comment.utils.ctype|. If given `nil`, it'll
---return a copy of { line, block } commentstring.
---@return nil|string|string[] #Returns stored commentstring
---@usage [[
---local ft = require('Comment.ft')
---local U = require('Comment.utils')
---
----- 1. Primary filetype
---ft.get('rust', U.ctype.linewise) -- `//%s`
---ft.get('rust') -- `{ '//%s', '/*%s*/' }`
---
----- 2. Compound filetype
----- NOTE: This will return `yaml` commenstring(s),
-----       as `ansible` commentstring is not found.
---ft.get('ansible.yaml', U.ctype.linewise) -- `#%s`
---ft.get('ansible.yaml') -- { '#%s' }
---@usage ]]
function meta.get(lang, type)
	local tuple = lang_cstr_table[lang]
	if not tuple then
		return nil
	end
	if not type then
		return vim.deepcopy(tuple)
	end
	return tuple[type]
end

---Get a language tree for a given range by walking the parse tree recursively.
---This uses 'lua-treesitter' API under the hood. This can be used to calculate
---language of a particular region which embedded multiple filetypes like html,
---vue, markdown etc.
---
---NOTE: This ignores `tree-sitter-comment` parser, if installed.
---@param tree vim.treesitter.LanguageTree Parse tree to be walked
---@param range integer[] Range to check
---{start_row, start_col, end_row, end_col}
---@return vim.treesitter.LanguageTree #Returns a |treesitter-languagetree|
---@see treesitter-languagetree
---@see lua-treesitter-core
---@usage [[
---local ok, parser = pcall(vim.treesitter.get_parser, 0)
---assert(ok, "No parser found!")
---local tree = require('Comment.ft').contains(parser, {0, 0, -1, 0})
---print('Lang:', tree:lang())
---@usage ]]
function meta.contains(tree, range)
	for lang, child in pairs(tree:children()) do
		if lang ~= "comment" and child:contains(range) then
			return meta.contains(child, range)
		end
	end

	return tree
end

---Calculate commentstring with the power of treesitter
---@param comment_params CommentCtx
---@return nil|string #Commentstring
---@see comment.utils.CommentCtx
function meta.calculate(comment_params)
	local _, parser = pcall(vim.treesitter.get_parser, vim.api.nvim_get_current_buf())

	if not parser then
		local filetype_comment = meta.get(vim.bo.filetype, comment_params.ctype) --[[ @as string ]]

		if not filetype_comment and config:get().optimistic_comments then
			return config:get().optimistic_comments_syntax --[[ @as string ]]
		end
		return filetype_comment
	end

	local lang = meta.contains(parser, {
		comment_params.range.srow - 1,
		comment_params.range.scol,
		comment_params.range.erow - 1,
		comment_params.range.ecol,
	}):lang()

	return meta.get(lang, comment_params.ctype) or meta.get(vim.bo.filetype, comment_params.ctype) --[[ @as string ]]
end

---@export meta
return setmetatable(meta, {
	__newindex = function(this, key, value)
		this.set(key, value)
	end,
	__call = function(this, langs, spec)
		for _, lang in ipairs(langs) do
			this.set(lang, spec)
		end
		return this
	end,
})
