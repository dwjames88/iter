# Paper paste log

Action log of tools/paste/paste-cycle.sh. The last line starting with "OK " names the last successful artboard.

## Trial, 2026-10-05 (F03 Spacing & radii)

- Permissions (granted to Ghostty, the terminal): Accessibility yes, Screen Recording yes, Automation of System Events yes.
- Clipboard with both `public.html` and `public.utf8-plain-text`: **Paper created nothing.** It evidently reads the HTML flavour first and ignores it.
- Clipboard with **plain text only: works.** One top-level artboard "F03 Spacing & radii", 1640 × 2408, layout and content matching the reference render; fill bound to the `canvas-artboard` token and selection colours listed by token name (tokens bind); layer names present (F03 › Page …).
- Position: it landed at X -183, Y -448, over F01 (not at its `layout.json` place). The new artboard is left selected.
- Undo takes **two** ⌘Z per paste. After 2 × ⌘Z the canvas matched the pre-paste screenshot exactly; the file was left clean.
- `NSRunningApplication.activate` from the terminal is deferred by macOS; `paperctl activate` now falls back to `open -b`.

## Full run (not started; needs the owner's go-ahead)

- Order: `tools/paste/ORDER.txt` (248 files: Foundations 6, Components 54, Screens (Light) 102, Screens (Dark) 81, Flows 5; F02 skipped). F01 is first: delete the partial F01 artboard before, or remove its line from ORDER.txt.
- Step: `tools/paste/run-all.sh next` does one step (a page switch, or one paste in plain-text mode) and stops; review the printed screenshot, then `tools/paste/paste-cycle.sh ok|fail <file> "<note>"`. `run-all.sh status` shows the last OK, the next entry and what remains. Resume is automatic: entries with an OK line are skipped. `paste-cycle.sh back` restores the owner's clipboard and app at the end.
- Page switching: click on the page list row (window-relative x 75; y Foundations 166, Flows 194, Screens (Dark) 222, Screens (Light) 251, Components 278, measured 2026-10-05 with the sidebar open at this window size), then a screenshot to confirm.
- Open issues before the full run: (1) every paste lands near the same spot, overlapping; (2) the pasted artboard stays selected, so the next paste may nest inside it. Both need one more short trial (a click on empty canvas or the page row to deselect, and a root `left`/`top` in the payload).

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
