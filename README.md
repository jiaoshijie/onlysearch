# OnlySearch

A nvim plugin that provides a beautiful search result views and powerful functionality(using ripgrep).

WARN: This plugin doesn't provide replace functionality!

- [ ] BUG: nvim_buf_set_extmark() api bug
- [ ] nvim_buf_clear_namespace api bug fix
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
- [ ] history(at least can resume last one)
- [ ] frequently used tool flag completion

### License

**MIT**
