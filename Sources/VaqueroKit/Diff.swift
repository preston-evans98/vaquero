import Foundation

/// One line of a comparison between two texts.
public enum DiffLine: Sendable, Hashable {
    case same(String)
    case removed(String)
    case added(String)

    /// The lines of `new`, with the lines it dropped from `old` in their places.
    public static func lines(from old: String, to new: String) -> [DiffLine] {
        let before = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let after = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let difference = after.difference(from: before)
        func offset(_ change: CollectionDifference<String>.Change) -> Int {
            switch change {
            case let .insert(offset, _, _), let .remove(offset, _, _): offset
            }
        }
        let removed = Set(difference.removals.map(offset))
        let added = Set(difference.insertions.map(offset))
        var lines: [DiffLine] = []
        var i = 0
        var j = 0
        while i < before.count || j < after.count {
            if i < before.count, removed.contains(i) {
                lines.append(.removed(before[i]))
                i += 1
            } else if j < after.count, added.contains(j) {
                lines.append(.added(after[j]))
                j += 1
            } else {
                lines.append(.same(after[j]))
                i += 1
                j += 1
            }
        }
        return lines
    }
}
