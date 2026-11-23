import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

// OWNER: W3 (screens). The Find tab: the map behind the sheet and the sheet's root.

/// The map behind the sheet for the Find tab: pins, your own spots (touch and hold to move), Add Spot, Search Here, all inset above
/// the sheet.
struct FindTabMap: View {
    let shell: IOSShell
    var body: some View {
        FindPhoneMap(model: shell.find, bottomInset: shell.mapBottomInset)
            .iterShellEnvironment(shell)
            .ignoresSafeArea()
    }
}

/// The Find tab's root inside the sheet (the shell wraps it in `NavigationStack(path: $shell.findPath)`): the search field at the
/// top, as in Maps, then what Find's card holds on the Mac.
struct FindTabRoot: View {
    let shell: IOSShell

    var body: some View {
        @Bindable var find = shell.find
        FindTabContent(shell: shell)
            .searchable(text: $find.text, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search places or ask Iter", comment: "Find search field prompt"))
            .onSubmit(of: .search) { find.submit() }
            .navigationTitle("Find")
            .navigationBarTitleDisplayMode(.inline)
            .iterShellEnvironment(shell)
    }
}

private struct FindTabContent: View {
    let shell: IOSShell
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        let find = shell.find
        VStack(spacing: 0) {
            FindAddTargetBanner(shell: shell)
            FindSheetContent(model: find, makeConditions: shell.makeConditions)
        }
        // Typing needs room: a field tapped at peek opens the sheet fully.
        .onChange(of: isSearching) { _, searching in if searching { shell.detent = PhoneSheet.full } }
        // A search that starts, and a place picked on the map or in the list, need more than the peek.
        .onChange(of: find.phase) { _, phase in
            switch phase {
            case .discovering, .lookingUp:
                dismissSearch()
                if shell.detent == PhoneSheet.peek { shell.detent = PhoneSheet.half }
            default: break
            }
        }
        .onChange(of: find.card?.id) { _, id in
            if id != nil, shell.detent == PhoneSheet.peek { shell.detent = PhoneSheet.half }
        }
    }
}

/// "Adding to Alberta Road Trip · Day 2": shown after Add Stop in the Trip Builder sent the user here. Add puts the place on the
/// card into that trip and day; Done goes back to the trip.
struct FindAddTargetBanner: View {
    let shell: IOSShell
    private var target: FindAddTarget { FindAddTarget.shared }

    var body: some View {
        if let id = target.tripID, let trip = shell.library.tripRow(id: id) {
            HStack(spacing: IterSpace.md) {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text("Adding to \(trip.name)", comment: "Find: the trip places are added to")
                        .font(IterFont.bodyEmphasis).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    Text(subtitle).font(IterFont.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                }
                Spacer(minLength: IterSpace.sm)
                if shell.find.card != nil {
                    Button { add(id) } label: { Text("Add", comment: "Button: add the place to the trip").frame(minWidth: 44, minHeight: 32) }
                        .buttonStyle(.bordered)
                }
                Button { done(id) } label: { Text("Done", comment: "Button: back to the trip").frame(minWidth: 44, minHeight: 32) }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, IterSpace.lg)
            .padding(.vertical, IterSpace.sm)
        }
    }

    private var subtitle: String {
        if let added = target.lastAdded { return String(localized: "Added \(added) on Day \(target.day + 1)", comment: "Find add target: confirmation") }
        return String(localized: "Day \(target.day + 1). Pick a place, then Add.", comment: "Find add target: instruction")
    }

    private func add(_ tripID: UUID) {
        guard let name = shell.find.card?.name else { return }
        if shell.find.addToTrip(tripID, day: target.day) { target.lastAdded = name }
    }

    private func done(_ tripID: UUID) {
        target.clear()
        shell.tripsPath = [.trip(tripID)]
        shell.tab = .trips
    }
}
