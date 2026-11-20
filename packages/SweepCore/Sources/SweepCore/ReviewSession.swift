import Foundation

/// One pass over a list of photos, one at a time, with unlimited undo.
///
/// The session only knows the order and the decisions; the app mirrors every
/// decision into `SweepState` so that progress survives a restart.
public struct ReviewSession: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let id: String
        public let decision: Decision

        public init(id: String, decision: Decision) {
            self.id = id
            self.decision = decision
        }
    }

    /// Photos of this pass, in display order.
    public let ids: [String]
    /// Index of the photo on screen (== number of decisions taken).
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

    /// 0…1, share of photos already decided.
    public var progress: Double {
        ids.isEmpty ? 1 : Double(position) / Double(ids.count)
    }

    /// The current photo followed by the next ones (at most `count` ids).
    public func upcoming(_ count: Int) -> [String] {
        guard position < ids.count, count > 0 else { return [] }
        return Array(ids[position..<min(ids.count, position + count)])
    }

    /// Decides the current photo and moves to the next one.
    @discardableResult
    public mutating func decide(_ decision: Decision) -> Step? {
        guard let id = current else { return nil }
        let step = Step(id: id, decision: decision)
        history.append(step)
        position += 1
        return step
    }

    /// Goes back one photo; returns the decision that was undone.
    @discardableResult
    public mutating func undo() -> Step? {
        guard let last = history.popLast() else { return nil }
        position -= 1
        return last
    }
}
