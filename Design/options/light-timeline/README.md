# Light through the day: layout options

The owner's note on the place card's "Light through the day" module (round 3, shot 10):

> i think this needs to be a bigger section. show me options with it as a full height bar on the left, and on the right replacing the places list.

There are three options. **A** is the full-height bar on the left. **B** replaces the places list on the right. **C** is a third option: a wide strip across the top of the map. Each is drawn in the real Explore window at 1280×820 and at 960×652, in light and dark. The data is Bixby Bridge on Tue Oct 6 2026, from OpenWeather, updated 11:50. The windows are Sunset 76 (18:09–18:43), Blue PM 78 and Night 79. Today's Blue AM and Sunrise have passed, and the marker is being dragged at 18:26.

For comparison, the module today is a 56 pt sky band about 252 pt wide inside the 360 pt place card. That is about **10.5 pt per hour**, with an 80 pt cloud plot under it.

The event unit (window symbol + score + time) is drawn tightly grouped everywhere. It will follow whatever the shared event-unit component ends up as.

Open `preview.html` to see every option in order.

---

## Option A: full-height bar on the left

**What it is.** The timeline becomes its own column between the sidebar and the places list, with time running top to bottom.

- The sky gradient is a 48 pt bar the full height of the window.
- A slim cloud and rain band runs beside the bar.
- The day's windows sit to the right as event units, with brackets showing each window's span.
- The column's header shows the range control (Day, Rise, Set) and a two-line readout.

**What gets bigger.** The day runs about 600 pt tall, so 24 hours get **about 25 pt per hour**: 2.4 times today. In "Set" mode the four hours around sunset fill the whole height, so the golden and blue minutes read in fine detail.

**What it costs.**
- **Map width.** The map loses the most: 680 pt becomes 492 at 1280, and 428 at 960.
- **List width.** The list drops to its 340 pt minimum.
- **Place card.** The card has to shrink to 320 (296 at 960).
- **Units.** The event units are compact (10 pt time), to fit the 208 pt column.
- **Weather.** The cloud chart becomes a 24 pt sliver. It shows the shape of the day but no detail.

**On resize.** The sidebar collapses first, as it does today. Then the map shrinks. The light column and the list keep their widths. Below about 400 pt of map, the card would need to become a sheet.

**Interaction.**
- **Scrubbing.** Hover or drag on the bar moves a horizontal marker, shown solid with a time pill in the axis gutter. The readout follows the marker. On release the marker turns dashed and stays put, and the readout returns to the selected window.
- **Windows.** Clicking a window selects it everywhere: in the column, on the pin and in the card's summary.
- **Keyboard.**
  - **Up/Down** still move the list selection, and the column follows.
  - **Left/Right** (or `[` and `]`) step through the windows.
  - **D, R and S** switch the range.
  - **Esc** ends a scrub.
- **Nothing selected.** The column shows today's sky for the area you're looking at, with sunrise and sunset marked, no scores and "Select a place to see its light". See `A-1280-empty-light`.
- **VoiceOver.** The bar is one adjustable element, read as "6:26 PM, Sunset", moving in 10-minute steps. Each window is its own element.

**What changes in the app.**
- A third column in the Explore split, with a width constant and a collapse rule.
- A vertical renderer for `LightTimelineSection`. The sky bar and the cloud band become a vertical `Canvas`, and the window and marker logic is shared with the horizontal renderer.
- `ExplorePlaceCard` drops its timeline section.
- The selection and marker state moves up to the Explore model so that the column, the pins and the card share it.

**Artboards.** `A-1280-light`, `A-1280-dark`, `A-960-light`, `A-960-dark`, `A-1280-sunset-light`, `A-1280-empty-light`.

---

## Option B: the light panel replaces the places list

**What it is.** Selecting a place turns the list column into that place's Light panel. Top to bottom it shows:

- a header with **‹ Places** (back) and **3 of 16** with up and down arrows;
- the spot's name and next event;
- "Light through the day" with the full segmented control and the readout;
- the timeline, grown;
- "Today", the day's window rows, each led by the event unit (symbol · score · time range) with the quality word and confidence at the right;
- "Coming up", tomorrow's windows.

The map stays exactly where it was.

**What gets bigger.**
- **Sky band:** 56 pt becomes **88 pt**.
- **Cloud plot:** 80 pt becomes **112 pt**.
- **Plot width:** about 252 pt becomes **328 pt**. The 44 pt label gutter is gone, because the percentages now sit inside the plot. That is about 13.7 pt per hour across the full day.
- **Zoomed views:** "Sunset ±2 h" fills the same width with four hours, at about 82 pt per hour.
- **Everything about light in one place:** today's windows and what's coming up sit in one readable column instead of scrolled sections of a 360 pt card.

**What it costs.**
- **The list.** While you look at a place's light, the list is hidden. Up and down still step through it.
- **Fixed width.** The panel only has the list's width. It is the biggest gain in height but the smallest in time resolution of the three options.
- **Place card.** The card loses its light sections and keeps the name, images and Good to know.

**On resize.** The column keeps its width (340 pt minimum), and the plot narrows with it. Below 350 pt the "Drag to read any time" hint is dropped. The panel scrolls: at 820 the cut is through "Coming up", and at 652 it is through "Today".

