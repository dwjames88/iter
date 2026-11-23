import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import IterFeatures
import IterModel
import IterStore
import IterUI

// Plain, testable pieces of the Trip Builder panel: what a drag carries, where a drop lands, the move arithmetic, the lazy
// export, and the debounced text fields.

// MARK: - Drag and drop

/// What a dragged stop row carries: enough to find the stop again, nothing else. Private to Iter.
struct StopDragItem: Codable, Hashable, Sendable, Transferable {
    var tripID: UUID
    var stopID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .iterStopDrag)
    }
}

extension UTType {
    /// In-app drag of a trip stop. It never leaves the app.
    static let iterStopDrag = UTType(exportedAs: "com.dwjames.iter.trip-stop")
}

/// Where a dragged stop would land.
enum StopDropSpot: Hashable, Sendable {
    /// Before this stop (a drop on a stop card, or on the drive that arrives at it).
    case before(UUID)
    /// At the end of this day (a drop on the day header or the Add Stop row).
    case endOfDay(Int)
}

/// The move arithmetic, pure so it can be tested: the model's `moveStop(_:toDay:index:)` takes the index into the
/// destination day with the moving stop already taken out.
enum StopMoves {
    /// The stops of each day in order, from the builder rows.
    static func dayStops(in rows: [BuildRow]) -> [Int: [UUID]] {
        var out: [Int: [UUID]] = [:]
        for row in rows {
            if case .stop(let stop) = row.kind { out[row.day, default: []].append(stop.id) }
        }
        return out
    }

    /// Where a stop dropped on `spot` goes, or nil when the drop changes nothing (onto itself).
    static func destination(of moving: UUID, dropping spot: StopDropSpot, dayStops: [Int: [UUID]]) -> (day: Int, index: Int?)? {
        switch spot {
        case .endOfDay(let day):
            let list = dayStops[day] ?? []
            if list.last == moving { return nil }
            return (day, nil)
        case .before(let target):
            guard target != moving else { return nil }
            for (day, list) in dayStops {
                guard let position = list.firstIndex(of: target) else { continue }
                let rest = list.filter { $0 != moving }
                let index = rest.firstIndex(of: target) ?? position
                // Dropping before the stop that already follows it changes nothing.
                if let from = list.firstIndex(of: moving), from + 1 == position { return nil }
                return (day, index)
            }
            return nil
        }
    }

    /// Move Up: the index in the day without the stop, or nil at the top.
    static func up(_ id: UUID, dayStops: [Int: [UUID]]) -> (day: Int, index: Int)? {
        for (day, list) in dayStops {
            guard let position = list.firstIndex(of: id) else { continue }
            return position > 0 ? (day, position - 1) : nil
        }
        return nil
    }

    /// Move Down: the index in the day without the stop, or nil at the bottom.
    static func down(_ id: UUID, dayStops: [Int: [UUID]]) -> (day: Int, index: Int)? {
        for (day, list) in dayStops {
            guard let position = list.firstIndex(of: id) else { continue }
            return position + 1 < list.count ? (day, position + 1) : nil
        }
        return nil
    }
}

/// The drop indicator's state. Dragging across rows changes `spot` many times a second; it is its own `@Observable` read only
/// by the indicator overlays, so only the two rows whose line flips are redrawn, never the list.
@MainActor @Observable
final class StopDropCoordinator {
    private(set) var spot: StopDropSpot?
    @ObservationIgnored let model: BuildModel

    init(model: BuildModel) { self.model = model }

    func target(_ spot: StopDropSpot, _ isTargeted: Bool) {
        if isTargeted {
            if self.spot != spot { self.spot = spot }
        } else if self.spot == spot {
            self.spot = nil
        }
    }

    func drop(_ items: [StopDragItem], on spot: StopDropSpot) -> Bool {
        self.spot = nil
        guard let item = items.first, item.tripID == model.tripID,
              let move = StopMoves.destination(of: item.stopID, dropping: spot, dayStops: StopMoves.dayStops(in: model.rows)) else { return false }
        model.moveStop(item.stopID, toDay: move.day, index: move.index)
        model.selectStop(item.stopID)
        return true
    }
}

/// The 2 pt accent line where a dropped stop will land, with a round end (the Reminders and Finder insertion mark).
struct StopDropLine: View {
    let spot: StopDropSpot
    let coordinator: StopDropCoordinator

    var body: some View {
        if coordinator.spot == spot {
            HStack(spacing: 0) {
                Circle().stroke(IterColor.accent, lineWidth: 2).frame(width: 8, height: 8)
                Rectangle().fill(IterColor.accent).frame(height: 2)
            }
            .padding(.horizontal, 12)
            .offset(y: -2)
            .allowsHitTesting(false)
            .transition(.identity)
        }
    }
}

extension View {
    /// Makes the view a drop destination for a dragged stop, with the drop line across its top (`line: false` for a row whose
    /// line the row above draws).
    func stopDrop(on spot: StopDropSpot, line: Bool = true, coordinator: StopDropCoordinator) -> some View {
        dropDestination(for: StopDragItem.self) { items, _ in
            coordinator.drop(items, on: spot)
        } isTargeted: { isTargeted in
            coordinator.target(spot, isTargeted)
        }
        .overlay(alignment: .top) { if line { StopDropLine(spot: spot, coordinator: coordinator) } }
    }
}

// MARK: - Export

/// A trip as an `.iter` file, built when the share or save is performed (never while a body is built).
struct TripExportItem: Transferable {
    var fileName: String
    var build: @MainActor @Sendable () -> Data?

    struct Unavailable: Error {}

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .iterTrip) { item in
            let data = await MainActor.run { item.build() }
            guard let data else { throw Unavailable() }
            return data
        }
        .suggestedFileName { $0.fileName }
    }
}

// MARK: - Debounced text

/// A text value edited in place and saved a moment after typing stops (and at once on Return or when focus leaves).
/// The field shows its own draft; an outside change replaces the draft only while nothing is waiting to be saved.
struct DebouncedText<Content: View>: View {
    let value: String
    let delay: Duration
    let save: (String) -> Void
    let content: (Binding<String>, @escaping () -> Void) -> Content

    @State private var draft = ""
    @State private var pending: Task<Void, Never>?

    init(value: String, delay: Duration = .seconds(1), save: @escaping (String) -> Void,
         @ViewBuilder content: @escaping (Binding<String>, @escaping () -> Void) -> Content) {
        self.value = value
        self.delay = delay
        self.save = save
        self.content = content
    }

    var body: some View {
        content(Binding(get: { draft }, set: { edited($0) }), commit)
            .onAppear { draft = value }
            .onChange(of: value) { if pending == nil { draft = value } }
            .onDisappear { commit() }
    }

    private func edited(_ text: String) {
        guard text != draft else { return }
        draft = text
        pending?.cancel()
        let delay = delay
        pending = Task { @MainActor in
            do { try await Task.sleep(for: delay) } catch { return }
            commit()
        }
    }

    private func commit() {
        pending?.cancel()
        pending = nil
        if draft != value { save(draft) }
    }
}
