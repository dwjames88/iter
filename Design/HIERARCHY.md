# Hierarchy

One page of rules for type, grouping, spacing and colour roles. References: macOS Maps (place card: large headline fact, quiet grey section labels, grouped rounded sections), macOS Weather (module cards: a small titled label, one strong number, the same padding and radius on every module), Craft (whitespace, a short type scale, calm grouping). Tokens are in `TOKENS.md`; components in `COMPONENTS.md`.

## Type scale

Five levels. Nothing else. Sizes are the macOS defaults of the text style (Dynamic Type still applies).

| Level | Token | Style, size, weight | Used for |
|---|---|---|---|
| Display | `type/score/large` | largeTitle 26, semibold, monospaced digits | The one strong fact of a module: the score in the large event unit, the When to go day. One per module, never two. |
| Title | `type/title/spot` (place names, New York 22 semibold); `type/title/section` (title2 17 semibold) | | The page's name; a page-level section heading on the full spot page only. |
| Headline | `type/headline` | headline 13 semibold | Row titles (spot name, window name, day), the module's headline sentence. |
| Body | `type/body`, `type/time` | body 13 regular | Running text and primary times (window ranges). |
| Secondary | `type/secondary` | subheadline 11 regular, `text/secondary` | All metadata: locality, distance, source line, band word, confidence word, "Tomorrow", axis labels. One quiet style; do not mix caption, footnote and subheadline for metadata. |

Module titles use `type/moduleTitle` (subheadline 11 semibold, `text/secondary`, a leading SF Symbol in the same colour), the Weather idiom without upper-casing. Primary vs secondary in a row is carried by weight and colour together: headline + `text/primary`, then secondary + `text/secondary`. Never two primaries side by side.

## The invisible grid

- **Spacing scale: 8 pt.** Steps are 8, 16, 24, 32 (`space/sm`, `space/lg`, `space/xl`, `space/xxl`). 4 (`space/xs`) is only for hairline-tight pairs: a title and its secondary line, a symbol and its number inside the event unit. `space/md` (12) and `space/xxs` (2) are not used in new layout.
- **Insets.** Every module card and every list inside a card has a 16 pt inset (`grid/inset`). Rows inside a card run edge to edge of the card's inset: the first lane starts 16 pt from the card edge, the last lane ends 16 pt from it.
- **Lanes** (left to right, fixed widths so columns line up across rows; tokens under `grid/lane/*`):
  1. disclosure (chevron) 16, or absent for the whole list (never present on some rows and blank on others unless the list has expandable rows; then the blank lane is kept so text aligns),
  2. label (flexible): window name, day or spot name,
  3. event unit (fixed: head and tail at their widest, measured; symbol, score and time live inside it),
  4. band + confidence (fixed: widest band word plus the confidence mark, measured).
  The time is part of the event unit, never a lane of its own.
  Lane gap 8 (`grid/lane/gap`).
- **Baselines.** Text in every lane of a row shares the first text baseline (`HStack(alignment: .firstTextBaseline)`); the event unit's number sits on that baseline.
- **Row heights.** Single-line rows 32 (`grid/row/single`), two-line rows 48 (`grid/row/double`). Rows are a minimum height, so a wrapping name grows the row in 16 pt steps of feel, never by odd padding.
- **Section headers** have one treatment: `type/moduleTitle`, 8 below it to the content, 24 above it from the previous section.
- **Check it.** Debug ▸ Show Layout Grid overlays the 8 pt grid and the lane guides on every list and card.

## Cards and grouping

- **A module card** holds one subject with one strong fact: When to go (the best day and its score), Light windows (the list), Light through the day, Sun and moon, Hour by hour, Good to know. Fill `background/module`, radius `radius/card` (12), padding 16, no border stroke. Title inside the card, at its top-left.
- **Plain grouping** (whitespace only, no fill) inside a card, and for page headers and action rows.
- **Dividers or whitespace, not both.** Rows in a list are separated by a hairline inset to the label lane; groups are separated by 24 of whitespace and no line. No card has both a border and a fill.
- **No decorative borders.** Strokes stay only where they carry meaning: selection (`accent/primary`), focus, and the hairline that keeps pale ramp fills (Poor, Fair) visible.
- **Selection** is the system idiom: a fill (`selection/fill`), and on the map scale plus shadow; never a coral outline around a callout.

## Colour roles in hierarchy

- `text/primary` for the one thing a row is about; `text/secondary` for everything that qualifies it; `text/tertiary` never carries information.
- The Light Index ramp appears only inside the event unit (and the pin dot). The symbol inside the chip takes the chip's ramp text colour, so the window and its score read as one fact.
- Coral marks only what acts or is selected; it never decorates a section, header or border.
- Standard controls (buttons, pickers, steppers, date pickers, toggles, forms) are system controls in their default styles. The event unit is the one deliberate custom chip.
