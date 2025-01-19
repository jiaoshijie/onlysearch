local highlights = {
  OnlysearchHeaderSearch  = { default = true, link = "Title" },
  OnlysearchHeaderPaths   = { default = true, link = "Title" },
  OnlysearchHeaderFlags   = { default = true, link = "Title" },
  OnlysearchHeaderFilters = { default = true, link = "Title" },
  OnlysearchFilename      = { default = true, link = "Underlined" },
  OnlysearchMatchLNum     = { default = true, link = "CursorLineNr" },
  OnlysearchMatchCtx      = { default = true, link = "Search" },
  OnlysearchError         = { default = true, link = "Error" },
  OnlysearchSep           = { default = true, link = "Ignore" },
  OnlysearchSepErr        = { default = true, link = "ErrorMsg" },
  OnlysearchSelectedLine  = { default = true, link = "Visual" },
}

for k, v in pairs(highlights) do
  vim.api.nvim_set_hl(0, k, v)
end
