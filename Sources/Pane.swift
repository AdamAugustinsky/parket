import Foundation

package struct PaneID: Hashable, Equatable, CustomStringConvertible {
    package let rawValue: UInt64

    package init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    package var description: String { "p\(rawValue)" }

    private static var nextRawValue: UInt64 = 1

    package static func next() -> PaneID {
        let id = PaneID(nextRawValue)
        nextRawValue += 1
        return id
    }
}

package struct Pane<Item: Equatable>: Equatable {
    package let id: PaneID
    package var windows: [Item]
    package var activeWindow: Item?

    package init(id: PaneID = PaneID.next(), windows: [Item], activeIndex: Int = 0) {
        self.id = id
        self.windows = windows
        if windows.indices.contains(activeIndex) {
            activeWindow = windows[activeIndex]
        } else {
            activeWindow = windows.first
        }
        normalizeActiveWindow()
    }

    package init(id: PaneID = PaneID.next(), windows: [Item], activeWindow: Item?) {
        self.id = id
        self.windows = windows
        self.activeWindow = activeWindow
        normalizeActiveWindow()
    }

    package var isEmpty: Bool { windows.isEmpty }
    package var isGrouped: Bool { windows.count > 1 }

    package var activeIndex: Int {
        get {
            guard let activeWindow,
                  let index = windows.firstIndex(of: activeWindow)
            else { return 0 }
            return index
        }
        set {
            guard windows.indices.contains(newValue) else { return }
            activeWindow = windows[newValue]
        }
    }

    package func contains(_ window: Item) -> Bool {
        windows.contains(window)
    }

    package func firstIndex(of window: Item) -> Int? {
        windows.firstIndex(of: window)
    }

    package mutating func normalizeActiveWindow(preferredIndex: Int? = nil) {
        guard !windows.isEmpty else {
            activeWindow = nil
            return
        }

        if let activeWindow, windows.contains(activeWindow) {
            return
        }

        if let preferredIndex {
            let clamped = min(max(preferredIndex, 0), windows.count - 1)
            activeWindow = windows[clamped]
        } else {
            activeWindow = windows[0]
        }
    }

    @discardableResult
    package mutating func activate(_ window: Item) -> Bool {
        guard windows.contains(window) else { return false }
        activeWindow = window
        return true
    }

    @discardableResult
    package mutating func remove(at index: Int) -> Item {
        let oldActiveIndex = activeIndex
        let removedWasActive = windows.indices.contains(index) && windows[index] == activeWindow
        let window = windows.remove(at: index)
        if removedWasActive {
            activeWindow = nil
        }
        let preferredIndex = removedWasActive ? index : oldActiveIndex
        normalizeActiveWindow(preferredIndex: preferredIndex)
        return window
    }

    @discardableResult
    package mutating func removeAll(where predicate: (Item) -> Bool) -> Int {
        let oldActiveIndex = activeIndex
        let before = windows.count
        windows.removeAll(where: predicate)
        normalizeActiveWindow(preferredIndex: oldActiveIndex)
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

    package static func location<Item: Equatable>(
        of paneID: PaneID,
        in panes: [Pane<Item>]
    ) -> Int? {
        panes.firstIndex { $0.id == paneID }
    }

    package static func focusOffset<Item: Equatable>(
        in panes: inout [Pane<Item>],
        from location: PaneLocation,
        offset: Int
    ) -> PaneLocation? {
        guard !panes.isEmpty, panes.indices.contains(location.paneIndex), offset != 0 else { return nil }
        panes[location.paneIndex].activeIndex = location.windowIndex

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

    package static func focusLeft<Item: Equatable>(
        in panes: [Pane<Item>],
        from location: PaneLocation
    ) -> PaneLocation? {
        guard panes.count > 1,
              panes.indices.contains(location.paneIndex),
              location.paneIndex != 0
        else { return nil }

        return PaneLocation(paneIndex: 0, windowIndex: panes[0].activeIndex)
    }

    package static func focusRight<Item: Equatable>(
        in panes: [Pane<Item>],
        from location: PaneLocation,
        rememberedStackPaneID: PaneID?
    ) -> PaneLocation? {
        guard panes.count > 1,
              panes.indices.contains(location.paneIndex),
              location.paneIndex == 0
        else { return nil }

        if let rememberedStackPaneID,
           let paneIndex = panes.firstIndex(where: { $0.id == rememberedStackPaneID }),
           paneIndex != 0 {
            return PaneLocation(paneIndex: paneIndex, windowIndex: panes[paneIndex].activeIndex)
        }

        return PaneLocation(paneIndex: 1, windowIndex: panes[1].activeIndex)
    }

    package static func moveFocused<Item: Equatable>(
        in panes: inout [Pane<Item>],
        from location: PaneLocation,
        offset: Int
    ) -> PaneLocation? {
        guard !panes.isEmpty, panes.indices.contains(location.paneIndex), offset != 0 else { return nil }
        panes[location.paneIndex].activeIndex = location.windowIndex

        if panes[location.paneIndex].windows.count > 1 {
            let targetWindow = location.windowIndex + offset
            guard panes[location.paneIndex].windows.indices.contains(targetWindow) else {
                return location
            }
            let window = panes[location.paneIndex].windows.remove(at: location.windowIndex)
            panes[location.paneIndex].windows.insert(window, at: targetWindow)
            panes[location.paneIndex].activeWindow = window
            return PaneLocation(paneIndex: location.paneIndex, windowIndex: targetWindow)
        }

        guard panes.count > 1 else { return location }
        let targetPane = location.paneIndex + offset
        guard panes.indices.contains(targetPane) else { return location }
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
        guard panes[location.paneIndex].windows.indices.contains(location.windowIndex) else { return nil }

        let window = panes[location.paneIndex].remove(at: location.windowIndex)
        var adjustedTarget = targetPane

        if panes[location.paneIndex].isEmpty {
            panes.remove(at: location.paneIndex)
            if targetPane > location.paneIndex {
                adjustedTarget -= 1
            }
        }

        if offset < 0 {
            let insertionIndex = panes[adjustedTarget].windows.count
            panes[adjustedTarget].windows.append(window)
            panes[adjustedTarget].activeWindow = window
            return PaneLocation(paneIndex: adjustedTarget, windowIndex: insertionIndex)
        }

        panes[adjustedTarget].windows.insert(window, at: 0)
        panes[adjustedTarget].activeWindow = window
        return PaneLocation(paneIndex: adjustedTarget, windowIndex: 0)
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
