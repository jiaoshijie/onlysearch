local command = vim.api.nvim_create_user_command

command("Os", require("onlysearch").hello, { nargs = 0 })
