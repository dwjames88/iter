# What Paper accepts, and how this kit is shaped by it

Researched on 2026-10-05 for placing the Iter design onto a Paper (paper.design) canvas. No Paper tool was called and the Paper app was not opened; everything below comes from Paper's public docs, its pricing page, the agent-plugins repository, the locally installed plugin, and the tool descriptions that Paper Desktop has cached on this Mac.

Each fact is marked **Confirmed** (read in a primary source, which is linked or named) or **Unconfirmed** (inferred; the first real session should test it).

## Sources

| Source | What it gave |
|---|---|
| [paper.design/docs](https://www.paper.design/docs) | Index of the doc pages |
| [paper.design/docs/mcp](https://www.paper.design/docs/mcp) | Setup (stdio via `paper mcp`; the older HTTP endpoint `127.0.0.1:29979` still works), troubleshooting. No tool list. |
| [paper.design/docs/paste/html](https://www.paper.design/docs/paste/html) | The HTML import rules (inline styles only, `layer-name`, no rich text, images) |
| [paper.design/docs/tokens](https://www.paper.design/docs/tokens) | Token types, no theme modes yet, agents can create tokens |
| [paper.design/docs/svg](https://www.paper.design/docs/svg) | SVG paste and editing |
| [paper.design/docs/support](https://www.paper.design/docs/support) | Shortcuts, troubleshooting, `get_basic_info` |
| [paper.design/pricing](https://paper.design/pricing) | MCP tool-call limits per plan |
| [github.com/paper-design/agent-plugins](https://github.com/paper-design/agent-plugins) and the local copy at `~/.claude/plugins/marketplaces/paper/` | Plugin packaging only: the plugin is a pointer to `~/.paper/bin/paper mcp`. No skills or agent instructions are shipped in it. |
| `~/.claude/plugins/cache/paper/paper-desktop/0.2.1/README.md` | Feature summary (read, write, tokens, design-to-code) |
| `~/.paper/bin/paper --help` | The CLI has one command, `mcp` (a stdio relay to Paper Desktop). Version 0.0.1. |
| Paper Desktop's V8 code cache, `~/Library/Application Support/Paper/Code Cache/js/` (read with `strings`, not run) | The full MCP tool list and their descriptions, including the agent guide for `write_html` quoted below. This is the editor build the app last loaded, so it is current for this Mac but can change with an update. |

## The server's own session instructions (Confirmed)

The Paper MCP server sends instructions to the agent when it connects. They reached this session without any tool call, and say:

- Load the full guide first: `get_guide({ topic: "paper-mcp-instructions" })`, once per session (one call).
- Call `get_basic_info` when starting on a file; `pageId` defaults to the page the owner is viewing, so pass it to build on another page without disturbing them.
- Call `get_font_family_info` before the first typographic styling in a session (one call per family: SF Pro, New York). Use px for font size and line height, em for letter spacing.
- Each `write_html` call should add roughly one visual group; prefer `duplicate_nodes` with `update_styles` and `set_text_content` when that is faster than rewriting HTML.
- Artboard height is a starting point: when content clips, set `height: "fit-content"` with `update_styles`.
- Repeated rows: fixed-width slots for icons and trailing actions (`flexShrink: 0`); gap alone does not align columns.
- Call `finish_working_on_nodes` when done; never show raw node IDs to the owner.

So every session carries a fixed overhead of about five calls (guide, basic info, two font lookups, finish) before any artboard is placed.

## The tools (Confirmed, from the cached editor build)

Read: `get_basic_info`, `get_selection`, `get_node_info`, `get_children`, `get_tree_summary`, `get_screenshot`, `get_jsx`, `get_computed_styles`, `get_fill_image`, `find_nodes`, `get_font_family_info`, `get_guide`, `get_tokens`, comment-thread tools.
Files and pages: `open_file`, `list_files` / `list_resources`, `create_file`, `rename_resource`, `create_page`, `rename_pages`.
Write: `create_artboard`, `write_html` (mode `insert-children` into a node, or `replace` a node), `set_text_content`, `rename_nodes`, `update_styles`, `duplicate_nodes`, `move_nodes`, `delete_nodes`, `create_tokens`, `set_tokens`, `finish_working_on_nodes` (must be called when done), `export`, `export_combined_pdf`.

Notable from the descriptions:
- Page-scoped tools take a `pageId`, so an agent can build on a page the owner is not looking at.
- `update_styles` and `write_html` "support design tokens as CSS variables"; styles that are inert in context are dropped and reported as `ignoredStyles`.
- `duplicate_nodes` returns a map of every cloned descendant ID, and `write_html` accepts `<x-paper-clone node-id="…">`, so repeated items can be cloned instead of rewritten.
- `create_tokens` takes `{type, name, value, description}` per entry, aliases with `var(--other)`, and asks for semantic colours first, then palette colours, and other types smallest first. `get_tokens` can return a `:root {}` stylesheet.
- `rename_nodes` truncates names over 50 characters.

## The HTML rules (Confirmed)

From Paper's agent guide for `write_html`, quoted:

> Always use inline styles (style="..") · Enforce consistency with design tokens as CSS variables if available · All Google Fonts and locally installed fonts are available in font-family · All CSS color formats are supported · Use flex as the primary layout mode. Flexbox, padding, and gap are the core layout tools · Absolute position is fully supported. Use it for decorative elements. Avoid covering the entire artboard with a single absolute element · **Do NOT use: margin, display: inline, display: grid, HTML tables.** Use padding and gap for spacing · display: block is acceptable for simple elements (text, decorative shapes) but not for layout containers · Assume border-box sizing everywhere · Do NOT use emojis as icons. Use SVG icons or images · Rich text isn't supported · Use the layer-name attribute to set names on elements in the Paper layer tree · Local images MUST use absolute paths in an img starting with paper-asset://

And from the HTML paste page: class names are dropped and selector styles ignored; a block whose children are only inline content becomes one Text node; inline elements become inline-block; `data-paper-locked` locks a layer and `hidden` hides it; inputs become frames with text children; images must be at a public URL (or, for agents, `paper-asset://`).

The guide also says to write incrementally ("each `write_html` call should create one visual item"). The live tool definitions (next section) make this a firm rule, so the kit splits every artboard into small fragments.

## Further confirmed by the lead session's live tool definitions (2026-10-05)

The coordinating session connected to Paper and read the official agent guide and tool schemas (this kit made no calls). Confirmed there:

- `write_html` inserts HTML as children of a target node, or replaces a node. The guide requires small pieces: "Each write_html call should add roughly ONE visual group — a header, a single list row, a button group, a card shell, or a footer. If you're writing more than ~15 lines of HTML in a single call, break it up." "Never batch an entire component." A screenshot review is expected after each section.
- Reuse is by cloning, not components: `<x-paper-clone node-id="…" style="…" />` inside `write_html`, or `duplicate_nodes` (deep copy of nodes or whole artboards, returning an old-to-new ID map) followed by `update_styles` and `set_text_content`. **There is no component, instance or variant system in the agent tools.**
- `create_artboard` takes a name and camelCase styles with whole-pixel width and height, defaults to `display:flex; flexDirection:column`, and accepts `height: fit-content`. Artboards are created on a named page (`create_page`).
- Inline SVG is supported, and SVG `fill`/`stroke` can use token variables. Local images are `<img src="paper-asset:///absolute/path">`.
- Tokens: `type` is exactly one of `color`, `spacing`, `radius`, `fontFamily`, `fontSize`, `fontWeight`, `letterSpacing`, `lineHeight`, `opacity`, `container`, `breakpoint`; `name` matches `--[a-zA-Z0-9_-]+`; optional description up to 1024 characters; values may alias with `var(--other)`. Names follow the Tailwind v4 theme namespaces: `--color-*`, `--spacing-*`, `--radius-*`, `--font-*` (families), `--font-weight-*`, `--text-*` (sizes), `--tracking-*`, `--leading-*`, `--opacity-*`, `--container-*`, `--breakpoint-*`. Order: semantic colours before palette colours (neutrals, then primary, secondary, accent); other types smallest value first.
- **No modes or themes**: one value per token. Translucency of a token colour is `color-mix(in srgb, var(--color-x) 40%, transparent)`.

## What this means for the kit

| Paper rule | How the kit follows it |
|---|---|
| Inline styles only, no classes | Every artboard is inline styles. The only stylesheet is a `<link>` to `tokens.css`, which gives a browser the token values; Paper ignores it and resolves the same `var()` names against its own tokens. The file you review in `preview.html` is the file that goes in. |
| No grid, margin, tables, inline | `tools/lib/h.mjs` refuses them at build time and `tools/check.mjs` lints the output. Specimen "grids" are flex rows and columns. |
| `layer-name` sets layer names | Every element has one; `check.mjs` fails on a missing or over-long (50+) name. |
| No rich text | Mixed weights are separate text nodes in a flex row. |
| Small `write_html` pieces | `tools/build.mjs` splits each artboard into an ordered fragment manifest (`*.fragments.json`): parent layer path plus about 15 lines of HTML per fragment, repeated subtrees marked as clones, dark screens marked as duplicates of their light twins with the exact changes. `tools/calls.mjs` counts calls from them. |
| Tailwind-namespaced tokens, no modes | `tokens.paper.json` is the exact `create_tokens` array. Colours exist twice: `--color-accent-primary` (light) and `--color-dark-accent-primary` (dark); dark artboards use the dark set. `tools/token-map.json` maps every app token to its Paper name. When Paper ships modes, the dark set becomes the Dark mode in one `set_tokens` pass and a find-and-replace on dark artboards. |
| No components | Component artboards are specimen sheets with named frames; screens are built by the same source functions, so structure and names match. The owner promotes specimens to Paper components by hand if Paper adds them; until then reuse is `x-paper-clone`. |
| Local fonts work | SF Pro and New York are installed on this Mac, so `"SF Pro"` and `"New York"` render in Paper Desktop. No web fonts. |
| Inline SVG with token fills | Icons (SF Symbols, converted locally) and the logo are inline SVG with `layer-name`s and `style` fills from tokens. |

## Still unconfirmed, and the fallback

| Assumption | If it is wrong | Fallback |
|---|---|---|
| `var()` works in every property used (`width`, `gap`, `border-radius`, `box-shadow`) | Some values drop (reported as `ignoredStyles`) | `node tools/build.mjs --literal` resolves every variable to its value from the same sources. |
| Dimension tokens that are not spacing (badge sizes, strokes, chart heights) are accepted as `spacing` | Some entries are refused | The per-entry result names them; inline them with `--literal`. |
| `font-variant-numeric: tabular-nums` survives | Digits are proportional | Cosmetic; on the check list. |
| `update_styles` takes about 50 node updates per batch call | Dark duplicates cost more calls | `calls.mjs` reports the count both ways. |
| Whether failed calls count against the quota, and when the week resets | Budget slips | Plan keeps a 10% margin. |

## The call limit (Confirmed, pricing page)

| Plan | MCP tool calls | Price as listed |
|---|---|---|
| Free | **100 per week** | $0 |
| Pro | 1,000,000 per week | $20 per editor per month, or $16 billed yearly |
| Organizations | as Pro | custom |

Every tool call counts, reads included (the cached build wraps all tools in one gated call path). Unconfirmed: whether a failed call counts, and when the week resets. `BUILD-PLAN.md` gives the call counts for both plans.
