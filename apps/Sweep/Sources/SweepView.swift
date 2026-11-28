import Photos
import SwiftUI
import SweepCore

/// The cleaning screen: one photo at a time.
/// Swipe left = keep, right = bin, up = decide later, down = favourite.
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
    @State private var laterTick = 0
    @State private var favoriteTick = 0
    /// Photos this session made favourite (undo removes the heart again).
    @State private var favoritedNow: Set<String> = []
    @State private var cardSize: CGSize = .zero
    // Zoom of the top card (pinch or double tap). While zoomed, dragging pans.
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var pinching = false

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
        .sensoryFeedback(.impact(weight: .light), trigger: laterTick)
        .sensoryFeedback(.success, trigger: favoriteTick)
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
                    SwipeCard(id: item.id, isTop: item.depth == 0,
                              targetSize: pixelSize == .zero ? CGSize(width: size.width * displayScale, height: size.height * displayScale) : pixelSize,
                              zoom: item.depth == 0 ? zoom : 1, pan: item.depth == 0 ? pan : .zero)
                        .frame(width: size.width, height: size.height)
                        .overlay {
                            if item.depth == 0 && !isZoomed { stamps }
                        }
                        .overlay(alignment: .top) {
                            if item.depth == 0 && isZoomed { zoomBadge }
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
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 2) { toggleZoom() }
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
        min(1, max(abs(offset.width), abs(offset.height)) / threshold)
    }

    private var isVertical: Bool { abs(offset.height) > abs(offset.width) }

    private func scale(for depth: Int) -> CGFloat {
        guard depth > 0 else { return 1 }
        return 1 - 0.05 * (CGFloat(depth) - swipeProgress)
    }

    private func lift(for depth: Int) -> CGFloat {
        guard depth > 0 else { return 0 }
        return 16 * (CGFloat(depth) - swipeProgress)
    }

    /// The move the card would do if released now (for haptics).
    private var dragZone: Move? {
        if flying || isZoomed || session?.isFinished != false { return nil }
        return move(for: offset)
    }

    /// Move for a translation past the threshold (dominant axis), if any.
    private func move(for t: CGSize) -> Move? {
        if abs(t.width) >= abs(t.height) {
            if t.width <= -threshold { return .keep }
            if t.width >= threshold { return .delete }
        } else {
            if t.height <= -threshold { return .later }
            if t.height >= threshold { return .favorite }
        }
        return nil
    }

    private func amount(_ value: CGFloat, vertical: Bool) -> CGFloat {
        guard vertical == isVertical else { return 0 }
        return min(1, max(0, value / threshold))
    }

    private var keepAmount: CGFloat { amount(-offset.width, vertical: false) }
    private var deleteAmount: CGFloat { amount(offset.width, vertical: false) }
    private var laterAmount: CGFloat { amount(-offset.height, vertical: true) }
    private var favoriteAmount: CGFloat { amount(offset.height, vertical: true) }

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
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(m3.tertiary.opacity(0.25 * laterAmount))
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(m3.favorite.accent.opacity(0.25 * favoriteAmount))
            Stamp(text: "DOPO", icon: "clock.arrow.circlepath", tones: m3.later)
                .scaleEffect(0.8 + 0.2 * laterAmount)
                .opacity(laterAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 90)
            Stamp(text: "PREFERITA", icon: "heart.fill", tones: m3.favorite)
                .scaleEffect(0.8 + 0.2 * favoriteAmount)
                .opacity(favoriteAmount)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 28)
        }
        .allowsHitTesting(false)
    }

    /// Icons behind the cards, revealed while dragging.
    private var edgeHints: some View {
        // Dragging a card uncovers the opposite edge.
        ZStack {
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
            VStack {
                IconBadge(icon: "heart.fill", tones: m3.favorite, size: 64, cookie: true)
                    .scaleEffect(0.6 + 0.4 * favoriteAmount)
                    .opacity(favoriteAmount)
                Spacer()
                IconBadge(icon: "clock.arrow.circlepath", tones: m3.later, size: 64, cookie: true)
                    .scaleEffect(0.6 + 0.4 * laterAmount)
                    .opacity(laterAmount)
            }
            .padding(.vertical, 20)
        }
        .allowsHitTesting(false)
    }

    // MARK: Zoom

    private var isZoomed: Bool { zoom > 1.01 }

    /// Videos are not zoomed (the player is not scaled).
    private var canZoom: Bool {
        guard let id = session?.current, !flying else { return false }
        return library.asset(id)?.mediaType != .video
    }

    private var zoomBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.magnifyingglass")
            Text("\(String(format: "%.1f", zoom).replacingOccurrences(of: ".", with: ","))× · doppio tocco per tornare")
        }
        .font(.m3LabelMedium)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.top, 14)
        .allowsHitTesting(false)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard canZoom else { return }
                if !pinching {
                    pinching = true
                    // A pinch is not a swipe: bring the card back to the centre.
                    withAnimation(.spring(duration: 0.25)) { offset = .zero }
                }
                zoom = min(ZoomMath.maxZoom, max(1, lastZoom * value.magnification))
                pan = ZoomMath.clamp(pan, zoom: zoom, size: cardSize)
            }
            .onEnded { _ in
                pinching = false
                lastZoom = zoom
                if zoom < 1.05 { withAnimation(.spring(duration: 0.3)) { resetZoom() } }
            }
    }

    private func toggleZoom() {
        guard canZoom else { return }
        withAnimation(.spring(duration: 0.35)) {
            if isZoomed {
                resetZoom()
            } else {
                zoom = ZoomMath.doubleTapZoom
                lastZoom = zoom
            }
        }
    }

    private func resetZoom() {
        zoom = 1
        lastZoom = 1
        pan = .zero
        lastPan = .zero
    }

    // MARK: Gesture and actions

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !flying, !pinching, session?.isFinished == false else { return }
                if isZoomed {
                    pan = ZoomMath.clamp(CGSize(width: lastPan.width + value.translation.width,
                                                height: lastPan.height + value.translation.height),
                                         zoom: zoom, size: cardSize)
                    return
                }
                offset = value.translation
            }
            .onEnded { value in
                guard !flying, session?.isFinished == false else { return }
                if isZoomed || pinching {
                    lastPan = pan
                    if !isZoomed { withAnimation(.spring(duration: 0.3)) { offset = .zero } }
                    return
                }
                let t = value.translation
                let p = value.predictedEndTranslation
                // A fast flick counts too, in the same direction as the drag.
                let flick = CGSize(width: abs(p.width) > threshold * 2.2 && p.width * t.width > 0 ? p.width : t.width,
                                   height: abs(p.height) > threshold * 2.2 && p.height * t.height > 0 ? p.height : t.height)
                if let move = move(for: t) ?? move(for: flick) {
                    commit(move)
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.35)) { offset = .zero }
                }
            }
    }

    /// Where a card goes when it leaves the screen with this move.
    private func exit(for move: Move, scale: CGFloat = 1.7) -> CGSize {
        let w = max(cardSize.width, 360) * scale
        let h = max(cardSize.height, 700) * scale
        switch move {
        case .keep: return CGSize(width: -w, height: offset.height + 40)
        case .delete: return CGSize(width: w, height: offset.height + 40)
        case .later: return CGSize(width: offset.width, height: -h)
        case .favorite: return CGSize(width: offset.width, height: h)
        }
    }

    private func commit(_ move: Move) {
        guard !flying, session?.current != nil else { return }
        flying = true
        if isZoomed { withAnimation(.spring(duration: 0.2)) { resetZoom() } }
        withAnimation(.easeIn(duration: 0.22)) {
            offset = exit(for: move)
        } completion: {
            finish(move)
        }
    }

    private func finish(_ move: Move) {
        guard var s = session, let step = s.apply(move) else {
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
        if let decision = step.decision { model.apply(decision, to: step.id) }
        switch move {
        case .keep: keepTick += 1
        case .delete: deleteTick += 1
        case .later:
            laterTick += 1
            if s.current == step.id { model.showToast("È l'ultima rimasta: decidi se tenerla o eliminarla.") }
        case .favorite:
            favoriteTick += 1
            if library.asset(step.id)?.isFavorite == false {
                favoritedNow.insert(step.id)
                Task { await library.setFavorite(step.id, true) }
            }
        }
        flying = false
        preheat()
    }

    private func undo() {
        guard !flying, var s = session, let step = s.undo() else { return }
        flying = true
        resetZoom()
        if step.decision != nil { model.revert(step.id) }
        if step.move == .favorite, favoritedNow.remove(step.id) != nil {
            Task { await library.setFavorite(step.id, false) }
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            session = s
            offset = .zero
            offset = exit(for: step.move, scale: 1.3)
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
            Spacer(minLength: 4)
            ActionCircle(icon: "heart.fill", caption: "Preferita", arrow: "arrow.down", tones: m3.favorite,
                         emphasis: favoriteAmount, size: 50) {
                commit(.favorite)
            }
            .padding(.top, 11)
            Spacer(minLength: 4)
            ActionCircle(icon: "arrow.uturn.backward", caption: "Annulla", arrow: nil,
                         tones: Tones(accent: m3.onSurfaceVariant, container: m3.surfaceContainerHigh, onContainer: m3.onSurfaceVariant),
                         size: 50, action: undo)
                .disabled(session?.canUndo != true || flying)
                .opacity(session?.canUndo == true ? 1 : 0.4)
                .padding(.top, 11)
            Spacer(minLength: 4)
            ActionCircle(icon: "clock.arrow.circlepath", caption: "Dopo", arrow: "arrow.up", tones: m3.later,
                         emphasis: laterAmount, size: 50) {
                commit(.later)
            }
            .padding(.top, 11)
            Spacer(minLength: 4)
            ActionCircle(icon: "trash", caption: "Elimina", arrow: "arrow.right", tones: m3.delete, emphasis: deleteAmount, arrowTrailing: true) {
                commit(.delete)
            }
        }
        .padding(.horizontal, 18)
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
    let arrow: String?
    let tones: Tones
    var emphasis: CGFloat = 0
    var arrowTrailing = false
    var size: CGFloat = 72
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(emphasis > 0.99 ? m3.surface : tones.onContainer)
                    .frame(width: size, height: size)
                    .background(emphasis > 0.99 ? tones.accent : tones.container, in: Circle())
                    .scaleEffect(1 + 0.12 * emphasis)
                    .animation(.spring(duration: 0.25), value: emphasis > 0.99)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(caption)

            HStack(spacing: 3) {
                if let arrow, !arrowTrailing { Image(systemName: arrow) }
                Text(caption)
                if let arrow, arrowTrailing { Image(systemName: arrow) }
            }
            .font(size < 60 ? .m3LabelSmall : .m3LabelMedium)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(m3.onSurfaceVariant)
        }
    }
}
