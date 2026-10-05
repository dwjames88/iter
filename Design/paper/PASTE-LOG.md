# Paper paste log

Action log of tools/paste/paste-cycle.sh. The last line starting with "OK " names the last successful artboard.

## Trial, 2026-10-05 (F03 Spacing & radii)

- Permissions (granted to Ghostty, the terminal): Accessibility yes, Screen Recording yes, Automation of System Events yes.
- Clipboard with both `public.html` and `public.utf8-plain-text`: **Paper created nothing.** It evidently reads the HTML flavour first and ignores it.
- Clipboard with **plain text only: works.** One top-level artboard "F03 Spacing & radii", 1640 × 2408, layout and content matching the reference render; fill bound to the `canvas-artboard` token and selection colours listed by token name (tokens bind); layer names present (F03 › Page …).
- Position: it landed at X -183, Y -448, over F01 (not at its `layout.json` place). The new artboard is left selected.
- Undo takes **two** ⌘Z per paste. After 2 × ⌘Z the canvas matched the pre-paste screenshot exactly; the file was left clean.
- `NSRunningApplication.activate` from the terminal is deferred by macOS; `paperctl activate` now falls back to `open -b`.

## Trial 2, 2026-10-05 (F03 then F04, positioned payloads)

- Deselect: **Escape works** once the paste has settled (an Escape sent while Paper was still loading the paste did nothing). With nothing selected, the next paste (F04) landed **at top level**, a sibling of F03, not nested. No click was needed. `paste-cycle.sh paste` now sends Escape before every ⌘V.
- Position: **ignored.** The root carried `position:absolute; left; top` from `layout.json` (F03 3520,120; F04 0,6024); Paper placed each board in the middle of the current view instead (F03 at -183,-448 both times, F04 at -103,72). The paste bundle has no other position mechanism.
- Arrow keys move a selected artboard **1 px** per press (F04 X -103 → -102). Spreading boards by nudges would need thousands of presses, so the driver does not do it: **boards on a page will overlap** in the middle of the view and need arranging afterwards, by the owner (drag) or by agent calls after the Paper limit resets (about 2026-10-09; one `update_styles` per board, or batched, with `left`/`top` from `layout.json`).
- Undo: 1 for the nudge, 2 per paste; after 5 × ⌘Z the canvas matched the pre-trial screenshot (F02 and F01 only, nothing selected). File left clean.
- Guard fix: a synthetic arrow key leaves the `fn` flag set in the combined state, which tripped the "owner active" check (idle was 25 s). `paperctl keysdown` no longer counts `fn`.

## F01

F01 Colour is **not in the paste order.** The partial F01 artboard (fragments 1 to 21 of 88) stays on the canvas, for the owner to delete or for the agent to finish by route B after the reset (see BUILD-LOG.md, "How to resume").

## Full run (not started; needs the owner's go-ahead)

- Order: `tools/paste/ORDER.txt`, 247 files: Foundations 5 (F03 to F07), Components 54, Screens (Light) 102, Screens (Dark) 81, Flows 5. F01 and F02 are skipped.
- Step: `tools/paste/run-all.sh next` does one step (a page switch, or Escape + one paste in plain-text mode) and stops; review the printed screenshot, then `tools/paste/paste-cycle.sh ok|fail <file> "<note>"`. `run-all.sh status` shows the last OK, the next entry and what remains. Resume is automatic: entries with an OK line are skipped. `paste-cycle.sh back` restores the owner's clipboard and app at the end.
- Page switching: click on the page list row (window-relative x 75; y Foundations 166, Flows 194, Screens (Dark) 222, Screens (Light) 251, Components 278, measured 2026-10-05 with the sidebar open at this window size), then a screenshot to confirm.
- Known result: boards land overlapping in the middle of the view on each page; arrange afterwards (see Trial 2).
- Time: about 30 s per board with a screenshot review each (8 s driver, about 20 s review), so about 2 h for 247 boards plus 5 page switches. Paper holds the screen and keyboard throughout.

## Log

