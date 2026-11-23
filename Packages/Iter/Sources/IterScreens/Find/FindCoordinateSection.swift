import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import IterFeatures
import IterModel
import IterUI

/// The coordinates of one of your own spots: Latitude and Longitude fields, Paste Coordinates, Adjust Location, and the same
/// point as MGRS and magnetic declination with where each came from in a quiet source line.
///
/// Typing waits for Return or leaving the field (so a spot is not moved, and no undo step made, on every keystroke). An
/// out-of-range value shows its problem and moves nothing.
struct FindCoordinateSection: View {
    @Bindable var model: FindModel
    let placeID: UUID
    let coordinate: Coordinate
    let elevationMeters: Double?
    @State private var readout: PositionReadout
    private enum Field { case latitude, longitude }
    @FocusState private var focused: Field?

    init(model: FindModel, placeID: UUID, coordinate: Coordinate, elevationMeters: Double?) {
        self.model = model
        self.placeID = placeID
        self.coordinate = coordinate
        self.elevationMeters = elevationMeters
        _readout = State(initialValue: model.spots.readout(for: coordinate, elevationMeters: elevationMeters))
    }

    private var spots: OwnSpotEditor { model.spots }

    var body: some View {
        let fields = Bindable(spots)
        VStack(alignment: .leading, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                field("Latitude", text: fields.fields.latitudeText, problem: spots.fields.latitudeProblem, focus: .latitude)
                Divider()
                field("Longitude", text: fields.fields.longitudeText, problem: spots.fields.longitudeProblem, focus: .longitude)
            }
            HStack(spacing: IterSpace.sm) {
                Button { paste() } label: { Label("Paste Coordinates", systemImage: "doc.on.clipboard") }
                    .help("Paste a latitude and longitude, or an Apple Maps link")
                Button { _ = spots.beginAdjusting(placeID) } label: { Label("Adjust Location", systemImage: "scope") }
                    .help("Pan the map under a crosshair to place this spot")
            }
            .controlSize(.small)
            if spots.fields.pasteFailed {
                Text("No coordinates found on the clipboard.").font(IterFont.caption).foregroundStyle(IterColor.danger)
            }
            Divider()
            readoutRows
        }
        .padding(IterSpace.md)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .onChange(of: coordinate) { _, new in
            readout = spots.readout(for: new, elevationMeters: elevationMeters)
            if spots.fields.coordinate != new { spots.editFields(for: placeID) }
        }
        .onAppear { spots.editFields(for: placeID) }
        .onChange(of: placeID) { _, new in spots.editFields(for: new) }
        .onChange(of: focused) { old, new in if old != nil, new != old { commit() } }
    }

    @ViewBuilder private var readoutRows: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            if let mgrs = readout.mgrs { fact("MGRS", mgrs) }
            if let declination = readout.declinationText { fact("Declination", declination) }
            let sources = FindText.readoutSources(readout)
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    ForEach(sources, id: \.self) { Text(verbatim: $0) }
                }
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title).foregroundStyle(IterColor.textSecondary)
            Spacer(minLength: IterSpace.sm)
            Text(verbatim: value).monospacedDigit().textSelection(.enabled)
        }
        .font(IterFont.body)
    }

    private func field(_ title: String, text: Binding<String>, problem: String?, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            LabeledContent {
                TextField(text: text, prompt: Text(verbatim: "0.0")) { Text(verbatim: title) }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: focus)
                    .onSubmit { commit() }
                    .monospacedDigit()
            } label: {
                Text(verbatim: title).foregroundStyle(IterColor.textSecondary)
            }
            .font(IterFont.body)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.danger)
            }
        }
    }

    private func commit() {
        guard spots.fields.coordinate != nil, spots.applyFields() else { return }
        model.didMoveSpot(placeID)
    }

    private func paste() {
        #if canImport(AppKit)
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #else
        let text = UIPasteboard.general.string ?? ""
        #endif
        if spots.pasteCoordinates(text) { commit() }
    }
}
