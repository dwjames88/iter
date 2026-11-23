import AppKit
import Foundation
import IterFeatures

/// File ▸ Send to iPhone: writes an `.iter` v2 file and offers it to AirDrop. The file merges into the iPhone's library by id,
/// so a trip sent again updates in place.
extension WindowShell {
    func sendCurrentTripToIPhone() {
        guard case .trip(let id) = route else { return }
        do {
            guard let url = try SendFile.trip(id, from: library) else { notice = .exportFailed("That trip is no longer in your library."); return }
            offerToAirDrop(url)
        } catch {
            notice = .exportFailed(error.localizedDescription)
        }
    }

    func sendLibraryToIPhone() {
        do { offerToAirDrop(try SendFile.library(library)) } catch { notice = .exportFailed(error.localizedDescription) }
    }

    private func offerToAirDrop(_ url: URL) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [url]) else {
            notice = .exportFailed("AirDrop isn't available on this Mac right now. Use Export instead and move the file yourself.")
            return
        }
        service.perform(withItems: [url])
    }
}
