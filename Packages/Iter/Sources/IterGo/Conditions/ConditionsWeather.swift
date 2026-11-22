import Foundation
import IterModel
import IterSources
import IterConditions

public enum ConditionsWeather {
    /// Current weather at a place: the nearest observation when there is one, else the current forecast hour (labelled).
    public static func info(from live: LiveConditions, subject: GoWeatherInfo.Subject) -> GoWeatherInfo? {
        if let obs = live.current {
            let c = obs.conditions
            return GoWeatherInfo(subject: subject, basis: .observation, tempC: c.tempC, cloudTotal: c.cloudTotal, visibilityKm: c.visibilityKm,
                                 precipChance: c.precipChance, windMs: c.windMs, stationName: obs.stationName,
                                 stationDistanceKm: obs.distanceKm, asOf: live.generatedAt.addingTimeInterval(-obs.age))
        }
        if let c = live.currentForecastHour {
            return GoWeatherInfo(subject: subject, basis: .forecast, tempC: c.tempC, cloudTotal: c.cloudTotal, visibilityKm: c.visibilityKm,
                                 precipChance: c.precipChance, windMs: c.windMs, stationName: nil, stationDistanceKm: nil,
                                 asOf: live.generatedAt)
        }
        return nil
    }

    /// Alerts in force at `now` (not yet ended or expired), most severe first.
    public static func alerts(from report: SkyReport?, now: Date) -> [GoAlertInfo] {
        guard let list = report?.alerts.value else { return [] }
        func rank(_ s: WeatherAlert.Severity) -> Int {
            switch s { case .extreme: 0; case .severe: 1; case .moderate: 2; case .minor: 3; case .unknown: 4 }
        }
        return list
            .filter { a in
                guard let end = a.ends ?? a.expires else { return true }
                return end > now
            }
            .sorted { rank($0.severity) < rank($1.severity) }
            .map { GoAlertInfo(id: $0.id, event: $0.event, headline: $0.headline, severity: $0.severity.rawValue.capitalized,
                               ends: $0.ends ?? $0.expires) }
    }

    /// True when any part of the answer says it could not be fetched for lack of a connection.
    public static func isOffline(live: [LiveConditions], reports: [SkyReport]) -> Bool {
        func offline(_ reasons: [NoDataReason]) -> Bool {
            reasons.contains { if case .offline = $0 { true } else { false } }
        }
        for l in live where offline(l.nowcast.reasons) || offline(l.observations.reasons) || l.forecastOfflineNote != nil { return true }
        for r in reports where r.offlineNote != nil || offline(r.forecast.reasons) || offline(r.observations.reasons) { return true }
        return false
    }
}
