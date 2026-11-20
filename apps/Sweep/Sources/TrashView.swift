import SwiftUI
import SweepCore

/// Photos swiped to the right, waiting to be deleted for real.
struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibrary.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    @State private var selection: Set<String> = []
    @State private var totalBytes: Int64 = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if model.state.trash.isEmpty {
                    VStack {
                        Spacer()
                        HeroMessage(icon: "trash", tones: m3.delete, title: "Cestino vuoto",
                                    message: "Scorri a destra le foto da eliminare: finiscono qui, e le elimini tutte insieme con una sola conferma.")
                            .padding(24)
                        Spacer()
                    }
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(m3.surface.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if !model.state.trash.isEmpty { bottomBar }
            }
            .navigationTitle("Cestino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
                if !model.state.trash.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selection.isEmpty ? "Seleziona tutte" : "Deseleziona") {
                            if selection.isEmpty {
                                selection = Set(model.state.trash)
                            } else {
                                selection.removeAll()
                            }
                        }
                    }
                }
            }
            .task(id: model.state.trashCount) {
                selection.formIntersection(model.state.trash)
                totalBytes = await library.totalSize(of: model.state.trash)
            }
        }
        .tint(m3.primary)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tocca le foto per selezionarle. Con «Tieni» escono dal cestino e restano nel telefono.")
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(model.state.trash.reversed()), id: \.self) { id in
                        TrashCell(id: id, selected: selection.contains(id))
                            .onTapGesture { toggle(id) }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if selection.isEmpty {
                Text("\(SweepFormat.photos(model.state.trashCount))\(totalBytes > 0 ? " · circa \(SweepFormat.bytes(totalBytes))" : "")")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .contentTransition(.numericText())
                Button {
                    Task { await model.emptyTrash(library: library) }
                } label: {
                    HStack(spacing: 10) {
                        if model.isDeleting { ProgressView().tint(m3.onError) } else { Image(systemName: "trash") }
                        Text("Elimina tutte dal telefono")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.m3DangerLarge)
                .disabled(model.isDeleting)
            } else {
                Text("\(SweepFormat.photos(selection.count)) selezionate")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onSurfaceVariant)
                HStack(spacing: 10) {
                    Button {
                        let ids = Array(selection)
                        selection.removeAll()
                        withAnimation(.spring(duration: 0.35)) { model.keep(ids) }
                    } label: {
                        Label("Tieni", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3TonalLarge)
                    Button {
                        let ids = model.state.trash.filter { selection.contains($0) }
                        Task {
                            await model.deleteFromLibrary(ids, library: library)
                            selection.formIntersection(model.state.trash)
                        }
                    } label: {
                        Label("Elimina", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3DangerLarge)
                    .disabled(model.isDeleting)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(m3.surfaceContainer)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.spring(duration: 0.3), value: selection.isEmpty)
    }
}

private struct TrashCell: View {
    @Environment(\.m3) private var m3
    let id: String
    let selected: Bool

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AssetImage(id: id, targetSize: CGSize(width: 360, height: 360), fill: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: selected ? 22 : 8, style: .continuous))
            .padding(selected ? 6 : 0)
            .background(selected ? m3.errorContainer : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? m3.error : .white)
                    .background(Circle().fill(selected ? m3.onError : .black.opacity(0.25)).padding(2))
                    .padding(8)
                    .shadow(color: .black.opacity(0.25), radius: 3)
            }
            .contentShape(Rectangle())
            .animation(.spring(duration: 0.25), value: selected)
    }
}
