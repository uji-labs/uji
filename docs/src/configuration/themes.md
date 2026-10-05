# Themes

uji starts out in `default`, and `uji.ui.configure` switches to another one
by name.

```lua
uji.ui.configure({ theme = "harbor" })
```

A name loads `lua/uji/themes/<name>.lua` from your config directory or from a
[pack](packs.md), and that file returns the theme. You can also pass the theme
itself.

## Building a theme

`require("uji.themes.default")` is a function that takes the parts you change
and returns a whole theme. Everything you leave out keeps its default.

```lua
local ito = require("ito")

return require("uji.themes.default")({
  name = "harbor",
  colors = {
    text = ito.rgb(0xc0caf5),
    muted = ito.rgb(0x565f89),
    accent = ito.rgb(0x7aa2f7),
    user_bg = ito.rgb(0x24283b),
  },
  styles = function(colors)
    return {
      user = ito.TextStyle({ foreground = colors.text, background = colors.user_bg, italic = true }),
    }
  end,
  symbols = { pointer = "▸" },
})
```

Changing a colour also changes every default style drawn in it, so a new
`accent` recolours the headings, the chosen items and the rest. `styles` is a
table of the styles you change, or a function that takes the theme's colours
and returns that table.

A theme that builds on another one reads its values:

```lua
local ito = require("ito")
local harbor = require("uji.themes.harbor")

return require("uji.themes.default")({
  name = "harbor_warm",
  colors = {
    text = harbor.colors.text,
    muted = harbor.colors.muted,
    accent = ito.rgb(0xff9e64),
  },
})
```

## The theme table

