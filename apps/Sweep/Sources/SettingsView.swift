import SwiftUI
import SweepCore
import UniformTypeIdentifiers

/// Settings: iCloud backup, JSON export/import, preferences, data.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CloudBackupService.self) private var cloud
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss

    @State private var showRestore = false
    @State private var exporting = false
    @State private var exportDocument: BackupDocument?
    @State private var preparingExport = false
    @State private var importing = false
    @State private var importedFile: BackupFile?
    @State private var confirmForget = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Backup iCloud")
                    SettingsGroup {
                        Toggle(isOn: $model.cloudBackup) {
                            RowLabel(icon: "icloud", title: "Backup automatico su iCloud Drive")
                        }
                        .tint(m3.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        SettingsDivider()
                        InfoRow(icon: "clock", title: "Ultimo backup", value: cloud.lastBackupAt.map(\.sweepLabel) ?? "mai")
                        SettingsDivider()
                        ActionRow(icon: "icloud.and.arrow.up", title: "Esegui backup ora", busy: cloud.isWorking) {
                            Task {
                                if await cloud.backup(force: true) { model.showToast("Backup salvato in iCloud Drive.") }
                            }
                        }
                        .disabled(cloud.isWorking)
                        SettingsDivider()
                        ActionRow(icon: "icloud.and.arrow.down", title: "Ripristina da iCloud") { showRestore = true }
                    }
                    if let error = cloud.lastError {
                        Footnote(text: error, color: m3.error)
                    }
                    Footnote(text: cloud.available == false
                             ? "iCloud Drive non disponibile: serve l'accesso a iCloud con iCloud Drive attivo (con l'installazione da Sideloadly il backup iCloud non c'è)."
                             : "In File › iCloud Drive › Backup › Sweep: un file al giorno (ultimi 30) più l'ultimo. Contiene le foto tenute e quelle nel cestino, l'avanzamento degli album e le impostazioni. Mai le foto.")

                    SectionTitle(title: "File")
                    SettingsGroup {
                        ActionRow(icon: "square.and.arrow.up", title: "Esporta backup (JSON)", busy: preparingExport) {
                            Task { await prepareExport() }
                        }
                        .disabled(preparingExport)
                        SettingsDivider()
                        ActionRow(icon: "square.and.arrow.down", title: "Importa backup da file") { importing = true }
                    }

                    SectionTitle(title: "Preferenze")
                    SettingsGroup {
                        HStack {
                            RowLabel(icon: "square.grid.2x2", title: "Mostra")
                            Spacer()
                            Picker("Mostra", selection: $model.filter) {
                                ForEach(MediaFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        SettingsDivider()
                        HStack {
                            RowLabel(icon: "arrow.up.arrow.down", title: "Ordine")
                            Spacer()
                            Picker("Ordine", selection: $model.order) {
                                ForEach(SweepOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                    }

                    SectionTitle(title: "Dati")
                    SettingsGroup {
                        InfoRow(icon: "checkmark", title: "Foto tenute", value: SweepFormat.count(model.state.kept.count))
                        SettingsDivider()
                        InfoRow(icon: "trash", title: "Nel cestino", value: SweepFormat.count(model.state.trashCount))
                        SettingsDivider()
                        InfoRow(icon: "xmark.bin", title: "Eliminate", value: SweepFormat.count(model.state.deletedCount))
                        SettingsDivider()
                        InfoRow(icon: "internaldrive", title: "Spazio liberato", value: SweepFormat.bytes(model.state.freedBytes))
                        SettingsDivider()
                        ActionRow(icon: "arrow.counterclockwise", title: "Rivedi le foto già tenute", destructive: true) {
                            confirmForget = true
                        }
                        .disabled(model.state.kept.isEmpty)
                    }

                    Text(versionText)
                        .font(.m3LabelMedium)
                        .foregroundStyle(m3.outline)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(m3.surface.ignoresSafeArea())
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .sheet(isPresented: $showRestore) {
                CloudRestoreView(firstLaunch: false)
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                          defaultFilename: String(CloudBackupPlan.exportName(for: Date()).dropLast(5))) { result in
                if case .success = result { model.showToast("Backup esportato.") }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog("Ripristinare questo backup?",
                                isPresented: Binding(get: { importedFile != nil }, set: { if !$0 { importedFile = nil } }),
                                titleVisibility: .visible) {
                Button("Ripristina", role: .destructive) {
                    if let file = importedFile {
                        Task { await cloud.restore(file) }
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                if let file = importedFile {
                    Text("Backup del \(file.exportedAt.sweepLabel): \(SweepFormat.photos(file.kept.count)) tenute, \(SweepFormat.photos(file.trash.count)) nel cestino. Sostituisce le scelte di adesso.")
                }
            }
            .confirmationDialog("Rivedere le foto già tenute?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Rivedi tutto da capo", role: .destructive) { model.forgetAllKept() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Le \(SweepFormat.photos(model.state.kept.count)) che hai deciso di tenere ti verranno riproposte. Il cestino non cambia.")
            }
        }
        .tint(m3.primary)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Sweep \(version) (\(build))"
    }

    private func prepareExport() async {
        preparingExport = true
        let file = await cloud.makeFile()
        preparingExport = false
        guard let data = try? file.encoded() else {
            model.showToast("Esportazione non riuscita.")
            return
        }
        exportDocument = BackupDocument(data: data)
        exporting = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            importedFile = try BackupFile.decode(data)
        } catch {
            model.showToast((error as? LocalizedError)?.errorDescription ?? "File non leggibile.")
        }
    }
}

/// JSON backup handed to the system "save to Files" sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Rows

/// Rounded tonal group of rows (Material 3 list).
private struct SettingsGroup<Content: View>: View {
    @Environment(\.m3) private var m3
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SettingsDivider: View {
    @Environment(\.m3) private var m3

    var body: some View {
        Rectangle()
            .fill(m3.outlineVariant.opacity(0.6))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

private struct RowLabel: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    var color: Color?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color ?? m3.primary)
                .frame(width: 24)
            Text(title)
                .font(.m3BodyLarge)
                .foregroundStyle(color ?? m3.onSurface)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct InfoRow: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            RowLabel(icon: icon, title: title)
            Spacer(minLength: 8)
            Text(value)
                .font(.m3LabelLarge)
                .monospacedDigit()
                .foregroundStyle(m3.onSurfaceVariant)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

private struct ActionRow: View {
    @Environment(\.m3) private var m3
    @Environment(\.isEnabled) private var isEnabled
    let icon: String
    let title: String
    var busy = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                RowLabel(icon: icon, title: title, color: destructive ? m3.error : nil)
                Spacer()
                if busy {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(m3.outline)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
    }
}

private struct Footnote: View {
    @Environment(\.m3) private var m3
    let text: String
    var color: Color?

    var body: some View {
        Text(text)
            .font(.m3BodySmall)
            .foregroundStyle(color ?? m3.onSurfaceVariant)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
