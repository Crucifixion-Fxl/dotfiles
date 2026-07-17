-- Keep zoxide history in sync with directory changes made inside Yazi,
-- including jumps performed by the built-in fzf plugin (`z`).
require("zoxide"):setup {
	update_db = true,
}
