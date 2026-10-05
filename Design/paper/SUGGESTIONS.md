# Suggestions for the design pass

These are the lead's opinions, kept out of the artboards. Every artboard draws the app as built, and each place where the app breaks its own rules carries a Note. This page says what I would look at first when you start finishing by hand. None of it is decided.

## The nine known deviations, with a lean

1. **Band word in compact places** (pins, Saved, Scout, Add Stop rows, outlook cells). The compact chip is 26 pt wide, so a word does not fit. A small glyph per band would break the "lightness, not hue" rule less than colour alone. Option: keep the number, add the band word only on hover and in the VoiceOver label (as now), and accept that compact means "number plus window". Decide on the LightBadge artboards first; every screen inherits it.
2. **"Sample data" twice on a screen.** Drop the header label wherever the attribution footer is visible. One label per screen is the rule, and the footer is the legal place for it.
3. **Rain colour.** Add a `weather/rain` token. With First Light everywhere, rain drawn in `sky/blueHour` reads as a sky band, and `accent/text` for rain figures now reads as coral, which is the brand. A cool slate would separate it.
4. **Accent on the outlook "Best" tag.** With First Light the accent is coral, the sun's colour, so a coral "Best" now says "good light" louder than before. Try the band fill for the tag, or ink on paper with the word "Best".
5. **Two coral marks on the sky arc** (legend dot and sun). Now that coral is also the interface accent, coral appears many times per view, so the old "one coral mark" rule no longer holds. Rewrite the rule for First Light before fixing the arc: coral is the accent; the sun marker needs a distinct shape rather than a distinct colour.
6. **Serif beyond place names** (trip names, the empty-state headline). Trip names are place-like and read well in New York. I would keep trip names and change the empty-state headline to the sans title style.
7. **Literal opacities.** They are now `--opacity-*` tokens in the kit (from `tools/canvas-tokens.json`). Promote them into `tokens.json` so the app and the file share them.
8. **Explore rows have no hover.** Give list rows the system hover, or nothing; avoid inventing a custom hover only for Explore.
9. **Trip builder at 960 × 640** truncates "25 min wal…". The session line could wrap to a second line under the pop-up, or drop "walk-in" to an icon (`figure.walk` is already in the symbol set).

## Things the build surfaced that are not in that list

- **`cloud.slash` does not exist** as an SF Symbol on this macOS, so the app shows an empty icon slot in the Explore notice and under the timeline. `icloud.slash` exists but means iCloud. A custom symbol may be best.
- **First Light makes coral do several jobs**: accent, selection, routes, pins, the sun and the logo dot. The ramp is amber and stays separate. Check the trip builder's route map and the spot page's arc side by side. That is where the colours meet hardest.
- **Selection fill on the sidebar and lists** is a pale peach in the kit (accent at 16%). macOS uses the accent at full strength for a key window's sidebar selection. Decide which you want; the token is `--opacity-selection-tint`.
- **Explore list width**: the source asks for 360 pt ideal; the snapshots show 520. A wider list shows full spot names without truncation and suits a list-first app.
- **Settings tab bar** is drawn as the standard macOS 26 toolbar tabs, because the snapshot could not render it. Nothing to change, but it has never been seen rendered.
