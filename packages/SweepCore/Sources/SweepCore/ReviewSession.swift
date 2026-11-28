import Foundation

/// What the user did with one photo of a session.
public enum Move: String, Codable, Sendable {
    /// Swipe left: keep.
    case keep
    /// Swipe right: put in the bin.
    case delete
    /// Swipe down: add to Favorites (and keep).
    case favorite
    /// Swipe up: decide later (the photo goes to the end of the queue).
    case later

    /// The decision recorded in `SweepState` (nil for `.later`).
    public var decision: Decision? {
        switch self {
        case .keep, .favorite: return .keep
        case .delete: return .delete
        case .later: return nil
        }
    }
}

/// One pass over a list of photos, one at a time, with unlimited undo.
///
/// The session only knows the order and the moves; the app mirrors every
/// decision into `SweepState` so that progress survives a restart.
public struct ReviewSession: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let id: String
        public let move: Move

        public init(id: String, move: Move) {
            self.id = id
            self.move = move
        }

        public var decision: Decision? { move.decision }
    }

    /// Photos of this pass, in display order ("later" moves one to the end).
    public private(set) var ids: [String]
    /// Index of the photo on screen (== number of photos decided).
    public private(set) var position: Int = 0
    public private(set) var history: [Step] = []

    public init(ids: [String]) {
        self.ids = ids
    }

    public var total: Int { ids.count }
    public var current: String? { position < ids.count ? ids[position] : nil }
    public var isFinished: Bool { position >= ids.count }
    public var remaining: Int { max(0, ids.count - position) }
    public var canUndo: Bool { !history.isEmpty }
    public var keptCount: Int { history.filter { $0.decision == .keep }.count }
    public var deletedCount: Int { history.filter { $0.decision == .delete }.count }
    public var favoriteCount: Int { history.filter { $0.move == .favorite }.count }

    /// 0…1, share of photos already decided.
    public var progress: Double {
        ids.isEmpty ? 1 : Double(position) / Double(ids.count)
    }

    /// The current photo followed by the next ones (at most `count` ids).
    public func upcoming(_ count: Int) -> [String] {
        guard position < ids.count, count > 0 else { return [] }
        return Array(ids[position..<min(ids.count, position + count)])
    }

    /// Applies a move to the current photo and shows the next one.
    @discardableResult
    public mutating func apply(_ move: Move) -> Step? {
        guard let id = current else { return nil }
        let step = Step(id: id, move: move)
        history.append(step)
        if move == .later {
            ids.remove(at: position)
            ids.append(id)
        } else {
            position += 1
        }
        return step
    }

    /// Keep / delete the current photo.
    @discardableResult
    public mutating func decide(_ decision: Decision) -> Step? {
        apply(decision == .keep ? .keep : .delete)
    }

    /// Goes back one move; returns the move that was undone.
    @discardableResult
    public mutating func undo() -> Step? {
        guard let last = history.popLast() else { return nil }
        if last.move == .later {
            // Undone in LIFO order: the postponed photo is the last one.
            if let index = ids.lastIndex(of: last.id) { ids.remove(at: index) }
            ids.insert(last.id, at: position)
        } else {
            position -= 1
        }
        return last
    }
}
