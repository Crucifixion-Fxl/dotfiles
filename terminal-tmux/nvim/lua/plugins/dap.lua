return {
	-- Debugging base (<leader>d keymaps, DAP UI) comes from the
	-- lazyvim.plugins.extras.dap.core import in config/lazy.lua.
	-- Language wiring: C/C++ reuse the codelldb binary that the Rust extra
	-- installs via Mason, Python uses debugpy, Go uses its dedicated delve.
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			{
				"mfussenegger/nvim-dap-python",
				config = function()
					require("dap-python").setup("debugpy-adapter")
				end,
			},
			{
				"leoluz/nvim-dap-go",
				opts = {},
			},
		},
		opts = function()
			local dap = require("dap")

			-- Mirrors rustaceanvim's get_codelldb_adapter wiring from the
			-- lang.rust extra; mason-nvim-dap usually registers this too, the
			-- guard just makes it work when that handler has not run yet.
			if not dap.adapters.codelldb then
				local codelldb = vim.fn.exepath("codelldb")
				if codelldb ~= "" then
					local lib_ext = vim.uv.os_uname().sysname == "Linux" and ".so" or ".dylib"
					local liblldb = vim.fn.stdpath("data") .. "/mason/opt/lldb/lib/liblldb" .. lib_ext
					dap.adapters.codelldb = {
						type = "server",
						port = "${port}",
						host = "127.0.0.1",
						executable = {
							command = codelldb,
							args = { "--liblldb", liblldb, "--port", "${port}" },
						},
					}
				end
			end

			dap.configurations.c = {
				{
					name = "Launch executable",
					type = "codelldb",
					request = "launch",
					program = function()
						return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file")
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = false,
				},
			}
			dap.configurations.cpp = dap.configurations.c
		end,
	},

	-- nvim-dap-python owns the python adapter; keep mason-nvim-dap from
	-- replacing it (same guard lazyvim's lang.python extra uses).
	-- automatic_installation stays off: every debug package is declared in
	-- ensure_installed above, and auto-install also tries packages that no
	-- longer exist in the registry (chrome-debug-adapter) on every startup.
	{
		"jay-babu/mason-nvim-dap.nvim",
		opts = {
			automatic_installation = false,
			handlers = { python = function() end },
		},
	},

	{
		"mason-org/mason.nvim",
		opts = function(_, opts)
			vim.list_extend(opts.ensure_installed, { "debugpy", "delve" })
		end,
	},
}
