import SwiftUI
import SweepCore

/// Restore from iCloud Drive: list of backups, preview, confirm.
/// Also shown at first launch when the app is empty and a backup exists.
struct CloudRestoreView: View {
    let firstLaunch: Bool

    @Environment(CloudBackupService.self) private var cloud
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss

    @State private var choice: CloudBackupPlan.Entry?
    @State private var preview: BackupFile?
    @State private var loading = false
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if firstLaunch {
                        HeroMessage(icon: "icloud.and.arrow.down", title: "Bentornato!",
                                    message: "In iCloud Drive c'è un backup di Sweep. Vuoi ritrovare le foto già viste, il cestino e le tue impostazioni?")
                            .padding(.vertical, 12)
                    }

                    SectionTitle(title: "iCloud Drive › Backup › Sweep")
                    if cloud.entries.isEmpty {
                        M3Card {
                            HStack(spacing: 12) {
                                if cloud.available == nil { ProgressView() }
                                Text(cloud.available == false ? "iCloud Drive non disponibile." : (cloud.available == nil ? "Cerco i backup…" : "Nessun backup trovato."))
                                    .font(.m3BodyMedium)
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                    } else {
                        VStack(spacing: 2) {
                            ForEach(Array(cloud.entries.enumerated()), id: \.element.id) { index, entry in
                                entryRow(entry, first: index == 0, last: index == cloud.entries.count - 1)
                            }
                        }
                    }

                    if let preview, choice != nil {
                        BackupPreviewCard(file: preview)
                        Button {
                            if model.hasData { confirm = true } else { Task { await doRestore() } }
                        } label: {
                            HStack(spacing: 10) {
                                if cloud.isWorking { ProgressView().tint(m3.onPrimary) } else { Image(systemName: "arrow.counterclockwise") }
                                Text("Ripristina questo backup")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.m3FilledLarge)
                        .disabled(cloud.isWorking)
                    }

                    if let error = cloud.lastError {
                        Text(error)
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.error)
                            .padding(.horizontal, 6)
                    }

                    Text("Il backup contiene solo le scelte fatte in Sweep (foto tenute e nel cestino), l'avanzamento degli album e le impostazioni. Le foto restano nella libreria di Foto.")
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(m3.surface.ignoresSafeArea())
            .navigationTitle("Ripristina da iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(firstLaunch ? "Inizia da zero" : "Chiudi") { dismiss() }
                }
            }
            .confirmationDialog("Sostituire i dati attuali?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Ripristina il backup", role: .destructive) { Task { await doRestore() } }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Le foto già viste, il cestino e le impostazioni di adesso verranno sostituiti da quelli del backup.")
            }
            .task {
                await cloud.refreshEntries()
                if let first = cloud.entries.first, choice == nil {
                    choice = first
                    await loadPreview(first)
                }
            }
        }
        .tint(m3.primary)
    }

    private func entryRow(_ entry: CloudBackupPlan.Entry, first: Bool, last: Bool) -> some View {
        let selected = choice == entry
        return Button {
            choice = entry
            Task { await loadPreview(entry) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: entry.isLatest ? "clock.arrow.circlepath" : "doc.text")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? m3.onPrimaryContainer : m3.primary)
                    .frame(width: 24)
                Text(title(entry))
                    .font(.m3TitleSmall)
                    .foregroundStyle(selected ? m3.onPrimaryContainer : m3.onSurface)
                Spacer()
                if selected {
                    if loading { ProgressView() } else { Image(systemName: "checkmark").foregroundStyle(m3.onPrimaryContainer) }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(selected ? m3.primaryContainer : m3.surfaceContainerLow,
                        in: UnevenRoundedRectangle(topLeadingRadius: first ? 22 : 6, bottomLeadingRadius: last ? 22 : 6,
                                                   bottomTrailingRadius: last ? 22 : 6, topTrailingRadius: first ? 22 : 6,
                                                   style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func title(_ entry: CloudBackupPlan.Entry) -> String {
        guard let day = entry.day else { return "Ultimo backup" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "it_IT"))).capitalized
    }

    private func loadPreview(_ entry: CloudBackupPlan.Entry) async {
        loading = true
        preview = try? await cloud.load(entry)
        loading = false
    }

    private func doRestore() async {
        guard let choice else { return }
        if await cloud.restore(choice) { dismiss() }
    }
}

/// What a backup contains, before restoring it.
struct BackupPreviewCard: View {
    @Environment(\.m3) private var m3
    let file: BackupFile

    var body: some View {
        M3Card(color: m3.surfaceContainer, padding: 16, corner: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Salvato il \(file.exportedAt.sweepLabel)")
                    .font(.m3TitleSmall)
                    .foregroundStyle(m3.onSurface)
                row("Foto tenute", SweepFormat.count(file.kept.count), "checkmark")
                row("Nel cestino", SweepFormat.count(file.trash.count), "trash")
                row("Eliminate finora", SweepFormat.count(file.deletedCount), "xmark.bin")
                row("Spazio liberato", SweepFormat.bytes(file.freedBytes), "internaldrive")
                if !file.albums.isEmpty {
                    row("Album", SweepFormat.count(file.albums.count), "rectangle.stack")
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(m3.primary)
                .frame(width: 20)
            Text(label).font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant)
            Spacer()
            Text(value).font(.m3LabelLarge).monospacedDigit().foregroundStyle(m3.onSurface)
        }
    }
}
