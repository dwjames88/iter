import Foundation
import IterModel
import IterSources

// Real drive times for the top results. Discovered places have no facing and the engine only knows straight-line distance,
// so after a run finishes the router (`RoutingProvider.eta`, departing now) is asked for the top few visible results, one or
// two at a time. Each row says "straight-line" until its answer arrives, then "drive". A new run or a cancel stops it.

extension FindModel {
    func cancelDriveTimes() {
        driveGeneration += 1
        driveTask?.cancel()
        driveTask = nil
        if !fetchingDrive.isEmpty {
            let ids = fetchingDrive
            fetchingDrive = []
            for id in ids { refreshRow(id) }
        }
    }

    /// Asks for the drive time of up to `driveTimeCount` visible results that have none yet (the selected result first).
    func startDriveTimes() {
        driveTask?.cancel()
        driveGeneration += 1
        let mine = driveGeneration
        guard let origin = location.current, configuration.driveTimeCount > 0 else { return }
        var ids = rows.prefix(configuration.driveTimeCount).map(\.id)
        if let selectedID, rows.contains(where: { $0.id == selectedID }), !ids.contains(selectedID) { ids.insert(selectedID, at: 0) }
        let targets: [(String, Coordinate)] = ids.compactMap { id in
            guard driveSeconds[id] == nil, !driveFailed.contains(id), let row = rows.first(where: { $0.id == id }) else { return nil }
            return (id, row.coordinate)
        }
        guard !targets.isEmpty else { return }
        for (id, _) in targets { fetchingDrive.insert(id) }
        for (id, _) in targets { refreshRow(id) }
        let routing = self.routing
        let departing = now()
        let width = configuration.driveTimeConcurrency
        driveTask = Task { [weak self] in
            await withTaskGroup(of: (String, TimeInterval?).self) { group in
                var next = 0
                func launch() {
                    guard next < targets.count else { return }
                    let (id, destination) = targets[next]
                    next += 1
                    group.addTask {
                        guard !Task.isCancelled else { return (id, nil) }
                        let eta = try? await routing.eta(from: origin, to: destination, departing: departing)
                        return (id, eta?.seconds)
                    }
                }
                for _ in 0..<min(width, targets.count) { launch() }
                for await (id, seconds) in group {
                    guard let self, self.driveGeneration == mine, !Task.isCancelled else { group.cancelAll(); return }
                    self.fetchingDrive.remove(id)
                    if let seconds, seconds > 0 { self.driveSeconds[id] = seconds } else { self.driveFailed.insert(id) }
                    self.refreshRow(id)
                    self.refreshCardDrive(id)
                    launch()
                }
            }
        }
    }
}