| Key | Meaning |
|---|---|
| `name` | The theme's name. Error messages use it. |
| `colors` | Named [colours](#colours). |
| `styles` | Named [text styles](#styles). |
| `symbols` | The symbols uji draws. See [Symbols, words and sizes](#symbols-words-and-sizes). |
| `borders` | The characters of each kind of box. See [Borders](#borders). |
| `text` | The words uji draws. |
| `limits` | Sizes and timings. |
| `options` | Anything the theme wants to keep for itself. |
| `templates` | How each part is drawn. See [The screen](#the-screen) and [Templates](#templates). |

Build a theme with `uji.themes.default`, which fills in everything you leave
out. `colors` and `styles` can also hold names of your own, for your own
templates.

## Colours

A colour is an `ito.Color` value, made in one of three ways:

- `ito.rgb(0xd4d4d4)` gives a colour from its red, green and blue parts.
- `ito.Color.indexed(245)` gives one of the terminal's 256 colours, numbered
  from `0` to `255`.
- `ito.Color.cyan` is one of the terminal's named colours. The names are
  `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`,
  `gray`, `dark_gray`, `light_red`, `light_green`, `light_yellow`,
  `light_blue`, `light_magenta` and `light_cyan`.

The default theme has these colours.

| Colour | Default |
|---|---|
| `text` | `ito.rgb(0xd4d4d4)` |
| `muted` | `ito.rgb(0x808080)` |
| `code` | `ito.rgb(0xe0af68)` |
| `accent` | `ito.Color.cyan` |
| `user_bg` | `ito.rgb(0x343541)` |
| `selected_bg` | `ito.rgb(0x3a3a4a)` |
| `cursor` | `ito.Color.white` |
| `error` | `ito.Color.red` |
| `notice` | `ito.Color.red` |

## Styles

A style is an `ito.TextStyle` value. It takes a table with `foreground`,
`background` and any of the flags `bold`, `dim`, `italic`, `underline`,
`reverse`, `strikethrough` and `blink`. The colours are `ito.Color` values,
and every field can be left out.

```lua
local ito = require("ito")

local note = ito.TextStyle({ foreground = ito.Color.yellow, italic = true })
```

`style:merge(other)` gives a style with the colours and flags of `other` on
top of those of `style`.

The default theme has these styles.

| Style | Used for | Default |
|---|---|---|
| `plain` | Text with the terminal's own style. | no style |
| `text` | Body text. | `text` |
| `bold` | Titles and tool calls. | `text`, bold |
| `muted` | Secondary text. | `muted` |
| `dim` | Hints and counts. | `muted`, dim |
| `faint` | The model's thinking. | `muted`, italic, dim |
| `system` | System messages. | `muted`, italic |
| `code` | Code and maths. | `code` |
| `accent` | Large headings and the chosen item. | `accent`, bold |
| `highlight` | Keywords in code and keys in hints. | `accent` |
| `user` | Your messages. | `text` on `user_bg` |
| `selected` | The background of a chosen row. | on `selected_bg` |
| `chosen` | A chosen row in a picker. | `text` on `selected_bg` |
| `chosen_name` | The name on a chosen suggestion. | `accent` on `selected_bg` |
| `chosen_desc` | The description on a chosen suggestion. | `muted` on `selected_bg` |
| `error` | Errors and failed tool output. | `error` |
| `notice` | Notices. | `notice` |
| `cursor` | The cursor. | `cursor`, blink |
| `input` | Text on the input line. | `text` |
| `border` | Borders. | `muted` |
| `reverse` | Selected text and the copy message. | reverse |
| `confirm_title` | The approval question's title. | `text`, bold |
| `confirm_body` | The approval question's details. | `text` |
| `confirm_selected` | The chosen answer. | `accent`, bold |
| `confirm_unselected` | The other answer. | `muted` |
| `heading1` to `heading6` | Markdown headings of each level. | `accent`, bold for 1 and 2, `text`, bold for the rest |
| `strong`, `emphasis`, `strikethrough`, `link` | Markdown bold, italic, struck and linked text, merged on top of the text around it. | bold, italic, strikethrough, underline |
| `table_head` | The header row of a table, merged on top of each cell. | bold |
| `code_keyword`, `code_string`, `code_number`, `code_comment` | Highlighted code. | `accent`, `code`, `code`, `muted` italic dim |
| `selection` | Text you select with the mouse. | reverse |

## Symbols, words and sizes

| Key | Meaning | Default |
|---|---|---|
| `symbols.spinner` | The frames of the waiting animation. | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` |
| `symbols.tool` | The mark before a tool call. | `•` |
| `symbols.branch` | The mark before a tool's output. | `└` |
| `symbols.more` | The mark before the count of hidden output lines. | `…` |
| `symbols.shell` | The mark before a command you ran. | `!` |
| `symbols.rule` | The line drawn where the session was compacted. | `─` |
| `symbols.notice` | The mark before a notice. | `!` |
| `symbols.thinking` | The bar beside the model's thinking. | `│` |
| `symbols.queued` | The mark before a queued message. | `›` |
| `symbols.running` | The mark before the tool that is running. | `⋯` |
| `symbols.jump` | The arrow on the jump to the bottom. | `↓` |
| `symbols.bullets` | The bullets of each list level, used in turn. | `• ◦ ▪` |
| `symbols.quote` | The bar beside a quote. | `│` |
| `symbols.column` | The line between table columns. | `│` |
| `symbols.task_done`, `symbols.task_open` | The marks of a done and an open task. | `[x]`, `[ ]` |
| `symbols.cursor` | The cursor in the input line and in pickers. | `█` |
| `symbols.mask` | What hidden input, such as a key, shows instead of each character. | `•` |
| `symbols.pointer` | The mark beside the chosen item in a list or an approval. | `›` |
| `symbols.prompt` | The mark before what you type in a picker or prompt. | `>` |
| `text.confirm_yes` | The word that allows a tool call. | `"Yes"` |
| `text.confirm_no` | The word that refuses it. | `"No"` |
| `text.called` | The word before a tool call that has no verb of its own. | `"Called"` |
| `text.exit` | The word before a command's exit status. | `"exit"` |
| `text.compacted` | The label where the session was compacted. | `"compacted"` |
| `text.hidden` | The count of hidden output lines. `%d` is the count. | `"+%d lines"` |
| `text.jump` | The label that takes you back to the bottom. | `"Jump to bottom"` |
| `text.ordered` | The number of an ordered list item. `%d` is the number. | `"%d."` |
| `text.current` | The label beside the item in use, such as the current model. | `"(current)"` |
| `text.range` | The count under a long list. The numbers are the first and last shown and the total. | `"%d–%d of %d"` |
| `text.confirm_allow`, `text.confirm_deny` | The rest of each approval answer, after `confirm_yes` and `confirm_no`. | `"proceed"`, `"and tell uji what to do differently"` |
| `text.scroll` | The line an approval shows when its details do not fit. | `"lines %d-%d of %d, scroll for more"` |
| `text.working` | The line shown while the model works. `%d` is the seconds so far. | `"Working (%ds)"` |
| `text.copied`, `text.copied_terminal` | The message after you copy a selection. `%d` is the line count. | `"copied %d line(s)"`, `"copied %d line(s) via the terminal"` |
| `text.pasted_lines`, `text.pasted_chars` | The placeholder for a long paste in the input line. The numbers are the paste's number and its size. | `"[paste #%d +%d lines]"`, `"[paste #%d %d chars]"` |
| `text.image` | The placeholder for an attached image. | `"[image #%d]"` |
| `text.sessions_title` | The title of `uji list`. `%s` is the directory. | `"Sessions in %s"` |
| `text.sessions_empty` | What `uji list` says when there is nothing to show. | `"No sessions in current directory"` |
| `text.column_title`, `text.column_updated`, `text.column_id` | The column heads of `uji list`. | `"TITLE"`, `"UPDATED"`, `"ID"` |
| `text.key_move`, `text.key_open`, `text.key_quit` | The keys in the hint under `uji list`. | `"↑/↓"`, `"enter"`, `"esc"` |
| `text.navigate`, `text.resume`, `text.quit` | What those keys do. | `"navigate"`, `"resume"`, `"quit"` |
| `limits.spinner_interval` | Seconds between spinner frames. | `0.08` |
| `limits.suggest_rows` | Rows the command suggestions may use. | `5` |
| `limits.tool_preview` | Rows of tool output shown before you open it. | `8` |
| `limits.argument_preview` | Characters of a tool call's arguments shown when it has no verb. | `200` |
| `limits.message_gap` | Blank rows between messages. | `1` |
| `limits.section_gap` | Blank rows before the notices, the queue and the running tool. | `1` |
| `limits.bottom_gap` | Rows kept free under the transcript, where the jump shows. | `1` |
| `limits.indent` | Columns each list or quote level is indented by. | `2` |
| `limits.rule_width` | The longest a markdown rule is drawn. | `60` |
| `limits.block_gap` | Blank rows between markdown blocks. | `1` |
| `limits.reply_margin` | Columns to the left of a reply. | `1` |
| `limits.input_rows` | The most rows the input line grows to. | `10` |
| `limits.select_rows` | The most items a list shows at once. | `12` |
| `limits.suggest_name` | The width of a command's name in the suggestions. | `12` |
| `limits.preview_min` | The width a picker needs on each side before it shows a preview. | `24` |
| `limits.sessions_updated`, `limits.sessions_id` | The widths of the UPDATED and ID columns of `uji list`. | `14`, `36` |
| `limits.float_width`, `limits.float_height` | The share of the screen, in percent, that a floating picker or overlay takes. | `90`, `80` |
| `limits.flash` | Seconds the copy message stays up. | `1` |
| `limits.paste_lines`, `limits.paste_chars` | The size a paste can be before the input line shows a placeholder for it. | `1`, `80` |

A key uji does not know is an error, so a misspelled one does not go unnoticed.

## Borders

`borders.plain` and `borders.rounded` give the characters a box of that kind
is drawn with. A horizontal border uses the plain border's `horizontal`.

```lua
borders = {
  rounded = {
    top_left = "╭",
    top_right = "╮",
    bottom_left = "╰",
    bottom_right = "╯",
    horizontal = "─",
    vertical = "│",
  },
}
```

The default plain border is `┌ ┐ └ ┘ ─ │`, and the rounded one is
`╭ ╮ ╰ ╯ ─ │`, in the same order as above.

## The screen

`templates.screen(ctx, screen)` lays out the whole screen. uji calls it each
time it draws a frame, and it returns a view built with
[ito](../ito/index.md). `screen` holds uji's parts, and each call gives a
fresh view of that part:

| Call | What it shows |
|---|---|
| `screen.transcript()` | The messages. |
| `screen.composer()` | The input line, or the approval question, which takes the input line's place while it is open. |
| `screen.modals()` | The lists to choose from, the prompts, the command suggestions and overlays opened with `float = false`. They take no room while none is open, and on a screen without this part they float in a box instead. |
| `screen.activity()` | The line shown while the model works, with no room while the model is idle. |

Plugins put their views in [toolbar sections](../ito/toolbars.md), and the
screen decides where each section sits with
`ito.ToolbarItems(ito.ToolbarPlacement.x)`. A section the screen leaves out is
not drawn. The theme never names a plugin, and no plugin names a part of the
screen.

This screen puts the input line in a rounded box at the top, the row of
keyboard items under it, and the bottom bar's items side by side:

```lua
local ito = require("ito")

return require("uji.themes.default")({
  templates = {
    screen = function(ctx, screen)
      local placement = ito.ToolbarPlacement
      return ito.VStack({
        screen.composer():border(ctx.borders.rounded),
        screen.modals(),
        ito.ToolbarItems(placement.keyboard, ito.HStack),
        screen.transcript():grow(),
        screen.activity(),
        ito.ToolbarItems(placement.bottom_bar, ito.HStack),
      })
    end,
  },
})
```

The default screen is this template:

```lua
screen = function(ctx, screen)
  local placement = ito.ToolbarPlacement
  return ito.VStack({
    ito.HStack({
      ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
      ito.Spacer(),
      ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
    }),
    screen.transcript():grow(),
    screen.activity():padding({ vertical = 1 }),
    screen.modals(),
    ito.ToolbarItems(placement.keyboard),
    screen.composer():border(ctx.borders.plain, { edges = ito.Edges.horizontal }),
    ito.ToolbarItems(placement.bottom_bar),
  })
end
```

A screen that raises an error is replaced by the default screen for that
frame, and uji shows the problem once as a notice, such as
`theme screen: align takes one of ito.Alignment`.

## Templates

Every part of the screen is drawn by a template in `templates`, and a theme
can replace any of them. A template is a function that takes `ctx` and the
data of what it draws. Unless the table below says it can return a
[view](../ito/views.md), it returns a list of lines. A line is a list of spans,
`{ text, style }` where the style is an `ito.TextStyle` such as
`ctx.styles.muted`, and can have an `on_click` function. A picker shown in
`screen.modals()` sits at the bottom of the room it has.

```lua
templates = {
  notice = function(ctx, notice)
    return { { { "note: ", ctx.styles.accent }, { notice.text, ctx.styles.text } } }
  end,
}
```

| Template | Data | What it draws |
|---|---|---|
| `user` | `text` | One of your messages. |
| `assistant` | `text`, `body`, `calls` | A reply. `body` is its markdown, already drawn, and `calls` are the tool calls in it. |
| `tool_header` | `name`, `arguments`, `verb`, `detail` | A tool call. `verb` and `detail` come from the tool and can be `nil`. |
| `tool_output` | `content`, `failed`, `expanded`, `toggle` | A tool's result. `toggle` opens or folds it when a line has it as `on_click`. |
| `shell` | `command`, `code`, `output`, `failed`, `expanded`, `toggle` | A command you ran with `!`. |
| `system`, `error`, `notice`, `queued`, `thinking` | `text` | A message or line of that kind. |
| `partial` | `text` | The last line of a reply that is still arriving. |
| `compaction` | none | The place where the session was compacted. |
| `running` | `name`, `line` | The tool that is running and the last line it printed. |
| `jump` | `follow` | The label that takes you back to the bottom. uji centres it in the bottom row of the transcript. |
| `heading` | `level`, `lines` | A markdown heading. `lines` are already wrapped and drawn in the heading's style. |
| `code_block` | `language`, `lines` | A fenced code block. `lines` holds lists of highlighted spans, and `language` can be `nil`. |
| `math_block` | `lines` | Display maths, already turned into text. |
| `table_row` | `cells`, `head` | One row of a table. `cells` holds one list of spans per cell, and `head` is true for the header row. |
| `rule` | none | A markdown rule. |
| `activity` | `frame`, `elapsed` | The line shown while the model works. `frame` is the spinner's current frame. |
| `flash` | `text` | The copy message in the top right corner. |
| `input` | `rows` | The input line. Each row has `before`, and the row with the cursor also has `after`, the text on each side of it. |
| `select` | `title`, `query`, `items`, `matches`, `selection`, `current`, `height` | A list to choose from, as lines or a view. `matches` are the indexes into `items` that fit the query, `selection` is a state that holds the chosen match, ready for [`ito.List`](../ito/controls.md#itolistitems-row), and `height` is the room there is. |
| `prompt` | `title`, `value` | A question with a text answer. |
| `suggest` | `items`, `selection`, `height` | The command suggestions, as lines or a view. Its items have `name` and `desc`, and `selection` holds the chosen one. |
| `confirm` | `title`, `body`, `allow`, `keys`, `scroll` | An approval, as `{ head = lines, body = lines, foot = lines }`. uji scrolls the body when it does not fit. `scroll` has `first`, `last` and `total` when it does not. |
| `pick` | `title`, `items`, `matches`, `selection`, `preview`, `query`, `total`, `height` | The picker with a preview, as a view that uji lays out in the room the picker has. |
| `sessions` | `directory`, `sessions`, `cursor`, `now`, `height` | The screen `uji list` shows, as a view of the whole screen. |

A template can call another one through `ctx.templates`, as the default
`assistant` does with `tool_header`. `ctx` holds the theme's `colors`,
`styles`, `symbols`, `borders`, `text`, `limits` and `options`, and
`ctx.width` is the room the template has. Asking `ctx.styles` for a name the
theme does not have raises an error, such as
`the theme has no style named heading7`. `ctx` also has these helpers.

| Helper | Returns |
|---|---|
| `ctx:wrap(text, opts)` | `text` wrapped into lines. `opts` has `style`, a `prefix` for every line, `fill` to pad each line to the full width, and `width`. |
| `ctx:chunks(text, width)` | The pieces of `text` wrapped to `width`, as strings. |
| `ctx:fold(text, opts)` | The rows of `text` wrapped to `opts.width`, at most `opts.limit` of them, and how many rows are left out. Without a limit it gives every row. |
| `ctx:element(name, data, width)` | The lines another template draws, falling back to the default one when it breaks. |
| `ctx:typed(field, styles)` | The spans of a text field with the cursor in it. `field` has `text`, `cursor` and `hidden`, and `styles` has `text` and `cursor`. |
| `ctx:clip(text, width)` | `text` cut to `width` columns. |
| `ctx:pad(text, width)` | `text` padded with spaces to `width` columns. |
| `ctx:measure(text)` | The number of columns `text` takes. |
| `ctx:first(text, count)` | The first `count` characters of `text`. |

A template that raises an error, or returns something other than a list, is
replaced by the default one for that part, and uji shows the problem once as a
notice, such as `theme queued: no queue today`. A template name uji does not
know is a mistake in the theme, unless it has a dot, as the names of
[plugin templates](../api/ui.md#ujiuitemplatename-default) do.

## A theme from a base16 palette

A base16 scheme gives sixteen colours, `base00` to `base0F`. Keep them in a
local table and pick the theme's colours from it:

```lua
local ito = require("ito")

local base = {
  base03 = ito.rgb(0x707880),
  base05 = ito.rgb(0xc5c8c6),
  base08 = ito.rgb(0xcc6666),
  base0A = ito.rgb(0xf0c674),
  base0D = ito.rgb(0x81a2be),
}

return require("uji.themes.default")({
  name = "dusk",
  colors = {
    text = base.base05,
    muted = base.base03,
    code = base.base0A,
    accent = base.base0D,
    error = base.base08,
    notice = base.base08,
  },
})
```

## Mistakes

A theme with a mistake raises an error that says where it is, such as
`theme.styles.user: must be an ito.TextStyle, not a table`, and the theme in
use stays on.
