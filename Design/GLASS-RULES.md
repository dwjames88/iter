# Glass rules

The rulebook every UI worker reads before touching UI. Liquid Glass is the system's, used the system's way. Colour and type come from the First Light palette (`Design/tokens.json`, see `Design/TOKENS.md`); screen order and emphasis come from `Design/HIERARCHY.md`. When this file and a hunch disagree, this file wins; when it disagrees with Apple Maps, measure Maps and update this file.

## Glass

- Glass only the system's way: `.glassEffect`, the system `.glass` and `.glassProminent` button styles, or on the Mac map card `NSGlassEffectView` in its sidebar variant (`FloatingPanelLayout.swift`), so card and sidebar are one material.
- No custom glass, no hand-drawn blur or frost, no `regularMaterial` over maps or photos.
- Groups of glass sit in a `GlassEffectContainer`. Never glass on glass.
- No global tint. Glass follows the system tint; `AccentColor` stays the accent and is used only on the main action.
- Glass lives in the navigation and controls layer floating above content. Rows, cards, place actions and text stay out of it (the content layer).
- Controls over photos use clear glass with the 35 % dimming layer.
- Map pins and clusters are solid plates, never material, so live and snapshot renders match.

## Geometry

Measured from Apple Maps. The latest values (b15548c) supersede earlier ones such as the 29 pt corner buttons.

- Corner buttons: 32 pt glass circles (`GlassCircleButtonStyle.swift`), used for Share, Close, filter and sort menus; previous and next share one glass capsule.
- Card corner 27.5 pt, concentric with the 32 pt corner buttons (the older 26 pt card went with 29 pt buttons). Do not hand-pick radii.
- Panels, imagery and prominent buttons use `ConcentricRectangle`, concentric with the window or parent shape.
- Sidebar search: 37 pt glass capsule, 13 pt text, 15 pt inset from the sidebar edges.
- Action tiles: 39 to 52 pt tall, one style and shape per row (`PlaceActionStyle.swift`); the main action filled with the accent, the rest the accent on a faint accent fill (or bordered, monochrome labels on iOS).
- Filter chips: 44 pt, system toggle buttons, monochrome (`FilterChip` and `filterChipStyle()` in `AppiOS/Sources/Explore/Components/SheetComponents.swift`).
- Map controls: one stack (`MapControlStack.swift`); Windy and Add Spot share a glass capsule at the top of it, not the toolbar.

## Components

- System components for everything: `List`, `NavigationStack`, toolbars, `Toggle`, `Menu`, `Picker`. Do not rebuild them. `RoundGlassButton` is gone; do not bring it back.
- Mac: full-bleed map under the toolbar, list on a floating glass card (`FloatingPanelLayout`, `FloatingPanelHeader`). Search lives in the sidebar, not over the card.
- iOS: large-title navigation bars; title, count and More/Share in the bar's toolbar glass group; an opened place is pushed in the sheet with the system Close and previous/next in the toolbar.
- iPhone: the map fills the screen and one floating system sheet (peek, half, full) holds the tab bar at its foot. Use system detents, no hand-built sheet or drag gesture.
- iPad: one glass column; header and close are system glass buttons.
- One prominent action per view. Standard control sizes; 44 pt minimum touch target on iOS.
- Reuse the helpers above before writing a new style; add to `Components/`, not inline.

## Content layer and colour

- Surfaces that sit on glass read `\.isOnGlass` (`GlassFill.swift`) and take the translucent system fills `ModuleFill`, `ControlFill`, `ContentFill` instead of opaque paper. Set `isOnGlass` on every glass surface (map card, iPad column, phone sheet).
- Inside the iPhone sheet screens drop their paper; at full height the sheet is solid.
- Colours from `tokens.json` through the generated tokens only; no raw hex, no new greys.
- Imagery is inset and concentric with its card.

## Copy

- Title-style capitalisation. No all-caps overlines or tracking-spaced labels.
- Action labels are verbs ("Add to Trip", "Open in Maps"); sentences end without full stops in buttons.
- Say what the thing is, not what the app is doing ("Sunset at 18:14").

## Checklist before you commit UI

- [ ] No custom glass: only `.glassEffect`, `.glass`, `.glassProminent` or `NSGlassEffectView` sidebar variant.
- [ ] Glass groups are in a `GlassEffectContainer`; no glass on glass; no glass in the content layer.
- [ ] No global or per-control tint except the accent on the one main action.
- [ ] Corners are `ConcentricRectangle` or the measured values above, not invented.
- [ ] Control sizes match the geometry list (32 pt corner buttons, 37 pt search, 44 pt chips).
- [ ] Anything on glass uses `isOnGlass` fills, not opaque paper.
- [ ] System `List`, toolbar, sheet and toggle used instead of a custom copy.
- [ ] Controls over photos: clear glass plus the 35 % dim; map pins solid.
- [ ] Title-style copy, no all-caps overlines.
- [ ] Checked light and dark, Mac and the iOS layout you touched.

## Links

Apple Human Interface Guidelines (the pages are script-rendered and did not load through a plain fetch when this was written; the rules above come from Sean's commits and the HIG as he applied it):

- https://developer.apple.com/design/human-interface-guidelines/components
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/design/human-interface-guidelines/buttons
- https://developer.apple.com/design/human-interface-guidelines/toolbars
- https://developer.apple.com/design/human-interface-guidelines/sidebars
- https://developer.apple.com/design/human-interface-guidelines/sheets
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- https://developer.apple.com/design/human-interface-guidelines/popovers
- https://developer.apple.com/design/human-interface-guidelines/segmented-controls
- https://developer.apple.com/design/human-interface-guidelines/menus
- https://developer.apple.com/design/human-interface-guidelines/search-fields
