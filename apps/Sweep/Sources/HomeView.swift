import SwiftUI
import SweepCore
import UIKit

/// Home: what to clean (whole library or one album), bin and totals.
struct HomeView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(SimilarScanner.self) private var scanner
    @Environment(\.m3) private var m3
    @Environment(\.openURL) private var openURL

    @State private var active: SweepSource?
    @State private var showTrash = false
    @State private var showSettings = false
    @State private var showSimilar = false
    @State private var confirmForget = false
    /// Reviewed items per source id (computed on demand, not on every swipe).
    @State private var reviewed: [String: Int] = [:]

    private struct ReloadKey: Hashable {
        let change: Int
        let filter: MediaFilter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if library.isLimited { limitedBanner }
                if model.state.trashCount > 0 { trashCard }
                filters
                libraryCard
                tools
                if model.state.deletedCount > 0 || !model.state.kept.isEmpty { stats }
                if !library.collections.isEmpty {
                    SectionTitle(title: "Raccolte")
                    albumList(library.collections)
                }
                if !library.albums.isEmpty {
                    SectionTitle(title: "I tuoi album", trailing: "\(library.albums.count)")
                    albumList(library.albums)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(m3.surface)
        .task(id: ReloadKey(change: library.changeCount, filter: model.filter)) {
            await library.reload(filter: model.filter)
            if model.filter == .all { model.prune(existing: library.libraryIDs) }
            refreshProgress()
        }
        .fullScreenCover(item: $active, onDismiss: refreshProgress) { source in
            SweepView(source: source)
        }
        .fullScreenCover(isPresented: $showSimilar, onDismiss: refreshProgress) {
            SimilarView()
        }
        .sheet(isPresented: $showTrash, onDismiss: refreshProgress) {
            TrashView()
        }
        .sheet(isPresented: $showSettings, onDismiss: refreshProgress) {
            SettingsView()
        }
        .onChange(of: model.restoreCount) { _, _ in
            refreshProgress()
        }
        .confirmationDialog("Rivedere le foto già tenute?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Rivedi tutto da capo", role: .destructive) {
                model.forgetAllKept()
                refreshProgress()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le \(SweepFormat.photos(model.state.kept.count)) che hai deciso di tenere ti verranno riproposte. Il cestino non cambia.")
        }
    }

    private func refreshProgress() {
        let state = model.state
        var result: [String: Int] = [SweepSource.library.id: state.reviewedCount(of: library.libraryIDs)]
        for album in library.collections + library.albums {
            result[album.id] = state.reviewedCount(of: album.ids)
        }
        reviewed = result
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sweep")
                    .font(.m3HeadlineLarge)
                    .foregroundStyle(m3.onSurface)
                Text("Sinistra tieni · destra elimini")
                    .font(.m3BodyMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer()
            IconButton(icon: "gearshape", label: "Impostazioni") { showSettings = true }
            Menu {
                Button {
                    showSettings = true
                } label: {
                    Label("Impostazioni e backup", systemImage: "gearshape")
                }
                Button {
                    confirmForget = true
                } label: {
                    Label("Rivedi le foto già tenute", systemImage: "arrow.counterclockwise")
                }
                .disabled(model.state.kept.isEmpty)
                Button {
                    showTrash = true
                } label: {
                    Label("Apri il cestino", systemImage: "trash")
                }
                .disabled(model.state.trashCount == 0)
                if library.isLimited {
                    Button {
                        openSettings()
                    } label: {
                        Label("Dai accesso a tutte le foto", systemImage: "photo.badge.checkmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .frame(width: 44, height: 44)
                    .background(m3.surfaceContainerHigh, in: Circle())
            }
            .accessibilityLabel("Altro")
        }
        .padding(.top, 12)
    }

    private var limitedBanner: some View {
        M3Card(color: m3.tertiaryContainer, padding: 14, corner: 22) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(m3.onTertiaryContainer)
                Text("Accesso limitato: vedi solo le foto che hai scelto.")
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onTertiaryContainer)
                Spacer(minLength: 4)
                Button("Cambia", action: openSettings)
                    .buttonStyle(.m3Text)
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    // MARK: Bin

    private var trashCard: some View {
        let count = model.state.trashCount
        return M3Card(color: m3.errorContainer, padding: 16, corner: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IconBadge(icon: "trash", tones: Tones(accent: m3.error, container: m3.error, onContainer: m3.onError), size: 48, cookie: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nel cestino")
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onErrorContainer)
                        Text("\(SweepFormat.photos(count)) da eliminare")
                            .font(.m3BodyMedium)
                            .foregroundStyle(m3.onErrorContainer.opacity(0.8))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button("Rivedi") { showTrash = true }
                        .buttonStyle(.m3Outlined)
                    Spacer()
                    Button {
                        Task { await model.emptyTrash(library: library) }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isDeleting { ProgressView().tint(m3.onError) }
                            Text("Elimina \(SweepFormat.count(count))")
                        }
                    }
                    .buttonStyle(M3ButtonStyle(kind: .dangerFilled))
                    .disabled(model.isDeleting)
                }
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    // MARK: Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MediaFilter.allCases, id: \.self) { f in
                        FilterChip(label: f.title, icon: f.icon, selected: model.filter == f) {
                            model.filter = f
                        }
                    }
                    Rectangle()
                        .fill(m3.outlineVariant)
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 4)
                    ForEach(SweepOrder.allCases, id: \.self) { o in
                        FilterChip(label: o.title, icon: o.icon, selected: model.order == o) {
                            model.order = o
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Library

    private var libraryCard: some View {
        let total = library.libraryIDs.count
        let done = min(total, reviewed[SweepSource.library.id] ?? 0)
        let left = total - done
        return Button {
            active = .library
        } label: {
            M3Card(color: m3.primaryContainer, padding: 20, corner: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        ZStack {
                            CookieShape().fill(m3.primary)
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(m3.onPrimary)
                        }
                        .frame(width: 60, height: 60)
                        Spacer()
                        if library.isLoading && !library.hasLoaded {
                            ProgressView().tint(m3.onPrimaryContainer)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.filter == .videos ? "Tutti i video" : "Tutte le foto")
                            .font(.m3HeadlineSmall)
                            .foregroundStyle(m3.onPrimaryContainer)
                        Text(library.hasLoaded ? subtitle(total: total, left: left) : "Caricamento…")
                            .font(.m3BodyMedium)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                            .contentTransition(.numericText())
                    }
                    M3Progress(value: total == 0 ? 0 : Double(done) / Double(total),
                               color: m3.primary, track: m3.primary.opacity(0.18), height: 8)
                    HStack {
                        Text(total == 0 ? "" : "\(Int((Double(done) / Double(max(total, 1)) * 100).rounded()))% fatto")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                        Spacer()
                        HStack(spacing: 8) {
                            Text(left == 0 && total > 0 ? "Rivedi" : (done > 0 ? "Continua" : "Inizia"))
                            Image(systemName: "arrow.right")
                        }
                        .font(.m3LabelLarge)
                        .foregroundStyle(m3.onPrimary)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(m3.primary, in: Capsule())
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!library.hasLoaded || total == 0)
    }

    private func subtitle(total: Int, left: Int) -> String {
        if total == 0 { return "Nessun elemento" }
        if left == 0 { return "\(SweepFormat.photos(total)) · tutte viste" }
        return "\(SweepFormat.photos(total)) · \(SweepFormat.count(left)) da vedere"
    }

    // MARK: Tools

    private var tools: some View {
        HStack(spacing: 10) {
            ToolCard(icon: "square.on.square", title: "Doppioni e simili", subtitle: similarSubtitle,
                     tones: Tones(accent: m3.tertiary, container: m3.tertiaryContainer, onContainer: m3.onTertiaryContainer)) {
                showSimilar = true
            }
            .disabled(!library.hasLoaded)
        }
    }

    private var similarSubtitle: String {
        switch scanner.phase {
        case .idle:
            return "Raffiche, copie e scatti ripetuti"
        case .scanning(let done, let total):
            return total > 0 ? "Ricerca… \(Int(Double(done) / Double(total) * 100))%" : "Ricerca…"
        case .ready:
            let count = Similarity.pending(scanner.groups, state: model.state).count
            return count == 0 ? "Nessun doppione da vedere" : "\(SweepFormat.count(count)) gruppi da vedere"
        }
    }

    // MARK: Albums

    private func albumList(_ items: [AlbumInfo]) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, album in
                AlbumRow(album: album, reviewed: reviewed[album.id] ?? 0,
                         first: index == 0, last: index == items.count - 1) {
                    active = album.source
                }
            }
        }
    }

    // MARK: Totals

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(value: SweepFormat.count(model.state.deletedCount), label: "eliminate", icon: "trash", tones: m3.delete)
            StatTile(value: SweepFormat.bytes(model.state.freedBytes), label: "liberati", icon: "internaldrive", tones: Tones(accent: m3.tertiary, container: m3.tertiaryContainer, onContainer: m3.onTertiaryContainer))
            StatTile(value: SweepFormat.count(model.state.kept.count), label: "tenute", icon: "checkmark", tones: m3.keep)
        }
    }

    private var footer: some View {
        Text("Le foto eliminate restano 30 giorni nell'album \"Eliminati di recente\" dell'app Foto.")
            .font(.m3BodySmall)
            .foregroundStyle(m3.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal, 20)
    }
}

