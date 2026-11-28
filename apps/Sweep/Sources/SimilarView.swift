import SwiftUI
import SweepCore

/// Duplicates and similar shots, one group at a time: tap the photos to
/// keep, the others go to the bin.
struct SimilarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibrary.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(SimilarScanner.self) private var scanner
    @Environment(\.m3) private var m3

    @State private var queue: [SimilarGroup] = []
    @State private var index = 0
    @State private var keep: Set<String> = []
    @State private var history: [Resolution] = []
    @State private var showTrash = false
    @State private var loaded = false
    @State private var keptNow = 0
    @State private var binnedNow = 0

    private struct Resolution {
        let group: SimilarGroup
        let kept: [String]
        let binned: [String]
    }

    private var current: SimilarGroup? {
        index < queue.count ? queue[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if loaded && !queue.isEmpty {
                M3Progress(value: Double(index) / Double(max(queue.count, 1)),
                           color: m3.primary, track: m3.surfaceContainerHighest, height: 5)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(m3.surface.ignoresSafeArea())
        .task {
            await scanner.scan()
            queue = Similarity.pending(scanner.groups, state: model.state)
            index = 0
            selectDefault()
            loaded = true
        }
        .sheet(isPresented: $showTrash) { TrashView() }
        .sensoryFeedback(.selection, trigger: keep)
        .sensoryFeedback(.impact(weight: .medium), trigger: index)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            IconButton(icon: "xmark", label: "Chiudi") { dismiss() }
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text("Doppioni e simili")
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onSurface)
                Text(subtitle)
                    .font(.m3LabelMedium)
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurfaceVariant)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            IconButton(icon: "trash", label: "Cestino", badge: model.state.trashCount) { showTrash = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var subtitle: String {
        if !loaded { return "Cerco…" }
        if queue.isEmpty { return "Nessun gruppo" }
        if current == nil { return "Tutti i gruppi visti" }
        return "Gruppo \(SweepFormat.count(index + 1)) di \(SweepFormat.count(queue.count))"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !loaded {
            scanning
        } else if queue.isEmpty {
            VStack(spacing: 24) {
                HeroMessage(icon: "checkmark", tones: m3.keep, title: "Nessun doppione",
                            message: "Non ho trovato foto uguali o scatti ripetuti da sistemare.")
                Button("Torna alla home") { dismiss() }
                    .buttonStyle(.m3Tonal)
            }
            .padding(24)
        } else if let group = current {
            groupView(group)
                .id(group.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
        } else {
            doneState
        }
    }

    private var scanning: some View {
        let (done, total): (Int, Int) = {
            if case .scanning(let d, let t) = scanner.phase { return (d, t) }
            return (0, 0)
        }()
        return VStack(spacing: 22) {
            HeroMessage(icon: "square.on.square", title: "Cerco doppioni…",
                        message: "Confronto le foto tra loro, senza scaricarle da iCloud. La prima volta ci vuole un po', poi controllo solo le foto nuove.")
            if total > 0 {
                VStack(spacing: 8) {
                    M3Progress(value: Double(done) / Double(total), color: m3.primary, track: m3.surfaceContainerHighest, height: 8)
                    Text("\(SweepFormat.count(done)) di \(SweepFormat.count(total))")
                        .font(.m3LabelLarge)
                        .monospacedDigit()
                        .foregroundStyle(m3.onSurfaceVariant)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 24)
            } else {
                ProgressView().tint(m3.primary)
            }
        }
        .padding(24)
    }

    private func groupView(_ group: SimilarGroup) -> some View {
        let binned = group.ids.filter { !keep.contains($0) }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label(group.kind == .duplicates ? "Doppioni" : "Scatti simili",
                              systemImage: group.kind == .duplicates ? "square.on.square" : "square.stack.3d.up")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onTertiaryContainer)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(m3.tertiaryContainer, in: Capsule())
                        Text("\(SweepFormat.photos(group.ids.count))")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                        Spacer()
                    }
                    Text("Tocca le foto da tenere: le altre vanno nel cestino. Ti ho già scelto la migliore.")
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(group.ids, id: \.self) { id in
                            SimilarCell(id: id, keep: keep.contains(id), best: id == group.best)
                                .onTapGesture { toggle(id) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(width: 52, height: 52)
                        .background(m3.surfaceContainerHigh, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .disabled(history.isEmpty)
                .opacity(history.isEmpty ? 0.4 : 1)
                .accessibilityLabel("Annulla ultimo gruppo")

                Button("Salta") { skip(group) }
                    .buttonStyle(.m3TonalLarge)

                Button {
                    confirm(group)
                } label: {
                    Text(binned.isEmpty ? "Tieni tutte" : "Nel cestino \(binned.count)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(M3ButtonStyle(kind: binned.isEmpty ? .filled : .dangerFilled, large: true))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    private var doneState: some View {
        let trash = model.state.trashCount
        return ScrollView {
            VStack(spacing: 22) {
                HeroMessage(icon: "checkmark", tones: m3.keep, title: "Fatto!",
                            message: "Hai visto tutti i gruppi di doppioni e foto simili.")
                    .padding(.top, 24)
                HStack(spacing: 10) {
                    StatTile(value: SweepFormat.count(keptNow), label: "tenute ora", icon: "checkmark", tones: m3.keep)
                    StatTile(value: SweepFormat.count(binnedNow), label: "nel cestino ora", icon: "trash", tones: m3.delete)
                }
                if trash > 0 {
                    Button {
                        Task { await model.emptyTrash(library: library) }
                    } label: {
                        HStack(spacing: 10) {
                            if model.isDeleting { ProgressView().tint(m3.onError) } else { Image(systemName: "trash") }
                            Text("Elimina \(SweepFormat.photos(trash)) dal telefono")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.m3DangerLarge)
                    .disabled(model.isDeleting)
                }
                Button {
                    dismiss()
                } label: {
                    Text("Torna alla home").frame(maxWidth: .infinity)
                }
                .buttonStyle(M3ButtonStyle(kind: trash > 0 ? .tonal : .filled, large: true))
                if !history.isEmpty {
                    Button { undo() } label: { Label("Annulla ultimo gruppo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.m3Text)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Actions

    private func selectDefault() {
        keep = current.map { [$0.best] } ?? []
    }

    private func toggle(_ id: String) {
        if keep.contains(id) { keep.remove(id) } else { keep.insert(id) }
    }

    private func confirm(_ group: SimilarGroup) {
        let kept = group.ids.filter { keep.contains($0) }
        let binned = group.ids.filter { !keep.contains($0) }
        for id in kept { model.apply(.keep, to: id) }
        for id in binned { model.apply(.delete, to: id) }
        keptNow += kept.count
        binnedNow += binned.count
        history.append(Resolution(group: group, kept: kept, binned: binned))
        advance()
    }

    private func skip(_ group: SimilarGroup) {
        history.append(Resolution(group: group, kept: [], binned: []))
        advance()
    }

    private func advance() {
        withAnimation(.spring(duration: 0.4)) {
            index += 1
            selectDefault()
        }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        for id in last.kept + last.binned { model.revert(id) }
        keptNow -= last.kept.count
        binnedNow -= last.binned.count
        withAnimation(.spring(duration: 0.4)) {
            index = max(0, index - 1)
            keep = last.kept.isEmpty ? [last.group.best] : Set(last.kept)
        }
    }
}

/// One photo of a group: green check = keep, red = to the bin.
private struct SimilarCell: View {
    @Environment(\.m3) private var m3
    let id: String
    let keep: Bool
    let best: Bool

    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                AssetImage(id: id, targetSize: CGSize(width: 600, height: 800), fill: true)
            }
            .overlay {
                if !keep {
                    m3.error.opacity(0.28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(keep ? m3.success : m3.error, lineWidth: 3)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: keep ? "checkmark" : "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(keep ? m3.onSuccessContainer : m3.onError)
                    .frame(width: 32, height: 32)
                    .background(keep ? m3.successContainer : m3.error, in: Circle())
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if best {
                    Label("Migliore", systemImage: "star.fill")
                        .font(.m3LabelMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(keep ? 1 : 0.96)
            .animation(.spring(duration: 0.25), value: keep)
    }
}