**Interaction.**
- **Entering.** Click a row or a pin, or press Return on a row, to enter the panel. A hovered row shows a chevron to signal this.
- **Going back.** **‹ Places**, **Esc**, or clicking Explore in the sidebar returns to the list, still at the same scroll position.
- **Stepping.** **Up/Down** (and the header arrows) move to the previous or next place without leaving the panel.
- **Scrubbing.** Hover or drag on the timeline scrubs it. A time pill replaces the hour label under the knob.
- **Windows.** Clicking a bracket or a window row selects that window everywhere.
- **Nothing selected.** With no place selected, the column is the list.
- **VoiceOver.** The header reads "Back to places" and "Place 3 of 16". The timeline is one adjustable element, as in COMPONENTS.md.

**What changes in the app.**
- The Explore list column becomes a two-state container: the list or the new `LightPanel`, driven by the selected place. Esc and back return to the list.
- `LightTimelineSection` gets a "wide" size: no gutter, labels inside the plot, a taller band and plot, and an axis pill.
- `DayWindowsSection` and "Coming up" move from the card into the panel.
- `ExplorePlaceCard` drops those sections.
- Little new state: selection already drives the card.

**Artboards.** `B-pair-light` and `B-pair-dark` show the list and light states side by side. The rest are `B-1280-list-light`, `B-1280-list-dark`, `B-1280-light-light`, `B-1280-light-dark`, `B-960-light-light`, `B-960-light-dark` and `B-1280-sunset-light`.

---

## Option C: a light strip across the top of the map

**What it is.** When a place is selected, a glass strip docks across the full width of the map, inset 12 pt like the place card. Its contents:

- **Header row:** the spot and its event unit, the readout, the range control, and a collapse chevron.
- **Timeline:** window event units above a 64 pt sky band, a label for every hour, and a 72 pt cloud plot with the legend inside it.
- **Map:** it re-centres below the strip.
- **Collapsed:** the strip folds to a 44 pt bar, a thin ribbon carrying only the scored windows.

**What gets bigger.** It gives the most time resolution: 632 pt across, **about 26 pt per hour** (2.5 times today), with every hour labelled. The list and the sidebar are untouched.

**What it costs.**
- **Map height.** The strip covers 276 of the map's 768 pt at 1280 (36%), and 268 of 600 pt at 960.
- **Place card.** It shrinks to 320 wide and has to share the remaining height. At 960 it opens already scrolled.
- **Windows and "Coming up".** These stay in the card, so light information sits in two places.

**On resize.** The strip is always the map's width minus 24 pt, and its band scales with it. At 960 the hour labels go to every two hours. Collapsing gives the map about 220 pt back.

**Interaction.**
- **Scrubbing and windows.** Hover or drag scrubs, with a time pill in the axis row. Click a window to select it.
- **Keyboard.**
  - **Esc** deselects the place, which removes the strip.
  - **⌥⌘L** or the chevron collapses and expands the strip.
  - **Up/Down** move the list selection, and the strip follows.
  - **Left/Right** step through the windows.
- **Nothing selected.** No strip.
- **VoiceOver.** One adjustable element.

**What changes in the app.**
- A new overlay in `ExploreMapPane`, with a top content inset so the camera keeps the pin clear.
- A wide variant of `LightTimelineSection`, with event-unit bracket labels, an inline legend and a collapsed mode.
- `ExplorePlaceCard` drops its timeline.

**Artboards.** `C-1280-light`, `C-1280-dark`, `C-960-light`, `C-960-dark`, `C-1280-collapsed-light`.

---

## Recommendation

**B.**

- **Best fit with the click.** Choosing a place is already the moment you want its light. B gives that moment the whole column, with the timeline, the window rows and what's coming up together in one readable stack.
- **Lowest cost.** It costs nothing on the map and has the smallest structural change: one column switching between two views, reusing the horizontal renderer.
- **Easy to undo.** Esc and the up/down arrows make it cheap to leave and to compare places.
- **A's trade-offs.** A is the most striking and the only one that keeps the timeline on screen while you browse the list. But it takes 188 pt of map, and its vertical weather band is too slim to read.
- **C's trade-offs.** C has the best time resolution, but it covers a third of the map and splits light across the strip and the card.

If time resolution matters most, take C's every-hour axis into B's zoomed views.

## Files

- `artboards/*.html`: Paper-form artboards (inline styles, literal token values). `manifest.json` lists their sizes.
- `src/`: the generator.
  - `shell.mjs`: the Explore window as the app draws it today.
  - `data.mjs`: Bixby Bridge's real data.
  - `timeline-h.mjs` and `timeline-v.mjs`: the timeline renderers.
  - `option-a/`, `option-b/`, `option-c/`: per-option parts.
  - `artboards/*.mjs`: one module per option.
  - `00-today`: the current app, for comparison.
- **Build:** `node Design/options/light-timeline/src/build.mjs [ids]`.
- **Render:** `Design/options/light-timeline/tools/render.sh [--2x] [ids]`, headless Chrome, writing to the session scratchpad.
- `preview.html`: every option in order, with the renders embedded.
