import Foundation
import Observation
import SweepCore

/// App state: decisions taken so far, preferences and the bin.
@Observable
@MainActor
final class AppModel {
    private(set) var state: SweepState
    var filter: MediaFilter {
        didSet { UserDefaults.standard.set(filter.rawValue, forKey: Keys.filter) }
    }
    var order: SweepOrder {
        didSet { UserDefaults.standard.set(order.rawValue, forKey: Keys.order) }
    }
    private(set) var isDeleting = false
    /// Short message shown as a snackbar (deletion done, errors…).
    var toast: String?

    @ObservationIgnored private let store: JSONFileStore<SweepState>
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private enum Keys {
        static let filter = "sweep.filter"
        static let order = "sweep.order"
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        store = JSONFileStore(url: base.appendingPathComponent("Sweep", isDirectory: true).appendingPathComponent("state.json"))
        state = (try? store.load()) ?? SweepState()
        filter = MediaFilter(rawValue: UserDefaults.standard.string(forKey: Keys.filter) ?? "") ?? .all
        order = SweepOrder(rawValue: UserDefaults.standard.string(forKey: Keys.order) ?? "") ?? .newestFirst
    }

    // MARK: Decisions

    func apply(_ decision: Decision, to id: String) {
        state.apply(decision, to: id)
        scheduleSave()
    }

    func revert(_ id: String) {
        state.revert(id)
        scheduleSave()
    }

    /// Takes photos out of the bin and keeps them.
    func keep(_ ids: [String]) {
        state.keep(ids)
        scheduleSave()
    }

    /// Takes photos out of the bin; they will be proposed again.
    func restore(_ ids: [String]) {
        state.restore(ids)
        scheduleSave()
    }

    /// "Review again" for one album.
    func forget(_ ids: [String]) {
        state.forget(ids)
        scheduleSave()
    }

    func forgetAllKept() {
        state.forgetAllKept()
        scheduleSave()
    }

    /// Drops remembered ids that are no longer in the library.
    func prune(existing: [String]) {
        guard !existing.isEmpty else { return }
        let before = state
        state.prune(existing: Set(existing))
        if state != before { scheduleSave() }
    }

    // MARK: Deletion

    /// Deletes the given items from the library (one iOS confirmation for all).
    func deleteFromLibrary(_ ids: [String], library: PhotoLibrary) async {
        guard !ids.isEmpty, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let result = try await library.delete(ids: ids)
            state.restore(result.missing)
            state.commitDeletion(of: result.deleted, bytes: result.bytes)
            saveNow()
            if result.deleted.isEmpty {
                showToast("Queste foto non c'erano più nella libreria.")
            } else {
                let what = SweepFormat.photos(result.deleted.count)
                let freed = result.bytes > 0 ? " · \(SweepFormat.bytes(result.bytes)) liberati" : ""
                showToast("Eliminate \(what)\(freed). Restano 30 giorni in \"Eliminati di recente\".")
            }
        } catch {
            if !PhotoLibrary.isUserCancel(error) {
                showToast("Eliminazione non riuscita: \(error.localizedDescription)")
            }
        }
    }

    func emptyTrash(library: PhotoLibrary) async {
        await deleteFromLibrary(state.trash, library: library)
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toast = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: Persistence

    /// Saves shortly after the last change, off the main thread, so that
    /// fast swiping never waits for the disk.
    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = state
        let store = self.store
        pendingSave = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            try? store.save(snapshot)
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        try? store.save(state)
    }
}