2026-10-05T16:26:54 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-162654-trial-F03-look.png
2026-10-05T16:26:59 PASTE-START /path/to/Iter/Design/paper/paste/foundations/003-F03-spacing-radii.html mode=both bytes=90827 window=12892 prev_front=com.dwjames.iter
2026-10-05T16:26:59 owner clipboard saved
2026-10-05T16:26:59 clipboard set changeCount=26
2026-10-05T16:27:03 ABORT could not activate Paper
FAIL 2026-10-05T16:27:15 /path/to/Iter/Design/paper/paste/foundations/003-F03-spacing-radii.html aborted before keystroke: activation refused (fixed with open -b fallback)
2026-10-05T16:27:20 PASTE-START /path/to/Iter/Design/paper/paste/foundations/003-F03-spacing-radii.html mode=both bytes=90827 window=12892 prev_front=com.dwjames.iter
2026-10-05T16:27:20 owner clipboard already saved this cycle (kept)
2026-10-05T16:27:20 clipboard set changeCount=27
2026-10-05T16:27:20 Paper frontmost
2026-10-05T16:27:20 KEYSTROKE cmd+v sent
2026-10-05T16:27:24 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-162724-003-F03-spacing-radii-after.png
FAIL 2026-10-05T16:27:32 /path/to/Iter/Design/paper/paste/foundations/003-F03-spacing-radii.html both flavours: no nodes created
2026-10-05T16:27:32 PASTE-START /path/to/Iter/Design/paper/paste/foundations/003-F03-spacing-radii.html mode=plain bytes=90827 window=12892 prev_front=com.dwjames.iter
2026-10-05T16:27:32 owner clipboard already saved this cycle (kept)
2026-10-05T16:27:32 clipboard set changeCount=28
2026-10-05T16:27:32 Paper frontmost
2026-10-05T16:27:33 KEYSTROKE cmd+v sent
2026-10-05T16:27:36 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-162736-003-F03-spacing-radii-after.png
2026-10-05T16:27:53 UNDO 1/1 sent
2026-10-05T16:27:55 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-162755-undo-undo.png
2026-10-05T16:28:17 UNDO 1/1 sent
2026-10-05T16:28:19 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-162819-undo-undo.png
2026-10-05T16:28:29 owner clipboard restored
2026-10-05T16:28:30 activated previous front com.dwjames.iter
FAIL 2026-10-05T16:28:30 /path/to/Iter/Design/paper/paste/foundations/003-F03-spacing-radii.html TRIAL: plain-text paste WORKED (artboard F03 created, tokens bound, layer names, real text) but landed at -183,-448 over F01; undone with 2x cmd-Z, file verified clean. Not counted as done.
2026-10-05T16:30:32 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163032-trial2-look.png
2026-10-05T16:30:41 PASTE-START /tmp/scratch/scratchpad/paste/t2/F03-pos.html mode=plain bytes=90849 window=12892 prev_front=com.dwjames.iter
2026-10-05T16:30:41 owner clipboard saved
2026-10-05T16:30:41 clipboard set changeCount=30
2026-10-05T16:30:42 Paper frontmost
2026-10-05T16:30:43 KEYSTROKE cmd+v sent
2026-10-05T16:30:46 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163046-F03-pos-after.png
2026-10-05T16:30:46 KEY escape sent
2026-10-05T16:30:48 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163048-key-escape-key.png
2026-10-05T16:31:01 KEY escape sent
2026-10-05T16:31:03 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163103-key-escape-key.png
2026-10-05T16:31:13 PASTE-START /tmp/scratch/scratchpad/paste/t2/F04-pos.html mode=plain bytes=33449 window=12892 prev_front=com.dwjames.iter
2026-10-05T16:31:13 owner clipboard already saved this cycle (kept)
2026-10-05T16:31:13 clipboard set changeCount=31
2026-10-05T16:31:13 Paper frontmost
2026-10-05T16:31:13 KEYSTROKE cmd+v sent
2026-10-05T16:31:17 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163117-F04-pos-after.png
2026-10-05T16:31:18 KEY right sent
2026-10-05T16:31:19 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163119-key-right-key.png
2026-10-05T16:31:34 ABORT owner active (keys: fn  idle: 16.19)
2026-10-05T16:31:55 UNDO 1/3 sent
2026-10-05T16:31:55 UNDO 2/3 sent
2026-10-05T16:31:56 UNDO 3/3 sent
2026-10-05T16:31:58 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163158-undo-undo.png
2026-10-05T16:32:07 UNDO 1/2 sent
2026-10-05T16:32:08 UNDO 2/2 sent
2026-10-05T16:32:10 SHOT window=12892 /tmp/scratch/scratchpad/paste/shots/20261005-163210-undo-undo.png
2026-10-05T16:32:20 owner clipboard restored
2026-10-05T16:32:22 activated previous front com.dwjames.iter
FAIL 2026-10-05T16:32:22 /tmp/scratch/scratchpad/paste/t2/F04-pos.html TRIAL 2: top level after Escape; position ignored (landed -103,72); undone
FAIL 2026-10-05T16:32:22 /tmp/scratch/scratchpad/paste/t2/F03-pos.html TRIAL 2: position ignored (landed -183,-448); undone; file verified clean
