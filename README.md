# OnlySearch

A nvim plugin that provides a beautiful search result views and powerful functionality(using ripgrep).

**WARNING**: This plugin doesn't provide replace functionality!

## TODOs

- [x] support search tool `ripgrep` and `grep`, maybe `gg`
- [x] support file filter
- [x] add `flags` to search tool
- [x] only make search when leaving insert mode
- [x] result protect methods
  + [x] `p` and `P` not handled
- [x] handle long line
- [x] fold support
- [x] Quickfix list
  + [x] support selecting item
    * [x] select a file
    * [x] select one match line
    * [x] support visual mode
    * [x] number-operator select
  + [x] support add all result to quickfix
  + [x] support append a selected result line to quickfix
  + [x] only make replace operation using quickfix replace operation like `cdo`
  + [x] auto open the quickfix list
  + [x] add a titile in statusline for quickfix list
- [x] frequently used tool flag completion
- [x] clear and select all item
- [x] refactor/redesign finder config
- [x] history(resume last one)
- [x] user config keymaps
- [x] add default highlight group
- [x] add user friendly documentation
  + [x] not finished
- [x] complete has a bug, when `--` entered, it also try to complete `-w`, etc.
- [ ] write own async functionality
- [ ] When open file to a window, check whether this window has `winfixbuf` set

## NeoVim Bug

- [ ] BUG: nvim_buf_set_extmark() api bug
  + if i set an extmark above the first real line, sometimes this extmark doesn't show up
- [ ] BUG: nvim_buf_clear_namespace api bug fix
  + [ ] I don't know if this is a bug or not
  + This bug is that when nvim add a highlight to a line with col_start = 0
  + and col_end = -1, as few cases the line column will be MAX_COL(the largest int32_t number),
  + nvim will using {lnum, col_start = 0} and {lnum + 1, col_end = 0} to highlight the whole line of lnum

### License

**MIT**
