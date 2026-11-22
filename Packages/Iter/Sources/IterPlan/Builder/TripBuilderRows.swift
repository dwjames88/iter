import Foundation
import IterModel
import IterSky

/// Where a row sits inside its day's card.
public enum TripBuilderRowPosition: Sendable, Equatable {
    case first, middle, last, only

    public var roundsTop: Bool { self == .first || self == .only }
    public var roundsBottom: Bool { self == .last || self == .only }
}

/// One row of the redesigned Trip Builder list: day cards with inline drives, and transfer cards between them.
public struct TripBuilderRow: Identifiable, Equatable, Sendable {
    public typealias Position = TripBuilderRowPosition

    public enum Kind: Equatable, Sendable {
        case dayHeader(TripDayGroup)
        case suggestion(OrderingSuggestion)
        case conflicts(Int)
        case stop(TripStopEntry)
        /// A drive between two stops of the same day, inside the card.
        case drive(TripDriveItem)
        /// "Add Stop", and the overnight note when it is not shown in a transfer card.
        case footer(day: Int, overnight: OvernightBoundary?)
        /// The card between two days: the drive from the previous day's last stop into this day's first, and the overnight.
        case transfer(drive: TripDriveItem?, overnight: OvernightBoundary?)
    }

    public var id: String
    public var day: Int
    public var kind: Kind
    /// nil for rows outside a day card (transfers).
    public var position: Position?

    public init(id: String, day: Int, kind: Kind, position: Position? = nil) {
        self.id = id
        self.day = day
        self.kind = kind
        self.position = position
    }

    public static func make(_ layout: TripDayLayout) -> [TripBuilderRow] {
        var rows: [TripBuilderRow] = []
        for (offset, group) in layout.groups.enumerated() {
            let day = group.index
            var driveIn: TripDriveItem?
            var inside: [TripBuilderRow] = [TripBuilderRow(id: "header-\(day)", day: day, kind: .dayHeader(group))]
            if let suggestion = group.suggestion {
                inside.append(TripBuilderRow(id: "suggestion-\(day)", day: day, kind: .suggestion(suggestion)))
            }
            if group.hasConflict {
                inside.append(TripBuilderRow(id: "conflicts-\(day)", day: day, kind: .conflicts(group.conflictCount)))
            }
            for item in group.items {
                switch item {
                case .driveIn(let drive): driveIn = drive
                case .stop(let entry): inside.append(TripBuilderRow(id: item.id, day: day, kind: .stop(entry)))
                case .drive(let drive): inside.append(TripBuilderRow(id: item.id, day: day, kind: .drive(drive)))
                case .addStop: break
                }
            }
            // The overnight of the previous day shows in this day's transfer card when there is one.
            if let driveIn {
                let previous = offset > 0 ? layout.groups[offset - 1] : nil
                rows.append(TripBuilderRow(id: "transfer-\(day)", day: day,
                                           kind: .transfer(drive: driveIn, overnight: previous?.overnightAfter)))
            }
            let nextHasDriveIn = offset + 1 < layout.groups.count
                && layout.groups[offset + 1].items.contains { if case .driveIn = $0 { true } else { false } }
            inside.append(TripBuilderRow(id: "addStop-\(day)", day: day,
                                         kind: .footer(day: day, overnight: nextHasDriveIn ? nil : group.overnightAfter)))
            for (index, var row) in inside.enumerated() {
                row.position = inside.count == 1 ? .only : index == 0 ? .first : index == inside.count - 1 ? .last : .middle
                rows.append(row)
            }
        }
        return rows
    }
}

/// The part of the day a moment falls in, for sentences like "Drive to the next area in the morning".
public enum DayPart: Sendable, Equatable {
    case earlyMorning, morning, afternoon, evening, night

    /// 00:00-04:59 early morning, 05:00-11:59 morning, 12:00-16:59 afternoon, 17:00-20:59 evening, 21:00-23:59 night.
    public static func of(_ date: Date, in zone: TimeZone) -> DayPart {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        switch calendar.component(.hour, from: date) {
        case 0..<5: return .earlyMorning
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

/// One card of the day selector.
public struct TripDaySummary: Equatable, Sendable, Identifiable {
    public var index: Int
    public var date: LocalDay
    public var stopCount: Int
    /// The kind of the day's best window, else the first stop's session; nil with no stops.
    public var primarySession: LightWindowKind?
    public var hasConflict: Bool

    public var id: Int { index }

    public static func make(_ layout: TripDayLayout) -> [TripDaySummary] {
        layout.groups.map { group in
            TripDaySummary(index: group.index, date: group.date, stopCount: group.stopCount,
                           primarySession: group.bestWindow?.window.kind ?? group.stops.first?.stop.session,
                           hasConflict: group.hasConflict)
        }
    }
}

extension TripDayLayout {
    public var daySummaries: [TripDaySummary] { TripDaySummary.make(self) }
}
