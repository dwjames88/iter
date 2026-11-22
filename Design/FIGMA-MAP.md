# Figma map

Which Swift component in `IterUI` corresponds to which part of the "Iter Design System" Figma file, and which snapshot images show it. Swift paths are under `Packages/Iter/Sources/IterUI/`. Snapshots are in `Design/snapshots/rebuild/`; each name below has a `-light` and a `-dark` image (the iOS ones are `-ios-light` and `-ios-dark`).

## How this was built

From the code, `COMPONENTS.md`, the Phase 5 brief and the changelog. **No Figma call was made** for this table. The Figma file was last checked on 2026-11-22; node ids below come from that check and are unverified beyond it. Nodes are on the Components page (5:2).

Naming: Figma and docs name everything by UI part (card, module, row, chip, button, window), never "grid" or "event". The Swift token namespace `IterEvent` (the score chip's metrics) has the Figma-facing alias `IterChip`.

## Components in Figma

| Component | Figma part / node | Swift file | Snapshots |
| --- | --- | --- | --- |
| Sidebar (280 x 943) | Sidebar `11:1768` | `Sidebar/SidebarSearchField.swift`, `SidebarSectionHeader.swift`, `SidebarRow.swift`, `SidebarDisclosureRow.swift`, `SidebarBottomBar.swift` | `sidebar-panel`, `sidebar-parts` |
| Sidebar parts (search field, section header, row, disclosure row, bottom bar) | Inside `11:1768`; child ids unknown | same files as above | `sidebar-parts` |
| Trip Builder module (639 x 943) | Trip Builder Module `11:1873` | `TripBuilder/BuilderType.swift` (type and metrics), `DayCardBackground.swift` | `builder-module` |
| Trip header card | Title `11:2746` | `TripBuilder/TripHeaderCard.swift` | `builder-header-card` |
| Trip meta row | Title `11:2746` | `TripBuilder/TripMetaRow.swift` (`TripMetaRow`, `TripMetaItem`) | `builder-meta-row` |
| Day selector | Day selector `25:4074` | `TripBuilder/DaySelector.swift` (`DaySelector`, `DaySelectorCard`) | `builder-day-selector` |
| Day card | Day cards `16:3329` and `42:4291` | `TripBuilder/DayCardBackground.swift` (`DayCard`, `DayCardBackground`) | `builder-module`, `builder-footer` |
| Day card header | Day cards `16:3329` and `42:4291` | `TripBuilder/DayCardHeader.swift` (`DayCardHeader`, `SunTimesRow`) | `builder-day-card-header` |
| Stop card | Stop card `21:3363` | `TripBuilder/StopCard.swift`, with `NumberBadge.swift`, `LightWindowPicker.swift`, `NotePlaceholder.swift` | `builder-stop-card`, `builder-badges`, `builder-light-window-picker`, `builder-note-placeholder` |
| Score chip | Score instances inside `21:3363`; the Score component's own node id is unknown | `Score/ScoreChip.swift`, `ScoreChipMetrics.swift` | `score-chip-sizes`, `score-chip-states`, `score-chip-pin`, `score-chip-fixedwidth` |
| Drive row (inline) | Drive row `44:170` | `TripBuilder/DriveSegmentRow.swift` (`.inline`), `DriveBadge.swift`, `TimeLabelColumn.swift` | `builder-drive-segments`, `builder-badges` |
| Overnight row (transfer) | Overnight row `44:283` | `TripBuilder/DriveSegmentRow.swift` (`.transfer`), `OvernightNote.swift`, `FindHotelsButton.swift` | `builder-drive-segments`, `builder-footer` |
| Add Stop row | Add row `21:3570` | `TripBuilder/AddStopButton.swift` | `builder-footer` |

## Controls (not Figma nodes)

These come from `GLASS-RULES.md` and Apple Maps measurements, not from a Figma node.

| Component | Swift file | Snapshots |
| --- | --- | --- |
| Glass circle button (`GlassCircleButtonStyle`) | `Controls/GlassCircleButtonStyle.swift` | `controls-glass-circle-button` |
| Place action button (`PlaceActionStyle`) | `Controls/PlaceActionStyle.swift` | `controls-place-actions` |
| Map control stack (`MapControlStack`) | `Controls/MapControlStack.swift` | `controls-map-stack` |

## Not yet in Figma

Built from the design docs only. Draw these in Figma next, then add their node ids here.

| Component | Swift file | Snapshots |
| --- | --- | --- |
| Source line | `Conditions/SourceLine.swift` | `conditions-source-line` |
| Data state view | `Conditions/DataStateView.swift` | `conditions-data-state`, `conditions-data-state-large-0` to `-4` |
| Factor row | `Conditions/FactorRow.swift` | `conditions-factor-row` |
| Confidence indicator | `Conditions/ConfidenceIndicator.swift` | `conditions-confidence` |
| Leave-by card | `Go/LeaveByCard.swift` | `go-leave-by-card` |
| Live sky card | `Go/LiveSkyCard.swift` | `go-live-sky-card` |
| Next stop card | `Go/NextStopCard.swift` | `go-next-stop-card` |

## Not applicable

| Part | Swift file | Why |
| --- | --- | --- |
| Window symbol | `Score/WindowSymbol.swift` | An SF Symbol per light window, not a Figma component |
| Text helpers (`LightText`, `TimeText`, `DataText`, `TripText`, `TripBuilderText`, `InflectedCount`) | `Text/` | Words and formatting only; no visual part |
| Tokens | `Tokens/` | Generated from `Design/tokens.json`; Figma variables live in the Foundation file |
