import SwiftUI
import SweepCore

/// The cleaning screen: one photo at a time.
/// Swipe left = keep and go on; swipe right = put in the bin and go on.
struct SweepView: View {
    let source: SweepSource

    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibrary.self) private var library
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.displayScale) private var displayScale

    @State private var session: ReviewSession?
    @State private var allIDs: [String] = []
    @State private var reviewedBefore = 0
    @State private var offset: CGSize = .zero
    @State private var flying = false
    @State private var showTrash = false
    @State private var keepTick = 0
    @State private var deleteTick = 0
    @State private var cardSize: CGSize = .zero

    private let threshold: CGFloat = 110

    private struct StackItem: Identifiable {
        let id: String
        let depth: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let session, !session.isFinished {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(m3.surface.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: keepTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteTick)
        .sensoryFeedback(.selection, trigger: dragZone)
        .onDisappear {
            library.stopPreheating()
            model.saveNow()
        }
    }

    // MARK: Loading

    /// Heavy videos are always shown heaviest first.
    private var order: SweepOrder {
        source == .largeVideos ? .largestFirst : model.order
    }

    private func load() async {
        let ids = await library.ids(for: source, filter: model.filter)
        var sizes: [String: Int64] = [:]
        if order.needsSizes {
            sizes = await SizeIndex.shared.sizes(for: ids)
        }
        let todo = model.state.unreviewed(order.arrange(newestFirst: ids, sizes: sizes))
        allIDs = ids
        reviewedBefore = ids.count - todo.count
        session = ReviewSession(ids: todo)
        preheat()
    }

    private func restart() {
        model.forget(allIDs)
        session = nil
        offset = .zero
        Task { await load() }
    }

    private func preheat() {
        guard let session, cardSize != .zero else { return }
        library.preheat(Array(session.upcoming(5).dropFirst()), targetSize: pixelSize)
    }

    private var pixelSize: CGSize {
        CGSize(width: cardSize.width * displayScale, height: cardSize.height * displayScale)
    }

    // MARK: Top bar

    private var doneCount: Int {
        reviewedBefore + (session?.position ?? 0)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            IconButton(icon: "xmark", label: "Chiudi") { dismiss() }
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text(source.title)
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                Text(counterText)
                    .font(.m3LabelMedium)
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurfaceVariant)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            IconButton(icon: "trash", label: "Cestino", badge: model.state.trashCount) { showTrash = true }
                .animation(.spring(duration: 0.3), value: model.state.trashCount)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var counterText: String {
        guard let session else { return "Caricamento…" }
        if allIDs.isEmpty { return "Nessun elemento" }
        if session.isFinished { return "\(SweepFormat.count(allIDs.count)) su \(SweepFormat.count(allIDs.count))" }
        return "\(SweepFormat.count(doneCount + 1)) di \(SweepFormat.count(allIDs.count))"
    }

    private var progressBar: some View {
        M3Progress(value: allIDs.isEmpty ? 0 : Double(doneCount) / Double(allIDs.count),
                   color: m3.primary, track: m3.surfaceContainerHighest, height: 5)
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let session {
            if allIDs.isEmpty {
                emptyState
            } else if session.isFinished {
                doneState(session)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                cardStack(session)
            }
        } else if let progress = SizeIndex.shared.progress, progress.total > 0 {
            VStack(spacing: 18) {
                HeroMessage(icon: "externaldrive", title: "Peso i file…",
                            message: "Per mostrarti prima le foto e i video più pesanti. Lo faccio una volta sola.")
                M3Progress(value: Double(progress.done) / Double(progress.total),
                           color: m3.primary, track: m3.surfaceContainerHighest, height: 8)
                    .padding(.horizontal, 24)
                Text("\(SweepFormat.count(progress.done)) di \(SweepFormat.count(progress.total))")
                    .font(.m3LabelLarge)
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurfaceVariant)
                    .contentTransition(.numericText())
            }
            .padding(24)
        } else {
            ProgressView()
                .tint(m3.primary)
        }
    }

    private func cardStack(_ session: ReviewSession) -> some View {
        GeometryReader { geo in
            let size = CGSize(width: max(1, geo.size.width - 32), height: max(1, geo.size.height - 28))
            let items = session.upcoming(3).enumerated().map { StackItem(id: $0.element, depth: $0.offset) }
            ZStack {
                edgeHints
                ForEach(items) { item in
                    SwipeCard(id: item.id, isTop: item.depth == 0, targetSize: pixelSize == .zero ? CGSize(width: size.width * displayScale, height: size.height * displayScale) : pixelSize)
                        .frame(width: size.width, height: size.height)
                        .overlay {
                            if item.depth == 0 { stamps }
                        }
                        .scaleEffect(scale(for: item.depth))
                        .offset(y: lift(for: item.depth))
                        .opacity(item.depth >= 2 ? swipeProgress : 1)
                        .offset(item.depth == 0 ? offset : .zero)
                        .rotationEffect(.degrees(item.depth == 0 ? Double(offset.width / 22) : 0), anchor: .bottom)
                        .zIndex(Double(10 - item.depth))
                        .allowsHitTesting(item.depth == 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
            .onAppear {
                cardSize = size
                preheat()
            }
            .onChange(of: geo.size) { _, _ in
                cardSize = size
            }
        }
        .padding(.top, 6)
    }

    /// 0…1: how far the top card is from the center, relative to the threshold.
    private var swipeProgress: CGFloat {
        min(1, abs(offset.width) / threshold)
    }

    private func scale(for depth: Int) -> CGFloat {
        guard depth > 0 else { return 1 }
        return 1 - 0.05 * (CGFloat(depth) - swipeProgress)
    }

    private func lift(for depth: Int) -> CGFloat {
        guard depth > 0 else { return 0 }
        return 16 * (CGFloat(depth) - swipeProgress)
    }

    /// -1 = past the keep threshold, 1 = past the delete threshold (for haptics).
    private var dragZone: Int {
        if flying || session?.isFinished != false { return 0 }
        if offset.width <= -threshold { return -1 }
        if offset.width >= threshold { return 1 }
        return 0
    }

    private var keepAmount: CGFloat { min(1, max(0, -offset.width / threshold)) }
    private var deleteAmount: CGFloat { min(1, max(0, offset.width / threshold)) }

    private var stamps: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(m3.success.opacity(0.28 * keepAmount))
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(m3.error.opacity(0.28 * deleteAmount))
            Stamp(text: "TIENI", icon: "checkmark", tones: m3.keep)
                .rotationEffect(.degrees(12))
                .scaleEffect(0.8 + 0.2 * keepAmount)
                .opacity(keepAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)
            Stamp(text: "ELIMINA", icon: "trash", tones: m3.delete)
                .rotationEffect(.degrees(-12))
                .scaleEffect(0.8 + 0.2 * deleteAmount)
                .opacity(deleteAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
        .allowsHitTesting(false)
    }

    /// Icons behind the cards, revealed while dragging.
    private var edgeHints: some View {
        // Dragging left uncovers the right edge and vice versa.
        HStack {
            IconBadge(icon: "trash", tones: m3.delete, size: 64, cookie: true)
                .scaleEffect(0.6 + 0.4 * deleteAmount)
                .opacity(deleteAmount)
            Spacer()
            IconBadge(icon: "checkmark", tones: m3.keep, size: 64, cookie: true)
                .scaleEffect(0.6 + 0.4 * keepAmount)
                .opacity(keepAmount)
        }
        .padding(.horizontal, 20)
        .allowsHitTesting(false)
    }

    // MARK: Gesture and actions

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !flying, session?.isFinished == false else { return }
                offset = CGSize(width: value.translation.width, height: value.translation.height * 0.3)
            }
            .onEnded { value in
                guard !flying, session?.isFinished == false else { return }
                let w = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if w <= -threshold || (predicted <= -threshold * 2.2 && w < 0) {
                    commit(.keep)
                } else if w >= threshold || (predicted >= threshold * 2.2 && w > 0) {
                    commit(.delete)
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.35)) { offset = .zero }
                }
            }
    }

    private func commit(_ decision: Decision) {
        guard !flying, session?.current != nil else { return }
        flying = true
        let direction: CGFloat = decision == .keep ? -1 : 1
        let distance = max(cardSize.width, 360) * 1.7
        withAnimation(.easeIn(duration: 0.22)) {
            offset = CGSize(width: direction * distance, height: offset.height + 40)
        } completion: {
            finish(decision)
        }
    }

    private func finish(_ decision: Decision) {
        guard var s = session, let step = s.decide(decision) else {
            flying = false
            return
        }
        if s.isFinished {
            // The last card is already off screen: keep its offset and fade in the summary.
            withAnimation(.spring(duration: 0.5)) { session = s }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                session = s
                offset = .zero
            }
        }
        model.apply(decision, to: step.id)
        if decision == .keep { keepTick += 1 } else { deleteTick += 1 }
        flying = false
        preheat()
    }

    private func undo() {
        guard !flying, var s = session, let step = s.undo() else { return }
        flying = true
        model.revert(step.id)
        let direction: CGFloat = step.decision == .keep ? -1 : 1
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            session = s
            offset = CGSize(width: direction * max(cardSize.width, 360) * 1.3, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
                offset = .zero
            } completion: {
                flying = false
            }
        }
    }

    // MARK: Bottom controls

    private var controls: some View {
        HStack(alignment: .top) {
            ActionCircle(icon: "checkmark", caption: "Tieni", arrow: "arrow.left", tones: m3.keep, emphasis: keepAmount) {
                commit(.keep)
            }
            Spacer()
            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant)
                    .frame(width: 52, height: 52)
                    .background(m3.surfaceContainerHigh, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(session?.canUndo != true || flying)
            .opacity(session?.canUndo == true ? 1 : 0.4)
            .padding(.top, 12)
            .accessibilityLabel("Annulla ultima scelta")
            Spacer()
            ActionCircle(icon: "trash", caption: "Elimina", arrow: "arrow.right", tones: m3.delete, emphasis: deleteAmount, arrowTrailing: true) {
                commit(.delete)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: End states

    private var emptyState: some View {
        VStack(spacing: 24) {
            HeroMessage(icon: "photo", title: "Niente da vedere",
                        message: "Non ci sono elementi qui con il filtro \"\(model.filter.title)\".")
            Button("Torna indietro") { dismiss() }
                .buttonStyle(.m3Tonal)
        }
        .padding(24)
    }

    private func doneState(_ session: ReviewSession) -> some View {
        let trash = model.state.trashCount
        let nothingThisTime = session.total == 0
        return ScrollView {
            VStack(spacing: 22) {
                HeroMessage(
                    icon: "checkmark",
                    tones: m3.keep,
                    title: nothingThisTime ? "Qui hai già finito" : "Fatto!",
                    message: nothingThisTime
                        ? "Hai già visto tutti i \(SweepFormat.count(allIDs.count)) elementi di \"\(source.title)\"."
                        : "Hai visto tutti gli elementi di \"\(source.title)\"."
                )
                .padding(.top, 24)

                if !nothingThisTime {
                    HStack(spacing: 10) {
                        StatTile(value: SweepFormat.count(session.keptCount), label: "tenute ora", icon: "checkmark", tones: m3.keep)
                        StatTile(value: SweepFormat.count(session.deletedCount), label: "nel cestino ora", icon: "trash", tones: m3.delete)
                    }
                }

                VStack(spacing: 10) {
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
                        Text("iOS ti chiederà una sola conferma per tutte.")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                            .padding(.bottom, 6)
                    }
                    Button {
                        dismiss()
                    } label: {
                        Text("Torna alla home").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(M3ButtonStyle(kind: trash > 0 ? .tonal : .filled, large: true))
                    HStack(spacing: 10) {
                        if session.canUndo {
                            Button {
                                undo()
                            } label: {
                                Label("Annulla ultima", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.m3Text)
                        }
                        Button {
                            restart()
                        } label: {
                            Label("Rivedi da capo", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.m3Text)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

/// "TIENI" / "ELIMINA" label on the card while dragging.
private struct Stamp: View {
    let text: String
    let icon: String
    let tones: Tones

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20, weight: .heavy))
            Text(text).font(.system(size: 24, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(tones.container, in: Capsule())
        .overlay(Capsule().strokeBorder(tones.accent, lineWidth: 3))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

/// Big round action button with a caption ("← Tieni", "Elimina →").
private struct ActionCircle: View {
    @Environment(\.m3) private var m3
    let icon: String
    let caption: String
    let arrow: String
    let tones: Tones
    var emphasis: CGFloat = 0
    var arrowTrailing = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(emphasis > 0.99 ? m3.surface : tones.onContainer)
                    .frame(width: 76, height: 76)
                    .background(emphasis > 0.99 ? tones.accent : tones.container, in: Circle())
                    .scaleEffect(1 + 0.12 * emphasis)
                    .animation(.spring(duration: 0.25), value: emphasis > 0.99)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(caption)

            HStack(spacing: 4) {
                if !arrowTrailing { Image(systemName: arrow) }
                Text(caption)
                if arrowTrailing { Image(systemName: arrow) }
            }
            .font(.m3LabelMedium)
            .foregroundStyle(m3.onSurfaceVariant)
        }
    }
}
