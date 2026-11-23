import Foundation
import IterConditions
import IterModel
import IterSky
import IterSources

// Conditions for the trip's stops: what is asked for and in which order, the scores the rows keep while a better forecast
// loads, honest progress, and the offline pack of a pinned trip.

extension BuildModel {
    // MARK: Requests

    /// The (place, day) slots in the order they should load: the selected day's stops first at on-screen priority, then the next
    /// days, then the days before it, in date order. A slot two stops share is listed once.
    func orderedRequests() -> [(place: Place, day: LocalDay, priority: ConditionsPriority)] {
        let count = currentDays.count
        let focus = min(max(selectedDay ?? 0, 0), max(0, count - 1))
        let order = Array(focus..<count) + Array(0..<focus)
        var seen = Set<SlotKey>()
        var out: [(Place, LocalDay, ConditionsPriority)] = []
        for index in order {
            let (day, places) = currentDays[index]
            for place in places where seen.insert(SlotKey(placeID: place.id, day: day)).inserted {
                out.append((place, day, index == focus ? .onScreen : .activeTrip))
            }
        }
        return out
    }

    /// The places whose stops are on screen: the selected day's (the first day's with none selected).
    func visiblePlaceIDs() -> Set<UUID> {
        guard !currentDays.isEmpty else { return [] }
        let focus = min(max(selectedDay ?? 0, 0), currentDays.count - 1)
        return Set(currentDays[focus].places.map(\.id))
    }

    /// Tells Conditions which places matter and asks for every slot not asked for yet (only the new ones after an edit).
    func syncConditions() {
        guard isOpen else { return }
        conditions.setActiveTrip(Set(currentPlaces.map(\.id)))
        conditions.setVisible(visiblePlaceIDs())
        for request in orderedRequests() where requested.insert(SlotKey(placeID: request.place.id, day: request.day)).inserted {
            conditions.request(request.place, day: request.day, priority: request.priority)
        }
    }

    // MARK: Scores kept

    /// Takes what Conditions has for every stop's slot. A score is kept while a better forecast loads: a lower tier never
    /// replaces a higher one, and an incomplete report that lacks a window keeps the earlier score for it. Returns whether
    /// anything changed.
    func updateKept() -> Bool {
        guard let record = library.trips.trip(id: tripID) else { return false }
        var changed = false
        var seen = Set<SlotKey>()
        for stop in record.orderedStops {
            guard let place = stop.place else { continue }
            let key = SlotKey(placeID: place.id, day: record.startDay.adding(days: stop.dayIndex))
            guard seen.insert(key).inserted else { continue }
            let sample = conditions.sample(placeID: key.placeID, day: key.day)
            guard let tier = sample.tier else { continue }
            let old = kept[key]
            if let old, tier < old.tier { continue }
            var scores = sample.scores
            if let old, tier != .complete { scores = old.scores.merging(sample.scores) { _, new in new } }
            let next = KeptSample(tier: tier, scores: scores, pending: sample.pendingSources)
            if next != old { kept[key] = next; changed = true }
        }
        return changed
    }

    // MARK: Progress

    func progress(for trip: Trip) -> BuildConditionsProgress {
        var progress = BuildConditionsProgress(totalStops: trip.stops.count)
        for stop in trip.stops {
            guard let sample = kept[SlotKey(placeID: stop.place.id, day: trip.day(stop.dayIndex))] else {
                progress.waitingStops += 1
                continue
            }
            if sample.tier == .complete {
                progress.readyStops += 1
            } else {
                progress.improvingStops += 1
                for name in Set(sample.pending.map(Self.sourceName)) { progress.pendingBySource[name, default: 0] += 1 }
            }
        }
        return progress
    }

    static func sourceName(_ id: SourceID) -> String {
        if id.rawValue.hasPrefix("noaa") { return "NOAA" }
        if id == .metNorway { return "MET Norway" }
        return id.rawValue
    }

    // MARK: Offline pack

    /// Builds the pack of a pinned trip: when the trip is pinned and open, on open (unless the stored pack is fresh) and again
    /// after an edit changes which stops or days it holds. Never for an unpinned trip.
    func refreshPackIfNeeded(onOpen: Bool) {
        guard isOpen, let packs, let trip, trip.isPinned else {
            if trip?.isPinned != true, packTask == nil { publish(\.packState, .none) }
            return
        }
        let signature = packSignature(trip)
        if onOpen {
            packSignatureBuilt = nil
        } else if signature == packSignatureBuilt {
            return
        }
        guard packTask == nil else { packDirty = true; return }
        let freshness = timing.packFreshness
        let current = now()
        let tripID = trip.id
        publish(\.packState, .building)
        packTask = Task { [weak self] in
            if onOpen, let builtAt = await packs.packBuiltAt(tripID: tripID), current.timeIntervalSince(builtAt) < freshness {
                guard let self, !Task.isCancelled else { return }
                self.packFinished(.ready(builtAt: builtAt), signature: signature)
                return
            }
            let latest = self?.trip ?? trip
            do {
                let builtAt = try await packs.buildOfflinePack(for: latest)
                guard let self, !Task.isCancelled else { return }
                self.packFinished(.ready(builtAt: builtAt), signature: self.packSignature(latest))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.packFinished(.failed, signature: nil)
            }
        }
    }

    private func packFinished(_ state: BuildPackState, signature: [String]?) {
        packTask = nil
        packSignatureBuilt = signature
        publish(\.packState, state)
        if packDirty {
            packDirty = false
            refreshPackIfNeeded(onOpen: false)
        }
    }

    /// What a pack holds: each stop's place and day. Changes when stops are added, removed, moved to another day, or the
    /// dates change.
    func packSignature(_ trip: Trip) -> [String] {
        trip.stops.map { "\($0.place.id.uuidString)|\(trip.day($0.dayIndex).iso)" }.sorted()
    }
}
