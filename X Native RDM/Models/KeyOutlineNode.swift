import Foundation

nonisolated struct KeyOutlineNode: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var redisKey: String?
    var descendantKeyCount: Int
    var children: [KeyOutlineNode]?

    var isFolder: Bool { children != nil }
}

nonisolated enum KeyTreeBuilder {
    static func build(keys: [String], separator: String) -> [KeyOutlineNode] {
        let root = MutableNode(title: "", path: "")
        for key in keys {
            insert(key, into: root, separator: separator)
        }
        return root.frozenChildren()
    }

    private static func insert(_ key: String, into root: MutableNode, separator: String) {
        let parts = split(key, separator: separator)
        var current = root
        var path = ""
        for (index, part) in parts.enumerated() {
            path = path.isEmpty ? part : path + separator + part
            if current.children[part] == nil {
                current.children[part] = MutableNode(
                    title: part.isEmpty ? "(空)" : part,
                    path: path
                )
            }
            current = current.children[part]!
            if index == parts.count - 1 {
                current.redisKey = key
            }
        }
    }

    private static func split(_ key: String, separator: String) -> [String] {
        guard !separator.isEmpty else { return [key] }
        var parts: [String] = []
        var remaining = Substring(key)
        while let range = remaining.range(of: separator) {
            parts.append(String(remaining[..<range.lowerBound]))
            remaining = remaining[range.upperBound...]
        }
        parts.append(String(remaining))
        return parts
    }
}

private final class MutableNode {
    let title: String
    let path: String
    var redisKey: String?
    var children: [String: MutableNode] = [:]

    init(title: String, path: String) {
        self.title = title
        self.path = path
    }

    func frozenChildren() -> [KeyOutlineNode] {
        children.values
            .map { $0.freeze() }
            .sorted(by: KeyOutlineNode.sort)
    }

    func freeze() -> KeyOutlineNode {
        let frozenChildren = frozenChildren()
        let childKeyCount = frozenChildren.reduce(0) { $0 + $1.descendantKeyCount }
        let ownCount = redisKey == nil ? 0 : 1

        if frozenChildren.isEmpty {
            return KeyOutlineNode(
                id: "key\u{0}\(redisKey ?? path)",
                title: title,
                redisKey: redisKey,
                descendantKeyCount: ownCount,
                children: nil
            )
        }

        var items = frozenChildren
        if let redisKey {
            items.insert(
                KeyOutlineNode(
                    id: "key\u{0}\(redisKey)",
                    title: title,
                    redisKey: redisKey,
                    descendantKeyCount: 1,
                    children: nil
                ),
                at: 0
            )
        }

        return KeyOutlineNode(
            id: "folder\u{0}\(path)",
            title: title,
            redisKey: nil,
            descendantKeyCount: ownCount + childKeyCount,
            children: items
        )
    }
}

extension KeyOutlineNode {
    static func sort(_ lhs: KeyOutlineNode, _ rhs: KeyOutlineNode) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder && !rhs.isFolder
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
