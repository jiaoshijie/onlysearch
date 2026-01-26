# OnlySearch

> [!CAUTION]
> This plugin does **NOT** provide replace functionality by itself.
>
> Only works on UNIX-like systems.

A simple Neovim plugin for searching across projects or files—search only, nothing more.

**Screenshot**

![onlysearch](https://i.imgur.com/XgFOxTw.png)

## Requirements

- nvim 0.11.0 or above
- [ripgrep](https://github.com/BurntSushi/ripgrep) or [gnu-grep](https://www.gnu.org/software/grep/)

## Features

1. VSCode-like search interface
2. Leverages the power of ripgrep or GNU grep
3. Sends all or selected search results to the quickfix list
4. Automatically searches when leaving insert mode
5. Maintains search history (manual, not automatic)
6. Minimal and lightweight (~1,500 LOC)
7. Supports completion for user-defined flags

## Non-Features

1. Replacement functionality

### How to Perform Replacements

1. Send the search results to the quickfix list.
2. Run `:cdo s/pattern/replace/gc` to replace each match with confirmation,
   or `:cdo s/pattern/replace/g` to replace without confirmation.

Using Neovim's built-in replacement commands allows you to leverage other features,
such as `undotree`, to safely undo or review changes. I like this approach.

Personally, replacements are not a frequent use case. I perform a lot of searches
but rarely need replacements, so Neovim's `quickfix` works fine.
If your workflow involves frequent replacements, this plugin may not be suitable for you.

## Download and Install

```sh
mkdir -p ~/.config/nvim/pack/github/start/
cd ~/.config/nvim/pack/github/start/
git clone https://github.com/jiaoshijie/onlysearch.git
```

Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'jiaoshijie/onlysearch'
```

## Usage

> [!NOTE]
> If you’re fine with the default settings, you don’t need to call the setup function.

### Configuration

Default settings are defined in [config.lua](./lua/onlysearch/config.lua).

Highlight groups are defined in [plugin/onlysearch.lua](./plugin/onlysearch.lua).

An example of how to configure this plugin can be found in [onlysearch.lua](https://github.com/jiaoshijie/nvim/blob/minimal/after/plugin/onlysearch.lua).

### Interface

> [!NOTE]
> This plugin restricts certain operations (e.g., `dd`, `p`), though not all.
>
> If the UI breaks accidentally, press `<C-M-r>` (default) to restore it.

> [!CAUTION]
> This plugin is designed for search only.
>
> While tools like `rg` support replacement via the `--replace` flag,
> using that with this plugin may result in undefined behavior.

Neovim's built-in `omnicompletion` is used to complete user-defined flags, as shown in the example above.
While on the **Flags** line, press `<C-x><C-o>` to trigger completion.

#### Default Keymaps

| Mappings     | Action                                     |
| :----:       | :----:                                     |
| `Enter`      | Open the matched item and jump to its line |
| `=`          | Toggle selection of the current item       |
| `<leader>=`  | Unselect all items                         |
| `Q`          | Send selected items to the quickfix list   |
| `S`          | Perform the search manually                |
| `<C-M-r>`    | Recover the UI if it breaks                |
| `<leader>qo` | Open the history window                    |
| `<leader>qa` | Add the current query to history           |
| `<leader>qc` | Close the history window                   |
| `<leader>qw` | Switch to the history window               |

##### History Window Keymaps

| Mappings | Action                                    |
| :----:   | :----:                                    |
| `dd`     | Delete the seleted item from history      |
| `q`      | Quit history window                       |
| `Enter`  | Apply the selected item                   |
| `p`      | Switch between history and preview window |

## Bug Reports

Bug reports are welcome.

## License

**MIT**