/// One album in a grouped Material list.
struct AlbumRow: View {
    @Environment(\.m3) private var m3
    let album: AlbumInfo
    let reviewed: Int
    let first: Bool
    let last: Bool
    let action: () -> Void

    var body: some View {
        let total = album.ids.count
        let done = min(total, reviewed)
        let finished = total > 0 && done >= total
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(icon: finished ? "checkmark" : album.icon,
                          tones: finished ? m3.keep : Tones(accent: m3.primary, container: m3.secondaryContainer, onContainer: m3.onSecondaryContainer),
                          size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(album.title)
                            .font(.m3TitleSmall)
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(finished ? "Fatto" : "\(SweepFormat.count(total - done))")
                            .font(.m3LabelMedium)
                            .monospacedDigit()
                            .foregroundStyle(finished ? m3.success : m3.onSurfaceVariant)
                    }
                    M3Progress(value: total == 0 ? 0 : Double(done) / Double(total),
                               color: finished ? m3.success : m3.primary,
                               track: m3.surfaceContainerHighest, height: 4)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m3.outline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(m3.surfaceContainerLow,
                        in: UnevenRoundedRectangle(topLeadingRadius: first ? 24 : 6,
                                                   bottomLeadingRadius: last ? 24 : 6,
                                                   bottomTrailingRadius: last ? 24 : 6,
                                                   topTrailingRadius: first ? 24 : 6,
                                                   style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct StatTile: View {
    @Environment(\.m3) private var m3
    let value: String
    let label: String
    let icon: String
    let tones: Tones

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tones.onContainer)
                .frame(width: 32, height: 32)
                .background(tones.container, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.m3TitleLarge)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Shortcut to a cleaning tool (duplicates, heavy videos).
struct ToolCard: View {
    @Environment(\.m3) private var m3
    @Environment(\.isEnabled) private var isEnabled
    let icon: String
    let title: String
    let subtitle: String
    let tones: Tones
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                IconBadge(icon: icon, tones: tones, size: 44, cookie: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.m3TitleSmall)
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(2, reservesSpace: true)
                        .contentTransition(.numericText())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle())
    }
}
