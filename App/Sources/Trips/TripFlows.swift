import SwiftUI
import UniformTypeIdentifiers
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Opens the New Trip sheet, optionally with a template chosen. Provided by `.tripFlows()` to everything inside it.
struct PresentNewTrip {
    var present: (_ templateID: String?) -> Void = { _ in }
    func callAsFunction(template: String? = nil) { present(template) }
}

extension EnvironmentValues {
    @Entry var presentNewTrip = PresentNewTrip()
}

/// The menu's "New Trip" and "Import Trip…" requests count up in `AppNavigation`. A request can arrive just before
/// the trips screen appears (the menu switches section and counts in one go), so what has been handled is
/// remembered per window here rather than in the view.
@MainActor
private enum HandledRequests {
    static var counts: [ObjectIdentifier: (newTrip: Int, importTrip: Int)] = [:]
}

private struct NewTripPresentation: Identifiable {
    let id = UUID()
    var templateID: String?
}

private struct TripFlowsModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    @State private var newTrip: NewTripPresentation?
    @State private var showsImporter = false
    @State private var importFailure: TripImportFailure?

    func body(content: Content) -> some View {
        content
            .environment(\.presentNewTrip, PresentNewTrip { template in newTrip = NewTripPresentation(templateID: template) })
            .onAppear(perform: consumeRequests)
            .onChange(of: navigation.newTripRequest) { consumeRequests() }
            .onChange(of: navigation.importRequest) { consumeRequests() }
            .sheet(item: $newTrip) { presentation in
                NewTripSheet(initialStart: model.today(in: .current).adding(days: 1), initialTemplate: presentation.templateID)
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.iterTrip, .json]) { result in
                switch result {
                case .success(let url): importTrip(from: url)
                case .failure: importFailure = .unreadable
                }
            }
            .alert(Text("Couldn't Import Trip", comment: "Alert title"), isPresented: Binding(
                get: { importFailure != nil }, set: { if !$0 { importFailure = nil } })) {
                Button(String(localized: "OK", comment: "Alert button")) { importFailure = nil }
            } message: {
                if let importFailure { Text(Self.message(for: importFailure)) }
            }
    }

    private func consumeRequests() {
        let key = ObjectIdentifier(navigation)
        var handled = HandledRequests.counts[key] ?? (0, 0)
        if navigation.newTripRequest != handled.newTrip {
            handled.newTrip = navigation.newTripRequest
            newTrip = NewTripPresentation(templateID: nil)
        }
        if navigation.importRequest != handled.importTrip {
            handled.importTrip = navigation.importRequest
            showsImporter = true
        }
        HandledRequests.counts[key] = handled
    }

    private func importTrip(from url: URL) {
        let home = TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
        switch home.importTrip(contentsOf: url) {
        case .success(let id): navigation.show(.trip(id))
        case .failure(let failure): importFailure = failure
        }
    }

    static func message(for failure: TripImportFailure) -> String {
        switch failure {
        case .corrupt:
            String(localized: "This file isn't an Iter trip, or it is damaged. Nothing was imported.", comment: "Import error")
        case .unsupportedVersion(let version):
            String(localized: "This trip was saved by a newer version of Iter (file format \(version)). Update Iter to open it. Nothing was imported.", comment: "Import error")
        case .unreadable:
            String(localized: "Iter couldn't read that file. Nothing was imported.", comment: "Import error")
        }
    }
}

extension View {
    /// New Trip sheet and Import Trip file picker, driven by the menu commands and by `presentNewTrip`.
    func tripFlows() -> some View { modifier(TripFlowsModifier()) }
}
