import Foundation
import IterCore
import IterFeatures
#if os(macOS)
import AppKit
#endif

/// `-IterPerfScript YES` with the trip builder open: a fixed, repeatable workload on the trip planner for performance
/// measurement. Launch with
/// `-IterInMemoryStore YES -IterSeedTrip YES -IterSection trip -IterLocation 37.0,-111.5 -IterSampleDataEnabled YES
/// -IterPerfScript YES -IterPerfQuit YES`.
///
/// It waits for the drive legs (30 s at most), then runs each interaction through `IterPerf.step` about a second apart
/// (`perf step <name> sync=<ms> settle=<ms>`): the day picker through every day and All Days twice, a selection of each
/// stop, a nudge down and back up, a drag-reorder (a drop before the first stop) and back, a move to another day and back. Counters and main-thread lag are reported after each
/// phase (`perf counts[...]`, the lag covering the work since the previous report), and it finishes with ten seconds of
/// idle, reported before and after, to show that nothing redraws or recomputes while the user does nothing.
/// `-IterPerfQuit YES` quits when it is done. Development only; nothing in the normal app path calls it.
@MainActor
enum TripPerfScript {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "IterPerfScript") }
    static var quitWhenDone: Bool { UserDefaults.standard.bool(forKey: "IterPerfQuit") }

    /// `chooseDay` and `select` are the view's own entry points (the day strip, a click on a row or pin), so the script
    /// exercises the same path as the user.
    static func run(_ builder: TripBuilderModel, chooseDay: @escaping (Int?) -> Void, select: @escaping (UUID?) -> Void,
                    moveByDrop: @escaping (UUID, Int, UUID?) -> Void) async {
        IterPerf.startLagMonitor()
        IterPerf.mark("trip.script.start")
        let start = Date()
        while Date().timeIntervalSince(start) < 30 {
            if builder.plan != nil, !builder.days.isEmpty, !builder.isLoadingLegs { break }
            await pause(0.1)
        }
        await pause(2)
        IterPerf.report("trip.loaded", resetLag: true)

        let dayIndices = builder.days.map(\.index)
        for round in 1...2 {
            for day in dayIndices {
                await IterPerf.step("trip.day \(day + 1) (round \(round))") { chooseDay(day) }
                await pause(1)
            }
            await IterPerf.step("trip.day all (round \(round))") { chooseDay(nil) }
            await pause(1)
        }
        IterPerf.report("trip.afterDays", resetLag: true)

        for entry in builder.days.flatMap(\.stops) {
            await IterPerf.step("trip.select \(entry.number)") { select(entry.id) }
            await pause(1)
        }
        await IterPerf.step("trip.deselect") { select(nil) }
        await pause(1)
        IterPerf.report("trip.afterSelect", resetLag: true)

        if let day = builder.days.first(where: { $0.stops.count >= 2 }), let moving = day.stops.first {
            await IterPerf.step("trip.nudge down") { builder.nudgeStop(moving.id, by: 1) }
            await pause(1)
            await IterPerf.step("trip.nudge up") { builder.nudgeStop(moving.id, by: -1) }
            await pause(1)
        }
        IterPerf.report("trip.afterNudge", resetLag: true)

        // A drag-reorder is a drop on the row the stop goes before: the same call the list's drop handler makes.
        if let day = builder.days.first(where: { $0.stops.count >= 2 }) {
            let first = day.stops[0].id, second = day.stops[1].id
            let after = day.stops.dropFirst(2).first?.id
            await IterPerf.step("trip.drop reorder") { moveByDrop(second, day.index, first) }
            await pause(1)
            await IterPerf.step("trip.drop restore") { moveByDrop(second, day.index, after) }
            await pause(1)
        }
        IterPerf.report("trip.afterDrop", resetLag: true)

        if let source = builder.days.first(where: { !$0.stops.isEmpty }), let other = builder.days.first(where: { $0.index != source.index }),
           let moving = source.stops.first?.stop {
            let followed = source.stops.dropFirst().first?.id
            await IterPerf.step("trip.move to day \(other.index + 1)") { builder.moveStop(moving.id, toDay: other.index) }
            await pause(1)
            await IterPerf.step("trip.move back to day \(source.index + 1)") { builder.moveStop(moving.id, toDay: source.index, before: followed) }
            await pause(1)
        }
        IterPerf.report("trip.afterMove", resetLag: true)

        IterPerf.report("trip.idle.before", resetLag: true)
        await pause(10)
        IterPerf.report("trip.idle.after", resetLag: true)
        IterPerf.mark("trip.script.end")
        #if os(macOS)
        if quitWhenDone { NSApp.terminate(nil) }
        #endif
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}
