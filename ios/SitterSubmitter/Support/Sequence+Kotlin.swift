/// The few Kotlin collection operations the view models rely on, with the same ordering guarantees.
extension Sequence {
    /// Like Kotlin's `groupBy`: keys in order of first appearance, elements in their original order.
    func groupedInOrder<Key: Hashable>(by key: (Element) -> Key) -> [(key: Key, elements: [Element])] {
        var keys: [Key] = []
        var groups: [Key: [Element]] = [:]
        for element in self {
            let elementKey = key(element)
            if groups[elementKey] == nil {
                keys.append(elementKey)
            }
            groups[elementKey, default: []].append(element)
        }
        return keys.map { ($0, groups[$0]!) }
    }

    /// Like Kotlin's `sortedBy`: a stable sort.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

extension Sequence where Element: Hashable {
    /// Like Kotlin's `distinct`: first occurrences, in order.
    func distinct() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension String {
    /// Kotlin/Java string ordering (UTF-16 code units, no Unicode normalization).
    func precedesInKotlinOrder(_ other: String) -> Bool {
        utf16.lexicographicallyPrecedes(other.utf16)
    }
}
