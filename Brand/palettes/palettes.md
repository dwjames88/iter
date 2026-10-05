# Iter round 3: colour study (First Light and Alpine)

Owner: "For colors i like first light and alpine." Blue Hour is dropped. Each family is shown as the round-two original plus tuned variations, and one cross. Roles are the same as round two (`ink`, `paper`, `accent`, `ink_dark`, `paper_dark`, `accent_dark`, icon ground / mark / accent). Ratios are WCAG 2.x, computed with round two's `contrast.py`. Targets: ink at least 7:1; accent at least 3:1 on the ground it sits on (4.5:1 shown for reference). Any accent under 3:1 would be flagged **below 3:1**: none of these variants is. Files: `colour/<slug>/{palette.json, swatch.svg, preview.svg}` (preview = the contour one-bend lockup on paper, on paper_dark, and the app icon; it will be swapped when the switchback set lands). Dropped after looking at renders: a warm-apricot First Light (terracotta on apricot paper read brown and muddy) and an ice-teal Alpine (cold, corporate).

## Summary

| Slug | ink / paper | accent | ink_dark / paper_dark | accent_dark | icon ground / mark / accent | ink:paper | acc:paper | acc:ink | inkD:paperD | accD:paperD | mark:gnd | iconacc:gnd |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `firstlight` | `#2A1710` / `#FFF6EC` | `#E4572E` | `#FFF1E3` / `#1C1210` | `#FF8A5C` | `#2A1710 / #FFF1E3 / #FF8A5C` | 15.99 | 3.45 | 4.64 | 16.57 | 7.91 | 15.42 | 7.36 |
| `firstlight-deep` | `#1E0F0A` / `#FFF8F0` | `#D9431A` | `#FFF4E8` / `#150C0A` | `#FF8A5C` | `#1E0F0A / #FFF4E8 / #FF8A5C` | 17.68 | 4.18 | 4.23 | 17.78 | 8.30 | 17.16 | 8.02 |
| `firstlight-coral-plus` | `#2A1710` / `#FFF6EC` | `#CF3E14` | `#FFF1E3` / `#1C1210` | `#FF7A45` | `#2A1710 / #FFF1E3 / #FF7A45` | 15.99 | 4.51 | 3.54 | 16.57 | 7.10 | 15.42 | 6.61 |
| `alpine` | `#0F2A20` / `#F1F3EC` | `#5E7F12` | `#EEF2E8` / `#0A1A14` | `#B9D86B` | `#0F2A20 / #EEF2E8 / #B9D86B` | 13.68 | 4.15 | 3.29 | 15.80 | 11.19 | 13.48 | 9.54 |
| `alpine-glacier` | `#0F2A20` / `#F0F4F2` | `#0A7C6E` | `#EEF4F1` / `#0A1A14` | `#5FE0C8` | `#0F2A20 / #EEF4F1 / #5FE0C8` | 13.79 | 4.59 | 3.00 | 16.10 | 11.09 | 13.73 | 9.46 |
| `alpine-pine` | `#0F2A20` / `#F1F3EC` | `#1F7F4F` | `#EEF2E8` / `#0A1A14` | `#7FE3A8` | `#0F2A20 / #EEF2E8 / #7FE3A8` | 13.68 | 4.46 | 3.07 | 15.80 | 11.49 | 13.48 | 9.80 |
| `cross-spruce-coral` | `#0F2A20` / `#F1F3EC` | `#D9431A` | `#EEF2E8` / `#0A1A14` | `#FF8A5C` | `#0F2A20 / #EEF2E8 / #FF8A5C` | 13.68 | 3.94 | 3.47 | 15.80 | 7.72 | 13.48 | 6.59 |

Nothing is below 3:1 (flagged). Weakest remaining: `alpine-glacier` accent on ink is exactly 3.00 and `alpine-pine` 3.07, but the accent never sits on the mark colour (the icon uses the bright dark-mode accent instead, 9+:1).

## First Light

Warm sunrise: espresso ink, cream paper, coral sun, peach glow on dark. The only real flaw was coral on cream at 3.45:1. The fix is a darker, more saturated coral; the dark-mode hex can stay luminous.

| Slug | Change | accent | acc:paper | Note |
|---|---|---|---|---|
| `firstlight` | original | `#E4572E` | 3.45 | the brightest, most sunrise, weakest at 16px |
| `firstlight-deep` | darker roast ink `#1E0F0A`, brighter paper `#FFF8F0`, burnt coral | `#D9431A` | 4.18 | highest ink contrast (17.68); the dot starts to lean brick |
| `firstlight-coral-plus` | same ink and paper, more saturated vermilion, brighter peach on dark | `#CF3E14` | 4.51 | first to clear 4.5:1; loud, close to warning red |

**Weak spot:** every fix trades sunrise warmth for contrast; going below `#D9431A` moves toward red.
**Recommended canonical: `firstlight-deep`.** It cures the 3.45 problem (4.18, comfortable for a dot at 16px), keeps the coral reading as coral rather than red, and the darker ink and brighter paper make the wordmark crisper. `coral-plus` is the fallback if the dot proves too weak in small sizes.

## Alpine

Forest at altitude: spruce ink, mineral stone paper. Round two's lichen read olive and dated next to cool UI greys. Both new accents are cleaner and cooler, with a bright mint/aqua pair on dark.

| Slug | Change | accent | acc:paper | Note |
|---|---|---|---|---|
| `alpine` | original lichen | `#5E7F12` | 4.15 | olive, dated |
| `alpine-glacier` | cooler stone paper, glacial teal-green | `#0A7C6E` | 4.59 | fresh and distinctive; moves toward water |
| `alpine-pine` | clean pine green | `#1F7F4F` | 4.46 | most "alpine forest"; close in hue to the ink so it separates by lightness only |

**Weak spot:** a green accent on a green ink is the family's built-in limit; the dot must stay clearly lighter than the stroke.
**Recommended canonical: `alpine-glacier`.** It is the one that stops reading olive, is the most ownable (teal-green with spruce is rare in travel apps), has the best paper contrast (4.59), and sits naturally with cool UI greys. `alpine-pine` is the safer, more literal alternative.

## Cross: `cross-spruce-coral`

Alpine spruce and stone with First Light's coral as the sun on the ridge. It holds together: in the renders the burnt coral against deep green is the strongest figure/ground pop of any option (complementary hues), and the stone paper keeps it from going festive. Accent on paper 3.94, on dark 7.72. Caveat: the coral must stay a small dot; a large coral area against green looks Christmassy. If chosen, it is a fourth palette, not a replacement.

## Suitability (the lead decides)

- **Switchback (heavy black-weight wordmark with one coloured dot):** `firstlight-deep`. A massive dark wordmark makes the single dot the entire colour story, so it needs the most chromatic, most contrasting dot: warm coral against near-black espresso is maximum pop, and the dot is large enough that a burnt (4.18) coral does not wash out. `cross-spruce-coral` is the alternative if the owner wants green.
- **Contour (small line-and-dot mark):** `alpine-glacier`. The line carries the form and the dot is tiny, so the dot must separate by hue, not size, and the teal-green stays legible on both grounds while the cool spruce stroke feels like terrain and a route; warm coral on a thin line reads more like an alert dot at 16px.
