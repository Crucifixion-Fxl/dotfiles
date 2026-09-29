return {
	-- nvim-treesitter's main-branch rewrite no longer auto-installs
	-- opts.ensure_installed and dropped the legacy `configs` module; LazyVim's
	-- default spec owns parser installation and highlight attach. Only extend
	-- the parser list here (lazy.nvim merges opts.ensure_installed via
	-- opts_extend) and never override `config`, or installs and highlight
	-- silently stop working. LazyVim's defaults already include lua, python,
	-- c, tsx, typescript, json, html, markdown, yaml, bash, ...
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"astro",
				"cmake",
				"cpp",
				"css",
				"fish",
				"gitignore",
				"go",
				"graphql",
				"http",
				"java",
				"php",
				"rust",
				"scss",
				"sql",
				"svelte",
			},
		},
		init = function()
			-- MDX files reuse markdown highlighting (from the upstream config).
			vim.filetype.add({
				extension = {
					mdx = "mdx",
				},
			})
			vim.treesitter.language.register("markdown", "mdx")
		end,
	},
}
