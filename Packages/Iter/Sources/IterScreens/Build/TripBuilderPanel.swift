import SwiftUI
import IterFeatures
import IterModel
import IterPlan
import IterUI

/// What one List row of the panel is: the header card, the selector, a row of the plan, or the 24 pt gap between two cards (a
/// row of its own, so a card's background never stretches over it).
enum PanelItem: Identifiable, Equatable {
    case row(BuildRow)
    case gap(String)

    var id: String {
        switch self {
        case .row(let row): row.id
        case .gap(let id): id
        }
    }

    static func items(_ rows: [BuildRow]) -> [PanelItem] {
        var items: [PanelItem] = []
        for row in rows {
            items.append(.row(row))
            switch row.kind {
            case .footer, .transfer: items.append(.gap("gap-\(row.id)"))
            default: break
            }
        }
        return items
    }
}

/// The Trip Builder panel's list: the header card, the day selector and the day cards (with the transfer cards between them) as
/// rows of one List, so everything scrolls together. The list has NO background of its own (it sits in the system inspector;
/// the cards keep their content fills). Reordering and moving between days is drag and drop on rows (drop on a row to go before
/// it, on a day header or the Add Stop row to go to the end), plus the context menu's Move Up, Move Down and Move to Day for the
/// keyboard and VoiceOver.
///
/// Every plan row is an `Equatable` view of its own value, so a selection, a day change or a drop redraws the rows whose content
/// changed and no others. The List has no selection of its own (its highlight would paint a blue bar over the card): a click on
/// a stop selects it and the card draws the accent outline.
struct TripBuilderPanelContent: View {
    let model: BuildModel
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.tripBuilderOpensModel) private var opensModel
    @State private var drops: StopDropCoordinator

    init(model: BuildModel) {
        self.model = model
        _drops = State(initialValue: StopDropCoordinator(model: model))
    }

    private static let edge = BuilderMetrics.panelInset - BuilderMetrics.listMargin

    var body: some View {
        let selected = model.selectedStopID
        let loadingScores = !model.conditionsProgress.isComplete
        let driven = Set(model.rows.compactMap { row -> UUID? in if case .drive(let drive) = row.kind { drive.toStopID } else { nil } })
        ScrollViewReader { proxy in
            List {
                if let header = model.header {
                    BuilderHeaderView(model: model, header: header)
                        .plain(top: IterSpace.sm, bottom: BuilderMetrics.sectionGap)
                        .id("panel-header")
                    if model.dayItems.count > 1 {
                        DaySelectorRow(model: model) { day in
                            model.selectDay(day)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: -BuilderMetrics.listMargin, bottom: 0, trailing: -BuilderMetrics.listMargin))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                ForEach(PanelItem.items(model.rows)) { item in
                    switch item {
                    case .row(let row):
                        BuilderRowView(row: row, isSelected: isSelected(row, selected), loadingScores: loadingScores,
                                       hasDriveAbove: hasDriveAbove(row, driven), model: model, drops: drops)
                            .equatable()
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: Self.edge, bottom: 0, trailing: Self.edge))
                            .listRowBackground(background(row))
                    case .gap:
                        Color.clear
                            .frame(height: BuilderMetrics.sectionGap)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if model.stops.contains(where: { $0.score != nil }) {
                    BuilderSourceLine()
                        .padding(.horizontal, Self.edge)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            #if os(macOS)
            .onDeleteCommand { if let id = model.selectedStopID { model.removeStop(id) } }
            // The List has no selection of its own, so its arrow keys do nothing: handle them here. A click on a row makes the
            // table view the first responder (so the keys arrive); `.focusable()` lets Tab reach it too. A focused text field
            // (the trip name, a note) takes the arrows before they get here.
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .down: model.selectNext()
                case .up: model.selectPrevious()
                default: break
                }
            }
            #endif
            // A selected day (chosen here, or already selected when the panel opens) scrolls its header to the top.
            .onChange(of: model.selectedDay, initial: true) {
                guard let day = model.selectedDay else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation { proxy.scrollTo("header-\(day)", anchor: .top) }
                }
            }
            .onChange(of: model.selectedStopID) {
                if let id = model.selectedStopID { proxy.scrollTo("stop-\(id)") }
            }
        }
        .onAppear { if opensModel { model.open() } }
        .onDisappear { if opensModel { model.close() } }
    }

    private func hasDriveAbove(_ row: BuildRow, _ driven: Set<UUID>) -> Bool {
        if case .stop(let stop) = row.kind { return driven.contains(stop.id) }
        return false
    }

    private func isSelected(_ row: BuildRow, _ selected: UUID?) -> Bool {
        if case .stop(let stop) = row.kind { return stop.id == selected }
        return false
    }

    @ViewBuilder private func background(_ row: BuildRow) -> some View {
        if let position = row.position {
            DayCardBackground(position: position.dayCardPosition)
        } else {
            Color.clear
        }
    }
}

extension TripBuilderRowPosition {
    var dayCardPosition: DayCardPosition {
        switch self {
        case .first: .first
        case .middle: .middle
        case .last: .last
        case .only: .only
        }
    }
}

private extension View {
    /// A List row with the panel's side inset, no background or separator, and the given spacing above and below.
    func plain(top: CGFloat, bottom: CGFloat) -> some View {
        padding(.top, top)
            .padding(.bottom, bottom)
            .listRowInsets(EdgeInsets(top: 0, leading: BuilderMetrics.panelInset - BuilderMetrics.listMargin, bottom: 0,
                                      trailing: BuilderMetrics.panelInset - BuilderMetrics.listMargin))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// The day selector as a list row; it reads the selected day itself, so choosing a day redraws the selector and not the list.
private struct DaySelectorRow: View {
    let model: BuildModel
    let choose: (Int?) -> Void

    var body: some View {
        DaySelector(items: model.dayItems.map { DaySelectorItem(DaySummary(index: $0.index, date: $0.date, stopCount: $0.stopCount,
                                                                           session: $0.primarySession)) },
                    selectedDay: model.selectedDay, onSelect: choose)
            .padding(.bottom, BuilderMetrics.sectionGap - 16)
    }
}

/// The quiet footer: where the numbers come from. Full credits live in Settings.
struct BuilderSourceLine: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sun and moon times are calculated for each place. Drive times come from Apple Maps.",
                 comment: "Trip Builder footer: where times come from")
            Text("Forecast sources and credits are listed in Settings.", comment: "Trip Builder footer: where to find credits")
        }
        .font(BuilderType.caption)
        .foregroundStyle(IterColor.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

extension EnvironmentValues {
    /// Whether the panel opens its model when it appears and closes it when it goes. Off by default: the shell owns the model's
    /// lifetime (it opens on route appear and closes on route disappear), so hiding the inspector never stops the route map.
    @Entry public var tripBuilderOpensModel = false
}
