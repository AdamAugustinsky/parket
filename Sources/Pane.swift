import Foundation

package struct Pane<Item: Equatable>: Equatable {
    package var windows: [Item]
    package var activeIndex: Int

    package init(windows: [Item], activeIndex: Int = 0) {
        self.windows = windows
        self.activeIndex = activeIndex
        normalizeActiveIndex()
    }

    package var isEmpty: Bool { windows.isEmpty }
    package var activeWindow: Item? { windows.indices.contains(activeIndex) ? windows[activeIndex] : nil }

    package func contains(_ window: Item) -> Bool {
        windows.contains(window)
    }

    package func firstIndex(of window: Item) -> Int? {
        windows.firstIndex(of: window)
    }

    package mutating func normalizeActiveIndex() {
        if windows.isEmpty {
            activeIndex = 0
        } else {
            activeIndex = min(max(activeIndex, 0), windows.count - 1)
        }
    }

    @discardableResult
    package mutating func activate(_ window: Item) -> Bool {
        guard let index = windows.firstIndex(of: window) else { return false }
        activeIndex = index
        return true
    }

    @discardableResult
    package mutating func remove(at index: Int) -> Item {
        let window = windows.remove(at: index)
        normalizeActiveIndex()
        return window
    }

    @discardableResult
    package mutating func removeAll(where predicate: (Item) -> Bool) -> Int {
        let before = windows.count
        windows.removeAll(where: predicate)
        normalizeActiveIndex()
        return before - windows.count
    }
}

package struct PaneLocation: Equatable {
    package var paneIndex: Int
    package var windowIndex: Int
}

package enum PaneOperations {
    package static func location<Item: Equatable>(
        of window: Item,
        in panes: [Pane<Item>]
    ) -> PaneLocation? {
        for (paneIndex, pane) in panes.enumerated() {
            if let windowIndex = pane.firstIndex(of: window) {
                return PaneLocation(paneIndex: paneIndex, windowIndex: windowIndex)
            }
        }
        return nil
    }

    package static func focusOffset<Item: Equatable>(
        in panes: inout [Pane<Item>],
        from location: PaneLocation,
        offset: Int
    ) -> PaneLocation? {
        guard !panes.isEmpty, panes.indices.contains(location.paneIndex), offset != 0 else { return nil }
        panes[location.paneIndex].activeIndex = location.windowIndex
        panes[location.paneIndex].normalizeActiveIndex()

        if offset > 0 {
            let pane = panes[location.paneIndex]
            if location.windowIndex + 1 < pane.windows.count {
                let target = PaneLocation(paneIndex: location.paneIndex, windowIndex: location.windowIndex + 1)
                panes[target.paneIndex].activeIndex = target.windowIndex
                return target
            }
            let targetPane = (location.paneIndex + 1) % panes.count
            let target = PaneLocation(paneIndex: targetPane, windowIndex: 0)
            panes[targetPane].activeIndex = 0
            return target
        }

        if location.windowIndex > 0 {
            let target = PaneLocation(paneIndex: location.paneIndex, windowIndex: location.windowIndex - 1)
            panes[target.paneIndex].activeIndex = target.windowIndex
            return target
        }
        let targetPane = (location.paneIndex - 1 + panes.count) % panes.count
        let targetWindow = max(panes[targetPane].windows.count - 1, 0)
        let target = PaneLocation(paneIndex: targetPane, windowIndex: targetWindow)
        panes[targetPane].activeIndex = targetWindow
        return target
    }

    package static func moveFocused<Item: Equatable>(
        in panes: inout [Pane<Item>],
        from location: PaneLocation,
        offset: Int
    ) -> PaneLocation? {
        guard !panes.isEmpty, panes.indices.contains(location.paneIndex), offset != 0 else { return nil }
        panes[location.paneIndex].activeIndex = location.windowIndex
        panes[location.paneIndex].normalizeActiveIndex()

        if panes[location.paneIndex].windows.count > 1 {
            let count = panes[location.paneIndex].windows.count
            let targetWindow = (location.windowIndex + offset + count) % count
            let window = panes[location.paneIndex].windows.remove(at: location.windowIndex)
            panes[location.paneIndex].windows.insert(window, at: targetWindow)
            panes[location.paneIndex].activeIndex = targetWindow
            return PaneLocation(paneIndex: location.paneIndex, windowIndex: targetWindow)
        }

        guard panes.count > 1 else { return location }
        let count = panes.count
        let targetPane = (location.paneIndex + offset + count) % count
        let pane = panes.remove(at: location.paneIndex)
        panes.insert(pane, at: targetPane)
        return PaneLocation(paneIndex: targetPane, windowIndex: 0)
    }

    package static func groupFocused<Item: Equatable>(
        in panes: inout [Pane<Item>],
        from location: PaneLocation,
        offset: Int
    ) -> PaneLocation? {
        guard panes.indices.contains(location.paneIndex), offset != 0 else { return nil }
        let targetPane = location.paneIndex + (offset < 0 ? -1 : 1)
        guard panes.indices.contains(targetPane) else { return nil }

        panes[location.paneIndex].activeIndex = location.windowIndex
        let source = panes.remove(at: location.paneIndex)

        if offset < 0 {
            let insertionIndex = panes[targetPane].windows.count
            panes[targetPane].windows.append(contentsOf: source.windows)
            panes[targetPane].activeIndex = insertionIndex + source.activeIndex
            return PaneLocation(paneIndex: targetPane, windowIndex: panes[targetPane].activeIndex)
        }

        let adjustedTarget = targetPane - 1
        panes[adjustedTarget].windows.insert(contentsOf: source.windows, at: 0)
        panes[adjustedTarget].activeIndex = source.activeIndex
        return PaneLocation(paneIndex: adjustedTarget, windowIndex: source.activeIndex)
    }

    package static func expelFocused<Item: Equatable>(
        from panes: inout [Pane<Item>],
        location: PaneLocation,
        offset: Int
    ) -> PaneLocation? {
        guard panes.indices.contains(location.paneIndex), offset != 0 else { return nil }
        guard panes[location.paneIndex].windows.count > 1 else { return nil }

        panes[location.paneIndex].activeIndex = location.windowIndex
        let window = panes[location.paneIndex].remove(at: location.windowIndex)
        let insertIndex = offset < 0 ? location.paneIndex : location.paneIndex + 1
        panes.insert(Pane(windows: [window]), at: insertIndex)
        return PaneLocation(paneIndex: insertIndex, windowIndex: 0)
    }
}
