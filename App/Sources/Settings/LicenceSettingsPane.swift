import SwiftUI
import IterDesign
import IterLicensing

/// Settings ▸ Licence on the Mac, and the pushed Licence page on iPhone and iPad. Hidden unless the app was launched
/// with `-IterShowLicensing YES` (see `AppLaunch.showLicensing`). The words and the state live in
/// `LicenceSettingsModel`; this view only lays them out.
struct LicenceSettingsPane: View {
    @State private var model = LicenceSettingsModel.live(suggestedName: LicenceSettingsPane.suggestedName, isolated: AppLaunch.isRenderCopy)
    @State private var confirmingDeactivate = false

    var body: some View {
        Form {
            if model.maskedKey != nil {
                statusSection
                detailsSection
                actionsSection
            } else {
                if model.state == .expired || model.state == .revoked { problemSection }
                enterKeySection
            }
            if let message = model.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(IterColor.danger)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isBusy)
        .task { await model.refresh() }
        .confirmationDialog(
            deactivateTitle, isPresented: $confirmingDeactivate, titleVisibility: .visible
        ) {
            Button(role: .destructive) { Task { await model.deactivate() } } label: {
                Text(deactivateTitle)
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Button") }
        } message: {
            Text("This frees one of your activations so you can use the key on another device. Iter keeps working here; you can activate this one again later.",
                 comment: "Licence: confirmation for deactivating this device")
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            LabeledContent {
                Text(model.statusTitle)
            } label: { Text("Status", comment: "Licence row") }
            if let email = model.email {
                LabeledContent {
                    Text(email).textSelection(.enabled)
                } label: { Text("Licensed to", comment: "Licence row: the buyer's email") }
            }
            if let date = model.activatedAt {
                LabeledContent {
                    Text(LicenceText.dateText(date))
                } label: { Text("Activated", comment: "Licence row: the date this device was activated") }
            }
            if let detail = model.statusDetail, model.email == nil || !model.isLicensed {
                Text(detail).foregroundStyle(IterColor.textSecondary)
            }
        }
    }

    private var detailsSection: some View {
        Section {
            if let key = model.maskedKey {
                LabeledContent {
                    Text(key).font(.body.monospaced()).textSelection(.enabled)
                } label: { Text("Key", comment: "Licence row: the masked licence key") }
            }
            if let name = model.instanceName {
                LabeledContent {
                    Text(name)
                } label: { Text(Self.deviceNameLabel) }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button { Task { await model.validate() } } label: { Text("Check Now", comment: "Button: asks the licence server whether the key is still good") }
            Button(role: .destructive) { confirmingDeactivate = true } label: { Text(deactivateTitle) }
            if model.isBusy { busyRow }
        } footer: { explanation }
    }

    private var problemSection: some View {
        Section {
            Label(model.statusTitle, systemImage: "exclamationmark.circle")
            if let detail = model.statusDetail { Text(detail).foregroundStyle(IterColor.textSecondary) }
        }
    }

    private var enterKeySection: some View {
        Section {
            TextField(text: Bindable(model).keyInput, prompt: Text(verbatim: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")) {
                Text("Licence key", comment: "Licence field")
            }
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            #endif
            .onSubmit { activate() }
            TextField(text: Bindable(model).nameInput) { Text(Self.deviceNameLabel) }
            Button { activate() } label: { Text("Activate", comment: "Button: uses the licence key on this device") }
                .disabled(!model.canActivate)
            if model.isBusy { busyRow }
        } footer: { explanation }
    }

    private var busyRow: some View {
        HStack(spacing: IterSpace.sm) {
            ProgressView().controlSize(.small)
            Text("Contacting the licence server…", comment: "Licence: shown while a request is running")
                .foregroundStyle(IterColor.textSecondary)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            Text("Iter is free while it's in preview. A licence key is for the signed release.", comment: "Licence footer")
            Link(destination: LicenceSetup.activateURL) {
                Text("Where's my key?", comment: "Licence: link to the site's activation page")
            }
        }
    }

    private func activate() {
        guard model.canActivate else { return }
        Task { await model.activate() }
    }

    // MARK: Platform words

    private var deactivateTitle: String {
        #if os(macOS)
        String(localized: "Deactivate This Mac…", comment: "Button: frees this Mac's licence activation")
        #else
        String(localized: "Deactivate This Device…", comment: "Button: frees this device's licence activation")
        #endif
    }

    private static var deviceNameLabel: LocalizedStringResource {
        #if os(macOS)
        LocalizedStringResource("This Mac's name", comment: "Licence field: the name this Mac is activated under")
        #else
        LocalizedStringResource("This device's name", comment: "Licence field: the name this device is activated under")
        #endif
    }

    private static var suggestedName: String {
        #if os(macOS)
        LicenceSettingsModel.accountName()
        #else
        UIDevice.current.name
        #endif
    }
}
